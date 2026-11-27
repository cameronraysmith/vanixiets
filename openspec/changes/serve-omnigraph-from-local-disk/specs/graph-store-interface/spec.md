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
magnetite's module SHALL declare the internal option `vanixiets.omnigraphRootStore` (`"local"` or `"r2"`), set it from `stores.magnetite`, and derive `services.omnigraph.storageUri` from it with `uriIn`.

#### Scenario: magnetite on its disk

- **WHEN** magnetite's configuration is evaluated with `stores.magnetite = "local"`
- **THEN** `services.omnigraph.storageUri` is `/var/lib/omnigraph/clusters/cookbooks-f17`

#### Scenario: magnetite on R2

- **WHEN** magnetite's configuration is evaluated with `stores.magnetite = "r2"`
- **THEN** `services.omnigraph.storageUri` is `s3://sciexp/omnigraph/clusters/cookbooks-f17`, as before this change

### Requirement: One value switches the store, and the local-root units follow it

`flake.lib.omnigraphClusterRoots.stores` SHALL hold each serving host's store, and on magnetite `vanixiets.omnigraphBackup.enable` SHALL be whether `stores.magnetite` is `"local"`.
`flake.lib.observabilityHostsFor` SHALL build the host table for given stores, `flake.lib.observabilityHosts` SHALL be it for `stores`, and a row SHALL list `flake.lib.omnigraphBackup.localRootUnits` among its `notifiedUnits` only while its host's store is `"local"`.

#### Scenario: on the disk

- **WHEN** magnetite is evaluated with `stores.magnetite = "local"`
- **THEN** the backup is on, and `restic-backups-omnigraph`, `omnigraph-backup-metric` and `zfs-set-root-omnigraph-quota` are notified and defined

#### Scenario: the way back

- **WHEN** magnetite is evaluated with `stores.magnetite = "r2"` and no other change
- **THEN** the backup is off, none of those three units is notified, every notified unit is a service with an `ExecStart`, and `system.build.toplevel` evaluates

### Requirement: A check reads magnetite on both stores

`checks.x86_64-linux.omnigraph-retired-roots` SHALL evaluate magnetite on its committed store and, through `extendModules` with the option and the notified units set as `stores` naming the other store would set them, on the other, and hold on each the storage URI, the server's R2 environment and environment file, the `omnigraph-r2` generator, the backup option and its textfile, the notified local-root units, and that every notified unit has an `ExecStart`.

#### Scenario: the check runs

- **WHEN** `nix build .#checks.x86_64-linux.omnigraph-retired-roots` runs
- **THEN** it passes, and over a row that lists the local-root units on either store it fails naming the units on `"r2"`

### Requirement: Activation removes every textfile no declared writer writes

`modules/nixos/node-exporter-textfile.nix` SHALL declare the read-only `vanixiets.nodeExporter.textfiles`, `<name>.prom` for each name in `vanixiets.nodeExporter.textfileWriters`, and an activation script that, at boot and on `switch-to-configuration switch` and `test`, removes and prints each `*.prom` file in `textfileDirectory` not in that list and leaves every other file.
Every textfile writer SHALL write only the file its declared name gives.

#### Scenario: a file no writer declares

- **WHEN** `vmTests.x86_64-linux.omnigraph-local-root` plants `retired-writer.prom` beside the declared writers' files and a `.prom.tmp` file and runs `switch-to-configuration test`
- **THEN** `retired-writer.prom` is gone and `node-exporter-textfile: removed <path>, which no writer in vanixiets.nodeExporter.textfileWriters writes` printed, every declared file and the `.tmp` file are kept, byte for byte where no writer rewrote them, and node_exporter's next scrape has none of the removed file's series

#### Scenario: a boot switch that drops a writer

- **WHEN** `switch-to-configuration boot` installs a generation whose `vanixiets.nodeExporter.textfileWriters` lacks a writer the running generation has
- **THEN** the switch does not activate, so that writer's file stays in `textfileDirectory`, still written by the running generation's writer, until the reboot, which empties `/run` and runs the script, and no alert fires on the file; `dry-activate` does not run the script either

#### Scenario: the backup's file on either store

- **WHEN** magnetite is evaluated on `"local"` and on `"r2"`
- **THEN** `omnigraph-backup.prom` is in `vanixiets.nodeExporter.textfiles` on `"local"` and not on `"r2"`

### Requirement: R2 settings apply only to an R2 root

On magnetite, `services.omnigraph.s3.endpointUrl`, `s3.region`, `environmentFile` and `extraEnvironment.OMNIGRAPH_CLUSTER_LEASE_SECONDS` SHALL be set only when `vanixiets.omnigraphRootStore = "r2"`, and the `omnigraph-r2` generator, `retired`, `rollback`, the lifecycle rules on `sciexp` and `checks.x86_64-linux.omnigraph-retired-roots` SHALL be unchanged by either value.

#### Scenario: a local root's environment

- **WHEN** magnetite's `systemd.services.omnigraph-server.environment` is evaluated with `"local"`
- **THEN** it has no `AWS_*` key and no `OMNIGRAPH_CLUSTER_LEASE_SECONDS`, and `clan.core.vars.generators.omnigraph-r2` still exists

### Requirement: The graph data has a dataset of its own

With `vanixiets.omnigraphRootStore = "local"`, magnetite's `disko.devices.zpool.zroot.datasets."root/omnigraph"` SHALL have `mountpoint = "/var/lib/omnigraph"` and `quota = "20G"` and SHALL NOT set `com.sun:auto-snapshot` to `false`; a oneshot `zfs-set-root-omnigraph-quota` SHALL assert the quota at boot; it, `restic-backups-omnigraph` and `omnigraph-backup-metric` SHALL be in magnetite's `notifiedUnits`; and every omnigraph unit SHALL carry `RequiresMountsFor` on the root's parent.

#### Scenario: the dataset is evaluated

- **WHEN** magnetite's configuration is evaluated with `"local"`
- **THEN** the dataset has the mountpoint and quota above, `zfs-set-root-omnigraph-quota` is a oneshot, and `omnigraph-server`'s `unitConfig.RequiresMountsFor` contains `/var/lib/omnigraph/clusters`

#### Scenario: on R2

- **WHEN** magnetite's configuration is evaluated with `"r2"`
- **THEN** neither the dataset nor `zfs-set-root-omnigraph-quota` exists, and magnetite's `notifiedUnits` name neither it nor the backup's units

### Requirement: The bootstrap creates and seeds the local root

On an empty local root with no marker, `omnigraph-cluster-bootstrap` SHALL create the root, write a seed-pending marker per seeded graph in `/var/lib/omnigraph/clusters/_omnigraph-markers/`, apply, and write the root's marker; each `omnigraph-seed-<graph>` SHALL then load its seed once the server is ready.

#### Scenario: the first local start

- **WHEN** magnetite starts with the empty dataset mounted and no marker
- **THEN** `cookbooks-f17.initialized` exists in the marker directory, no `.seed-pending` marker remains once the seed units finish, and `/readyz` reports 10 served and 10 ready graphs

### Requirement: Every omnigraph unit runs as the static user omnigraph

`modules/nixos/omnigraph.nix` SHALL declare the system user and group `omnigraph` and run every omnigraph unit with `User` and `Group` `omnigraph`, `StateDirectory = "omnigraph"` and `DynamicUser` unset, whatever the store.
For a local `storageUri` the `omnigraph-cluster` wrapper SHALL run `omnigraph` through `runuser -u omnigraph`.

#### Scenario: either store is evaluated

- **WHEN** magnetite's configuration is evaluated with `"local"` or with `"r2"`
- **THEN** `omnigraph-server`, `omnigraph-cluster-bootstrap`, `omnigraph-cluster-apply` and each `omnigraph-seed-<graph>` have `User = "omnigraph"` and no `DynamicUser` setting, and `users.users.omnigraph.isSystemUser` is true

#### Scenario: the wrapper on each store

- **WHEN** the `omnigraph-cluster` wrapper is built for a local root and for an `s3://` root
- **THEN** only the local root's wrapper runs `omnigraph` through `runuser -u omnigraph`

#### Scenario: one owner on the dataset

- **WHEN** a dataset at `/var/lib/omnigraph` is created owned by root, the units start, and the root is then written by the bootstrap, the seeds, `omnigraph-cluster apply` run as root, the server, the recovery and a restore ending in `chown -R omnigraph:omnigraph /var/lib/omnigraph`
- **THEN** after each step the dataset's root and every file on it belong to `omnigraph`

### Requirement: The state directory survives the moves between stores and generations

`vmTests.x86_64-linux.omnigraph-state-directory-transitions`, with RustFS on the node standing in for R2, SHALL show that the first static-user start migrates a `DynamicUser` generation's private state directory with no step before it, that a switch from the local root to the bucket with the dataset mounted starts and serves, and that only a rollback to a `DynamicUser` generation with the dataset mounted fails.

#### Scenario: the first start under the static user

- **WHEN** a host whose `/var/lib/omnigraph` is a `DynamicUser` symlink to `/var/lib/private/omnigraph` starts the units under `omnigraph` on the bucket
- **THEN** systemd logs `Found pre-existing private StateDirectory= directory /var/lib/private/omnigraph, migrating to /var/lib/omnigraph.` and the server serves

#### Scenario: local to the bucket with the dataset mounted

- **WHEN** the host switches from the local root to the bucket with the dataset still mounted at `/var/lib/omnigraph`
- **THEN** every unit starts and the server serves from the bucket

#### Scenario: a rollback to a DynamicUser generation

- **WHEN** the host switches to a generation whose units run as a `DynamicUser`, first with the dataset mounted at `/var/lib/omnigraph` and then after `zfs unmount zroot/root/omnigraph`
- **THEN** the units first fail with `Device or resource busy` and status 238/STATE_DIRECTORY, then start and serve

### Requirement: Optimize is not enabled on a local root

For a local `storageUri`, evaluation SHALL fail when `services.omnigraph.optimize.enable` is set, with a message that `omnigraph optimize` leaves its admission lock behind on a local root, that the server's stale-lock recovery refuses that lock, and that the server stays down until `omnigraph-cluster force-unlock <LOCK_ID>`.

#### Scenario: the optimize timer on a local root

- **WHEN** a configuration sets `services.omnigraph.optimize.enable = true` with a local `storageUri`
- **THEN** evaluation fails with that message

#### Scenario: the optimize timer on an R2 root

- **WHEN** a configuration sets `services.omnigraph.optimize.enable = true` with an `s3://` `storageUri`
- **THEN** the assertion does not fail evaluation

### Requirement: The server's start clears a stale serve lock

For a local `storageUri`, `omnigraph-server`'s first `ExecStartPre` SHALL be `+` and the program `flake.lib.omnigraphLockRecovery` builds for the root, in no other unit and absent for an `s3://` root; its `omnigraph` calls SHALL run as `omnigraph`.
It SHALL run `cluster force-unlock <lock_id>` only in the clearing scenarios below; otherwise it SHALL leave `<root>/__cluster/lock.json` unchanged, print the reason and the manual command, announce them as `A refusal is announced` says, and exit 1.

#### Scenario: no lock

- **WHEN** the program runs and `<root>/__cluster/lock.json` is absent
- **THEN** it exits 0 and runs nothing

#### Scenario: a dead server's lock

- **WHEN** the program runs with a `serve` lock whose pid is absent and no omnigraph process naming the root
- **THEN** it runs `force-unlock` with exactly that `lock_id` and exits 0

#### Scenario: a running direct writer

- **WHEN** the program runs while `omnigraph --target /var/lib/omnigraph/clusters/cookbooks-f17 …` is running
- **THEN** it exits 1 naming that process's pid and executable name, and `lock.json` is unchanged

#### Scenario: a direct writer's lock

- **WHEN** the program runs with a lock whose `operation` is not `serve`
- **THEN** it exits non-zero naming `cluster apply --deployment-id … --writers-stopped`, and `lock.json` is unchanged

#### Scenario: a live pid in this boot

- **WHEN** the program runs with a `serve` lock whose pid exists and whose `created_at` is after `btime`
- **THEN** it exits non-zero and `lock.json` is unchanged

#### Scenario: an omnigraph server at the lock's pid after a clock step

- **WHEN** the program runs with a `serve` lock whose `created_at` is earlier than `btime` and whose pid runs an executable named `omnigraph-server` with arguments that do not name the root
- **THEN** it exits non-zero naming that pid and executable, and `lock.json` is unchanged

#### Scenario: an unreadable boot time

- **WHEN** `/proc/stat` cannot be read, or holds no integer `btime`, whether or not the lock's pid runs
- **THEN** it exits non-zero saying the boot time cannot be read, and `lock.json` is unchanged

#### Scenario: an unreadable process table

- **WHEN** `/proc` cannot be listed, or a process with a non-empty command line has an `exe` link that cannot be read, or a process named `omnigraph` outside the Nix store has a `status` that cannot be read
- **THEN** it exits non-zero naming what it could not read, and `lock.json` is unchanged

#### Scenario: a kernel thread

- **WHEN** a process has an empty command line and no readable `exe` link
- **THEN** the program skips it

#### Scenario: an id mismatch or an unreadable record

- **WHEN** `omnigraph --target <root> cluster status --json` reports a `lock_id` other than the record's, or the record lacks string `lock_id`, `operation`, `created_at` or integer `pid`
- **THEN** it exits non-zero and `lock.json` is unchanged

#### Scenario: the process scan

- **WHEN** a process whose executable is named `omnigraph` or `omnigraph-server`, and lies under `/nix/store/*-omnigraph-*/bin/` from any version or runs as root or `omnigraph`, has an argument naming the root as `/var/lib/omnigraph/…`, compared with the root after normalising both lexically, without reading the file system (runs of slashes collapsed, `.` segments dropped, a `..` segment taking away the one before it, a trailing slash removed), so that `/var/lib/omnigraph//clusters/x/../cookbooks-f17/` and `file:///var/lib/omnigraph/clusters/cookbooks-f17` name it too; a symbolic link in the argument is not followed
- **THEN** the program refuses, whatever the record says

#### Scenario: another user's executable named omnigraph

- **WHEN** a process run by a user other than root and `omnigraph`, whose executable is named `omnigraph` and lies outside the Nix store, has an argument naming the root
- **THEN** the program does not count it, and clears a dead server's lock

#### Scenario: a lock from before the boot

- **WHEN** the program runs with a `serve` lock whose `created_at` is earlier than `btime` in `/proc/stat`, its pid now belongs to an unrelated process, and no omnigraph process names the root
- **THEN** it runs `force-unlock` with exactly that `lock_id` and exits 0

### Requirement: The recovery ends only by nothing to do, a recovery or a refusal

The program SHALL end in exactly one of three ways: exit 0 with nothing run when `lock.json` is absent, exit 0 after a `force-unlock` that reports `"unlocked": true`, or a refusal as `The server's start clears a stale serve lock` describes it.
It SHALL refuse a `cluster status --json` answer that is not exactly one JSON object whose `lock_id` is a string or null, and a program it runs that is not on its PATH.

#### Scenario: an unreadable status answer

- **WHEN** `cluster status --json` exits 0 printing `not json`, `[1]`, `{"lock_id":5}`, two objects, or nothing
- **THEN** the program exits 1 saying the answer is not one JSON object with a string or null `lock_id`, posts one refusal notice, and `lock.json` is unchanged

#### Scenario: a missing program

- **WHEN** `jq` is not on the program's PATH
- **THEN** it exits 1 naming `jq`, posts one refusal notice, and `lock.json` is unchanged

### Requirement: An unforeseen failure in the recovery is refused once

Through an `ERR` trap that functions and command substitutions inherit, the program SHALL refuse any failing step that no guard covers, naming the failing command, its line and its exit status; in a subshell the trap SHALL only pass the status on, and the refusal SHALL disarm the trap, so that the program refuses once and exits 1 whether or not its post succeeds.

#### Scenario: an unforeseen failure

- **WHEN** the program's working directory for `omnigraph` cannot be made
- **THEN** it exits 1 naming the failing `mktemp -d` and its exit status, posts one refusal notice whether the post succeeds or fails, and `lock.json` is unchanged

### Requirement: Recoveries are counted and announced

After a successful `force-unlock`, the program SHALL add one to the integer in `/var/lib/omnigraph-metrics/lock-recoveries` (starting from 0 when absent) and post one message at low priority to the `fleet-alerts` topic through `ntfy-send` with `services.observability-notify.tokenFile`, naming the host, the root and the cleared `lock_id`; a failed post SHALL NOT fail the start.

#### Scenario: one recovery

- **WHEN** the program clears one lock on a host whose counter file holds 2
- **THEN** the file holds 3 and one low-priority message naming the `lock_id` is posted

### Requirement: A recovery that cannot be counted is still announced

After a successful `force-unlock`, a counter that cannot be written SHALL be logged and named in the recovery message in place of the count, the message SHALL still be posted, and the program SHALL exit 0.

#### Scenario: a counter that cannot be written

- **WHEN** the program clears one lock and the counter's directory cannot be made
- **THEN** it exits 0, logs `the lock-recovery counter <file> could not be written`, and posts one low-priority message naming the `lock_id`

### Requirement: A refusal is announced

Every refusal, and a `force-unlock` that does not report `"unlocked": true`, SHALL post one message at default priority to the `fleet-alerts` topic through `ntfy-send` with `services.observability-notify.tokenFile`, titled `omnigraph lock not recovered on <host>`, carrying the printed reason and manual command; a post that fails or does not finish in 30 s SHALL be logged and SHALL NOT change the exit status 1.

#### Scenario: a refusal's notice

- **WHEN** the program refuses for any reason of `The server's start clears a stale serve lock`
- **THEN** it posts exactly one such message and exits 1, whether the post succeeds or fails

#### Scenario: nothing to do

- **WHEN** the program runs and `lock.json` is absent
- **THEN** it posts nothing

### Requirement: A refusal's message carries no record, token or argument

A refusal's message MAY name the root's path, the lock's `lock_id`, `operation`, `pid` and `created_at`, and a process's pid and executable name; it SHALL carry no line of `lock.json`, no token and no argument of any process, whose command line the program prints to the journal only.

#### Scenario: a refusal that names a process

- **WHEN** the program refuses because of a running process whose command line is `omnigraph --target /var/lib/omnigraph/clusters/cookbooks-f17 load --data /tmp/seed.jsonl`
- **THEN** the message names that process's pid and `omnigraph` and none of its arguments, and the journal holds `pid <pid> runs <exe>: omnigraph --target … load --data /tmp/seed.jsonl`

### Requirement: A rehearsal holds the recovery's verdicts

`checks.x86_64-linux.omnigraph-lock-recovery-rehearsal`, class `small`, SHALL run the program from `flake.lib.omnigraphLockRecovery` against stubs of `omnigraph` and `ntfy-send`, a scripted process table and boot time, and a fresh lock directory per row, asserting for each scenario of the recovery's requirements above the exit status, the stubs' logs, the counter and the lock file.

#### Scenario: the check runs

- **WHEN** `nix build .#checks.x86_64-linux.omnigraph-lock-recovery-rehearsal` runs
- **THEN** every row passes, the rows where a writer or the configured root spells the root with doubled slashes, a `.` segment, a trailing slash or a `file://` prefix and the row where the refusal's post fails included; a mutant that skips the process scan fails the running-writer row, one that accepts any boot time fails the unreadable-boot-time rows, and one that lets the boot time excuse an omnigraph server at the lock's pid fails the clock-step row

#### Scenario: the packaged record

- **WHEN** a release of the packaged omnigraph changes the record `omnigraph-server` leaves when killed
- **THEN** the check's row over a record written by the packaged `omnigraph-server` fails

#### Scenario: the rows of the second verification

- **WHEN** the check runs
- **THEN** the rows for an unreadable status answer, `jq` missing from the PATH, a failing working directory with and without a failed post, an unwritable counter, and writers naming the root through `..` pass; every refusal exits 1 and its notice holds no argument of a process; a mutant without the status answer's guard fails the status-answer row, and one without the `ERR` trap fails the failing-step row

### Requirement: The backup job copies a ZFS snapshot to its R2 repository

With `vanixiets.omnigraphBackup.enable`, `services.restic.backups.omnigraph` SHALL back up only `/var/lib/omnigraph/.zfs/snapshot/restic`, a snapshot its prepare step takes fresh and its cleanup step destroys, to repository `sciexp-omnigraph-backup/<hostName>` at the account's R2 endpoint, and the module SHALL assert that `services.omnigraph.storageUri` is a local path.

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

### Requirement: The backup job removes stale repository locks before it backs up

The first `ExecStart` of `restic-backups-omnigraph`, and of `restic-backups-postgresql` in `modules/nixos/postgresql-backup.nix`, SHALL be `restic unlock`, before `restic backup`, so that an exclusive lock that a prune or check left when its run was cut short does not stop the backup; `unlock` removes only locks older than 30 minutes or taken on the same host by a process that is gone (restic 0.20.0, `internal/repository/lock_file.go`).

#### Scenario: a stale exclusive lock

- **WHEN** a `restic prune` against the repository is killed while it holds its exclusive lock, and the job then runs
- **THEN** the job removes that lock, backs up and leaves no lock

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

### Requirement: The probe reports a failed per-graph read

With the `monitor` token, the probe SHALL publish `vanixiets_omnigraph_graph_reads_ok`, 1 when `GET /graphs` and the snapshot read of every ready graph succeeded and 0 otherwise, SHALL log `omnigraph-probe: GET <path> answered HTTP <status>` for each failed request, with status `000` for no HTTP answer, and SHALL still exit 0; the series SHALL be in `nodeExporterKeep`.

#### Scenario: the monitor actor is refused

- **WHEN** the probe runs while the server answers `GET /graphs` with 403
- **THEN** `omnigraph.prom` holds `vanixiets_omnigraph_graph_reads_ok 0` and no per-graph series, the journal holds `omnigraph-probe: GET /graphs answered HTTP 403`, and the unit succeeds

#### Scenario: every read succeeds

- **WHEN** the probe runs on a served root the `monitor` actor may read
- **THEN** `omnigraph.prom` holds `vanixiets_omnigraph_graph_reads_ok 1`

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

`vmTests.x86_64-linux.omnigraph-local-root`, declared `medium` in `testSizes.vmTests`, SHALL boot a VM with ZFS, a dataset created owned by root and mounted at `/var/lib/omnigraph`, and the real omnigraph, probe and backup modules, and SHALL assert the scenarios below and the scenario `one owner on the dataset`.

#### Scenario: crash and recovery

- **WHEN** the server is killed with `kill -9` after seeding and restarted
- **THEN** it serves the same entity counts and stored-query answer, and the recovery counter is 1

#### Scenario: refusal while a direct writer holds the root

- **WHEN** a direct `omnigraph` writer holds the root and the server is started
- **THEN** the start fails with the reason, the refusal's message is attempted, and `lock.json` is unchanged

#### Scenario: backup and restore

- **WHEN** a backup to a local restic repository is taken, the dataset emptied, the backup restored with `restic-omnigraph restore`, its files given to `omnigraph` with `chown -R`, and its lock removed with `omnigraph-cluster force-unlock`
- **THEN** the server serves the same entity counts and stored-query answer, and every probe series is present

#### Scenario: a prune killed while holding its lock

- **WHEN** a `restic prune` is killed with SIGKILL after writing its exclusive lock to the local repository, and the backup job is started
- **THEN** the job succeeds, the repository holds one more snapshot, and no lock remains

#### Scenario: a reboot

- **WHEN** the VM reboots
- **THEN** the dataset is mounted before the units, whose `RequiresMountsFor` names it, and the server serves the same answers

#### Scenario: the test runs on pyrite

- **WHEN** `nix build .#vmTests.x86_64-linux.omnigraph-local-root` runs on pyrite
- **THEN** it passes within the medium limit of 300 s
