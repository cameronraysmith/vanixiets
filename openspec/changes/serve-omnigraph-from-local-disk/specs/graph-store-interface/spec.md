## ADDED Requirements

### Requirement: The interface's trust boundary

These requirements SHALL be read as properties of the evaluated configuration, of programs run in a build sandbox, and of a test VM, and SHALL NOT be cited as guarantees about what lies outside them.
Outside them lie: OmniGraph's lock record and `force-unlock` (A232), ZFS snapshots as instant images (A235), R2 keeping what restic wrote, the operator's keeping the identity that decrypts the clan vars, a later OmniGraph release opening a restored root, and systemd running a timer on the real host.

#### Scenario: a claim beyond the boundary

- **WHEN** a requirement here is cited as proof that magnetite's graph data survived the loss of its disk
- **THEN** the citation is incomplete without a graph backup restored from R2 by the runbook

#### Scenario: the runtime evidence

- **WHEN** the real host's behaviour is in question
- **THEN** the evidence is the `OmnigraphNotServing` and `OmnigraphBackupStale` alerts and the probe's series, not these requirements

### Requirement: The root store setting yields the root's location

`flake.lib.omnigraphClusterRoots` SHALL provide `localDirectory = "/var/lib/omnigraph/clusters"` and `uriIn`, mapping `"local"` and a root name to `"<localDirectory>/<root>"`, `"r2"` and a root name to `uri <root>`, and rejecting any other store.
magnetite's `services.omnigraph.storageUri` SHALL be `uriIn` of the `let` value `omnigraphRootStore` in `modules/machines/nixos/magnetite/default.nix` and the root `name { family = "cookbooks"; createdAtFormat = 17; }`.

#### Scenario: magnetite on its disk

- **WHEN** magnetite's configuration is evaluated with `omnigraphRootStore = "local"`
- **THEN** `services.omnigraph.storageUri` is `/var/lib/omnigraph/clusters/cookbooks-f17`

#### Scenario: magnetite on R2

- **WHEN** magnetite's configuration is evaluated with `omnigraphRootStore = "r2"`
- **THEN** `services.omnigraph.storageUri` is `s3://sciexp/omnigraph/clusters/cookbooks-f17`, as before this change

### Requirement: R2 settings apply only to an R2 root

On magnetite, `services.omnigraph.s3.endpointUrl`, `s3.region`, `environmentFile` and `extraEnvironment.OMNIGRAPH_CLUSTER_LEASE_SECONDS` SHALL be set only when `omnigraphRootStore = "r2"`, and the `omnigraph-r2` generator, `retired`, `rollback`, the lifecycle rules on `sciexp` and `checks.x86_64-linux.omnigraph-retired-roots` SHALL be unchanged by either value.

#### Scenario: a local root's environment

- **WHEN** magnetite's `systemd.services.omnigraph-server.environment` is evaluated with `"local"`
- **THEN** it has no `AWS_*` key and no `OMNIGRAPH_CLUSTER_LEASE_SECONDS`, and `clan.core.vars.generators.omnigraph-r2` still exists

### Requirement: The graph data has a dataset of its own

With `omnigraphRootStore = "local"`, magnetite's `disko.devices.zpool.zroot.datasets."root/omnigraph"` SHALL have `mountpoint = "/var/lib/private/omnigraph/clusters"` and `quota = "20G"` and SHALL NOT set `com.sun:auto-snapshot` to `false`; a oneshot `zfs-set-root-omnigraph-quota` SHALL assert the quota at boot; it and `restic-backups-omnigraph` SHALL be in magnetite's `notifiedUnits`; and every omnigraph unit SHALL carry `RequiresMountsFor` on the mountpoint.

#### Scenario: the dataset is evaluated

- **WHEN** magnetite's configuration is evaluated with `"local"`
- **THEN** the dataset has the mountpoint and quota above, `zfs-set-root-omnigraph-quota` is a oneshot, and `omnigraph-server`'s `unitConfig.RequiresMountsFor` contains `/var/lib/private/omnigraph/clusters`

#### Scenario: on R2

- **WHEN** magnetite's configuration is evaluated with `"r2"`
- **THEN** neither the dataset nor `zfs-set-root-omnigraph-quota` exists

### Requirement: The bootstrap creates and seeds the local root

On an empty local root with no marker, `omnigraph-cluster-bootstrap` SHALL create the root, write a seed-pending marker per seeded graph in `/var/lib/omnigraph/clusters/_omnigraph-markers/`, apply, and write the root's marker; each `omnigraph-seed-<graph>` SHALL then load its seed once the server is ready.

#### Scenario: the first local start

- **WHEN** magnetite starts with the empty dataset mounted and no marker
- **THEN** `cookbooks-f17.initialized` exists in the marker directory, no `.seed-pending` marker remains once the seed units finish, and `/readyz` reports 10 served and 10 ready graphs

### Requirement: The server's start clears a stale serve lock

For a local `storageUri`, `omnigraph-server`'s first `ExecStartPre` SHALL be `+` and the program `flake.lib.omnigraphLockRecovery` builds for the root, run by no other unit, and absent for an `s3://` root.
The program SHALL run `omnigraph --target <root> cluster force-unlock <lock_id> --json` only in the clearing scenarios below; otherwise it SHALL leave `<root>/__cluster/lock.json` unchanged, print the reason and the manual command, and exit non-zero.

#### Scenario: no lock

- **WHEN** the program runs and `<root>/__cluster/lock.json` is absent
- **THEN** it exits 0 and runs nothing

#### Scenario: a dead server's lock

- **WHEN** the program runs with a `serve` lock whose pid is absent and no omnigraph process naming the root
- **THEN** it runs `force-unlock` with exactly that `lock_id` and exits 0

#### Scenario: a running direct writer

- **WHEN** the program runs while `omnigraph --target /var/lib/omnigraph/clusters/cookbooks-f17 …` is running
- **THEN** it exits non-zero naming that process, and `lock.json` is unchanged

#### Scenario: a direct writer's lock

- **WHEN** the program runs with a lock whose `operation` is not `serve`
- **THEN** it exits non-zero naming `cluster apply --deployment-id … --writers-stopped`, and `lock.json` is unchanged

#### Scenario: a live pid in this boot

- **WHEN** the program runs with a `serve` lock whose pid exists and whose `created_at` is after `btime`
- **THEN** it exits non-zero and `lock.json` is unchanged

#### Scenario: an id mismatch or an unreadable record

- **WHEN** `omnigraph --target <root> cluster status --json` reports a `lock_id` other than the record's, or the record lacks string `lock_id`, `operation`, `created_at` or integer `pid`
- **THEN** it exits non-zero and `lock.json` is unchanged

#### Scenario: the process scan

- **WHEN** any process whose executable is the packaged `omnigraph` or `omnigraph-server` has an argv naming the root as `/var/lib/omnigraph/…` or `/var/lib/private/omnigraph/…`
- **THEN** the program refuses, whatever the record says

#### Scenario: a lock from before the boot

- **WHEN** the program runs with a `serve` lock whose `created_at` is earlier than `btime` in `/proc/stat`, its pid now belongs to an unrelated process, and no omnigraph process names the root
- **THEN** it runs `force-unlock` with exactly that `lock_id` and exits 0

### Requirement: Recoveries are counted and announced

After a successful `force-unlock`, the program SHALL add one to the integer in `/var/lib/omnigraph-metrics/lock-recoveries` (starting from 0 when absent) and post one message at low priority to the `fleet-alerts` topic through `ntfy-send` with `services.observability-notify.tokenFile`, naming the host, the root and the cleared `lock_id`; a failed post SHALL NOT fail the start.

#### Scenario: one recovery

- **WHEN** the program clears one lock on a host whose counter file holds 2
- **THEN** the file holds 3 and one low-priority message naming the `lock_id` is posted

### Requirement: A rehearsal holds the recovery's verdicts

`checks.x86_64-linux.omnigraph-lock-recovery-rehearsal`, class `small`, SHALL run the program built by `flake.lib.omnigraphLockRecovery` against a stub `omnigraph`, a scripted process table and boot time, and a fresh lock directory per row, asserting for each scenario of `The server's start clears a stale serve lock` the exit status, the stub's argv log, the counter and the lock file.
It SHALL hold one record written by the packaged `omnigraph-server`, so a changed record shape fails it.

#### Scenario: the check runs

- **WHEN** `nix build .#checks.x86_64-linux.omnigraph-lock-recovery-rehearsal` runs
- **THEN** every row passes, and a mutant that skips the process scan fails the running-writer row

### Requirement: The backup job copies a ZFS snapshot to its R2 repository

With `vanixiets.omnigraphBackup.enable`, `services.restic.backups.omnigraph` SHALL back up only `/var/lib/private/omnigraph/clusters/.zfs/snapshot/restic`, a snapshot its prepare step takes fresh and its cleanup step destroys, to repository `sciexp-omnigraph-backup/<hostName>` at the account's R2 endpoint, and the module SHALL assert that `services.omnigraph.storageUri` is a local path.

#### Scenario: the repository and snapshot steps

- **WHEN** magnetite's job is evaluated with the backup on
- **THEN** `repository` is `s3:https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com/sciexp-omnigraph-backup/magnetite`, `extraOptions` holds `s3.bucket-lookup=path` and `s3.region=auto`, `backupPrepareCommand` destroys any leftover `zroot/root/omnigraph@restic` before `zfs snapshot zroot/root/omnigraph@restic`, and `backupCleanupCommand` destroys it

#### Scenario: retention, check and secrets

- **WHEN** magnetite's `services.restic.backups.omnigraph` is evaluated with the backup on
- **THEN** `pruneOpts` are `--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --group-by host`, `checkOpts` is `--read-data-subset=10%`, the password comes from generator `omnigraph-backup-restic` (generated) and the environment from `omnigraph-backup-r2` (prompted, hidden)

#### Scenario: the job is evaluated

- **WHEN** magnetite's `services.restic.backups.omnigraph` is evaluated with the backup on
- **THEN** its repository ends in `/sciexp-omnigraph-backup/magnetite`, its only path is the snapshot directory, and its prepare step names `zfs snapshot zroot/root/omnigraph@restic`

#### Scenario: a live path

- **WHEN** a configuration sets `paths` to `/var/lib/omnigraph/clusters` or turns the backup on with an `s3://` root
- **THEN** evaluation fails

### Requirement: The backup job runs nightly and catches up a missed night

The job's `timerConfig` SHALL hold `OnCalendar = "*-*-* 03:30:00 UTC"`, `RandomizedDelaySec = "15m"` and `Persistent = true`, and its `ExecStartPost` SHALL write `vanixiets_omnigraph_backup_last_success_timestamp_seconds` to its record and the textfile directory, republished every minute by `omnigraph-backup-metric`, which seeds the record on its first run.

#### Scenario: the timer is evaluated

- **WHEN** magnetite's `systemd.timers.restic-backups-omnigraph.timerConfig` is evaluated
- **THEN** it holds the three values above

### Requirement: The backup bucket deletes nothing by age

`modules/terranix/cloudflare.nix` SHALL declare `cloudflare_r2_bucket.sciexp-omnigraph-backup` with `lifecycle.prevent_destroy = true`, and no lifecycle rule SHALL name that bucket.

#### Scenario: the terraform configuration is evaluated

- **WHEN** the terranix configuration is rendered
- **THEN** it holds the bucket resource and no `cloudflare_r2_bucket_lifecycle` with `bucket_name = "sciexp-omnigraph-backup"`

### Requirement: The probe publishes readiness each minute

On a host with `services.omnigraph.enable` and the textfile collector, `omnigraph-probe.service` SHALL run every 60 s and write `omnigraph.prom` into the textfile directory by write-then-rename, holding `vanixiets_omnigraph_ready`, `vanixiets_omnigraph_graphs{state}` and `vanixiets_omnigraph_start_to_ready_seconds`, with every series in `nodeExporterKeep` and `omnigraph` in `vanixiets.nodeExporter.textfileWriters`.

#### Scenario: the series' values

- **WHEN** the probe runs while `/readyz` answers
- **THEN** `vanixiets_omnigraph_ready` is 1 only for `ready: true`, and `vanixiets_omnigraph_graphs` has one line each for `served`, `ready`, `loading` and `blocked`

#### Scenario: the server is down

- **WHEN** the probe runs while nothing listens on the server's port
- **THEN** `omnigraph.prom` holds `vanixiets_omnigraph_ready 0`

### Requirement: The probe publishes per-graph and storage series

With the `monitor` token, the probe SHALL publish `vanixiets_omnigraph_graph_entities{graph}`, `vanixiets_omnigraph_graph_manifest_version{graph}` and `vanixiets_omnigraph_graph_storage_format{graph}` from `GET /graphs/{id}/snapshot`, omitting a graph whose read fails; on a local root it SHALL publish `vanixiets_omnigraph_dataset_used_bytes`, `vanixiets_omnigraph_dataset_quota_bytes`, `vanixiets_omnigraph_dataset_snapshots` and `vanixiets_omnigraph_lock_recoveries_total`.

#### Scenario: a served local root

- **WHEN** the probe runs on magnetite serving its local root
- **THEN** `omnigraph.prom` has one `vanixiets_omnigraph_graph_entities` line per served graph and the four storage series

### Requirement: The monitor actor reads and nothing else

`services.omnigraph.extraBearerTokenFiles` SHALL add each named actor's token to the server's assembled tokens file, refusing an actor the tokens file already names; magnetite SHALL set `monitor` from generator `omnigraph-monitor-token`; `server.policy.yaml` SHALL grant `monitor` only `graph_list` and `examples.policy.yaml` only `read`.

#### Scenario: the policy check runs

- **WHEN** `nix build .#checks.x86_64-linux.omnigraph-cluster-actor-policy` runs
- **THEN** `monitor` is allowed `read` on the first and last graph and denied `change`, `export`, `schema_apply` and `maintain`

### Requirement: OmnigraphNotServing reports a graph store that is not serving

`rules.nix` SHALL hold `OmnigraphNotServing` with expression `vanixiets_omnigraph_ready == 0 or vanixiets_omnigraph_graphs{state="blocked"} > 0`, `for = "5m"`, severity `warning`, and an annotation naming the runbook; `checks.x86_64-linux.fleet-alert` SHALL hold a promtool case, a threshold mutant, a fixture series and a fire-and-resolve leg for it.

#### Scenario: the check runs

- **WHEN** `nix build .#checks.x86_64-linux.fleet-alert` runs
- **THEN** a series at 0 for 6 minutes fires one alert for magnetite, a series at 0 for 4 minutes does not, the mutant `for = "50m"` is rejected, and the leg posts one firing and one resolved message

### Requirement: OmnigraphBackupStale reports an overdue backup

`rules.nix` SHALL hold `OmnigraphBackupStale` with expression `time() - vanixiets_omnigraph_backup_last_success_timestamp_seconds > 129600`, `for = "10m"`, severity `warning`, and an annotation naming the runbook, with a promtool case, a threshold mutant, a fixture series and a fire-and-resolve leg.

#### Scenario: the check runs

- **WHEN** `nix build .#checks.x86_64-linux.fleet-alert` runs
- **THEN** a stamp that stops advancing fires after 36 h 10 min and not at 36 h, a stamp advancing every 24 h never fires, and the mutant `> 1296000` is rejected

### Requirement: The omnigraph view is provisioned and query-checked

`modules/nixos/perses/resources/dashboard-omnigraph.json` SHALL be a dashboard in project `fleet` using datasource `greptimedb-promql`, with a panel for each series of the probe, the backup stamp's age and `omnigraph-server`'s memory, and SHALL be in `queryChecked` of `vmTests.x86_64-linux.perses-greptimedb`.

#### Scenario: the lint runs

- **WHEN** `nix build .#checks.x86_64-linux.perses-lint` runs
- **THEN** it passes with the view present

### Requirement: A runtime test proves recovery, refusal and restore

`vmTests.x86_64-linux.omnigraph-local-root`, declared `medium` in `testSizes.vmTests`, SHALL boot a VM with ZFS, the dataset at `/var/lib/private/omnigraph/clusters`, and the real omnigraph, probe and backup modules, and SHALL assert the scenarios below.

#### Scenario: crash and recovery

- **WHEN** the server is killed with `kill -9` after seeding and restarted
- **THEN** it serves the same entity counts and stored-query answer, and the recovery counter is 1

#### Scenario: refusal while a direct writer holds the root

- **WHEN** a direct `omnigraph` writer holds the root and the server is started
- **THEN** the start fails with the reason and `lock.json` is unchanged

#### Scenario: backup and restore

- **WHEN** a backup to a local restic repository is taken, the dataset emptied, the backup restored and its lock unlocked
- **THEN** the server serves the same entity counts and stored-query answer, and every probe series is present

#### Scenario: the test runs on pyrite

- **WHEN** `nix build .#vmTests.x86_64-linux.omnigraph-local-root` runs on pyrite
- **THEN** it passes within the medium limit of 300 s
