# Z2Z (Zimbra2Zimbra Migration Tool)

Version: **1.0.3** | Maintained by: **alsyundawy**

Copyright (C) 2016-2026 Fabio Soares Schmidt <fabio@respirandolinux.com.br>, alsyundawy

## Overview

This tool simplifies the migration process between Zimbra environments, regardless of which edition is deployed (Open Source or Network Edition). Z2Z supports diverse migration scenarios — "A2Z: Anything/Anywhere to Zimbra".

**Intended for upgrades (migrating TO a newer Zimbra version). Proper functionality during downgrades is not guaranteed.**

## Quickstart

Run the migration export utility on the source Zimbra server:

```bash
su - zimbra
cd /path/to/Zimbra2Zimbra-Migration-Tool
chmod +x z2z.sh func.sh skell/importar_ldap.sh util/*.sh
./z2z.sh
```

## Dependencies

- Zimbra Collaboration Server (8.x, 9.x, 10.x)
- Standard Zimbra CLI tools: `zmprov`, `zmmailbox`, `ldapsearch`, `ldapadd`, `ldapdelete`
- Bash shell (4.0+)

## Configuration

Server hostnames and export destinations are configured interactively during execution. Environment variables are automatically sourced from `/opt/zimbra/bin/zmshutil`.

## Running Tests

Verify shell script syntax before running:

```bash
bash -n z2z.sh func.sh skell/importar_ldap.sh util/*.sh
```

## Documentation

- **Changelog**: Please refer to the [CHANGELOG](CHANGELOG) file.
- **Installation**: Please refer to the [INSTALL](INSTALL) file.
- **Usage**: Please refer to the [INSTALL](INSTALL) file.

## What Will Be Migrated

Although Zimbra provides built-in utilities, Z2Z automates the process by exporting:

- [x] **Classes of Service (COS)**
- [x] **User Accounts** (passwords preserved with internal auth)
- [x] **Aliases** (Alternative names)
- [x] **Distribution Lists** (including zimbraGroup objects)
- [x] **Mailboxes** (emails, calendars, tasks, contacts, briefcase, preferences)

In this version, Z2Z automates the export of entries above and generates batch scripts to export mailboxes using `zmmailbox`. **Domains must be created manually on the destination server prior to import.**

![Screenshot](https://respirandolinux.files.wordpress.com/2017/02/zimbrazimbratmp333z2z-master.jpg)

## User Feedback

### Filipe A. Motta Braga - Regional Labor Court (13th Region)

> "We recently used **Z2Z** to support the migration of 2,400 accounts at the Regional Labor Court of the 13th Region. The tool was very useful because we were on a very old version of Zimbra which made updates via script impossible. The migration was performed incrementally due to the volume of accounts until the cutover. Everything went as expected and we are now running on the latest version of Zimbra."

### Marco Brandão - Plus Informática

> "I would like to congratulate you on the excellent Z2Z tool. It helped me immensely during a migration from Zimbra 8.0.7 to 8.7.11. Great work!"

### Alisson S. Conde - Paranatex Têxtil LTDA

> "Congratulations on this excellent tool; it would have been impossible to migrate our company's legacy server without this project. The import was flawless: nearly 160 accounts with over 700GB of data, zero failures, and a fast, stable environment after import."

### Fernando Lima - Gobah! Soluções em TI

> "I used Z2Z to perform a migration between two Zimbra servers (8.8.11 > 8.8.12). My experience with the tool was outstanding; everything proceeded smoothly without errors. Previously, we attempted manual migration for mailboxes larger than 2GB which caused numerous timeouts and took nearly 3 days. With Z2Z, we completed the job in just one day without hassle."

## Roadmap

- Multi-Server environment support involving hostname substitution across multiple mailbox servers.
- Incremental export and import capabilities to support phased migration strategies.
- Domain migration automation.

## Contributing

Feedback, bug reports, and contributions are welcome. Please submit issues or pull requests via GitHub.

## License

DISTRIBUTED UNDER CREATIVE COMMONS LICENSE: Attribution-NonCommercial-ShareAlike (CC BY-NC-SA)

This license allows others to adapt the original work non-commercially, as long as they credit the creator appropriately (original banner and Copyright) and license new creations under the same terms. This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

## Contact

- **Maintainer**: alsyundawy
- **Original Developer**: Fabio Soares Schmidt <fabio@respirandolinux.com.br> | <https://respirandolinux.com.br>
