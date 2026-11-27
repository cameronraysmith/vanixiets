---
title: PostgreSQL backups
description: "How magnetite's PostgreSQL databases reach R2 every night, what PostgresqlBackupStale means and what to do about it, how to restore one database or all of them, the off-host drill, and the checklist for turning the backup on."
---

This runbook covers the nightly off-host backup of a host's PostgreSQL databases, `flake.modules.nixos.postgresql-backup` in `modules/nixos/postgresql-backup.nix` (openspec change `back-up-postgresql-off-host`).
Today magnetite is the only host running PostgreSQL.

## What is and is not backed up

Backed up, every night:
- every database in `services.postgresql.ensureDatabases` except those of parked services (`vanixiets.postgresqlCollation.parkedDatabases`). On magnetite these are gitea, gitea-mq, matrix-synapse, niks3, nixbot and omnigent;
- the roles and their password hashes, as `globals.sql`.

Not backed up:
- gitea's repositories and LFS objects;
- synapse's media store and signing key;
- niks3's NARs, which are already in R2;
- the services' clan vars, which are already in the repository;
- a parked service's database (cognee) while it stays parked.

Losing magnetite therefore still loses every gitea repository that is not mirrored elsewhere.
The recovery point is up to 24 h: there is no WAL archiving.

## The nightly flow

At 02:30 UTC (with up to 15 min of random delay, and at the next boot if a night was missed) the timer starts `restic-backups-postgresql.service`:

1. Its prepare step starts, one at a time, `postgresqlBackup-<db>.service` for every database and then `postgresql-dump-globals.service`. Each writes an uncompressed `pg_dump -C` file, `<db>.sql`, or `globals.sql`, to `/var/backup/postgresql-nightly`, keeping the previous night's `<db>.sql` as `<db>.prev.sql`. If any dump fails, the job fails before uploading anything, so restic never uploads an old dump as tonight's.
2. `restic unlock` removes the repository's stale locks: one more than 30 minutes old, which a running restic refreshes every 5 minutes, or one taken on this host by a process that is gone (restic 0.20.0, `internal/repository/lock_file.go`). A run interrupted in its prune or check leaves an exclusive lock, and restic refuses a backup while any exclusive lock is in the repository, so this step comes before the backup. It never removes the lock of a restic that is still running.
3. `restic backup` uploads exactly those files to the repository `s3:https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com/sciexp-postgresql-backup/<host>`.
4. `restic forget --prune` keeps 7 daily, 4 weekly and 6 monthly snapshots. Restic owns every deletion in the bucket: never add an age-based lifecycle rule to `sciexp-postgresql-backup`, because deleting packs behind restic's back corrupts the repository.
5. `restic check --read-data-subset=10%` reads back a random tenth of the repository, so the whole repository is verified every few weeks.
6. Only if all of these succeeded, the job writes `vanixiets_postgresql_backup_last_success_timestamp_seconds` with the current time. The value goes to its record `/var/lib/postgresql-backup-metrics/backup.prom` and to `postgresql-backup.prom` in node_exporter's textfile directory, `/run/node-exporter-textfile`.

A failed dump unit or a failed job posts a failure notice naming the unit.

`/var/backup/postgresql-nightly` is its own dataset, `zroot/root/postgresql-dumps`, with auto-snapshot off and a 16G quota.

### Why the timestamp is copied every 60 s

`postgresql-backup-metric.service` runs at boot and then every 60 s from its timer:
- when the record under `/var/lib` is missing, it writes it with the current time;
- otherwise it copies the record into the textfile directory again.

The record lives under `/var/lib` so the last success survives a reboot; the textfile directory is under `/run`, so its copy is lost at every boot and must be restored. The copy is also refreshed every minute, not only after each night's run, because `HostProbeStale` fires on any textfile older than 300 s on a host with a textfile writer. A file written once a night would keep that alert firing all day.

The seed covers a host that never completes a backup: its record holds the time the module was first activated, so `PostgresqlBackupStale` reports it 36 h later.

## PostgresqlBackupStale

The alert fires when `time() - vanixiets_postgresql_backup_last_success_timestamp_seconds > 129600` (36 h) has held for 10 min. The night's run either did not happen or never succeeded. A run that fails also posts its own unit notice. This alert also covers a timer that never fires.

On the host, as root:

```bash
systemctl list-timers restic-backups-postgresql
systemctl status restic-backups-postgresql 'postgresqlBackup-*' postgresql-dump-globals
journalctl -u restic-backups-postgresql --since -2d
cat /var/lib/postgresql-backup-metrics/backup.prom
date -d @"$(awk '$1 ~ /timestamp/ { print $2 }' /var/lib/postgresql-backup-metrics/backup.prom)"
```

Then fix the cause and start a run by hand:

```bash
systemctl start restic-backups-postgresql
```

Common causes:
- a dump failed: read its unit's journal;
- R2 refused the key: the token was revoked or rescoped;
- the repository is locked by a restic that is still running, or by one whose lock is less than 30 minutes old, which the job's own `unlock` leaves: `restic-postgresql --no-lock list locks` and `restic-postgresql --no-lock cat lock <id>` show its host, pid and time; once it has stopped, `restic-postgresql unlock`;
- the dataset is full: `zfs list zroot/root/postgresql-dumps`.

The alert resolves within a few minutes after the next successful run, once the metric unit has copied the new time.

If `postgresql-backup-metric.service` itself fails, `HostProbeStale` fires for magnetite instead; read its journal.

## Listing snapshots

On the host, as root, the job's wrapper carries the repository, key and password:

```bash
restic-postgresql snapshots
restic-postgresql ls latest
```

For yesterday's data without R2, the previous dump of each database is still on disk as `/var/backup/postgresql-nightly/<db>.prev.sql`, next to the current `<db>.sql`.

## Restoring one database in place

As root on the host, for database `<db>`:

1. Fetch the dump:

   ```bash
   restic-postgresql restore latest --include /var/backup/postgresql-nightly/<db>.sql --target /tmp/r
   ```

   Use a snapshot ID from `restic-postgresql snapshots` instead of `latest` for an older night.
2. Stop the service that owns the database and everything that writes to it, for example `systemctl stop gitea` for `gitea`, `systemctl stop nixbot` for `nixbot`.
3. Drop and reload. The dump recreates the database with its owner and options, so load it while connected to `postgres`:

   ```bash
   sudo -u postgres dropdb '<db>'
   cat /tmp/r/var/backup/postgresql-nightly/<db>.sql | sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d postgres
   ```

   The dump is piped from root because the restored directories are readable by root only.
4. If glibc's collation version changed between the dump and now, `PostgresqlCollationDrift` names the database. Reindex it before starting the service:

   ```bash
   sudo -u postgres psql -d '<db>' -c 'REINDEX DATABASE "<db>"' -c 'ALTER DATABASE "<db>" REFRESH COLLATION VERSION'
   ```

5. Start the services again and `rm -rf /tmp/r`.

### Restoring under a scratch name

To inspect an old copy beside the live database, rename it in the dump before loading. The dump names the database in its `CREATE DATABASE`, `ALTER DATABASE` and `\connect` lines; check them first, since names with a hyphen are quoted:

```bash
grep -n -E '^(CREATE|ALTER) DATABASE|^\\connect' /tmp/r/var/backup/postgresql-nightly/<db>.sql
sed -e 's/^CREATE DATABASE <db> /CREATE DATABASE <db>_restore /' \
    -e 's/^ALTER DATABASE <db> /ALTER DATABASE <db>_restore /' \
    -e 's/^\\connect <db>$/\\connect <db>_restore/' \
    /tmp/r/var/backup/postgresql-nightly/<db>.sql | sudo -u postgres psql -X -v ON_ERROR_STOP=1 -d postgres
```

Drop `<db>_restore` when done.

## Restoring everything onto a rebuilt host

After a reinstall, the services' modules create their databases empty at PostgreSQL's first start, so each must be dropped before its dump recreates it.

1. Deploy the host, then stop every service using PostgreSQL. Leave `postgresql.service` running.
2. Fetch all files: `restic-postgresql restore latest --target /tmp/r`.
3. Load the roles first. `globals.sql` recreates `postgres` and the service roles, which already exist, so expect one `already exists` error per such role; its `ALTER ROLE` lines still set the passwords:

   ```bash
   cat /tmp/r/var/backup/postgresql-nightly/globals.sql | sudo -u postgres psql -X -d postgres
   ```

4. For each database: `sudo -u postgres dropdb '<db>'`, then load its dump as in "Restoring one database in place".
5. Reindex where `PostgresqlCollationDrift` names a database, start the services, and remove `/tmp/r`.

## The off-host drill

This proves that a checkout and the operator's identity are enough to read the backups without magnetite (task 7.4).
Run it on a workstation with magnetite untouched. Nothing secret is written to disk or placed on a command line: the key comes from process substitution, the password from a command restic runs.

```bash
cd vanixiets   # a checkout of main
set -a; source <(clan vars get magnetite postgresql-backup-r2/env); set +a
export RESTIC_PASSWORD_COMMAND="clan vars get magnetite postgresql-backup-restic/password"
export RESTIC_REPOSITORY=s3:https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com/sciexp-postgresql-backup/magnetite
restic() { nix shell nixpkgs#restic -c restic -o s3.bucket-lookup=path -o s3.region=auto "$@"; }
restic snapshots
restic restore latest --target /tmp/drill \
  --include /var/backup/postgresql-nightly/globals.sql \
  --include /var/backup/postgresql-nightly/omnigent.sql
```

Load it into a throwaway PostgreSQL of the same major (16 on magnetite) and count the rows of one table:

```bash
nix shell nixpkgs#postgresql_16 -c bash -euc '
  initdb -U postgres -D /tmp/drill/pg >/dev/null
  pg_ctl -D /tmp/drill/pg -o "-k /tmp/drill -c listen_addresses=" -l /tmp/drill/pg.log start
  psql -X -h /tmp/drill -U postgres -d postgres -f /tmp/drill/var/backup/postgresql-nightly/globals.sql
  psql -X -h /tmp/drill -U postgres -d postgres -v ON_ERROR_STOP=1 -f /tmp/drill/var/backup/postgresql-nightly/omnigent.sql
  psql -X -h /tmp/drill -U postgres -d omnigent -c "SELECT count(*) FROM <table>"
  pg_ctl -D /tmp/drill/pg stop'
rm -rf /tmp/drill
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY RESTIC_PASSWORD_COMMAND
```

Compare the count with the same query on magnetite at the snapshot's time, and record the transcript in the change's `verify.md`.

## Never regenerate postgresql-backup-restic

The repository is encrypted under the password in clan var `postgresql-backup-restic/password`, generated once.
Never run `clan vars generate --regenerate` on that generator, and never let a deploy generate it outside the repository. A new password cannot read the existing repository, so every snapshot taken under the old one becomes unreadable.

If the password is ever lost:
- initialise a new repository under a new prefix in the same bucket;
- keep the old prefix until the new one holds seven nights.

Rotating the R2 key is safe: mint a new token, run `clan vars generate magnetite --generator postgresql-backup-r2 --regenerate`, deploy, and revoke the old token.

## Turning the backup on for a host

The module is off by default (`vanixiets.postgresqlBackup.enable`). Its generators must not exist until their vars are in the repository. `clan machines update` runs every missing generator before it deploys, so an unattended deploy would fail on the hidden prompts or generate the restic password where nobody keeps it. A host waiting for its vars is listed in `flake.lib.postgresqlBackup.awaitingSecrets`, and the machine check accepts it with the backup off.

Before the enable change lands:
1. Create the dump dataset on the host, so its mount does not fail at deploy:

   ```bash
   zfs create -o mountpoint=/var/backup/postgresql-nightly -o com.sun:auto-snapshot=false -o quota=16G zroot/root/postgresql-dumps
   chown postgres: /var/backup/postgresql-nightly && chmod 0700 /var/backup/postgresql-nightly
   ```

2. Apply the bucket: `just terraform-plan -target=cloudflare_r2_bucket.sciexp-postgresql-backup`, check it adds exactly one resource, `just terraform-apply`, and commit the encrypted state.
3. In the Cloudflare dashboard, under R2, Manage R2 API Tokens, create an Account API token:
   - permission: Object Read & Write;
   - scope: the bucket `sciexp-postgresql-backup` only.

The enable change makes four edits together; leaving out any one fails the host's machine check:
1. `vanixiets.postgresqlBackup.enable = true;` in the host's configuration.
2. The host removed from `flake.lib.postgresqlBackup.awaitingSecrets`.
3. The host's `notifiedUnits` in `modules/lib/observability-hosts.nix` gain, sorted with the rest:
   - `restic-backups-postgresql`;
   - `postgresql-dump-globals`;
   - `postgresqlBackup-<db>` for each backed-up database;
   - on magnetite, `zfs-assert-root-postgresql-dumps-noautosnap` and `zfs-set-root-postgresql-dumps-quota`.
4. The generated vars under `vars/per-machine/<host>/postgresql-backup-r2/` and `vars/per-machine/<host>/postgresql-backup-restic/`.

Generate the vars in a private clone of the enable change, not in a working copy that agents or deploys share:

```bash
clan vars generate <host> --generator postgresql-backup-r2
clan vars generate <host> --generator postgresql-backup-restic
clan vars get <host> postgresql-backup-restic/password | wc -c
```

The first command asks for two hidden values, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, the token's access key ID and secret access key. Enter them only at those prompts. The second asks nothing. The last prints `44` without printing the password.

After the enable change deploys:
- start `restic-backups-postgresql.service` once by hand and watch its journal;
- check that `restic-postgresql snapshots` lists the dumps and `globals.sql`;
- check that the series for the host appears in the `fleet` database.

## Changing the module

Rerun the restore test and its mutant on a builder with `uid-range` (magnetite) after every change to `modules/nixos/postgresql-backup.nix`:

```bash
nix-fast-build --remote magnetite.zt --skip-cached --no-download --flake .#vmTests.x86_64-linux.postgresql-backup-restore
nix-fast-build --remote magnetite.zt --skip-cached --no-download --flake .#vmTests.x86_64-linux.postgresql-backup-restore.prepareStartsNoDumps
```

`vmTests.x86_64-linux.postgresql-backup-restore` drops two databases and a role and restores them from the job's own snapshot. Its mutant, a job whose prepare step starts no dumps, must fail on the sentinel row.
