# Z2Z Export Directory

## Overview

This directory serves as the staging repository for exported LDAP directory data, domain definitions, global configuration snapshots, and generated mailbox batch archiving scripts during Z2Z execution.

## Quickstart

After export completes, transfer this directory to the destination Zimbra server:

```bash
scp -r export/ zimbra@destination-server:/tmp/export/
```

## Dependencies

- Zimbra Collaboration Suite CLI tools (`ldapsearch`, `zmmailbox`, `zmprov`)
- Bash 4.1+ environment

## Configuration

Default export artifacts are stored in this staging directory (`export/`). Hostname substitution can be configured interactively during `z2z.sh` execution.

## Generated Artifacts

- `DOMINIOS.ldif`: Email domain LDAP directory definitions.
- `create_domains.sh`: Companion CLI domain provisioning helper script.
- `CONFIG_GLOBAL.ldif`: Server-wide LDAP global configuration object.
- `global_settings_snapshot.txt`: Text snapshot of MTA restrictions and relayhost settings.
- `COS.ldif`: Class of Service LDAP directory records.
- `CONTAS.ldif`: User account objects with password hashes.
- `APELIDOS.ldif`: Email alias mapping definitions.
- `LISTAS.ldif`: Distribution lists and Zimbra group memberships.
- `importar_ldap.sh`: Automated domain and LDAP object restoration script.
- `script_export_FULL.sh` / `script_import_FULL.sh`: Full mailbox batch archiving scripts.
- `script_export_TRASH.sh` / `script_import_TRASH.sh`: Trash folder batch scripts.
- `script_export_JUNK.sh` / `script_import_JUNK.sh`: Junk/Spam folder batch scripts.

## Running Tests

Verify presence and readability of exported LDIF files:

```bash
ls -la export/*.ldif
```

## Contributing

Contributions are managed through the main repository pull requests.

## License

Copyright (C) 2016-2026 Fabio Soares Schmidt <fabio@respirandolinux.com.br>, alsyundawy
