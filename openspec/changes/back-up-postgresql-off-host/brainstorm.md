<!--
Raw capture of the brainstorming for this change.
The exploration was the PostgresBackupSurvey research report (2026-11-19, ten clan and NixOS fleets surveyed) and the operator's answers to Q50-Q53 the same day; this file records that decision chain as it happened.
-->

# Brainstorm: back up PostgreSQL off the host

## Background

magnetite runs PostgreSQL 16.16 for six services, whose databases the configuration creates (`services.postgresql.ensureDatabases`, evaluated 2026-11-19): `matrix-synapse`, `gitea-mq`, `omnigent`, `nixbot`, `niks3` (1.2 GB) and `gitea`; nixbot is 257 MB.
cognee's database also exists on disk but cognee is parked, its module is off and its database is unreadable without pgvector (F63), so it is not in that list.

Nothing backs these databases up.
The only copies are:
- ZFS auto-snapshots of the root dataset that holds `/var/lib/postgresql` (`magnetite/default.nix:200-206`: hourly 4, daily 3, weekly 1), on the same pool and disk (`disko.nix:43-50`). They are crash-consistent [INFERENCE: PGDATA and pg_wal share one dataset] and are lost with the disk.
- One `pg_dump` of omnigent that its deploy workflow takes before each deploy (the `deploy-omnigent` Atomic workflow, since removed with the atomic 0.10.3 bump).
- The manual dumps the orchestrator took tonight before reindexing every database for the glibc collation change, in `/var/backup/postgresql/pre-reindex-20261119T0031Z/`.

Losing magnetite's disk today loses every service's state.

## What the survey found

- Every surveyed fleet backs PostgreSQL up the same way: a nightly logical dump to local disk, shipped off the host by a file-backup tool. Nobody runs WAL archiving or PITR.
- clan-core's built-in path is `clan.core.postgresql.databases.<db>`, which adds `clan.core.state` hooks (`pg_dump -Fc --compress=zstd`, and a restore hook that drops and recreates the database). The hooks run only when the backup provider calls them, and the only provider clan ships is borg over SSH. clan has no restic or S3 provider. `clan.core.postgresql` also takes over database creation in `postgresql.postStart`.
- The timing bug: in clan-infra and Mic92's configs the dump timer (01:15) fires after the backup timer (00:00 or 01:00), so each night's archive carries the previous night's dump. jfly avoids it by starting the dump from restic's `backupPrepareCommand`.
- pinpox alerts when restic's last success is more than 36 h old or absent; jfly at 2 days.
- clan-core's NixOS test `service-postgresql` is the only automated restore test found: dump, back up, drop, restore, compare.
- nixpkgs' `services.pgbackrest` sets `archive_command`, keeps S3 keys out of options, needs group access on the data directory (fresh initdb only), and is tested only against posix and sftp repositories.
- `clan.core.backups.providers` has no type restriction, so a restic provider could be declared; no surveyed repository does.

## Decision chain

**Q50 (operator, 2026-11-19): recovery point.**
Up to 24 h of loss is acceptable. No WAL archiving or PITR now. pgBackRest with continuous WAL to R2 stays a later option for a database that proves it needs it.
Why not now: a continuous archive whose `archive_command` fails keeps every WAL segment in `pg_wal` until archiving succeeds, so an R2 outage or a revoked key fills the database's disk and stops every service on the host. That failure mode needs its own alert and runbook before it is worth taking on.

**Q51 (operator): destination.**
Cloudflare R2 through restic, with a new R2 token scoped to a dedicated backup bucket, held as a clan var and separate from niks3's token. Not a Hetzner Storage Box.
Consequence: the clan borg path is out, because borg needs SSH.

**Q52 (operator): cognee.**
Skip it while parked. Its revival note covers backup.
Consequence: the backup set is the configuration's database list, which already omits cognee while it is off; reviving cognee puts it back in the list and so in the backup set.

**Q53 (operator): its own OpenSpec change and a new Linear story.**

## Forks decided in design (agent, for operator review at Gate 1)

1. Dumps: nixpkgs `services.postgresqlBackup` with `compression = "none"` and no timer of its own, plus a globals-only dump of roles, over `clan.core.postgresql`. The clan module's hooks need a provider to call them (we would be writing that provider), its dumps are compressed custom format that dedups poorly, and it takes over database creation from the six upstream modules that already create their databases.
2. The restic job starts every dump unit in its prepare step, so a night's snapshot always holds that night's dumps and a failed dump fails the job.
3. Dumps go to a dedicated ZFS dataset with auto-snapshot off. On the root dataset each nightly rewrite of ~1.5 GB would be pinned by the daily and weekly snapshots.
4. restic paths are the dump files by name, not the directory, so tonight's manual pre-reindex dumps and the `.prev` rotation are not uploaded.
5. Retention `--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --group-by host`; `--group-by host` keeps one retention group when the database list changes.
6. Monitoring: the backup and dump units are notified on failure, and a staleness alert fires at 36 h on a success timestamp written to node_exporter's textfile collector (the collation probe's mechanism). A seed at first activation makes "never succeeded" age like a stale success.
7. Restore test: a NixOS container test (nspawn, the devloop-ingest pattern) that uses the real module. A sentinel row is inserted after an older dump exists and before the restic job starts, so the dump-after-backup bug fails it.
8. Provider for `clan backups`: not now. Its restore hook expects clan's custom-format dumps and drops the live database; a hand-written provider would be the only one of its kind and untested. The runbook uses the `restic-postgresql` wrapper instead.
9. Bucket: terranix declares `sciexp-postgresql-backup` with the same resource the other buckets use. The token is minted by hand like the existing three R2 tokens. The pinned provider (5.27.0) can mint tokens, but only if the terraform credential can mint any token, and the result would still have to be copied into clan vars by hand.
10. Regulators: a fleet obligation on every `nixos-<host>` check, judging the evaluated configuration of any host that runs PostgreSQL, plus a fixture check with one mutant per failure.

## Relation to other work

- CAM-111 (magnetite's memory budget): the nightly dumps and restic compete with nixbot's evaluations for magnetite's memory, so their units join `memoryBudgetUnits`. Related, not blocking.
- CAM-113 (store garbage collection): no shared mechanism. Not related.
- F61 collation drift (chain `zqpxwylx`): supplies `vanixiets.postgresqlCollation.parkedDatabases`, which the backup set honours, and the textfile collector pattern. This change builds on that chain.
