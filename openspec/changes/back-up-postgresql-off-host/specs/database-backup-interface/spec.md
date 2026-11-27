## ADDED Requirements

### Requirement: The dump units cover the backup set

On every NixOS host with `vanixiets.postgresqlBackup.enable` and `services.postgresql.enable`, the evaluated `services.postgresqlBackup.databases` SHALL equal `services.postgresql.ensureDatabases` minus `vanixiets.postgresqlCollation.parkedDatabases`, with `compression = "none"` and `location` equal to `flake.lib.postgresqlBackup.location` (`/var/backup/postgresql-nightly`).

#### Scenario: magnetite's dumps are evaluated

- **WHEN** magnetite's configuration is evaluated with the backup on and cognee parked
- **THEN** `services.postgresqlBackup.databases` is `gitea`, `gitea-mq`, `matrix-synapse`, `niks3`, `nixbot` and `omnigent` in some order, and compression is `"none"`

#### Scenario: a host without PostgreSQL

- **WHEN** cinnabar's configuration is evaluated
- **THEN** it has no `postgresqlBackup-*`, `postgresql-dump-globals` or `restic-backups-postgresql` unit

### Requirement: The dump units have no timer of their own

No `postgresqlBackup-<db>` unit SHALL have a non-empty `startAt`, so `systemd.timers` SHALL hold no `postgresqlBackup-*` timer on any host.

#### Scenario: timers are evaluated

- **WHEN** magnetite's `systemd.timers` is evaluated
- **THEN** it has `restic-backups-postgresql` and no `postgresqlBackup-*` attribute

### Requirement: Roles are dumped beside the databases

A oneshot `postgresql-dump-globals.service`, running as `postgres` and requiring `postgresql.target`, SHALL write `pg_dumpall --globals-only` to `<location>/globals.sql` through an in-progress file under umask 0077.

#### Scenario: the unit is evaluated

- **WHEN** magnetite's `systemd.services.postgresql-dump-globals` is evaluated
- **THEN** its `serviceConfig.Type` is `"oneshot"`, its `User` is `"postgres"`, and its script writes `globals.sql` under `/var/backup/postgresql-nightly` only after `pg_dumpall` succeeds

### Requirement: The backup job reaches its R2 repository

`services.restic.backups.postgresql` SHALL have `repository` `s3:https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com/sciexp-postgresql-backup/<hostName>`, `extraOptions` containing `s3.bucket-lookup=path` and `s3.region=auto`, `initialize = true` and `createWrapper = true`.

#### Scenario: the repository is evaluated

- **WHEN** magnetite's `services.restic.backups.postgresql.repository` is evaluated
- **THEN** it ends in `/sciexp-postgresql-backup/magnetite`

### Requirement: The backup job runs nightly and catches up a missed night

The job's `timerConfig` SHALL hold `OnCalendar = "*-*-* 02:30:00 UTC"`, `RandomizedDelaySec = "15m"` and `Persistent = true`.

#### Scenario: the timer is evaluated

- **WHEN** magnetite's `systemd.timers.restic-backups-postgresql.timerConfig` is evaluated
- **THEN** it holds exactly those three settings

### Requirement: The backup job starts every dump

The job's `backupPrepareCommand` SHALL run `systemctl start --wait` on every `postgresqlBackup-<db>.service` of the backup set and on `postgresql-dump-globals.service`, and SHALL exit non-zero when any of them fails.

#### Scenario: a dump fails during the prepare step

- **WHEN** one `postgresqlBackup-<db>.service` fails while `restic-backups-postgresql.service` starts
- **THEN** the prepare step exits non-zero, restic's `backup` command does not run, and `restic-backups-postgresql.service` is failed

### Requirement: The backup job uploads exactly the dump files

The job's `paths` SHALL equal `<location>/<db>.sql` for each database of the backup set plus `<location>/globals.sql`.

#### Scenario: paths are evaluated

- **WHEN** magnetite's `services.restic.backups.postgresql.paths` is evaluated
- **THEN** it holds exactly seven files, the six `<db>.sql` files and `globals.sql` under `/var/backup/postgresql-nightly`, and no `.prev` file or directory

### Requirement: The backup job keeps 7 daily, 4 weekly and 6 monthly copies and checks a tenth each night

The job's `pruneOpts` SHALL be `--keep-daily 7`, `--keep-weekly 4`, `--keep-monthly 6` and `--group-by host`, and its `checkOpts` SHALL be `--read-data-subset=10%`.

#### Scenario: retention is evaluated

- **WHEN** magnetite's `services.restic.backups.postgresql` is evaluated
- **THEN** `pruneOpts` and `checkOpts` hold exactly those values

### Requirement: The backup bucket deletes nothing by age

`modules/terranix/cloudflare.nix` SHALL declare `cloudflare_r2_bucket.sciexp-postgresql-backup` with `lifecycle.prevent_destroy = true`, and SHALL declare no lifecycle rule on that bucket that deletes objects by age.

#### Scenario: a lifecycle rule is proposed

- **WHEN** a change adds an age-based delete rule for `sciexp-postgresql-backup`
- **THEN** it contradicts this requirement and the comment on the bucket resource, and is refused at review

### Requirement: The backup job's R2 key is a clan var of its own

The job's `environmentFile` SHALL be the `env` file of clan vars generator `postgresql-backup-r2`, whose hidden, persisted, undeployed prompts `access-key` and `secret-key` hold an R2 token scoped to `sciexp-postgresql-backup` alone, and which no other service uses.

#### Scenario: the environment file is evaluated

- **WHEN** magnetite's `services.restic.backups.postgresql.environmentFile` is evaluated
- **THEN** it is `clan.core.vars.generators.postgresql-backup-r2.files.env.path`, and no other unit's `EnvironmentFile` names that path

### Requirement: The repository password is a generated clan var

The job's `passwordFile` SHALL be the `password` file of clan vars generator `postgresql-backup-restic`, generated with no prompt.

#### Scenario: the password file is evaluated

- **WHEN** magnetite's `services.restic.backups.postgresql.passwordFile` is evaluated
- **THEN** it is `clan.core.vars.generators.postgresql-backup-restic.files.password.path`

### Requirement: Every backup unit is a notified unit

For every host whose backup is on, `flake.lib.observabilityHosts.<host>.notifiedUnits` SHALL contain `restic-backups-postgresql`, `postgresql-dump-globals` and `postgresqlBackup-<db>` for each database of the backup set.

#### Scenario: a unit is missing from the host table

- **WHEN** a `postgresqlBackup-<db>` unit exists on a host and is absent from that host's `notifiedUnits`
- **THEN** the host's machine check fails naming the unit

### Requirement: A successful run writes its time to the host's one textfile directory

On success, `restic-backups-postgresql.service`'s `ExecStartPost` SHALL write `vanixiets_postgresql_backup_last_success_timestamp_seconds` with the current Unix time to its record `/var/lib/postgresql-backup-metrics/backup.prom`, and copy the record by write-then-rename to `postgresql-backup.prom` in `vanixiets.nodeExporter.textfileDirectory`. The module SHALL name itself `postgresql-backup` in `vanixiets.nodeExporter.textfileWriters`, SHALL add no `--collector.textfile.directory` flag of its own, and the series SHALL be in `nodeExporterKeep`.

#### Scenario: the collector wiring is evaluated

- **WHEN** magnetite's configuration is evaluated with the backup on
- **THEN** `vanixiets.nodeExporter.textfileWriters` contains `postgresql-backup`, node_exporter's `extraFlags` carry `--collector.textfile.directory` once, on `vanixiets.nodeExporter.textfileDirectory`, and `flake.lib.otelCollectorSchema.nodeExporterKeep` contains the series name

### Requirement: The last success is seeded and republished

A oneshot `postgresql-backup-metric.service`, wanted by `multi-user.target` and started every 60 s by its timer, SHALL write the record with the current time when no record exists, and otherwise SHALL copy the record into the textfile directory again.

#### Scenario: first activation

- **WHEN** magnetite activates the configuration with the backup on for the first time and no `backup.prom` exists
- **THEN** the unit writes the series with that activation's time, and later runs leave the record unchanged and refresh the published copy, so it reappears within a minute of a boot and stays younger than `HostProbeStale`'s 300 s

### Requirement: PostgresqlBackupStale fires when the last success is 36 h old

fleet-alert SHALL carry rule `PostgresqlBackupStale` with `expr = "time() - vanixiets_postgresql_backup_last_success_timestamp_seconds > 129600"`, `for = "10m"`, severity warning, and an annotation naming the restore runbook.

#### Scenario: the promtool case runs

- **WHEN** `checks.x86_64-linux.fleet-alert` runs the rule over a series whose value stops advancing at hour 2
- **THEN** the rule does not fire at 38 h, when the value is exactly 36 h old, is pending at 38 h 5 min and fires one alert labelled `host_name="magnetite"` at 38 h 11 min, and a series advancing every 24 h never fires

#### Scenario: the threshold is mutated

- **WHEN** the rule's threshold is replaced by `1296000`
- **THEN** the promtool case fails and the check reports the `staleThreshold` mutant rejected

### Requirement: The dumps live on their own dataset with auto-snapshot off

While its backup is on, magnetite's disko configuration SHALL declare `zroot/root/postgresql-dumps` at `/var/backup/postgresql-nightly` with `com.sun:auto-snapshot=false` and `quota=16G`, and oneshots `zfs-assert-root-postgresql-dumps-noautosnap` and `zfs-set-root-postgresql-dumps-quota` SHALL enforce both at boot. `services.zfs.autoSnapshot` SHALL keep `hourly = 4`, `daily = 3`, `weekly = 1`.

#### Scenario: the dataset is evaluated

- **WHEN** magnetite's `disko.devices.zpool.zroot.datasets."root/postgresql-dumps".options` is evaluated with the backup on
- **THEN** it holds the mountpoint, `com.sun:auto-snapshot = "false"` and `quota = "16G"`

### Requirement: A restore test drops and restores from the backup job's own copy

`vmTests.x86_64-linux.postgresql-backup-restore` SHALL run `flake.modules.nixos.postgresql-backup` in a container with magnetite's PostgreSQL package and a local restic repository, and SHALL pass only when a restore from the snapshot taken by starting `restic-backups-postgresql.service` alone brings back every row, the role and a sentinel row written after an older dump existed.

#### Scenario: the test runs

- **WHEN** the test seeds two databases and a role, runs every dump unit, inserts a sentinel, starts the backup job, records row counts, drops the databases and role, and restores globals then each dump from the latest snapshot
- **THEN** every row count equals its recorded count, the sentinel and the role exist, the snapshot's paths are exactly the dump files, and both the record and the published copy hold a time later than the test's start

#### Scenario: the prepare step is mutated

- **WHEN** the test runs a node whose `backupPrepareCommand` starts no dumps
- **THEN** the test fails on the sentinel assertion

### Requirement: A host's backup set is pinned by a fleet obligation

`flake.lib.postgresqlBackupObligations.failures name hostConfig` SHALL be registered as `fleetObligations.postgresqlBackupObligations`, which `modules/checks/machines.nix` folds into every `nixos-<host>` and `darwin-<host>` check. It SHALL return `[ ]` for a host without PostgreSQL. For a host with PostgreSQL it SHALL return one message for each of:
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

### Requirement: The backup stays off until the host's vars are in the repository

`vanixiets.postgresqlBackup.enable` SHALL default to `false`. The vars generators `postgresql-backup-r2` and `postgresql-backup-restic` SHALL be declared only where it is set, and a host SHALL set it only in the commit that adds those generators' vars to the repository.

#### Scenario: magnetite before its vars exist

- **WHEN** magnetite is evaluated with `"magnetite"` in `awaitingSecrets` and the backup off
- **THEN** its configuration has no `postgresql-backup*` generator and no backup unit, and `failures "magnetite"` is `[ ]`

#### Scenario: the backup is turned on without the vars

- **WHEN** magnetite sets `vanixiets.postgresqlBackup.enable = true` before `vars/per-machine/magnetite/postgresql-backup-r2/env/secret` and `…/postgresql-backup-restic/password/secret` exist
- **THEN** `checks.x86_64-linux.nixos-magnetite` fails naming `postgresqlBackupObligations` and the missing vars
