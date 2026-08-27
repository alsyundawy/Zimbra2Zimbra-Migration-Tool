# Z2Z Export Directory

## Overview

This directory stores exported LDAP data and generated mailbox batch scripts during Z2Z execution.

## Quickstart

Copy this directory to the destination Zimbra server:

```bash
scp -r export zimbra@destination-server:/tmp/
```

## Dependencies

- Zimbra LDAP utilities
- Generated LDIF files (`COS.ldif`, `CONTAS.ldif`, `APELIDOS.ldif`, `LISTAS.ldif`)

## Configuration

Configuration is determined automatically during the export process.

## Running Tests

Verify presence and readability of exported LDIF files:

```bash
ls -la export/*.ldif
```

## Contributing

Contributions are managed through the main project repository.

## License

Copyright (C) 2016-2026 Fabio Soares Schmidt <fabio@respirandolinux.com.br>, alsyundawy
