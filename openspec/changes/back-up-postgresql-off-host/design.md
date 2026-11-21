## Context

On magnetite, PostgreSQL 16.16 holds the state of six services. Their databases are the configuration's `services.postgresql.ensureDatabases`, evaluated 2026-11-19 as `["matrix-synapse","gitea-mq","omnigent","nixbot","niks3","gitea"]`:
- niks3 and nixbot add theirs through `database.createLocally` (`modules/nixos/niks3.nix:84`, `nixbot.nix:248`);
- gitea through its module's `database.createDatabase` default;
- gitea-mq, matrix-synapse and omnigent list theirs directly (`gitea-mq.nix:98`, `matrix.nix:365`, `omnigent.nix:71`).

cognee's database exists on disk, but cognee is parked (`vanixiets.cognee.enable = false`), so its module adds nothing. Chain `zqpxwylx` (F61) declares it in `vanixiets.postgresqlCollation.parkedDatabases`. No other NixOS host enables PostgreSQL (evaluated for cinnabar, pyrite, electrum, galena and scheelite).

What protects the data today:
- ZFS auto-snapshots of `zroot/root/nixos`, which holds `/var/lib/postgresql` (`magnetite/default.nix:200-206`, `disko.nix:43-50`).
- One pre-deploy omnigent dump, taken by the `deploy-omnigent` Atomic workflow before each deploy. That workflow was removed with the atomic 0.10.3 bump (atomic 0.10.0 dropped workflows), so no deploy takes this dump any more.
- Tonight's manual dumps in `/var/backup/postgresql/pre-reindex-20261119T0031Z/`.

What the fleet already has:
- R2, through three hand-minted tokens held as clan vars: `niks3-s3`, `omnigraph-r2` and `greptimedb-r2`, the last two as `EnvironmentFile`s (`magnetite/default.nix:405-443,589-627`). The account endpoint is `https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com`.
- terranix declaring R2 buckets with `cloudflare_r2_bucket` (`modules/terranix/cloudflare.nix`; provider 5.27.0; state encrypted and committed).
- Failure notices for units listed in a host's `notifiedUnits` (`modules/lib/observability-hosts.nix`).
- fleet-alert rules with promtool and fixture cases (`modules/nixos/fleet-alert/rules.nix`, `modules/checks/fleet-alert.nix`).
- A textfile-collector probe pattern, `modules/nixos/postgresql-collation.nix` on chain `zqpxwylx`. node_exporter refuses a repeated `--collector.textfile.directory` flag (F75), so every textfile writer names itself in `vanixiets.nodeExporter.textfileWriters` and writes its own file into the host's one `vanixiets.nodeExporter.textfileDirectory` (`modules/nixos/node-exporter-textfile.nix`); each series must be in `nodeExporterKeep`.
- Fleet obligations asserted on every machine check (`modules/checks/machines.nix`, `withFleetObligations`).

The nixpkgs modules at the pinned revision behave as follows:
- `services.postgresqlBackup` creates one oneshot `postgresqlBackup-<db>` per database. Each runs `pg_dump -C <db>` as `postgres`, writes `<location>/<db>.sql` through an `.in-progress` file, and keeps one `.prev`. It gets a timer only when `startAt` is non-empty.
- `services.restic.backups.<name>` creates `restic-backups-<name>` (oneshot, root). Its `preStart` runs `backupPrepareCommand` and, with `initialize`, `restic init`. ExecStart runs `backup`, then `forget --prune <pruneOpts>`, then `check <checkOpts>`. It has `extraOptions` (`-o`), `environmentFile`, `passwordFile`, `createWrapper` and `timerConfig`.

The research survey (agent `PostgresBackupSurvey`, 2026-11-19) and the operator's Q50 to Q53 are recorded in `brainstorm.md`.

Stakeholders:
- the operator, who restores, holds the secrets and pays for R2;
- the services' users, who would lose accounts, chat history, CI and queue history and cache metadata;
- nixbot's evaluations, which share magnetite's memory with the nightly job (CAM-111).

## Goals / Non-Goals

**Goals:**
- Every night, every unparked database on a PostgreSQL host, and its roles, reach an off-host copy taken that night.
- A failed run, and 36 h without a successful one, each reach the operator.
- A restore is proven by an automated test against the real module, and the operator can restore from a workstation using only the repository and its vars.
- A host that adds a database without backing it up fails its machine check before deploy, at no added evaluation cost.

**Non-Goals:**
- Point-in-time recovery, WAL archiving, pgBackRest (D1).
- State outside PostgreSQL: gitea's repositories and LFS objects, synapse's media store and signing key, niks3's NARs (already in R2), and the services' clan vars (already in the repository). A follow-up change can extend restic's paths to these (open question 1).
- Backing up cognee while it is parked (D2).
- A `clan backups` provider (D14).
- Protecting backups from a compromised magnetite, for example with object lock or append-only storage (open question 3).
- Backups for non-PostgreSQL hosts.

## Decisions

### D1: Recovery point up to 24 h; no WAL archiving now (operator Q50)
- **Choice**: Nightly logical dumps only.
- **Rationale**: 24 h of loss is acceptable for these services. A continuous archive would add a failure mode that takes the host down. When `archive_command` fails, PostgreSQL keeps every WAL segment in `pg_wal` until archiving succeeds (A164), so an R2 outage or a revoked token fills `zroot/root/nixos` and stops every service on magnetite. Taking that on needs its own alert on archiver failure and its own runbook. nixpkgs' `services.pgbackrest` also needs group access on the existing data directory (fresh `initdb` only), and its S3 path is untested upstream.
- **Later option**: pgBackRest with `repo1-type=s3` to R2, for a database that proves it needs PITR, in its own change.
- **Alternatives considered**: pgBackRest now; ZFS send (R2 cannot receive it, and no second ZFS host exists).

### D2: Skip parked services' databases (operator Q52)
- **Choice**: The backup set is `ensureDatabases` minus `vanixiets.postgresqlCollation.parkedDatabases`.
- **Rationale**: A parked service's module adds nothing to `ensureDatabases`, so its database is already absent. Subtracting the parked list as well keeps the backup and the collation probe in agreement if a parked service's database is ever still declared. Reviving cognee adds its database to `ensureDatabases`, and the obligation (D15) then fails magnetite's check unless the database is backed up. The revival note is enforced, not just remembered.
- **Boundary**: first-party; one parked list for both probes, not a second convention.

### D3: nixpkgs `services.postgresqlBackup`, uncompressed, with no timer of its own
- **Choice**: A first-party module `flake.modules.nixos.postgresql-backup` in `modules/nixos/postgresql-backup.nix`. Every NixOS base imports it, and it acts only where `vanixiets.postgresqlBackup.enable` (D16) and `services.postgresql.enable` are both set. It sets:
  - `services.postgresqlBackup.enable = true`;
  - `databases` = the backup set (D2);
  - `compression = "none"`;
  - `startAt = [ ]`;
  - `location` = `flake.lib.postgresqlBackup.location` (`/var/backup/postgresql-nightly`).

  It keeps `pgdumpOptions = "-C"`, so each dump recreates its database.
- **Rationale**:
  - Uncompressed SQL lets restic deduplicate unchanged rows across nights and compress them itself.
  - `-C` makes a dump self-contained for restore (A161).
  - `startAt = [ ]` removes the dump timers, so the backup job is the only thing that dumps (D4).
- **Boundary**: vendored-versus-first-party. We set upstream options and never copy upstream's script, so a nixpkgs change to the dump script still applies. The obligation judges the evaluated units, not our option values.
- **Alternatives considered**:
  - `clan.core.postgresql` state hooks. They run only if a backup provider calls them, and clan ships only borg (D14). Its `-Fc --compress=zstd` dumps dedup poorly. It takes over database creation in `postgresql.postStart`: for the six databases upstream modules already create, every entry would need `create.enable = false`, or two mechanisms would create the same database with different owners and options.
  - `backupAll` (`pg_dumpall`). One file means one failure loses every database's copy, and restoring one database means editing a dump of all of them.
  - gzip or zstd `--rsyncable`. Dedups worse than none, and restic compresses anyway.

### D4: The backup job starts the dumps
- **Choice**: `services.restic.backups.postgresql.backupPrepareCommand` runs `systemctl start --wait` over every `postgresqlBackup-<db>.service` and `postgresql-dump-globals.service`. It exits non-zero if any start fails.
- **Rationale**: This removes the dump-after-backup timing bug the survey found in clan-infra and Mic92's configs, where each archive carried the previous night's dump. Starting the dumps through their own units keeps one failure notice per failing database (D10). A failed dump fails the prepare step, so restic never uploads a stale dump as tonight's.
- **Alternatives considered**:
  - Ordering the restic timer after the dump timers. A missed dump still leaves restic uploading an old file.
  - `restic backup --stdin-from-command` per database. This needs one restic job per database, and the jobs would contend for the repository lock with each job's prune.

### D5: Dumps on a dedicated dataset with auto-snapshot off
- **Choice**: The dataset is `zroot/root/postgresql-dumps`, mounted at `/var/backup/postgresql-nightly`, with `com.sun:auto-snapshot=false` and `quota=16G`. It is declared in `disko.nix` and created by hand on the installed host, as `root/greptimedb` was. It is kept by `zfs-assert-root-postgresql-dumps-noautosnap` and `zfs-set-root-postgresql-dumps-quota` oneshots in magnetite's `default.nix`, which join its `notifiedUnits` like their siblings. The declaration and both oneshots exist only while `vanixiets.postgresqlBackup.enable` is set (D16), so the mount and the `zfs set` units never come before the dataset.
- **Rationale**:
  - Each nightly rewrite of ~1.5 GB on the root dataset would be pinned by up to three daily and one weekly snapshot, about 6 GB more on the disk with no recovery value, since restic already keeps every night's copy (A165).
  - The quota bounds a runaway dump.
  - The path is new, so the manual dumps in `/var/backup/postgresql/` are neither shadowed nor uploaded.
- **Boundary**: source-versus-delivered. disko applies only at install, so the dataset exists on the running host only after the operator creates it (tasks 2.1).
- **Alternatives considered**: the root dataset (pinned snapshots); `/var/backup/postgresql` (would mount over tonight's manual dumps).

### D6: restic to R2 (operator Q51)
- **Choice**:
  - `services.restic.backups.postgresql` with `repository = "s3:https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com/sciexp-postgresql-backup/<hostName>"`.
  - `extraOptions = [ "s3.bucket-lookup=path" "s3.region=auto" ]`.
  - `initialize = true`, `createWrapper = true` (the `restic-postgresql` command for the runbook).
  - `paths` = `<location>/<db>.sql` for each backed-up database, plus `<location>/globals.sql`.
  - `timerConfig = { OnCalendar = "*-*-* 02:30:00 UTC"; RandomizedDelaySec = "15m"; Persistent = true; }`. The zone is named because `observability-notify` asserts that every notified unit's timer names its zone.
- **Rationale**:
  - R2 is already the fleet's object store and charges no egress, so the nightly read check (D7) and a restore cost nothing to read.
  - Path-style addressing and `region=auto` are what R2 requires of S3 clients.
  - One prefix per host leaves room for a second PostgreSQL host.
  - Naming files rather than the directory keeps `.prev` and any stray file out of the repository.
  - `Persistent` runs a missed night at the next boot.
  - 02:30 UTC is clear of harmonia-gc (04:00) and of the dataset's absent snapshots.
- **Boundary**: vendored-versus-first-party; the upstream module and package, configured only through options.
- **Alternatives considered**:
  - A Hetzner Storage Box with borg (rejected by the operator).
  - The existing `sciexp` bucket under a prefix. Its tokens would then reach the backups, and its lifecycle rules are owned by an unrelated resource.

### D7: Retention 7 daily, 4 weekly, 6 monthly; nightly 10% read check
- **Choice**: `pruneOpts = [ "--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6" "--group-by host" ]` and `checkOpts = [ "--read-data-subset=10%" ]`.
- **Rationale**:
  - The retention is the operator's.
  - `--group-by host` keeps one retention group. With restic's default grouping (host and paths), adding a database would start a new group and leave the old group's last snapshots unpruned forever.
  - The read check downloads a random tenth of the packs each night, so over a few weeks the whole repository is read back and verified, at no egress cost.
- **Constraint**: the backup bucket has no age-based delete lifecycle rule. Deleting packs behind restic's back corrupts the repository, so restic owns all deletion in it (A163).

### D8: Credentials as clan vars on magnetite
- **Choice**: Two generators in the module.
  - `postgresql-backup-r2`: hidden, persisted prompts `access-key` and `secret-key`, not deployed. Its `env` file holds `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` and is the job's `environmentFile` (the `omnigraph-r2` pattern).
  - `postgresql-backup-restic`: generates `password` with `openssl rand -base64 32`, with no prompt. It is the job's `passwordFile`.
- **Rationale**:
  - The token is new and scoped to `sciexp-postgresql-backup` alone, Object Read & Write (operator Q51). It is separate from `niks3-s3`, `omnigraph-r2` and `greptimedb-r2`, so revoking one service's key cannot stop backups, and the backup key reaches no other bucket.
  - Both values are sops-encrypted in the repository, for magnetite and the operator's identity. A restore after magnetite's loss needs only a checkout and the operator's key (A162).
- **Risk owned here**: regenerating `postgresql-backup-restic` would make the existing repository unreadable to the new password. See Risks.

### D9: terranix declares the bucket; the operator mints the token by hand
- **Choice**: `resource.cloudflare_r2_bucket.sciexp-postgresql-backup` (`location = "enam"`, `lifecycle.prevent_destroy = true`) in `modules/terranix/cloudflare.nix`. The token is minted in the Cloudflare dashboard, as an Account API token with Object Read & Write on that bucket, and entered with `clan vars generate magnetite --generator postgresql-backup-r2`.
- **Rationale**:
  - The bucket resource is the same one `sciexp-nix-cache` and `sciexp` use.
  - The pinned provider (5.27.0) has `cloudflare_account_token`, so terraform could mint the token too. But the terraform credential would then need permission to mint any token, which widens what that credential can do. The S3 key pair (the token id, and the SHA-256 of its value) would also still have to be read from terraform output and set as clan vars by hand. Every existing R2 token was minted by hand.
- **Alternatives considered**: `cloudflare_account_token` with the S3 pair as sensitive outputs (open question 2, if the operator prefers it).

### D10: The backup and dump units notify on failure
- **Choice**: magnetite's `notifiedUnits` gains:
  - `restic-backups-postgresql`;
  - `postgresql-dump-globals`;
  - `postgresqlBackup-<db>` for each of the six databases;
  - the two dataset oneshots (D5).

  `memoryBudgetUnits` gains `restic-backups-*.service`, `postgresqlBackup-*.service` and `postgresql-dump-globals.service`.
- **Rationale**: A failed dump posts a notice naming its database, and the job's own notice says the night's copy is missing. They are two notices for one cause, and the first one carries the cause. Listing the units makes `SystemdUnitFailed` exclude them, so no unit is reported twice. `notifiedUnits` is static host-table data, so the list is literal, and the obligation (D15) fails the host when it drifts from the evaluated units. The memory entries put the nightly job into CAM-111's budget records beside nixbot.
- **Alternatives considered**: notifying only the restic unit. The notice would not say which database failed, and the dump unit would also raise `SystemdUnitFailed`.

### D11: `PostgresqlBackupStale` at 36 h, seeded so "never" ages too
- **Choice** (metrics placement decided 2026-11-19 after F75):
  - On success, the job's `ExecStartPost` writes `vanixiets_postgresql_backup_last_success_timestamp_seconds <unix time>` to its record `/var/lib/postgresql-backup-metrics/backup.prom` (directory 0755, root), then copies the record by write-then-rename to `postgresql-backup.prom` in the host's one textfile directory, `vanixiets.nodeExporter.textfileDirectory` (`/run/node-exporter-textfile` by default, `modules/nixos/node-exporter-textfile.nix`).
  - The module names itself `postgresql-backup` in `vanixiets.nodeExporter.textfileWriters`, so node_exporter's one `--collector.textfile.directory` flag covers it. It adds no flag of its own: node_exporter refuses a repeated flag, and that module asserts at most one.
  - `postgresql-backup-metric.service` (wanted by `multi-user.target`, and every 60 s by its timer) writes the record with the current time when none exists, and otherwise copies it into the textfile directory again.
  - An assertion, in the collation probe's former form, requires node_exporter on, the series in `nodeExporterKeep`, and the textfile directory flag present.

  The rule is:
  - `alert = "PostgresqlBackupStale"`;
  - `expr = "time() - vanixiets_postgresql_backup_last_success_timestamp_seconds > 129600"`;
  - `for = "10m"`, severity warning;
  - an annotation pointing at the runbook;
  - no presence selector, as for `PostgresqlCollationDrift`, because the host table does not say which hosts run PostgreSQL.
- **Rationale**:
  - 36 h is one missed night plus a margin for the randomized delay and a slow run (pinpox's threshold).
  - `ExecStartPost` runs only after every ExecStart command succeeded: backup, prune and check.
  - The record sits under `/var/lib` so the timestamp survives reboots. The shared directory is under `/run`, so its copy is lost at each boot; the metric unit restores it within a minute of boot.
  - Republishing every minute keeps the file's mtime fresh. `HostProbeStale` fires on any textfile older than 300 s on a host with a textfile writer (F76), so a file written only at each night's success would fire it all day.
  - The seed means a host that never completes a backup is reported 36 h after the module is first deployed, which covers a timer that never fires.
  - The unit failure notice (D10) covers a run that fails. This rule covers a run that never happens.
- **Alternatives considered**:
  - `absent()` (no per-host semantics in the evaluator).
  - A presence selector through a new host-table field (data duplicated from the configuration).
  - Keeping the record only under `/run`, which would lose the timestamp at reboot and re-seed it.
  - A third `--collector.textfile.directory` flag on `/var/lib/postgresql-backup-metrics` (the plan before F75). node_exporter refuses a repeated flag and did not start on magnetite on 2026-11-19.

### D12: Restore proven by a container test of the real module
- **Choice**: `vmTests.x86_64-linux.postgresql-backup-restore`, `pkgs.testers.runNixOSTest` with one nspawn container, following `modules/vm-tests/devloop-ingest.nix`. The node imports `flake.modules.nixos.postgresql-backup` with magnetite's PostgreSQL package, two databases created by `ensureDatabases`, and the repository overridden to a local path `/var/lib/restic-test` with a fixed test password. No credentials are needed. The script:
  1. Seeds rows in both databases and a role, then starts every dump unit by hand, so an older copy of every file exists.
  2. Inserts a sentinel row, then starts `restic-backups-postgresql.service` only.
  3. Records row counts, drops both databases and the role.
  4. Runs `restic-postgresql restore latest --target /restore`, then `psql -f globals.sql` and `psql -f <db>.sql` for each database.
  5. Asserts the role exists, every row count equals the recorded count, and the sentinel is present.
  6. Asserts `restic-postgresql snapshots --json` holds exactly the expected paths, and that `backup.prom` holds a timestamp later than the test start.
- **Rationale**:
  - The sentinel is what makes the test severe. With D4 broken, the job would upload the older dump and the sentinel would be missing.
  - The property involves systemd ordering and a service on NixOS but no kernel or multiple machines, so nspawn is the cheapest regulator that observes it.
  - `vmTests` is the repository's place for on-demand runtime tests outside the PR checks. It runs at apply and whenever the module changes (tasks 5.3).
- **Alternatives considered**:
  - A sandbox derivation with `postgresqlTestHook`. It is cheaper but cannot observe the units' ordering.
  - Full QEMU. No envelope here needs it.
  - Putting it in `checks`. Per-PR cost on every change, for a module that rarely changes.

### D13: Restore runbook, exercised off the host
- **Choice**: `packages/docs/src/content/docs/development/operations/postgresql-backup.md`, linked from the rule's annotation and the operations index. It covers:
  - listing snapshots;
  - restoring one database in place (stop its service, `dropdb`, `psql -f`, start it, then reindex if the restored dump crossed a glibc collation change);
  - restoring everything onto a rebuilt magnetite (globals first);
  - restoring from a workstation after losing magnetite, with `clan vars get magnetite postgresql-backup-r2/env` and `postgresql-backup-restic/password` and a nix-shell restic.

  The workstation path is exercised once at apply (tasks 7.4).
- **Rationale**: The container test proves the mechanism. Only the off-host drill proves that the secrets and the bucket are reachable without magnetite, which is what an off-host copy is for.

### D14: No `clan backups` provider for restic
- **Choice**: Do not declare `clan.core.backups.providers.restic`.
- **Rationale**:
  - The clan CLI's restore runs each state entry's `postRestoreCommand`. For PostgreSQL that is `clan.core.postgresql`'s `dropdb` plus `pg_restore -C` of a custom-format dump, which D3 does not produce. We would be writing both the provider and the hooks, and no surveyed fleet runs such a provider.
  - A restore is a rare act the operator performs deliberately. The wrapper and runbook give the same commands with less to keep working.
- **Alternatives considered**: a provider whose `restore` wraps `restic restore` and whose hooks run `psql -f`. Reconsider if a second backed-up host makes `clan backups list` across hosts worth it.

### D15: Regulators: a fleet obligation and a fixture check
- **Choice**: `flake.lib.postgresqlBackupObligations`, in `modules/nixos/postgresql-backup.nix` beside `flake.lib.postgresqlBackup` (`location`, `seriesName`, `jobName`, `metricsDirectory`), exposes:
  - a pure judge `problems { postgresql, enable, awaiting, secretsGenerated, parked, postgresqlBackup, services, restic, notifiedUnits }`;
  - `factsOf name hostConfig`, which reads those facts from the evaluated configuration, the repository's vars and the host table entry;
  - `failures name hostConfig`, the judge over `factsOf`. It returns `[ ]` when PostgreSQL is off.

  The judge reports, one message each:
  - PostgreSQL on, the backup off, and the host absent from `flake.lib.postgresqlBackup.awaitingSecrets` (D16);
  - the backup on and the host still in `awaitingSecrets`;
  - the backup on and either generator's deployed file (`postgresql-backup-r2/env`, `postgresql-backup-restic/password`) absent from the repository.

  With the backup on, it also reports:
  - each database in `ensureDatabases` minus `parked` absent from `postgresqlBackup.databases`;
  - each `postgresqlBackup-<db>` with a non-empty `startAt`;
  - compression other than `"none"`;
  - each dump file absent from the restic job's `paths`;
  - each dump unit, or `postgresql-dump-globals`, not named in `backupPrepareCommand`;
  - each backup unit absent from `notifiedUnits`.

  `modules/checks/machines.nix` asserts `failures` in `withFleetObligations`. `modules/checks/postgresql-backup-obligations.nix` defines `checks.x86_64-linux.postgresql-backup-obligations` over literal fixtures. Four cases give 0 problems: the accepted configuration, a parked database absent from the backup set, a host awaiting its secrets with the backup off, and a host without PostgreSQL. One mutant per message gives exactly 1 problem each: missingDatabase, dumpTimer, compressed, pathMissing, prepareMissing, unitNotNotified, notEnabled, awaitingButEnabled and secretsMissing.
- **Rationale**:
  - The facts are configuration values, and the machine checks already evaluate every configuration, so this costs no attribute and no evaluation.
  - The fixture check's key is a literal gated on `x86_64-linux`.
  - Each mutant runs only its own case.
  - Module `assertions` would pass by construction, because the same module sets the values. The obligation judges the final merged value, so a later `mkForce`, an added database or an edit to the host table fails the check.
- **Alternatives considered**: a standalone check evaluating every host (re-pays each fixpoint).

### D16: The backup is off until the host's vars are in the repository
- **Choice**: The module declares `vanixiets.postgresqlBackup.enable`, default `false`. Everything it configures, the two vars generators included, is under that option, and so are magnetite's dataset declaration and dataset oneshots (D5). `flake.lib.postgresqlBackup.awaitingSecrets = [ "magnetite" ]` names the PostgreSQL hosts whose vars the operator has not yet generated.

  One later commit, the one that adds magnetite's generated vars, makes four edits:
  - sets `vanixiets.postgresqlBackup.enable = true` on magnetite;
  - removes magnetite from `awaitingSecrets`;
  - adds the backup units and the dataset oneshots to magnetite's `notifiedUnits` (D10);
  - adds the vars files under `vars/per-machine/magnetite/postgresql-backup-{r2,restic}/`.
- **Rationale**:
  - `clan machines update` runs every missing generator of every machine before it deploys anything (clan-core d718bcf, `clan_cli/machines/update.py:210`). If the generators were declared before their vars existed, an unattended deploy, such as the fleet deployer's, would fail on the hidden prompts. A deploy without prompts would generate the restic password in a checkout that is not committed, and the repository would be created under a password the repository does not hold (D8).
  - Without the option, the module's units would exist on magnetite with `EnvironmentFile` and `RESTIC_PASSWORD_FILE` at clan's `/no-such-path` placeholder, so every night's run would fail and post a notice.
  - The obligation locks the four edits together. Each of the following fails `nixos-magnetite`:
    - turning the backup on while magnetite is still in `awaitingSecrets`;
    - removing magnetite from `awaitingSecrets` without turning the backup on;
    - turning it on without the vars;
    - turning it on without the notified units.

    Any other host that enables PostgreSQL fails its check until it either backs up or is listed as awaiting.
- **Before the later commit**: magnetite evaluates and builds with no backup unit, timer, generator, dataset mount or textfile writer of this module, and `failures "magnetite"` is `[ ]`. Deploying `main` adds nothing to magnetite. The bucket, once applied, holds nothing. The alert rule has no series to fire on.
- **Alternatives considered**:
  - Declaring the generators unconditionally. This breaks every unattended deploy until the operator generates the vars.
  - An `enable` defaulting to `services.postgresql.enable`, with magnetite setting it `false` for now. That needs the same exemption in the obligation, and adds a setting on the host that exists only to be deleted.

## Risks / Trade-offs

- [Risk] `postgresql-backup-restic` is regenerated (`clan vars generate --regenerate`) and the repository becomes unreadable → Mitigation:
  - The runbook states that the password must never be regenerated.
  - The off-host drill (7.4) reads it from the repository.
  - If it is ever lost, the repository is re-initialized under a new prefix and the old one is kept until the new one holds 7 nights.
- [Risk] A compromised magnetite holds a write token and can delete every backup → Accepted for now (open question 3); a token kept off the host could later move the prune elsewhere.
- [Risk] A dump restored after a glibc collation change has stale text indexes → Mitigation: the runbook reindexes after restore, and the F61 drift alert reports what was missed.
- [Risk] The nightly job competes with a nixbot evaluation for memory → Mitigation: the units join CAM-111's budget records. restic's memory for a ~2 GB repository is small [INFERENCE: hundreds of MB at most]; it is measured on the first nights (7.2).
- [Risk] `-C` dumps recreate the database with its original owner and options, so restoring under a different name needs editing → Accepted; the runbook restores in place, and a scratch-name restore uses `sed` on the `CREATE DATABASE`/`\connect` lines (documented).
- [Risk] Per-database dumps are taken at different moments, so cross-database references (gitea-mq ↔ gitea through the API, not the database) can disagree by minutes → Accepted (A160); the services already reconcile through their APIs.
- [Trade-off] Only PostgreSQL is covered. gitea's repositories and synapse's media are not (open question 1) → Accepted per scope; the restic job's `paths` is where they would be added.
- [Trade-off] A local `.prev` dump doubles the dataset's use to ~3 GB → accepted for a fast local restore of yesterday; bounded by the quota.

## Migration Plan

1. Land the obligation and fixture check red, then the module, with the backup off and magnetite in `awaitingSecrets` (D16). `nixos-magnetite` proves the backup set through `extendModules` mutants before any deploy (group 1).
2. In parallel, land the dataset declaration (group 2), the alert rule (group 3), the bucket resource (group 4), the restore test (group 5) and the runbook (group 6).
3. Operator, by hand (tasks 2.1, 4.2, 4.3):
   - apply the bucket (`nix run .#terraform` plan and apply);
   - `zfs create -o mountpoint=/var/backup/postgresql-nightly -o com.sun:auto-snapshot=false -o quota=16G zroot/root/postgresql-dumps` on magnetite;
   - in the working copy of the enable commit (D16), mint the token and run `clan vars generate magnetite --generator postgresql-backup-r2`, then generate `postgresql-backup-restic`.
4. Run the restore container test and its mutant (tasks 5.1, 5.2).
5. Land the enable commit, deploy magnetite, start `restic-backups-postgresql.service` once by hand and watch it. Confirm the snapshot, the textfile and the series in the store. Read every alert posted since the deploy started (task 7.1).
6. Over the next nights: scheduled snapshots, memory peaks, prune and check output, the off-host drill and the reporting paths (tasks 7.2 to 7.5).

Rollback:
- Revert the module commit. The R2 bucket and its snapshots are kept (`prevent_destroy`).
- The dataset can stay. It is empty of anything the system needs.

## Open Questions

1. Should a follow-up change extend the same restic job to the services' file state (gitea repositories and LFS, synapse media and signing key)? Without that, losing magnetite still loses every gitea repository not mirrored elsewhere.
2. Does the operator prefer terraform to mint the token (`cloudflare_account_token`, which needs a token-minting permission on the terraform credential) over D9's hand-minted token?
3. Should backups be protected from deletion by magnetite itself (R2 bucket lock on `data/`, or a prune run from a host holding a separate key)? This conflicts with restic's own prune unless prune moves off the host.
4. Are the new assumption numbers A160 to A166 free at merge time? `delegate-fleet-deploys` ends at A159, and other in-flight changes may claim the same numbers.
5. Should a monthly restore probe on magnetite (restore the latest snapshot into a scratch database and compare row counts) add a runtime guard beyond the on-demand container test?

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
The repository has no BDD runner and no `.feature` file, so no row routes to a Gherkin scenario. Each requirement is witnessed by one of:
- a build gate: `nix eval`, `nix build`, the fleet obligation on the machine checks, the fixture check, or the fleet-alert check;
- the on-demand container test;
- a smoke observation on magnetite, recorded in `verify.md`.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| Every unparked service's data is copied off its host every night | `database-backup` | behavioral | build gate (obligation, fixture check), container test and smoke | tasks 1.1-1.6, 5.1, 7.1, 7.2 |
| An off-host copy holds that night's data | `database-backup` | behavioral | container test (sentinel, mutant) and smoke | tasks 5.1, 5.2, 7.1, 7.2 |
| A parked service's data is left out until the service is revived | `database-backup` | behavioral | build gate (fixture check parked case, obligation) | tasks 1.2, 1.6 |
| Off-host copies are kept on a schedule | `database-backup` | behavioral | build gate (`nix eval`) and smoke | tasks 1.4, 7.3 |
| Off-host copies survive the loss of the host and are readable only with the operator's secrets | `database-backup` | behavioral | smoke (off-host drill) | tasks 4.2, 4.3, 7.4 |
| Service data can be restored from an off-host copy | `database-backup` | behavioral | container test and smoke (drill) | tasks 5.1, 6.1, 7.4 |
| A failed backup run reaches the operator | `database-backup` | behavioral | build gate (obligation) and smoke | tasks 1.3, 1.5, 7.5 |
| An overdue backup reaches the operator | `database-backup` | behavioral | build gate (fleet-alert check) and smoke | tasks 3.1-3.3, 7.5 |
| Local rollback stays available | `database-backup` | behavioral | build gate (`nix eval`) and smoke | task 2.3 |
| Each `database-backup-interface` requirement | `database-backup-interface` | interface | build gate and container test | tasks 1.1-1.6, 2.2, 3.1-3.3, 4.1, 5.1, 5.2 |
| A160-A166 | `world-assumptions` | world | monitoring (violation scenarios) | A160 and A161 by 5.1 and 7.4; A162 by 7.4; A163 by 4.1 and 7.3; A164 by review before any change that turns on WAL archiving; A165 by 2.3; A166 by open question 1 |
