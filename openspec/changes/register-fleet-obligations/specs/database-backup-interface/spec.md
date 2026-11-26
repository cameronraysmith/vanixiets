## MODIFIED Requirements

### Requirement: A host's backup set is pinned by a fleet obligation

`flake.lib.postgresqlBackupObligations.failures name hostConfig` SHALL be registered as the fleet obligation `postgresqlBackupObligations` for the `nixos` and `darwin` classes, so that it is asserted on every `nixos-<host>` and `darwin-<host>` check, as the `fleet-obligation-registry-interface` requirement "Every machine check asserts every judge registered for its class" states. It SHALL return `[ ]` for a host without PostgreSQL. For a host with PostgreSQL it SHALL return one message for each of:
- the backup being off while the host is not in `flake.lib.postgresqlBackup.awaitingSecrets`;
- the backup being on while the host is still in that list;
- the backup being on without both generators' deployed files in the repository;
- each violation of this capability's dump, path, prepare-step and notified-unit requirements.

#### Scenario: the fixture check runs

- **WHEN** `checks.x86_64-linux.postgresql-backup-obligations` is built
- **THEN** four fixtures give no problem: the accepted one, one whose parked database is left out, one awaiting its secrets with the backup off, and one without PostgreSQL. Each of the mutants missingDatabase, dumpTimer, compressed, pathMissing, prepareMissing, unitNotNotified, notEnabled, awaitingButEnabled and secretsMissing gives exactly one

#### Scenario: a database is added without a backup

- **WHEN** magnetite's configuration, with the backup on, gains a database in `ensureDatabases` that the backup set or the host's notified units do not cover
- **THEN** `checks.x86_64-linux.nixos-magnetite` fails naming `postgresqlBackupObligations` and the database's dump unit

#### Scenario: the registration is removed

- **WHEN** the `postgresqlBackupObligations` entry is removed from the fleet obligation registry
- **THEN** evaluating any machine check fails on the registry's key-list assertion, naming the missing key
