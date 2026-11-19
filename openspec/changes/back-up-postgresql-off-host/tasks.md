## 1. Module and regulators (red first)

Owner files: `modules/nixos/postgresql-backup.nix` (new), `modules/checks/postgresql-backup-obligations.nix` (new), `modules/checks/machines.nix`, `modules/lib/observability-hosts.nix`, `modules/clan/services/otel-collector/schema.nix`. Builds on chain `zqpxwylx`, which supplies `vanixiets.postgresqlCollation.parkedDatabases` and touches the same `schema.nix` list region and `observability-hosts.nix`. Sequential within the group.

- [ ] 1.1 In `modules/nixos/postgresql-backup.nix`, add `flake.lib.postgresqlBackup` with `location = "/var/backup/postgresql-nightly"`, `jobName = "postgresql"`, `metricsDirectory = "/var/lib/postgresql-backup-metrics"` and `seriesName = "vanixiets_postgresql_backup_last_success_timestamp_seconds"`. Add `flake.lib.postgresqlBackupObligations` with the pure judge `problems` and `failures name hostConfig` of design D15. `failures` returns `[ ]` when `services.postgresql.enable` is false, and otherwise reads the evaluated `ensureDatabases`, `parkedDatabases`, `postgresqlBackup`, the `postgresqlBackup-*`/`postgresql-dump-globals` units, `services.restic.backups.postgresql` and `flake.lib.observabilityHosts.<name>.notifiedUnits` — verify: `nix eval .#lib.postgresqlBackup.seriesName` prints the name; the judge's behaviour is verified by 1.2, and `failures` on real hosts by 1.3 and 1.5
- [ ] 1.2 Add `modules/checks/postgresql-backup-obligations.nix` defining `checks.x86_64-linux.postgresql-backup-obligations`, gated on `system == "x86_64-linux"`, over literal fixtures. An accepted configuration and a parked database left out each give 0 problems. Mutants missingDatabase, dumpTimer, compressed, pathMissing, prepareMissing and unitNotNotified give exactly 1 problem each, and each mutant runs only its own case — verify: before 1.1 lands, evaluation fails on the missing `postgresqlBackupObligations` (red, recorded); after, `nix build .#checks.x86_64-linux.postgresql-backup-obligations` succeeds; changing one mutant's expected count to 0 fails the build naming that case
- [ ] 1.3 Assert `postgresqlBackupObligations.failures` in `withFleetObligations` in `modules/checks/machines.nix`, listed in its message beside the other obligations — verify: with the judge in place and before 1.4, `nix eval .#checks.x86_64-linux.nixos-magnetite.drvPath` fails naming `postgresqlBackupObligations` and each of the six databases (red, recorded in `verify.md`); `nixos-cinnabar` still evaluates
- [ ] 1.4 Implement `flake.modules.nixos.postgresql-backup` in the same file and import it from `flake.modules.nixos.base`. Under `mkIf services.postgresql.enable` it sets:
  - `services.postgresqlBackup` per D3: the backup set, `compression = "none"`, `startAt = [ ]`, `location`.
  - `postgresql-dump-globals.service`: oneshot as `postgres`, `pg_dumpall --globals-only` to `globals.sql` through an `.in-progress` file, `umask 0077`, `requires`/`after` `postgresql.target`.
  - `services.restic.backups.postgresql` per D4, D6 and D7. Its `backupPrepareCommand` runs `systemctl start --wait` over every dump unit and exits non-zero on any failure, and `ExecStartPost` writes the series to `<metricsDirectory>/backup.prom`.
  - `postgresql-backup-metric-seed.service` per D11.
  - `systemd.tmpfiles` for `metricsDirectory` (0755).
  - node_exporter's `--collector.textfile` and `--collector.textfile.directory=<metricsDirectory>` flags, with an assertion in the collation probe's form that the flags and the keep-list entry are present.
  - The vars generators `postgresql-backup-r2` and `postgresql-backup-restic` per D8.
  - Add `seriesName` to `nodeExporterKeep`, and `restic-backups-*.service`, `postgresqlBackup-*.service` and `postgresql-dump-globals.service` to `memoryBudgetUnits`, in `schema.nix`.

  — verify: `nix eval --json .#nixosConfigurations.magnetite.config.services.postgresqlBackup.databases` lists the six databases; `…services.restic.backups.postgresql.paths` lists six `.sql` files and `globals.sql`; `…systemd.timers` has no `postgresqlBackup-*` key and has `restic-backups-postgresql`; `…services.restic.backups.postgresql.pruneOpts` and `.checkOpts` match D7; `nix eval` of `nixosConfigurations.cinnabar.config.systemd.services ? restic-backups-postgresql` is `false`
- [ ] 1.5 Add to magnetite's `notifiedUnits` in `modules/lib/observability-hosts.nix`:
  - `restic-backups-postgresql`;
  - `postgresql-dump-globals`;
  - `postgresqlBackup-gitea`, `postgresqlBackup-gitea-mq`, `postgresqlBackup-matrix-synapse`, `postgresqlBackup-niks3`, `postgresqlBackup-nixbot`, `postgresqlBackup-omnigent`;
  - `zfs-assert-root-postgresql-dumps-noautosnap` and `zfs-set-root-postgresql-dumps-quota` (group 2's units).

  Keep the list sorted.

  — verify: `nix build .#checks.x86_64-linux.nixos-magnetite` succeeds (green); `checks.x86_64-linux.fleet-alert` and `otel-envelope` build; `flake.lib.postgresqlBackupObligations.failures "magnetite" …` is `[ ]`
- [ ] 1.6 Verify regression protection with `extendModules` mutants of magnetite's real configuration, leaving the tree untouched:
  - removing `nixbot` from `services.postgresqlBackup.databases` (`mkForce`);
  - setting `startAt` on the dumps;
  - adding a database to `ensureDatabases` without changing anything else;
  - parking that database through `parkedDatabases`.

  — verify: the first three return one problem each naming the cause; the fourth returns `[ ]`; recorded in `verify.md`

## 2. Dump dataset on magnetite

Owner files: `modules/machines/nixos/magnetite/disko.nix`, `modules/machines/nixos/magnetite/default.nix`. Runs in parallel with group 1. 2.1 is the operator's.

- [ ] 2.1 (operator, by hand) On magnetite: `zfs create -o mountpoint=/var/backup/postgresql-nightly -o com.sun:auto-snapshot=false -o quota=16G zroot/root/postgresql-dumps`, then `chown postgres: /var/backup/postgresql-nightly && chmod 0700 /var/backup/postgresql-nightly` — verify: `zfs get -H -o property,value mountpoint,com.sun:auto-snapshot,quota zroot/root/postgresql-dumps` shows the three values; recorded in `verify.md`
- [ ] 2.2 Declare `root/postgresql-dumps` in `disko.nix` with the comment that it was created by hand (the `root/greptimedb` form). In `default.nix`, add `zfs-assert-root-postgresql-dumps-noautosnap` and `zfs-set-root-postgresql-dumps-quota` oneshots in the existing sibling form — verify: `nix eval .#nixosConfigurations.magnetite.config.disko.devices.zpool.zroot.datasets."root/postgresql-dumps".options` shows the properties; `nix eval` of both units' `serviceConfig.Type` is `"oneshot"`; `nixos-magnetite` builds
- [ ] 2.3 Confirm local rollback is unchanged: `services.zfs.autoSnapshot` keeps hourly 4, daily 3, weekly 1, and `root/nixos` (which holds `/var/lib/postgresql`) keeps auto-snapshot on — verify: `nix eval --json .#nixosConfigurations.magnetite.config.services.zfs.autoSnapshot` matches; after the deploy in 7.1, `zfs get -H com.sun:auto-snapshot zroot/root/nixos` is `true` and `zfs list -t snapshot zroot/root/postgresql-dumps` is empty

## 3. Staleness alert

Owner files: `modules/nixos/fleet-alert/rules.nix`, `modules/checks/fleet-alert.nix` (and its `fleet-alert/fixtures/series.json` if the fixture case needs it). It depends on chain `zqpxwylx`, whose collation rule and test edit the same files, and on the series name contract in `flake.lib.postgresqlBackup.seriesName`, not on group 1's module. Runs in parallel with groups 1, 2, 4, 5 and 6.

- [ ] 3.1 Add `PostgresqlBackupStale` to `rules.nix` per D11. The comment names the seed and the runbook. The annotation names the runbook path — verify: the `rules.yaml` rendered by `checks.x86_64-linux.fleet-alert`'s promtool pass contains the rule with `for: 600` seconds in the evaluator's JSON and passes `promtool check rules`
- [ ] 3.2 Add a promtool case in `modules/checks/fleet-alert.nix`, in `collationDriftTest`'s form. Over 41 h at 1 h steps, a series whose value (a success time) stops advancing at hour 2 must not fire at hour 38 (exactly 36 h stale), must be pending at hour 39, and must fire one alert for magnetite at hour 40. A series that advances every 24 h must never fire. The mutant `staleThreshold` (`> 129600` → `> 1296000`) must fail the test — verify: `nix build .#checks.x86_64-linux.fleet-alert` passes; the build log shows "mutant staleThreshold rejected"
- [ ] 3.3 Add a fixtureRehearsal case: the rule's expression answering one stale series for magnetite posts one warning whose title names magnetite and whose message names the runbook — verify: `nix build .#checks.x86_64-linux.fleet-alert` passes; before the rule exists the case fails with no post (red, recorded)

## 4. Backup bucket and secrets

Owner file: `modules/terranix/cloudflare.nix`. 4.2 and 4.3 are the operator's. Runs in parallel with groups 1, 2, 3, 5 and 6, and must finish before 7.1.

- [ ] 4.1 Add `resource.cloudflare_r2_bucket.sciexp-postgresql-backup` (`location = "enam"`, `lifecycle.prevent_destroy = true`) with a comment that restic owns every deletion in it, so no age-based lifecycle rule may be added (D7, A163) — verify: `nix build .#terraform` (or the terranix config's `config.tf.json`) contains the resource; `nix run .#terraform -- plan` (operator) shows exactly one resource to add
- [ ] 4.2 (operator, by hand) Apply the plan. In the Cloudflare dashboard, mint an Account API token with Object Read & Write on `sciexp-postgresql-backup` only. Then run `clan vars generate magnetite --generator postgresql-backup-r2` with its access key ID and secret — verify: `vars/per-machine/magnetite/postgresql-backup-r2/env/secret` exists; the bucket lists in the dashboard; the token's scope shows the one bucket
- [ ] 4.3 (operator) `clan vars generate magnetite --generator postgresql-backup-restic` — verify: `vars/per-machine/magnetite/postgresql-backup-restic/password/secret` exists; `clan vars get magnetite postgresql-backup-restic/password` prints a value on the operator's workstation

## 5. Restore test

Owner file: `modules/vm-tests/postgresql-backup-restore.nix` (new). It can be written in parallel with group 1 against the D12 contract, but it builds only once 1.4 has landed. It runs on a builder with `uid-range` (magnetite, as devloop-ingest does).

- [ ] 5.1 Add `vmTests.x86_64-linux.postgresql-backup-restore` per D12: one nspawn container importing `flake.modules.nixos.postgresql-backup`, using magnetite's PostgreSQL package, two databases and one role, with the repository overridden to `/var/lib/restic-test` and the password and environment files taken from the test. The header comment says what the test establishes and what it does not (R2, the real secrets, the real timer) — verify: `nix build .#vmTests.x86_64-linux.postgresql-backup-restore` passes; its log shows the recorded and restored row counts equal, the sentinel present, the role restored, and the snapshot's paths
- [ ] 5.2 Mutant: a variant of the node whose `backupPrepareCommand` starts no dumps (the dump-after-backup bug) must fail on the sentinel assertion, and runs only that case — verify: the mutant's build fails with the sentinel message; recorded in `verify.md`
- [ ] 5.3 State in the module's header that `vmTests.x86_64-linux.postgresql-backup-restore` is rerun on every change to the module, and add that rerun to the module's README entry or the runbook's maintenance section — verify: `rg -n "postgresql-backup-restore" modules/nixos/postgresql-backup.nix packages/docs` finds both

## 6. Restore runbook

Owner files: `packages/docs/src/content/docs/development/operations/postgresql-backup.md` (new) and the operations index that lists its siblings. Runs in parallel with every other group.

- [ ] 6.1 Write the runbook per D13. It covers:
  - what is and is not backed up, including the file state left out (open question 1);
  - listing snapshots with `restic-postgresql snapshots`;
  - restoring one database in place: stop its service and its dependants, `dropdb`, `restic-postgresql restore latest --include /var/backup/postgresql-nightly/<db>.sql --target /tmp/r`, `psql -f`, the F61 reindex if needed, then start;
  - restoring all onto a rebuilt host, globals first;
  - restoring from a workstation without magnetite;
  - restoring under a scratch name;
  - never regenerating `postgresql-backup-restic`;
  - what `PostgresqlBackupStale` and the unit notices mean.

  — verify: the docs site builds (`nix build .#docs` or the package's check); every command in it is run at least once in 7.1 or 7.4, and the drill's transcript is recorded

## 7. Integration Verification

Sequential, after groups 1 to 6 have merged and 2.1, 4.2 and 4.3 are done. Each deploy reads every alert posted since it started from fleet-alert's journal on magnetite and records each one with its cause.

- [ ] 7.1 Deploy magnetite. Start `restic-backups-postgresql.service` by hand and watch the journal — verify:
  - each `postgresqlBackup-*` and `postgresql-dump-globals` unit ran inside the job's start;
  - `restic-postgresql snapshots` lists one snapshot whose paths are the six dumps and `globals.sql`;
  - `/var/lib/postgresql-backup-metrics/backup.prom` holds the run's time, and the series for magnetite is in the `fleet` database within one interval;
  - `systemctl list-timers` shows only the restic timer;
  - every alert since the deploy is recorded.
- [ ] 7.2 After the first scheduled night — verify:
  - a second snapshot was taken by the timer between 02:30 and 02:45;
  - the units' `MemoryPeak` appears in the memory-budget series (CAM-111), with the peak and the run's duration recorded;
  - no alert fired except as recorded.
- [ ] 7.3 After eight nights — verify:
  - `restic-postgresql snapshots` shows at most 7 daily plus the weekly survivors, and the job's journal shows `forget --prune` removing the eighth day;
  - `check --read-data-subset=10%` reports no errors on each night;
  - the bucket's size in the dashboard is recorded, a few GB at most;
  - no lifecycle rule exists on the bucket.
- [ ] 7.4 Off-host drill, on stibnite with magnetite untouched and using only a checkout and the operator's identity: `clan vars get` the env and password, then `nix shell nixpkgs#restic` and `restic -o s3.bucket-lookup=path -o s3.region=auto -r s3:…/sciexp-postgresql-backup/magnetite restore latest --include …/omnigent.sql`. Load it into a local throwaway PostgreSQL 16 and count rows in one table. Compare with the count on magnetite at the snapshot's time (A162) — verify: the counts match, and the transcript is in `verify.md`
- [ ] 7.5 Verify both reporting paths end to end, in a window the operator picks:
  - `systemctl show -p OnFailure restic-backups-postgresql postgresqlBackup-niks3` names `observability-notify@`, and `systemctl start observability-notify@restic-backups-postgresql.service` delivers a notice to the operator's device.
  - Writing a timestamp 37 h old into `backup.prom` makes `PostgresqlBackupStale magnetite` reach the operator within 15 min. Starting the job then resolves it.

  — verify: both posts and the resolve are seen and recorded with their causes
- [ ] 7.6 Close-out: the change adds no migration flag. The seed's `ConditionPathExists` is permanent behaviour, not a migration branch. The one by-hand dataset creation is recorded in `disko.nix`'s comment. Ask the operator whether tonight's manual dumps in `/var/backup/postgresql/pre-reindex-20261119T0031Z/` can now be deleted, and record the answer — verify: the answer recorded in `verify.md`
