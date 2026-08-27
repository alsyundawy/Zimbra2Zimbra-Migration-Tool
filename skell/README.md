# Z2Z Skeleton Directory

## Overview

This directory contains template scripts and banners copied into the `export/` directory during execution.

## Quickstart

Grant execution permissions to template scripts:

```bash
chmod +x skell/importar_ldap.sh
```

## Dependencies

- Zimbra Collaboration Server
- OpenLDAP client binaries (`ldapadd`, `ldapdelete`, `ldapsearch`)

## Configuration

Templates are configured at runtime when copied into the `export/` directory.

## Running Tests

Verify syntax of template scripts:

```bash
bash -n skell/importar_ldap.sh
```

## Contributing

Contributions are managed through the main project repository.

## License

Copyright (C) 2016-2026 Fabio Soares Schmidt <fabio@respirandolinux.com.br>, alsyundawy
