# Z2Z Skeleton Directory

## Overview

This directory contains template provisioning scripts and terminal banners that are copied into the `export/` staging directory during execution.

## Quickstart

Grant execution permissions to template scripts:

```bash
chmod +x skell/importar_ldap.sh
```

## Dependencies

- Zimbra Collaboration Server (ZCS 7.x – 10.1.x, Carbonio CE/FOSS)
- OpenLDAP client binaries (`ldapadd`, `ldapdelete`, `ldapsearch`)
- Bash shell (4.1+)

## Configuration

Templates are dynamically configured at runtime when staged into the `export/` directory.

## Running Tests

Verify syntax across template scripts:

```bash
bash -n skell/importar_ldap.sh
```

## Contributing

Contributions are managed through the main project repository.

## License

Copyright (C) 2016-2026 Fabio Soares Schmidt <fabio@respirandolinux.com.br>, alsyundawy
