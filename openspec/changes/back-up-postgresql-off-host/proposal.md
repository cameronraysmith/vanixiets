---
linear_story_id: CAM-117
linear_story_identifier: CAM-117
linear_story_title: "Back up PostgreSQL off the host"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-117/back-up-postgresql-off-the-host
linear_story_state: Todo
linear_team: CAM
linear_project: fleet-observability
last_synced_state: Todo
last_synced_at: "2026-11-19T00:57:01Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-19T00:57:01Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-117 created in Todo in project aeed302bea3b (Fleet observability) with description seeded from proposal.md; related to CAM-111 (magnetite memory budget); state and project confirmed by read-only view" }
---

## Why

magnetite's PostgreSQL holds the state of six fleet services (gitea, gitea-mq, matrix-synapse, nixbot, niks3, omnigent), and nothing copies it off the host. Its only copies are ZFS snapshots on the same disk and one pre-deploy dump of omnigent. If the disk is lost, every service's accounts, history and metadata are lost with it. Tonight's reindex for the glibc collation change needed hand-made dumps for exactly this reason. This change adds nightly off-host copies with a recovery point of at most 24 h, reports a failed or missing backup to the operator, and proves restore with a test and a runbook.

## What Changes

Decisions tagged `D<n>` are developed in `design.md`. The operator settled Q50 to Q53 on 2026-11-19 (D1, D2, D6). The rest are proposed for approval at Gate 1.

**Nightly dumps started by the backup (P1)**
- From: no scheduled dump; ZFS snapshots on the same disk.
- To: every database the configuration creates, except a parked service's, is dumped nightly as plain uncompressed SQL, plus a globals-only dump of roles. The backup job starts the dumps itself, so each night's off-host copy holds that night's dumps (D3, D4, D5).
- The dumps live on a dedicated ZFS dataset with auto-snapshot off (D5).

**Off-host copies on R2 (P2)**
- restic copies the dumps to a new R2 bucket, `sciexp-postgresql-backup`, under one prefix per host. Retention is 7 daily, 4 weekly and 6 monthly, with a 10% data read check each night (D6, D7).
- The R2 key and restic password are clan vars. The key is a new token scoped to that bucket alone (D8).
- terranix declares the bucket. The operator mints the token by hand (D9).
- ZFS snapshots stay as local rollback.

**A failed or missing backup reaches the operator (P3)**
- A failure notice is sent when the backup or any dump unit fails (D10).
- A new alert, `PostgresqlBackupStale`, fires when no backup has succeeded for 36 h, including when none ever has, so a timer that never fires is also reported (D11).

**Restore is proven (P4)**
- A container test uses the real module: dump, back up to a local restic repository, drop, restore, then compare row counts. It includes a sentinel row that the dump-after-backup bug would lose (D12).
- A restore runbook in the operations docs, exercised once from a workstation using only the repository's vars (D13).

**Not now, recorded (P5)**
- No WAL archiving or PITR (D1): a failing archive fills `pg_wal`.
- No `clan backups` provider for restic (D14).
- cognee's database is not backed up while cognee is parked (D2).

**Regulators**
- `flake.lib.postgresqlBackupObligations`, registered as `fleetObligations.postgresqlBackupObligations` and so asserted on every `nixos-<host>` check, fails a host that runs PostgreSQL when:
  - a database it creates, other than a parked one, is missing from the backup set;
  - a dump has a timer of its own;
  - the backup job does not start or upload a dump;
  - a dump is compressed;
  - a backup unit is not notified.
- `checks.x86_64-linux.postgresql-backup-obligations` runs the judge over literal fixtures, with one mutant per failure (D15).

## Capabilities

### New Capabilities
- `database-backup` (stratum: `behavioral`): every unparked service's data on a fleet host is copied off the host every night, with a recovery point of at most 24 h, kept by a retention schedule, readable only with secrets the operator can reach without that host, restorable by a tested procedure, and reported to the operator when a copy fails or is overdue.
- `database-backup-interface` (stratum: `interface`): the dump units, their dataset, the restic job (repository, paths, prepare step, retention, check), the success timestamp series and its textfile, the `PostgresqlBackupStale` rule, the notified units, the vars generators, the R2 bucket resource, the restore container test, and the obligation and fixture check that pin them.
  Trust boundary: this machine declares the units, job, rule and resources, and judges the evaluated configuration and a restore inside a test container. It does not guarantee that R2 keeps what restic wrote, that the operator keeps the identity that decrypts the vars, that a dump restores into a future PostgreSQL major, or that systemd runs the timer on the real host. The staleness alert is the runtime evidence for the last of these.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): A160 to A166 record per-database dump consistency, what a plain-SQL dump carries and how it restores, restic's encryption and password custody, R2 keeping objects until a credential deletes them, the WAL archive failure mode behind Q50, ZFS snapshots sharing the pool's fate, and that the six services' file state lies outside PostgreSQL. `Grounded vocabulary for behavioral requirements` gains `service data`, `service login`, `database instance`, `parked service`, `backup run`, `off-host copy`, `backup storage`, `recovery point`, `restore` and `local rollback`, each with one sense.

## Impact

- Code:
  - new `modules/nixos/postgresql-backup.nix` and `modules/checks/postgresql-backup-obligations.nix`;
  - `modules/checks/machines.nix`;
  - `modules/nixos/fleet-alert/rules.nix` and `modules/checks/fleet-alert.nix`;
  - `modules/clan/services/otel-collector/schema.nix` (`nodeExporterKeep`, `memoryBudgetUnits`);
  - `modules/lib/observability-hosts.nix`;
  - `modules/machines/nixos/magnetite/{default,disko}.nix`;
  - `modules/terranix/cloudflare.nix`;
  - new `modules/vm-tests/postgresql-backup-restore.nix`;
  - a runbook under `packages/docs/src/content/docs/development/operations/`.
- Depends on chain `zqpxwylx` (F61 collation drift) for `vanixiets.postgresqlCollation.parkedDatabases` and its changes to `rules.nix` and `fleet-alert.nix`.
- Hosts: magnetite only, which is today the only host running PostgreSQL. The obligation applies to any NixOS host that later enables it.
- Operator by hand:
  - apply the bucket with terranix;
  - mint the scoped R2 token and `clan vars set` it;
  - create the dump dataset on the installed host.
- Spending: a few GB of R2 storage, with no egress charge.
- Memory: the nightly dumps and restic run inside magnetite's memory budget (CAM-111), and their units are recorded in it.
- No new flake input.
