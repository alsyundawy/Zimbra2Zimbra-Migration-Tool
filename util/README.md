# Z2Z Utilities Directory

## Overview

This directory contains standalone maintenance and diagnostic utilities for Zimbra Collaboration servers.

## Quickstart

Run a utility script directly with appropriate `zimbra` or `root` privileges:

```bash
su - zimbra
cd util/
./mailbox_size.sh
./audit_forwards.sh
./audit_shares.sh
```

## Dependencies

- Zimbra Collaboration Server CLI tools (`zmprov`, `zmmailbox`)
- User privileges: `zimbra` (for reports) or `root` (for disclaimer management)

## Configuration

Utilities read server-wide configurations dynamically from Zimbra environment tools (`zmsetvars` and `zmlocalconfig`).

## Available Utilities

- `mailbox_size.sh`: Generates storage consumption reports across all active mailboxes (Bytes to TB).
- `audit_forwards.sh`: Audits administrative and user-preference forwarding rules.
- `audit_shares.sh`: Discovers and audits shared folders and permissions across mailboxes.
- `add_disclaimer.sh`: Configures per-domain legal disclaimers and signatures (ZCS 8.5+).

## Running Tests

Verify syntax across all utility scripts:

```bash
bash -n util/*.sh
```

## Contributing

Contributions are managed through the main project repository.

## License

Copyright (C) 2016-2026 Fabio Soares Schmidt <fabio@respirandolinux.com.br>, alsyundawy
