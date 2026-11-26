## Context

magnetite runs `omnigraph-server` 0.16.0 over the cluster root `s3://sciexp/omnigraph/clusters/cookbooks-f17`, serving ten example graphs, one per cookbook of the pinned `omnigraph-cookbooks`, each seeded once by `omnigraph-seed-<graph>` after the create-once bootstrap made the root (`modules/machines/nixos/magnetite/default.nix`, `services.omnigraph`; `modules/nixos/omnigraph.nix`; `modules/lib/omnigraph-bootstrap.nix`).
The bucket `sciexp` is declared with `location = "enam"` (`modules/terranix/cloudflare.nix`); magnetite is a Hetzner CX53 in fsn1 (`modules/lib/cloud-machines.nix`).
A start takes about 4 min 50 s to open the ten graphs; the root took about 26 min to create.
The R2 settings are `s3.endpointUrl`, `s3.region = "auto"`, the `omnigraph-r2` generator's `EnvironmentFile`, and `OMNIGRAPH_CLUSTER_LEASE_SECONDS = "120"`.

What the omnigraph module already does for a local root:
- `storageUri` may be a plain path or `file://`; with the bootstrap on, an assertion requires it beneath `/var/lib/omnigraph`, the units' `StateDirectory`, because every unit runs with `ProtectSystem=strict` and `DynamicUser` and has no `ReadWritePaths`.
- The bootstrap creates a missing local root directory and keeps its markers as files in `<parent>/_omnigraph-markers/`.
- `vmTests.x86_64-linux.omnigraph-seed` serves `/var/lib/omnigraph/clusters/test` with magnetite's graphs and policies.
- The server unit's `ExecStartPre` assembles the bearer tokens file from the tokens file and each seed actor's token; `ExecStartPost` is the readiness probe (`modules/lib/omnigraph-readiness.nix`); `Restart=on-failure` with a start limit sized from the readiness timeout.
- The sandbox includes `ProtectProc=invisible`, `ProcSubset=pid` and `PrivateUsers=true`.

On magnetite, `/var/lib/omnigraph` is a symlink to `private/omnigraph`, root-owned, dated Aug 6 (observed 2026-11-26); `/var/lib/private` is `0700 root`.
Pool `zroot` holds 188 GiB with 111 GiB free; datasets created by hand on the installed host are declared in `disko.nix` for a reinstall and their properties are enforced by `zfs-set-*` and `zfs-assert-*` oneshots in `default.nix` (`root/greptimedb`, `root/postgresql-dumps`).
`services.zfs.autoSnapshot` keeps hourly 4, daily 3, weekly 1.

What the fleet already has that this change reuses:
- `modules/nixos/postgresql-backup.nix`: restic to a dedicated R2 bucket under the host's name, generated restic password, prompted R2 keys, a success stamp in `ExecStartPost`, a minutely publisher into the one textfile directory (`vanixiets.nodeExporter.textfileWriters`), `nodeExporterKeep`, and `PostgresqlBackupStale` at 36 h; its job and timer naming a zone, as `observability-notify` asserts for notified units.
- `modules/nixos/fleet-alert/rules.nix` with promtool cases, threshold mutants, fixture series and fire-and-resolve legs in `modules/checks/fleet-alert.nix`.
- Perses views provisioned from `modules/nixos/perses/resources/`, each placed in `queryChecked` or `notQueryChecked` in `modules/vm-tests/perses-greptimedb.nix`, linted by `checks.x86_64-linux.perses-lint`.
- The filesystem scraper covers every `fileSystems` entry of type `zfs`, so a dataset declared in disko falls under `FilesystemFillingWarn` and `FilesystemFull` without a rule change.

A separate change, in flight, fixes the collector's systemd allow-list entry (`omnigraph.service` on trunk, `schema.nix:30`) to `omnigraph-server.service` and adds `omnigraph-server` to magnetite's `notifiedUnits`.
This change assumes that lands first or alongside, and does not edit those two lines.

The evidence is nine research reports of 2026-11-26 and the operator's decisions recorded in `brainstorm.md`; the key one is a crash probe of a local root with the packaged 0.16.0 binary.

Stakeholders: the operator, who restores, holds the secrets and pays for R2; agents and people on pyrite and the Macs who query the graphs through cinnabar's fronts.

## Goals / Non-Goals

**Goals:**
- Watch the server that runs today, on R2, before anything moves.
- Serve magnetite's graphs from its own disk, with R2 still selectable per host.
- Restart after a crash without a person when, and only when, nothing else can hold the root.
- An off-host copy every night, restorable to identical answers, with an alert when it is overdue.
- Prove crash, refusal and restore in a runtime test before the switch.

**Non-Goals:**
- Copying `cookbooks-f17` from R2 to disk: the graphs are example data, seeded fresh.
- Trace export, a JSON log receiver, scheduled `omnigraph cleanup` (D11).
- Turning on `omnigraph-optimize`, or served optimize.
- The collector's unit name and the server's failure notice (separate change).
- Any client-side change: the URL stays.
- Hetzner Object Storage, a self-hosted S3 server, or a new R2 location for the graph data.

## Decisions

### D1: The graph data lives on a dataset of its own on magnetite's disk
- **Choice**: dataset `zroot/root/omnigraph`, `quota=20G`, auto-snapshot inherited (on), mounted at `/var/lib/private/omnigraph/clusters`. The root is `/var/lib/omnigraph/clusters/cookbooks-f17`; its bootstrap markers sit in `clusters/_omnigraph-markers/`, on the same dataset, so one snapshot holds the root and its markers together.
- **Rationale**: OmniGraph allows one writer and no replicas (A231), so storage local to the one writer loses nothing; Lance ranks local NVMe fastest; the quota keeps the graph data from starving the pool. The mountpoint is under `private/` because `/var/lib/omnigraph` is systemd's symlink (A241), and a mount on the symlink's path would block systemd's handling of the state directory.
- **Alternatives considered**: Hetzner Object Storage (conditional writes undocumented on unversioned buckets, HDD, its FAQ advises against this workload; A237); a new R2 bucket in western Europe (still a network round trip per request, and R2's latency is unmeasured from fsn1); a self-hosted S3 server on the same disk (a second service to run for no gain over the filesystem); dropping `DynamicUser` to mount at `/var/lib/omnigraph` (migrates the state directory of every omnigraph unit; larger than needed).
- **Boundary**: source versus delivered: disko declares the dataset only for a reinstall; on the installed host the operator creates it once (D12).

### D2: The new root is created and seeded by the existing bootstrap
- **Choice**: no data migration. With the root pointed at the empty local path, `omnigraph-cluster-bootstrap` finds no state and no marker, creates the directory, writes seed-pending markers, applies, and the seed units load each cookbook's seed once the server serves.
- **Rationale**: the ten graphs are example data whose seeds are pinned; a fresh root is the path the module already proves.
- **Alternatives considered**: `rclone` or `aws s3 sync` of the live R2 root (a copy of a live root is not safe, A234, and stopping the server for a 26-minute download buys example data).

### D3: One host setting selects disk or R2 for the same root name
- **Choice**: `flake.lib.omnigraphClusterRoots` gains `localDirectory = "/var/lib/omnigraph/clusters"` and `uriIn = store: root:` returning `"${localDirectory}/${root}"` for `"local"` and the existing `s3://` URI for `"r2"`; `rootOf` also recognises a local URI. magnetite holds one `let` value `omnigraphRootStore` (`"local"` or `"r2"`) and derives `storageUri` from it; `s3`, `environmentFile` and `OMNIGRAPH_CLUSTER_LEASE_SECONDS` are set only for `"r2"`. The `omnigraph-r2` generator, the lifecycle rules, `retired`, `rollback` and `checks.omnigraph-retired-roots` are unchanged. Local-only behaviour (D4, D5, the dataset series in D6) keys off the URI being a plain path, which the module already classifies.
- **Rationale**: the root name already records the storage format; the same name in both places keeps the format window and the retired-roots logic one concept. Switching back is one value; R2's root is what it was when the host left it, and the R2 markers make the bootstrap a no-op there.
- **Alternatives considered**: a `services.omnigraph` option naming R2 (couples the generic module to one provider); deleting the R2 settings (makes the way back a revert of several hunks).

### D4: The server's own start clears a crashed server's lock, and nothing else does
- **Choice**: `flake.lib.omnigraphLockRecovery` builds a program that the server unit runs as its first `ExecStartPre`, with the `+` prefix, only when the root is local. It reads `<root>/__cluster/lock.json` and:
  1. no lock file: exit 0;
  2. any process whose executable is the packaged `omnigraph` or `omnigraph-server` and whose argv names the root (either `/var/lib/omnigraph/...` or `/var/lib/private/omnigraph/...`): refuse;
  3. the record is not well-formed, or `omnigraph --target <root> cluster status --json` reports a `lock_id` other than the record's: refuse;
  4. `operation` is not `serve`: refuse, naming the direct writer's recovery (`cluster apply --deployment-id … --writers-stopped`);
  5. the pid exists in `/proc` and `created_at` is not before the current boot (`btime` in `/proc/stat`): refuse;
  6. otherwise run `omnigraph --target <root> cluster force-unlock <lock_id> --json`, require `"unlocked": true`, add one to the counter in `/var/lib/omnigraph-metrics/lock-recoveries`, post an info notice, and exit 0.
  A refusal exits non-zero with the reason and the exact manual command; the start job fails, `Restart=on-failure` retries within the start limit, and the failure notice reports it.
- **Rationale**: a local lock is never taken over and `force-unlock` checks only the id (A232); without this, every crash needs a person. `+` is needed because the sandbox hides other users' processes (`ProtectProc=invisible`, `PrivateUsers`) and a direct writer run through `omnigraph-cluster` runs as root. Running before the server starts, and only there, means no second unit can race the server's own start; the bootstrap and apply units are ordered before the server.
- **Alternatives considered**: a separate recovery unit (`Before=`/`Conflicts=` ordering to keep in step with the server's restarts, for nothing); trusting the pid alone (pids are reused, and the record carries no boot id); unlocking a non-`serve` lock (a direct writer's interrupted work needs its own recovery, not a bare unlock).
- **Boundary**: first-party program over a vendored binary's on-disk record; the record's meaning is A232 and is checked at each OmniGraph bump by the rehearsal and the runtime test.

### D5: Nightly backup from a ZFS snapshot to `sciexp-omnigraph-backup`
- **Choice**: `modules/nixos/omnigraph-backup.nix`, `vanixiets.omnigraphBackup.enable`, modelled on `postgresql-backup.nix`: `services.restic.backups.omnigraph` with repository `s3:<account endpoint>/sciexp-omnigraph-backup/<hostName>`, `s3.bucket-lookup=path`, `s3.region=auto`; `backupPrepareCommand` destroys any leftover `zroot/root/omnigraph@restic` and takes it anew; `paths = [ "/var/lib/private/omnigraph/clusters/.zfs/snapshot/restic" ]`, a fixed path so restic finds its parent snapshot; `backupCleanupCommand` destroys the snapshot; `--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --group-by host`; `--read-data-subset=10%`; `OnCalendar = "*-*-* 03:30:00 UTC"`, `RandomizedDelaySec = "15m"`, `Persistent = true`. Generators `omnigraph-backup-r2` (prompted, hidden) and `omnigraph-backup-restic` (generated). The success stamp `vanixiets_omnigraph_backup_last_success_timestamp_seconds` and its minutely publisher follow the PostgreSQL module. terranix declares `cloudflare_r2_bucket.sciexp-omnigraph-backup` with `prevent_destroy` and no lifecycle rule. The module asserts the root is local and the job is in the host's `notifiedUnits`.
- **Rationale**: a snapshot is an instant image (A235); a live copy is not safe (A234). 03:30 keeps the job apart from the PostgreSQL job's memory at 02:30.
- **Alternatives considered**: `zfs send` to a remote pool (no second pool exists); stopping the server for a copy (an outage every night); `omnigraph export` (logical, per branch, and loses the cluster ledger).
- **Boundary**: first-party module over nixpkgs' restic module, as the PostgreSQL backup.

### D6: A minutely probe publishes the server's state to the textfile collector
- **Choice**: `modules/nixos/omnigraph-probe.nix`, on with `services.omnigraph.enable` on a host with the textfile collector; `omnigraph-probe.service` (oneshot, `MemoryMax=32M`) and a 60 s timer, writer `omnigraph`. Series, each added to `nodeExporterKeep`:
  - `vanixiets_omnigraph_ready` (1 only when `/readyz` answers `ready: true`; 0 when it answers otherwise or not at all);
  - `vanixiets_omnigraph_graphs{state="served|ready|loading|blocked"}`;
  - `vanixiets_omnigraph_start_to_ready_seconds` (from `omnigraph-server`'s `ExecMainStartTimestampMonotonic` and `ActiveEnterTimestampMonotonic`);
  - with the monitor token: `vanixiets_omnigraph_graph_entities{graph}` (sum of `entity_count` of `GET /graphs/{id}/snapshot`), `vanixiets_omnigraph_graph_manifest_version{graph}`, `vanixiets_omnigraph_graph_storage_format{graph}`;
  - on a local root: `vanixiets_omnigraph_dataset_used_bytes`, `vanixiets_omnigraph_dataset_quota_bytes`, `vanixiets_omnigraph_dataset_snapshots`, and `vanixiets_omnigraph_lock_recoveries_total` from D4's counter.
  The file is written then renamed; a failed per-graph read omits that graph's series and leaves the readiness series.
  Settled in implementation: the probe runs as node_exporter's user, not a `DynamicUser`, because a `DynamicUser`'s files sit under `/run/private`, which node_exporter cannot traverse (as `magnetite-memory-budget.nix` found). The per-graph reads list the graphs with `GET /graphs` (action `graph_list`) and read the snapshot of each graph whose `state` is `ready`; both routes refuse a request without the `Omnigraph-Http-Api` header, whose value the probe takes from the same header on the `/readyz` answer, which the server sets on every response. A ZFS series names the dataset mounted at the root's parent directory, under `/var/lib/omnigraph/…` or `/var/lib/private/omnigraph/…`; with none the dataset series are left out. `vanixiets_omnigraph_lock_recoveries_total` is 0 while D4's counter file is absent. The probe is on only where node_exporter runs, so a VM serving omnigraph without it, as `vmTests.x86_64-linux.omnigraph-seed`, gets no probe.
- **Rationale**: OmniGraph has no metrics endpoint (A238); the textfile collector is the fleet's pattern; `HostProbeStale` already reports a probe that stops.
- **Alternatives considered**: scraping `/metrics` (none exists); log-derived counters (D11).

### D7: A read-only `monitor` actor with a generated token
- **Choice**: generator `omnigraph-monitor-token` on magnetite; `services.omnigraph` gains `extraBearerTokenFiles` (actor name to token file), merged by the existing `ExecStartPre` exactly as seed tokens are, refusing an actor already named; the probe receives the same file by `LoadCredential`. `server.policy.yaml` grants group `monitors: [monitor]` `graph_list`; `examples.policy.yaml` grants it `read` and nothing else. `checks.omnigraph-cluster-actor-policy` gains allow cases for those and deny cases for `change`, `export`, `schema_apply` and `maintain`, and for `config_manage` on the `cluster` bundle. An extra actor that is also a seed actor fails evaluation, as two seed actors with different token files do.
- **Rationale**: per-graph counts need a token; a separate actor keeps `admin`'s token off a minutely timer.
- **Alternatives considered**: the admin token (broad write access in a probe); the seeder (`change` on `main`).
- **Boundary**: the policy reaches a root only through an apply; the new local root gets it at creation, the R2 root only through a hand-run apply (Open Questions 2).

### D8: Two rules
- **Choice**: in `rules.nix`, `OmnigraphNotServing`: `vanixiets_omnigraph_ready == 0 or vanixiets_omnigraph_graphs{state="blocked"} > 0`, `for = "5m"`, warning; `OmnigraphBackupStale`: `time() - vanixiets_omnigraph_backup_last_success_timestamp_seconds > 129600`, `for = "10m"`, warning. Each gets a promtool case with a threshold mutant, a fixture series in `fleet-alert/fixtures/series.json`, and a fire-and-resolve leg in `legs`. The annotations name the runbook.
- **Rationale**: the two failure classes a person must act on; the 36 h window is the PostgreSQL backup's.
- **Alternatives considered**: a lock-recovery rule (D4 posts its own notice; recoveries are expected events, not failures).

### D9: A Perses view and docs
- **Choice**: `modules/nixos/perses/resources/dashboard-omnigraph.json` in project `fleet`, datasource `greptimedb-promql`, panels: readiness and graph states, start-to-ready seconds, entities per graph, manifest version and format per graph, dataset used against quota, snapshot count, backup age, lock recoveries, `omnigraph-server` memory. Placed in `queryChecked`. Docs: `fleet-observability.md`'s alert table, and a runbook `packages/docs/src/content/docs/development/operations/omnigraph.md` beside `postgresql-backup.md`, begun with the monitoring and completed with recovery, restore and switching back.

### D10: A runtime test with ZFS in the VM
- **Choice**: `vmTests.x86_64-linux.omnigraph-local-root`, `testSizes.vmTests.omnigraph-local-root.class = "medium"` with `measured = false` until a run backs it; one node with `boot.supportedFilesystems = [ "zfs" ]`, a second virtual disk holding a pool, the dataset at `/var/lib/private/omnigraph/clusters`, the real omnigraph, probe and backup modules, two of magnetite's graphs, and a restic repository on a local path. Cases: seeded counts and a stored query's answer; `kill -9` of the server, restart with recovery, same counts and answer, counter 1; a held `omnigraph` direct writer on the root makes the start refuse with the reason; backup, wipe the dataset, restore, the restored lock unlocked, identical counts and answer; the probe's series present. Run on pyrite.
- **Rationale**: the recovery and restore act on real files and processes; only a VM shows them end to end.

### D11: No traces, no JSON log receiver, no scheduled cleanup
- **Choice**: none of the three.
- **Rationale**: OmniGraph's exporter trusts only public certificate authorities (A239) and the fleet's collector serves an internal one; the fatal log events end the server process, which the readiness rule and the failure notice already report; `cleanup` runs only with the server stopped (A240), which an unattended timer would turn into a nightly outage. At 20 GiB of quota against a few MB of data, growth is watched by the dataset series and the filesystem rules instead.

### D12: Three delivery commits and a gated rollout
- **Choice**: (1) monitoring of the running server; (2) local-root support with magnetite still on R2; (3) magnetite's switch. The operator's hand steps (dataset, bucket apply, token, vars) sit between (2) and (3).
- **Rationale**: each commit evaluates and deploys on its own; (2) changes nothing on magnetite's running server.

## Risks / Trade-offs

- [Risk] The disk is lost with magnetite. → Mitigation: nightly off-host copy (D5), recovery point at most 24 h plus margin; the graphs are example data and reseedable.
- [Risk] Recovery unlocks a lock a live writer holds. → Mitigation: refuse on any omnigraph process naming the root, on a non-`serve` lock, on an id mismatch, and on a live pid within the boot (D4); the rehearsal and the runtime test hold each refusal.
- [Risk] A refused start leaves the server down. → Mitigation: the start fails visibly; `OmnigraphNotServing` and the failure notice report it; the reason names the manual command.
- [Risk] systemd re-owns the state directory after the dynamic uid changes and does not reach into the mounted dataset. → Mitigation: the hand step sets the dataset root's owner to the state directory's; the runtime test runs the real module over the mount; Open Questions 1.
- [Risk] `OmnigraphNotServing` fires during an R2 start (about 4 min 50 s, close to the 5 min window). → Mitigation: accepted for the days between commits (1) and (3); on disk a start takes seconds.
- [Risk] OmniGraph changes its lock record in a later release. → Mitigation: the program refuses a record it cannot read; the rehearsal runs against the packaged binary's record at every bump.
- [Trade-off] Switching back to R2 loses local writes. → Accepted: example data; the runbook says so.
- [Trade-off] Local snapshots and the off-host copy both hold the restic snapshot only briefly; auto-snapshots pin old Lance files for up to a week. → Accepted within 20 GiB.

## Migration Plan

1. Commit (1): deploy magnetite; the probe and `OmnigraphNotServing` watch the R2 server. Per-graph series appear only if the operator applies the policy to the R2 root by hand (Open Questions 2).
2. Commit (2): deploy magnetite; `nix eval` shows `storageUri` unchanged (`s3://…/cookbooks-f17`), no recovery `ExecStartPre`, no backup job. Run `vmTests.x86_64-linux.omnigraph-local-root` on pyrite.
3. Operator: create the dataset (`zfs create -o mountpoint=/var/lib/private/omnigraph/clusters -o quota=20G zroot/root/omnigraph`, then `chown --reference=/var/lib/private/omnigraph /var/lib/private/omnigraph/clusters`); `just terraform-plan -target=cloudflare_r2_bucket.sciexp-omnigraph-backup`, apply only after an explicit yes, commit the state; mint a token for that bucket alone; `clan vars generate magnetite` for `omnigraph-backup-r2` and `omnigraph-backup-restic`. The `omnigraph-monitor-token` vars land with commit (1).
4. Commit (3): `omnigraphRootStore = "local"`, the dataset in disko, its oneshots, `vanixiets.omnigraphBackup.enable`, the notified units. Deploy: the bootstrap creates and seeds `/var/lib/omnigraph/clusters/cookbooks-f17`; record start-to-ready seconds; read every alert and notice posted since the deploy began.
5. Rollback: activate the previous generation; it serves `cookbooks-f17` on R2, untouched, whose markers make the bootstrap a no-op. The local dataset stays.

## Open Questions

1. Does systemd's recursive re-owning of a `DynamicUser` state directory reach into a dataset mounted below it? Recommended: settle it in the runtime test by changing the owner of `/var/lib/private/omnigraph` before a start; if it does not reach, add a `tmpfiles` `Z` rule for the clusters path.
2. Apply the `monitor` policy to the R2 root by hand during stage (1)? It needs the server stopped and an apply over R2. Recommended: no; stage (1) watches readiness only on R2, and the per-graph series arrive with the local root, whose bootstrap applies the policy.
3. The info notice: a direct `ntfy-send` post at low priority to `fleet-alerts` using `services.observability-notify.tokenFile`, or a third rule over the counter? Recommended: the direct post, as the operator fixed the rule set at two.
4. Location of `sciexp-omnigraph-backup`: recommended `enam`, matching `sciexp-postgresql-backup`.
5. Are A231 to A241 free at merge time? The highest number in the corpus and in-flight changes is A230.
6. Which policy action does `GET /graphs/{id}/snapshot` check? Settled: `read` on the requested branch, `main` by default (`server_snapshot` in omnigraph 0.16.0's `crates/omnigraph-server/src/handlers.rs`), and `GET /graphs` checks `graph_list` against the `cluster` bundle (`server_graphs_list`). The policy check can only hold the actor to those actions, not show which action a route checks, so the source is the evidence.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
The repository has no BDD runner and no `.feature` file, so no row routes to a Gherkin scenario, and no requirement routes to an executable-specification modality. Each requirement is witnessed by a build gate (`nix eval`, `nix build` of a check), the rehearsal check, the runtime test, or a smoke observation on magnetite recorded in `verify.md`.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| Graph data lives on the disk of the host that serves it | `graph-store` | behavioral | build gate and smoke | tasks 4.1, 4.3, 5.1 |
| The storage location is chosen per host and switching back serves what the bucket held | `graph-store` | behavioral | build gate and smoke | tasks 2.1, 4.3, 5.4 |
| The graph store recovers from its own crash without a person | `graph-store` | behavioral | rehearsal check, runtime test | tasks 2.2, 2.3, 2.6 |
| The graph store refuses to clear a writer claim it cannot prove stale | `graph-store` | behavioral | rehearsal check, runtime test | tasks 2.2, 2.3, 2.6 |
| Graph data is copied off its host every night from an instant image | `graph-store` | behavioral | build gate, runtime test and smoke | tasks 2.4, 2.6, 5.3 |
| Graph data can be restored to identical answers | `graph-store` | behavioral | runtime test and runbook drill | tasks 2.6, 2.7, 5.3 |
| Local snapshots stay available | `graph-store` | behavioral | build gate and smoke | tasks 4.1, 5.2 |
| The operator learns when the graph store is not serving | `graph-store` | behavioral | build gate (fleet-alert check) and smoke | tasks 1.3, 1.6, 5.1 |
| The operator learns when graph backups are overdue | `graph-store` | behavioral | build gate (fleet-alert check) | task 2.5 |
| The graph store's state is visible on a dashboard | `graph-store` | behavioral | build gate (perses checks) and smoke | tasks 1.4, 1.6, 5.1 |
| Each `graph-store-interface` requirement | `graph-store-interface` | interface | build gate, rehearsal check and runtime test | tasks 1.1-1.5, 2.1-2.6, 4.1-4.3 |
| A231-A241 | `world-assumptions` | world | violation condition | A232, A233 and A234 by 2.3 and 2.6 at each OmniGraph bump; A235 by 2.6; A236 and A237 by review before a store change; A238 and A239 by review at each OmniGraph bump; A240 by review before automating cleanup; A241 by 3.1 |
