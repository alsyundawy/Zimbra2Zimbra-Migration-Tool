# Z2Z DOKUMENTASI TEKNIS & MANUAL ARSITEKTUR (DOCNOTE)

Enterprise Cross-Version & Cross-Platform Zimbra to Zimbra Migration Engine (ZCS 7.x – 10.1.x / Carbonio)

By **Harry Dertin Sutisna Alsyundawy**

---

## 1. Arsitektur & Prinsip Kerja Sistem

**Z2Z (Zimbra to Zimbra Migration Tool)** dirancang untuk menyelesaikan tantangan migrasi infrastruktur mail server Zimbra tanpa merusak integritas data, tanpa batasan ukuran mailbox (*zero timeout*), dan tanpa dependensi compiler atau library pihak ketiga.

```text
┌──────────────────────────────────────────────────────────────────────────────────┐
│                         Z2Z v1.0.4 ARCHITECTURE PIPELINE                         │
├──────────────────────────────────────────────────────────────────────────────────┤
│ [SOURCE SERVER]                                                                  │
│  ├── 1. Pre-Flight Checks (UID, PATH, zmshutil, LDAP URI)                        │
│  ├── 2. LDAP Export (Domains -> Global Config -> COS -> Accounts -> Aliases)    │
│  ├── 3. Hostname Substitution (Portable Stream Replacement across all LDIFs)     │
│  ├── 4. Interactive Mailbox Filter (All Accounts, Active Only, or Domain)        │
│  └── 5. Batch Script Generator (Full, Trash, Junk via zmmailbox REST API)        │
│                                                                                  │
│ [DATA STAGING & TRANSFER]                                                        │
│  └── Transfer export/ (LDIF records, batch scripts, .tgz archives via scp/rsync) │
│                                                                                  │
│ [DESTINATION SERVER]                                                             │
│  ├── 1. Automated Domain Ingestion (DOMINIOS.ldif / create_domains.sh)            │
│  ├── 2. LDAP Ingestion (importar_ldap.sh: COS -> Accounts -> Aliases -> DLs)     │
│  ├── 3. Mailbox Ingestion (script_import_FULL.sh with resolve=skip merge)        │
│  └── 4. Post-Migration Verification (mailbox_size, audit_forwards, audit_shares)  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Spesifikasi Objek LDAP & Skema Zimbra

Z2Z berinteraksi langsung dengan direktori OpenLDAP Zimbra melalui protokol LDAP standar menggunakan kredensial administratif internal (`zimbra_ldap_userdn` dan `zimbra_ldap_password`).

### 2.1. Email Domains (`DOMINIOS.ldif` & `create_domains.sh`)

- **Object Class:** `zimbraDomain`
- **Tujuan:** Menyimpan seluruh domain email, konfigurasi mekanisme autentikasi (`zimbraAuthMech`), mode GAL (`zimbraGalMode`), status domain (`zimbraDomainStatus`), dan catch-all address.
- **Otomasi Provisioning:** Diimpor pertama kali pada `importar_ldap.sh` sebelum akun dan COS sehingga server target siap menerima akun tanpa perlu membuat domain secara manual.

### 2.2. Global Configuration & MTA Settings (`CONFIG_GLOBAL.ldif`)

- **Object Class:** `zimbraGlobalConfig`
- **Tujuan:** Snapshot konfigurasi server global (`zimbraMtaRelayHost`, `zimbraMtaMyNetworks`, `zimbraMtaRestriction`, `zimbraMtaDnsLookupsEnabled`) yang disimpan dalam `global_settings_snapshot.txt` untuk acuan administrator di server baru.

### 2.3. Class of Service (`COS.ldif`)

- **Object Class:** `zimbraCOS`
- **Tujuan:** Menyimpan definisi kuota, fitur webmail, permission protokol (IMAP/POP/ActiveSync), dan batasan COS bawaan maupun kustom.
- **Mekanisme Import:** Skrip `importar_ldap.sh` secara otomatis menghapus entri default (`cn=default,cn=cos,cn=zimbra` dan `cn=defaultExternal,cn=cos,cn=zimbra`) pada server tujuan sebelum mengimpor definisi dari server asal untuk mencegah konflik duplikasi ID.

### 2.4. Akun Pengguna (`CONTAS.ldif`)

- **Object Class:** `zimbraAccount`
- **Atribut Terpenting:** `userPassword` (hash password OpenLDAP `{SSHA512}`, `{SSHA}`, atau `{CRYPT}` dipertahankan secara utuh), `zimbraMailDeliveryAddress`, `zimbraAccountStatus`, `zimbraMailHost`.
- **Filter Pengecualian Sistem:**

  ```text
  (&(!(zimbraIsSystemResource=TRUE))
    (!(zimbraIsSystemAccount=TRUE))
    (!(uid=spam.*))
    (!(uid=ham.*))
    (!(uid=virus-quarantine.*))
    (!(uid=galsync*))
    (!(uid=zimbra))
    (!(uid=root))
    (objectClass=zimbraAccount))
  ```

  Pengecualian ini sangat krusial agar akun sistem pada server tujuan tidak tertimpa oleh ID atau token lama dari server asal.

### 2.5. Mail Aliases (`APELIDOS.ldif`)

- **Object Class:** `zimbraAlias`
- **Atribut:** `uid`, `zimbraMailAlias`, `zimbraMailForwardingAddress`.
- **Optimasi v1.0.4:** Menggunakan query atomik *single-pass*:

  ```bash
  ldapsearch -x -H "${ldap_uri}" -D "${binddn}" -w "${password}" -b '' -LLL \
    '(&(!(uid=root))(!(uid=postmaster))(objectclass=zimbraAlias))'
  ```

  Mengeliminasi ribuan sub-query iteratif lama, memangkas waktu eksekusi dari puluhan menit menjadi hitungan detik.

### 2.6. Distribution Lists & Groups (`LISTAS.ldif`)

- **Object Class:** `zimbraDistributionList`, `zimbraGroup`
- **Atribut:** `zimbraMailForwardingAddress`, `zimbraGroupStatus`, `zimbraDistributionListSubscriptionPolicy`.

---

## 3. Mekanisme Migrasi Mailbox via REST API (`zmmailbox`)

Z2Z memanfaatkan REST API native Zimbra yang tertanam pada Mailboxd (`Jetty`) untuk melakukan dump dan ingest konten mailbox dalam format terkompresi `.tgz`.

```text
┌─────────────────────────┬────────────────────────────────────────────────────────┐
│ Parameter zmmailbox     │ Fungsi Teknis & Alasan Implementasi                    │
├─────────────────────────┼────────────────────────────────────────────────────────┤
│ `-z`                    │ Menjalankan autentikasi otomatis sebagai admin Zimbra  │
│ `-m '<account>'`        │ Menargetkan mailbox user spesifik                      │
│ `-t 0`                  │ Meniadakan batas waktu koneksi (timeout = 0 / infinite)│
│ `getRestURL "//?fmt=tgz"`│ Mengunduh seluruh hierarki folder, tags, flag, & pesan │
│ `postRestURL ...`       │ Mengunggah arsip .tgz ke mailbox target                │
│ `resolve=skip`          │ Mencegah penolakan duplicate message ID & safe merge   │
└─────────────────────────┴────────────────────────────────────────────────────────┘
```

---

## 4. Matriks Kompatibilitas Sistem Operasi & Versi Zimbra

| Komponen / Versi | ZCS 7.x | ZCS 8.0-8.6 | ZCS 8.7-8.8 | ZCS 9.0 | ZCS 10.0-10.1 | Carbonio CE |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **OpenLDAP Location** | `/openldap` | `/openldap` | `/common` | `/common` | `/common` | `/common` |
| **zmshutil Support** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **REST API TGZ Export** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Ubuntu 10.04 LTS (Lucid)** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Ubuntu 12.04 LTS (Precise)** | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ |
| **Ubuntu 14.04 LTS (Trusty)** | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Ubuntu 16.04 LTS (Xenial)** | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| **Ubuntu 18.04 LTS (Bionic)** | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| **Ubuntu 20.04 LTS (Focal)** | ❌ | ❌ | ✅ (P20+) | ✅ | ✅ | ✅ |
| **Ubuntu 22.04 LTS (Jammy)** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| **Ubuntu 24.04 LTS (Noble)** | ❌ | ❌ | ❌ | ❌ | ✅ (FOSS) | ✅ (Modern) |
| **CentOS 5 / RHEL 5** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **CentOS 6 / RHEL 6** | ✅ | ✅ | ✅ (Early) | ❌ | ❌ | ❌ |
| **CentOS 7 / RHEL 7** | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **CentOS 8 / RHEL 8** | ❌ | ❌ | ✅ (P22+) | ✅ | ✅ | ✅ |
| **Rocky / AlmaLinux 8** | ❌ | ❌ | ✅ (P22+) | ✅ | ✅ | ✅ |
| **RHEL 9 / Rocky / Alma 9** | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| **Debian 8–12 (Community)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 5. DNS & Routing Infrastructure (Unbound, BIND9, dnsdist, RPZ, CDB)

Selama proses migrasi mail server antar-versi, arsitektur DNS dan jaringan lokal memegang peranan krusial:

### 5.1. Split-Horizon DNS & Local Resolvers

- **Unbound & BIND9:** Server Zimbra mewajibkan rekaman DNS MX dan A yang valid secara lokal. Sebelum cutover, konfigurasi resolver lokal (Unbound pada port 53 atau BIND9) untuk memetakan nama domain ke IP server baru guna menghindari *mail delivery loop* (*Host or domain name not found*).
- **dnsdist & RPZ (Response Policy Zones):** Dapat digunakan di depan mail gateway untuk mengarahkan trafik DNS, memblokir domain spam botnet (RBL / RPZ), dan mendistribusikan query load ke upstream caching server.

### 5.2. Postfix CDB, Hash & LMTP Routing

- Postfix pada Zimbra memanfaatkan tabel lookup format hash atau CDB (*Constant Database*). Selama fase transisi, transport table (`/opt/zimbra/common/conf/transport`) dapat diarahkan sementara ke server lama atau server baru untuk skenario *split-domain routing*.

### 5.3. Firewall Hardening (UFW / Iptables / nftables)

- Port 25 (SMTP), 465 (SMTPS), 587 (Submission), 993 (IMAPS), 995 (POP3S), 80/443 (HTTPS) dibuka untuk publik.
- Port 7071 (Zimbra Admin Console) dan Port 389/636 (OpenLDAP) **WAJIB** dibatasi hanya untuk IP administrator atau jaringan internal demi mencegah serangan brute-force dan eksploitasi CVE (seperti CVE-2024-45519 atau CVE-2026-73570).

---

## 6. Panduan Operasional Standar (RFC 2119)

### 🔴 MUST (Wajib Dilakukan)

1. **MUST Run as Zimbra User:** Skrip `z2z.sh` dan `importar_ldap.sh` **WAJIB** dieksekusi dengan akun sistem `zimbra` (`su - zimbra`).
2. **MUST Validate FQDN Hostnames:** Apabila melakukan penggantian hostname, pastikan format FQDN valid (`mail.domain.com`) dan terverifikasi pada DNS.

### 🟡 SHOULD (Sangat Dianjurkan)

1. **SHOULD Audit Mailbox Sizes:** Jalankan `./util/mailbox_size.sh` sebelum migrasi untuk memperkirakan kebutuhan kapasitas disk dan alokasi waktu *maintenance window*.
2. **SHOULD Audit Forwarding & Shares:** Jalankan `./util/audit_forwards.sh` dan `./util/audit_shares.sh` guna mendeteksi *forwarding loop* atau konfigurasi hak akses folder bersama.
3. **SHOULD Execute Extended Permission Healing:** Setelah seluruh data terimpor pada server tujuan, jalankan `/opt/zimbra/libexec/zmfixperms --extended` sebagai `root`.

### 🟢 MAY (Opsional Sesuai Kebijakan)

1. **MAY Use Account Filters:** Administrator dapat memilih filter akun aktif saja (`zimbraAccountStatus=active`) atau domain tertentu jika menjalankan migrasi bertahap (*phased cutover*).
2. **MAY Omit Trash & Junk:** Administrator dapat memilih untuk tidak mengimpor `script_import_TRASH.sh` dan `script_import_JUNK.sh` guna menghemat ruang penyimpanan server baru.
3. **MAY Run Mailbox Migration in Parallel:** Administrator berpengalaman dapat membagi daftar akun dalam `script_export_FULL.sh` ke dalam beberapa terminal tmux/screen untuk akselerasi eksekusi multi-core.

### ⛔ AVOID (Dilarang Keras)

1. **AVOID Raw `/opt/zimbra` Rsync:** Dilarang menyalin direktori `/opt/zimbra` secara mentah (*raw rsync*) antar server dengan versi sistem operasi atau versi Zimbra berbeda karena akan merusak biner OpenLDAP, database MySQL/MariaDB, dan struktur InnoDB.
2. **AVOID Destructive `resolve=reset` Mode:** Hindari penggunaan `resolve=reset` saat impor mailbox karena akan menghapus data yang telah ada di akun tujuan.
