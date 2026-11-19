# Apply evidence: back-up-postgresql-off-host

Recorded during apply on 2026-11-19 (chain `ylqkynyz`). Builds ran on magnetite with `nix-fast-build --remote magnetite.zt --skip-cached --no-download`. The evaluations ran locally on stibnite (x86_64-linux configurations, evaluated only).

## 1.2 Fixture check

- Red: before `flake.lib.postgresqlBackupObligations` existed, evaluating `checks.x86_64-linux.postgresql-backup-obligations` failed with `attribute 'postgresqlBackupObligations' missing`.
- Green: `checks.x86_64-linux.postgresql-backup-obligations` builds.
- Mutant: with `compressed` expecting 0 problems, evaluation failed with `postgresql-backup-obligations: the judge misjudges compressed`.

## 1.3 Machine check

- Red: with `awaitingSecrets = [ ]`, `nix eval .#checks.x86_64-linux.nixos-magnetite.drvPath` failed with `postgresqlBackupObligations [PostgreSQL runs without vanixiets.postgresqlBackup.enable, and the host is not in flake.lib.postgresqlBackup.awaitingSecrets]`.
- Green: with magnetite awaiting, `nixos-magnetite`, `nixos-cinnabar` and `darwin-stibnite` evaluate. `failures "magnetite"` and `failures "cinnabar"` are `[ ]`.

## 1.4 and 2.2 Evaluated facts

Magnetite was extended with `vanixiets.postgresqlBackup.enable = true`:
- `databases`: `matrix-synapse gitea-mq omnigent nixbot niks3 gitea`; `compression`: `none`.
- `paths`: those six `.sql` files and `globals.sql` under `/var/backup/postgresql-nightly`.
- No `postgresqlBackup-*` timer.
- `restic-backups-postgresql` `timerConfig`: `OnCalendar = *-*-* 02:30:00`, `RandomizedDelaySec = 15m`, `Persistent = true`.
- `pruneOpts`: `--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --group-by host`; `checkOpts`: `--read-data-subset=10%`.
- `repository`: `…/sciexp-postgresql-backup/magnetite`.
- `textfileWriters`: `magnetite-memory-budget postgresql-backup`. One `--collector.textfile.directory` flag, on `/run/node-exporter-textfile`. No failing assertion.
- The `root/postgresql-dumps` options are `mountpoint=/var/backup/postgresql-nightly`, `com.sun:auto-snapshot=false` and `quota=16G`. Both dataset oneshots are `oneshot`. `fileSystems."/var/backup/postgresql-nightly"` exists.

Magnetite as committed has no `postgresql-backup*` generator, no `root/postgresql-dumps` dataset, no dataset oneshot and no `/var/backup/postgresql-nightly` mount. cinnabar has no `restic-backups-postgresql`.

`services.zfs.autoSnapshot` on magnetite: hourly 4, daily 3, weekly 1 (2.3, evaluated part).

## 1.6 Mutants of magnetite with the backup on

The judge read `factsOf` with `awaiting = false`, `secretsGenerated = true` and the 1.5 notified units:
- as configured: `[ ]`;
- `nixbot` removed with `mkForce`: `database nixbot is not in services.postgresqlBackup.databases`;
- `startAt` set: one `postgresqlBackup-<db> has a timer of its own` per dump unit (6);
- `scratch` added to `ensureDatabases`: `postgresqlBackup-scratch is not in the host's notifiedUnits`;
- `scratch` added and parked: `[ ]`;
- the backup on without the vars (real `secretsGenerated`): the single message that the vars of both generators are not in the repository.

## 3.1–3.3 fleet-alert

- `checks.x86_64-linux.fleet-alert` builds, including `promtoolRehearsal` and `fixtureRehearsal`. promtool's log shows `SUCCESS: 18 rules found` and `mutant staleThreshold rejected`.
- Red, rule absent: with the rule renamed, evaluation of the check fails with `fleet-alert check: no rule PostgresqlBackupStale`.
- Red, leg expectation: with the leg expecting `no-such-runbook.md`, its derivation failed with `no posted message carries: no-such-runbook.md`.

## 4.1 Bucket

The `config.tf.json` derivation of `packages.x86_64-linux.terraform` has `cloudflare_r2_bucket.sciexp-postgresql-backup` with `location = enam` and `lifecycle.prevent_destroy = true`. `cloudflare_r2_bucket_lifecycle` holds only `sciexp`. The plan and apply are the operator's (4.2).

## 5.1–5.2 Restore test

- `vmTests.x86_64-linux.postgresql-backup-restore` passes on magnetite (nspawn container, uid-range):
  - recorded row counts `{'alpha': '501', 'beta': '300'}`, restored `{'alpha': '501', 'beta': '300'}`;
  - the sentinel and role `app` were restored, and `alpha` is owned by `app`;
  - the snapshot paths are `alpha.sql`, `beta.sql` and `globals.sql`;
  - both `backup.prom` and the published `postgresql-backup.prom` hold `1795113857`, after the test's start.
- `vmTests.x86_64-linux.postgresql-backup-restore.prepareStartsNoDumps` builds. The mutant's own run failed with `AssertionError: sentinel missing: the snapshot holds a dump older than the backup run`, with restored `alpha` at 500 rows against 501 recorded.
