# Z2Z Utilities Directory

## Overview

This directory contains standalone migration and diagnostic utilities for Zimbra Collaboration Suite and Carbonio CE servers.

## Quickstart

Run a utility script directly with `zimbra` privileges:

```bash
su - zimbra
cd util/

# 1. Pre-flight DNS Diagnostics
./dns_diagnostic.sh

# 2. DKIM Snapshot
./export_dkim_keys.sh

# 3. Webmail Signatures & Identities
./export_signatures.sh
./import_signatures.sh

# 4. Sieve Mail Filters
./export_sieve_filters.sh
./import_sieve_filters.sh

# 5. Out-of-Office Responders
./export_ooo.sh
./import_ooo.sh

# 6. Calendar Resources & Equipment
./export_calendar_resources.sh
./import_calendar_resources.sh

# 7. Incremental Delta Sync
./sync_delta_mailbox.sh 2026/08/20 ./export/delta

# 8. Post-Migration Verification
./verify_migration.sh

# 9. Source Account Freeze & Cutover
./freeze_source_accounts.sh --freeze

# 10. Direct SSH Mailbox Streaming Pipeline
./stream_mailbox_direct.sh zimbra@target-server.com

# 11. Generic IMAP Ingestion Wrapper
./imapsync_wrapper.sh imap.oldserver.com mail.newserver.com accounts.csv

# 12. Executive HTML Report Generator
./generate_migration_report.sh ./export/migration_report.html

# 13. Diagnostics & Audits
./mailbox_size.sh
./audit_forwards.sh
./audit_shares.sh
sudo ./add_disclaimer.sh
```

## Dependencies

- Zimbra Collaboration Server CLI tools (`zmprov`, `zmmailbox`, `zmlocalconfig`)
- `dig` (via `bind-utils` on RHEL/Rocky/Alma or `bind9-dnsutils` on Debian/Ubuntu)
- `imapsync` (required only for `imapsync_wrapper.sh`)
- User privileges: `zimbra` (for all utilities except `add_disclaimer.sh` which requires `root`)

## Configuration

Utilities dynamically load the local Zimbra environment via `zmsetvars` and `zmlocalconfig`. For utility scripts that accept parameters (e.g., `sync_delta_mailbox.sh` or `stream_mailbox_direct.sh`), pass the target parameters via CLI arguments as described in the help headers.

## Available Utilities

| Utility Script | Purpose & Description |
| :--- | :--- |
| `dns_diagnostic.sh` | Validates domain DNS records (MX, SPF, DKIM, DMARC) and resolver reachability. |
| `export_dkim_keys.sh` | Snapshots DKIM selector and public keys per domain with security rotation advisory. |
| `export_signatures.sh` / `import_signatures.sh` | Exports and restores webmail signatures (plain-text & HTML) and persona identity mappings. |
| `export_sieve_filters.sh` / `import_sieve_filters.sh` | Exports and restores user Sieve mail filter rules (`zimbraMailSieveScript`). |
| `export_ooo.sh` / `import_ooo.sh` | Exports and restores Out-of-Office vacation responders with Base64 payload protection. |
| `export_calendar_resources.sh` / `import_calendar_resources.sh` | Provisions calendar resources/equipment and migrates calendar data TGZ archives. |
| `sync_delta_mailbox.sh` | Incremental delta mailbox sync using REST timestamp queries (`after:YYYY/MM/DD`). |
| `verify_migration.sh` | Post-migration data integrity verification and mailbox health audit. |
| `freeze_source_accounts.sh` | Manages account maintenance status (`--freeze` / `--unfreeze`) during DNS cutover. |
| `stream_mailbox_direct.sh` | Direct SSH streaming pipeline from source to target without intermediate local disk staging. |
| `imapsync_wrapper.sh` | Multi-account IMAP ingestion wrapper for migrating non-Zimbra mail servers to Zimbra. |
| `generate_migration_report.sh` | Generates a standalone, interactive executive HTML migration report. |
| `mailbox_size.sh` | Generates storage consumption reports across all active mailboxes (Bytes to TB). |
| `audit_forwards.sh` | Audits administrative and user-preference forwarding rules. |
| `audit_shares.sh` | Discovers and audits shared folders and permissions across mailboxes. |
| `add_disclaimer.sh` | Configures per-domain legal disclaimers and signatures (ZCS 8.5+). |

## Running Tests

Verify syntax and static analysis across all utility scripts:

```bash
bash -n util/*.sh
shellcheck --norc util/*.sh
```

## Contributing

Contributions and enhancements are welcome via pull requests on the main repository.

## License

Copyright (C) 2016-2026 Fabio Soares Schmidt, alsyundawy. Licensed under CC BY-NC-SA 4.0 / GPL.
