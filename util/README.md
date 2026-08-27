# Z2Z Utilities Directory

## Overview

This directory contains standalone utility scripts for Zimbra server maintenance.

## Quickstart

Run a utility script directly with Zimbra privileges:

```bash
su - zimbra
cd util/
./mailbox_size.sh
```

## Dependencies

- Zimbra Collaboration Server
- User privileges: `zimbra` or `root` (for disclaimer configuration)

## Configuration

Disclaimer text files are read from `/opt/zimbra/postfix/conf/disclaimer.{txt,html}`.

## Running Tests

Verify syntax across all utility scripts:

```bash
bash -n util/*.sh
```

## Contributing

Contributions are managed through the main project repository.

## License

Copyright (C) 2016-2026 Fabio Soares Schmidt <fabio@respirandolinux.com.br>, alsyundawy
