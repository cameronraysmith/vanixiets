---
title: "ADR-007: Packaging, host placement and clan service shape"
---

## Status

Proposed

## Context

Charter D7 asks for one packaging strategy, one host placement and the clan service shape.
The human gate of 2026-10-06 placed GreptimeDB on `magnetite`; this record confirms that placement against the memory evidence that has accumulated since, and states the containment it requires.
ADR-001 fixes the store as GreptimeDB standalone consumed from the root nixpkgs pin, ADR-006 fixes R2 as its substrate and a daily Parquet export, ADR-003 fixes the collection topology, and ADR-002 fixes the dashboard layer.
This record depends on four of their assumptions: only the `ingress` collector on `magnetite` writes to the store, over loopback (ADR-003); Perses on `magnetite` reads the store over loopback with a read-only credential (ADR-002); no MySQL or PostgreSQL wire port is needed (ADR-002); and the databases are `fleet`, `devloop` and `agent` with TTLs of 30, 365 and 90 days (ADR-004).

### Packaging evidence

`pkgs.greptimedb` is 1.1.4 at the root pin, lock node `nixpkgs_10` at `ac1faec4`, with `mainProgram = "greptime"`, and its outputs are cache-resident for `x86_64-linux` and `aarch64-darwin` (`NixOS/nixpkgs@ac1faec4:pkgs/by-name/gr/greptimedb/package.nix:15`, `:85`, root node `nixpkgs_10`; `research/nix-packaging-status.md` R2, R4).
The derivation is a from-source `buildRustPackage` with a pinned `cargoHash` and `RUSTC_BOOTSTRAP = 1` (`NixOS/nixpkgs@ac1faec4:pkgs/by-name/gr/greptimedb/package.nix:26`, `:61`, root node `nixpkgs_10`), so changing its version changes both the source hash and the vendored-crate hash and forfeits the cache.
A source build of this workspace takes about 34 minutes on eight cores (`research/nix-packaging-status.md` F14).
The bump to 1.2.1 is open upstream as https://github.com/NixOS/nixpkgs/pull/574558 (`research/nix-packaging-status.md` R6).
Upstream publishes a checksummed `greptime-linux-amd64-v1.2.1.tar.gz` (`research/nix-packaging-status.md` R15), and the house `-bin` convention exists (`research/nix-packaging-status.md` F18, F19).
The nixpkgs build omits the embedded dashboard (`research/nix-packaging-status.md` R9), which ADR-002 does not need.
No NixOS module for GreptimeDB exists in any nixpkgs revision, so the module is ours to write (`research/nix-packaging-status.md` R8).

### Placement evidence

`magnetite` is a Hetzner `cx53` with 16 vCPU and 30.6 GiB RAM (`cameronraysmith/vanixiets@109c67346:modules/terranix/hetzner.nix:24-29`, `research/otel-collector-topology.md` F39).
Charter RK3 has fired: overlapping evaluations OOM-killed the host on 2026-09-27 and 2026-10-01 (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:5-7`).
nixbot evaluates under `MemoryHigh = "12G"` with no `MemoryMax`, and its peak occupies about 6.9 GiB of real RAM inside zram (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:13`, `cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:444-448`).
The zram pool is charged to no cgroup, so a service's swapped pages occupy RAM outside every limit on the host (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:49-51`).
The host now serializes evaluations behind a lock that sets the evaluator's `oom_score_adj` to 900, and `nix-daemon` runs at 250 from srvos (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:16`, `:60-64`).
The minimum `MemAvailable` measured during one nixbot `8 x 4096` evaluation under `MemoryHigh = 12G` was 7.89 GiB, in a measurement log that is not committed and therefore not A2-resolvable; the committed incident note names that log as the source of nixbot's sizing (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:14`).
Deferred phase-2 work on that host includes `MemoryLow` floors for critical services and `MemorySwapMax` per workload (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:79-86`).

GreptimeDB auto-sizes its caches and buffers from host RAM unless each knob is set (`research/greptimedb.md` F32, F33), and every knob is overridable at `v1.2.1`: `global_write_buffer_size`, `sst_meta_cache_size`, `vector_cache_size`, `page_cache_size`, `selector_result_cache_size`, `range_result_cache_size`, `experimental_compaction_memory_limit`, the query `memory_pool_size` defaulting to 50% of RAM, `scan_memory_limit` defaulting to unlimited, and `max_in_flight_write_bytes` defaulting to unlimited (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:33`, `:441`, `:615`, `:627-664`, `:709`).
With R2 storage the local disk still holds the WAL, the metadata store, and read and write caches that default to 5 GB and 5 GiB (`research/greptimedb.md` R21-R23).
`magnetite`'s documented failures are storage exhaustion, which produced the `/nix` quota and the `/` and `/home` reservations (`research/fleet-emitter-inventory.md` F20, `cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/disko.nix:41-70`).
Disko options apply only at dataset creation, so the host asserts quotas and reservations with boot-time oneshots (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:226-263`).

`cinnabar` is a `cx43` with 8 vCPU and 16 GB RAM, is the ZeroTier controller, and serves the `.zt` resolver for the whole fleet (`cameronraysmith/vanixiets@109c67346:modules/terranix/hetzner.nix:10-15`, `research/otel-collector-topology.md` R19).
`pyrite` is a 15.5 GiB laptop that is also a daily driver and has livelocked under zram pressure (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/pyrite/default.nix:497-500`, `cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:449-450`).

### Default listeners and egress

At `v1.2.1` the HTTP, gRPC, MySQL and PostgreSQL servers bind `127.0.0.1` on ports 4000 to 4003, and MySQL, PostgreSQL, OpenTSDB, InfluxDB and Prometheus remote storage are enabled by default (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:66`, `:104`, `:133-135`, `:168-170`, `:196`, `:201`, `:221`).
Loopback is reachable by every local UID on `magnetite`, including two worker accounts, so the store must require credentials on loopback (`research/telemetry-security-and-tenancy.md` "Bearing on D8 and D3").
Anonymous usage reporting is on by default (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:51`), and the event recorder creates a 90-day table unless its event list is empty (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:920-929`).
Configuration values can be supplied through environment variables prefixed `GREPTIMEDB_STANDALONE` with `__` as the separator (`GreptimeTeam/greptimedb@179ff8e50:src/cmd/src/standalone.rs:287`, `GreptimeTeam/greptimedb@179ff8e50:src/common/config/src/config.rs:23`).

### Credential evidence

The open build authenticates HTTP Basic against a static user file whose lines may carry `ro`, `wo` or `rw` (`research/greptimedb.md` R26, R27).
The watch-file provider survives a sops-nix symlink swap only from `v1.3.0-beta.1`, so 1.1.4 and 1.2.1 need `restartUnits` for rotation (`research/telemetry-security-and-tenancy.md` C3).
`LoadCredential` snapshots the file at unit start regardless of provider (`research/telemetry-security-and-tenancy.md` F41).
The repository's generator patterns are `omnigraph-bearer-tokens` for generated secrets and `omnigraph-r2` for externally minted ones, both with `restartUnits` (`research/telemetry-security-and-tenancy.md` F37, F38), and a verbatim-reading consumer needs the trailing newline stripped (`research/telemetry-security-and-tenancy.md` F40).

## Decision

Packaging: the store package is `pkgs.greptimedb` from the root nixpkgs input with no overlay, no `-bin` derivation and no second nixpkgs input; version steps arrive by root-pin bumps as ADR-001 states.

Placement: the store runs on `magnetite`, as the human chose, inside an explicit memory and disk containment rather than on host defaults.
The unit sets `MemoryHigh = "3G"`, `MemoryMax = "4G"`, `MemorySwapMax = "0"` and `OOMScoreAdjust = 500`, with `Restart = "on-failure"`, `RestartSec = 30` and `StartLimitIntervalSec = 0`.
Every GreptimeDB memory knob is set explicitly, so the process does not size itself from host RAM: `global_write_buffer_size = "256MB"`, `max_in_flight_write_bytes = "128MB"` with policy `wait`, `memory_pool_size = "512MB"`, `scan_memory_limit = "512MB"` with `scan_memory_on_exhausted = "fail"`, `experimental_compaction_memory_limit = "256MB"`, `max_background_compactions = 2`, `max_background_flushes = 2`, `max_concurrent_queries = 8`, `page_cache_size = "256MB"`, `sst_meta_cache_size = "64MB"`, and 32 MB each for the vector, selector-result and range-result caches.
Local state lives on a new ZFS dataset `zroot/root/greptimedb` mounted at `/var/lib/greptimedb`, with `quota = 16G`, `reservation = 12G` and `com.sun:auto-snapshot = false`, asserted by boot-time oneshots in the existing pattern; the write cache and the read cache are each capped at 4 GiB.
The process runs as a static system user `greptimedb`, not `DynamicUser`, because its state is a persistent dataset.

Listeners and egress: HTTP binds `127.0.0.1:4000`; gRPC, MySQL, PostgreSQL, OpenTSDB, InfluxDB, Prometheus remote storage and the Jaeger query API are disabled; OTLP, the PromQL API and SQL over HTTP stay enabled; no firewall port is opened; `enable_telemetry = false`; the event recorder's event list is empty.

Credentials: one clan vars generator, `greptimedb-users`, writes four random passwords and a users file with exactly four lines, `admin:rw=…`, `collector:wo=…`, `perses:ro=…` and `regulator:ro=…`, consumed by the store through `LoadCredential` and `static_user_provider:file:` at the unit's credentials directory, with `restartUnits = [ "greptimedb.service" ]` on the users file.
Its secret files are `admin-password`, `collector-password`, `perses-password` and `regulator-password`.
The `collector-password`, `perses-password` and `regulator-password` files are written with `printf '%s'` and mode `0400`; the first two carry `restartUnits` for the ADR-003 `ingress` collector unit and the ADR-002 Perses unit respectively, and `regulator-password` needs none because its consumers are timer-driven oneshots that load it at each start.
`admin` is used only by the local `greptimedb-schema` and `greptimedb-export` oneshots of this record and ADR-006.
`collector` is used only by the ADR-003 `ingress` collector, and `perses` only by the ADR-002 Perses service.
`regulator` is used only by the read-only regulators: the `otel-envelope` oneshot of ADR-003, ADR-004 and ADR-008, the `devloop-reconcile` oneshot of ADR-005, and the `greptimedb-envelope` oneshot of this record.
The R2 credentials are the `greptimedb-r2` and `greptimedb-r2-export` generators of ADR-006.

Clan service shape: the store is a NixOS module, `flake.modules.nixos.greptimedb` with options under `services.greptimedb`, imported by `magnetite` the way `omnigraph` is, and is not a clan service role.
Perses is likewise a plain NixOS module, `modules/nixos/perses.nix` of ADR-002, imported by `magnetite` and not a clan service role; its memory envelope is ADR-002's verbatim: plugin archives restricted to the ten-plugin subset, measured at 84 MiB against 257 MiB for the full vendored set, with `/run/perses/plugins` held at or below 96 MiB.
Collectors are the `otel-collector` clan service with roles `agent` and `ingress` and generators `otel-ca` and `otel-cert`, as ADR-003 defines; the store module exposes nothing that role needs other than the loopback endpoint and the `collector-password` path.
A oneshot `greptimedb-schema.service`, ordered after the store reports ready, idempotently creates the `fleet`, `devloop` and `agent` databases with ADR-004's TTL defaults of 30, 365 and 90 days, and sets the TTL of the `fleet` logs table to ADR-004's 14 days.
The `greptimedb-schema`, `greptimedb-export` and `greptimedb-envelope` units set `OnFailure=observability-notify@%n.service`, the shared ntfy notifier that ADR-003 defines (ADR-003 Q9).

## Rationale

Consuming the pinned attribute is the only route with no first-party build and no first-party package: the output is substituted (`research/nix-packaging-status.md` R4), and the `package-<attr>` flake check that every `pkgs/by-name` entry produces does not arise (`research/nix-packaging-status.md` F22).
An `overrideAttrs` to 1.2.1 would put a 34-minute Rust build into the closure operator (`research/nix-packaging-status.md` F14), and the x86_64-linux builders that would run it are `magnetite` and `pyrite`, the two hosts whose memory incidents this record is containing.
A `-bin` derivation over the 1.2.1 tarball is admissible under C6 on Linux, but it adds a package, an update script and a flake check to buy PromQL fixes that a pin bump will deliver once https://github.com/NixOS/nixpkgs/pull/574558 merges.

`magnetite` is kept because both alternatives are worse on the axis that matters.
`cinnabar` has about half of `magnetite`'s RAM, and placing the store there would make one host the ZeroTier controller, the fleet's `.zt` resolver and the telemetry store, so a single fault would take out mesh control, name resolution and the observation of that fault.
`pyrite` is an intermittent laptop with a smaller RAM budget and its own zram livelock history.
The challenge to the human's choice is therefore not where, but how: on `magnetite` the store must not size itself from the host and must not grow uncharged into zram.

The 4 GiB ceiling is derived from the explicit knobs.
The bounded allocations above sum to roughly 2.1 GB, and the 3 GiB `MemoryHigh` leaves headroom for index buffers, the flownode, metadata and allocator overhead `[INFERENCE: GreptimeDB documents no total-RSS formula; the envelope regulator below measures the real peak]`.
Against the measured 7.89 GiB minimum free during a nixbot evaluation, a 4 GiB maximum leaves the host above its previous floor, though the figure comes from an uncommitted measurement and the regulator, not the figure, is what this record relies on.
`MemorySwapMax = 0` keeps the store's footprint inside its own cgroup rather than in the uncharged zram pool, which is the specific gap the incident note names.
`OOMScoreAdjust = 500` ranks the store as the first host-OOM victim after the evaluator at 900, ahead of the ADR-003 `ingress` collector at 300, `nix-daemon` workers at 250 and PostgreSQL and other services at 0 or lower, because a store kill costs a restart with WAL replay while the surviving collector queues, whereas a daemon-worker kill fails CI.

The dataset with quota and reservation follows the host's own response to pool starvation (`research/fleet-emitter-inventory.md` F20); a retention policy alone does not bound WAL and cache growth.
Capping both caches at 4 GiB rather than the default 5 GB and 5 GiB brings the local floor under the 16 GiB quota with room for the 1 GB WAL purge threshold and the metadata store; the cost is more R2 reads for queries over data older than the write cache's 8-hour TTL (`research/greptimedb.md` R22).
Disabling the wire protocols, gRPC, the Jaeger query API and unused ingest protocols removes listeners that every local UID could reach and that no ADR consumes.

Restart on rotation is kept even after a `v1.3` release, because `LoadCredential` snapshots at start, so the hot-reloading provider would only help if the store read the secret path directly, which would drop the credentials-directory isolation.
The store is not a clan service role because it has one instance, no per-machine vars and only loopback consumers; a clan role would add an inventory instance that relates nothing.

## Rejected alternatives

- `overrideAttrs` overlay to 1.2.1: forfeits the cache and adds a 34-minute Rust build on memory-constrained builders (`research/nix-packaging-status.md` F14).
- `pkgs/by-name/greptimedb-bin` over the 1.2.1 tarball: admissible under C6 but adds a package, an updater and a flake check that a pin bump makes redundant (`research/nix-packaging-status.md` R15, F22).
- A second nixpkgs input for one attribute: adds a third nixpkgs node to a lock whose two nodes already caused misattributed findings (`research/store-alternatives.md` FL1).
- Building with the `servers/dashboard` feature: needs a fixed-output asset fetch to pre-populate `dist` and ADR-002 does not use the embedded UI (`research/nix-packaging-status.md` R11).
- Placement on `cinnabar`: half the RAM and co-locates telemetry with the mesh controller and the fleet resolver.
- Placement on `pyrite`: an intermittent daily-driver laptop with 15.5 GiB and a zram livelock history.
- A new dedicated host: contradicts the human's placement and adds a machine to observe a ten-machine fleet, with no failure prevented that containment on `magnetite` does not also prevent.
- Host defaults on `magnetite`: the process sizes caches and the query pool from 30.6 GiB of RAM and grows into uncharged zram (`research/greptimedb.md` F32, F33).
- `DynamicUser`: a persistent dataset whose owner can change across uid allocation, with no isolation gain over a static system user here.
- `watch_file_user_provider`: does not survive the symlink swap before `v1.3.0-beta.1`, and behind `LoadCredential` it gains nothing at any version.
- Per-person store users: the open build does not authorize per database, so they would be labels, not boundaries (`research/telemetry-security-and-tenancy.md` R1, R2); see ADR-008.
- A clan service role for the store: one instance with no cross-machine relation, so the role relates nothing.

## Consequences

`magnetite` gains one service with a hard 4 GiB ceiling and a 12 GiB disk reservation drawn from a pool that was 24% allocated (`research/otel-collector-topology.md` F39).
Under host-wide memory exhaustion the store is killed first and the ADR-003 `ingress` collector second, both before `nix-daemon` workers and PostgreSQL, so telemetry ingestion pauses and the collector, while it survives, queues during exactly the incidents the store exists to observe; the collector's queue depth is therefore the store's real availability bound.
Queries that need more than 512 MB of scan or query memory fail rather than wait, which bounds dashboard and export load and makes heavy analytics a job for the ADR-006 export.
Rotating any store credential restarts the store and the consuming unit, which costs a WAL replay and a collector retry cycle.
If the R2 stanza fails and ADR-006's fallback to local `File` storage applies, the dataset quota must be raised to hold the SSTs.

## Operating envelope and regulator

Envelope E7.1, configuration: the store unit has `MemoryMax`, `MemoryHigh`, `MemorySwapMax = 0` and `OOMScoreAdjust` set; every memory knob listed in the Decision is present in the generated TOML; every listener address is in `127.0.0.0/8`; gRPC, MySQL, PostgreSQL, OpenTSDB, InfluxDB, Prometheus remote storage and the Jaeger query API are disabled; `user_provider` is set; `enable_telemetry = false`; and, while the package version is below `1.3.0-beta.1`, the users-file generator's `restartUnits` contains `greptimedb.service`.
Regulator R7.1: a flake check, `modules/checks/greptimedb-envelope.nix`, evaluates `magnetite`'s configuration and asserts each clause, and also evaluates an enumerated mutant per clause, one dropping `MemoryMax`, one dropping `page_cache_size`, one binding HTTP to `0.0.0.0`, one re-enabling MySQL, one removing `user_provider`, one omitting `enable_telemetry`, and one removing `restartUnits`, asserting that each mutant produces a non-empty failure list, following `modules/checks/omnigent-environment.nix` (`research/dev-loop-signals.md` F12).

Envelope E7.2, runtime memory: the store cgroup's `memory.peak` stays below `MemoryHigh`, and its `memory.events` `oom_kill` and `max` counters do not increase between samples.
Regulator R7.2: a `greptimedb-envelope.timer` on `magnetite`, hourly, runs a oneshot that reads those cgroup files and fails the unit on breach; the same oneshot runs ADR-006's R6.1 to R6.4 probes.
A failed oneshot is a failed systemd unit, whose `OnFailure=` notifier is ADR-003's shared ntfy unit (ADR-003 Q9), so the regulator needs no alerting component of its own.
It is shown able to fail by running it once with the `memory.peak` threshold set below the observed value and recording the failed unit in the implementing change.

Envelope E7.3, disk: `zroot/root/greptimedb` used bytes stay below 80% of its quota, and the quota and reservation hold their declared values.
Regulator R7.3: the boot-time `zfs set` oneshots enforce the values, and the envelope oneshot reads `zfs get -Hp used,quota zroot/root/greptimedb` and fails above 80%.

Envelope E7.4, credential freshness: the store unit's start time is later than the users file's modification time.
Regulator R7.4: the envelope oneshot compares the two and fails if the file is newer, which is the rotation-staleness SLI (`research/fleet-emitter-inventory.md` F26).

## Failure prevented

Consuming the pinned attribute prevents a first-party Rust build of the store from entering the closure operator on the hosts that have run out of memory.
The memory knobs and `MemoryMax` prevent the store from sizing itself from `magnetite`'s RAM and competing with nixbot's evaluation, which is RK3's confirming observation.
`MemorySwapMax = 0` prevents the store's footprint from moving into the uncharged zram pool, the mechanism that let two evaluations exhaust the host.
`OOMScoreAdjust = 500` prevents a host OOM from killing `nix-daemon` workers ahead of the store and failing CI.
The dedicated dataset with quota and reservation prevents store WAL and cache growth from starving `/nix`, `/` or `/home`, the 2026-06-10 failure.
Disabling unused listeners prevents worker accounts on `magnetite` from reaching wire protocols no consumer uses.
Disabling usage reporting and the event recorder prevents an undeclared outbound connection and an unrequested 90-day table.
`restartUnits` on the users file prevents a rotated credential from leaving the store authenticating against the superseded file.
Keeping the store out of the clan inventory prevents an inventory instance whose roles relate nothing.

## Implementation surface

- Add `modules/nixos/greptimedb.nix`: `flake.modules.nixos.greptimedb` with `services.greptimedb.{enable,package,settings,databases,export}`, TOML generation, the `greptimedb` system user and group, `greptimedb.service` with the unit limits above and `LoadCredential` for the users file, `EnvironmentFile` for the R2 env file, `greptimedb-schema.service`, the ADR-006 export service and timer, `greptimedb-envelope.service` and `.timer`, and the ADR-001 and ADR-006 evaluation-time assertions.
- Modify `modules/machines/nixos/magnetite/default.nix`: import `greptimedb` and the ADR-002 `perses` module from `flakeModules`, set `services.greptimedb`, declare the `greptimedb-users`, `greptimedb-r2` and `greptimedb-r2-export` generators beside the existing `omnigraph-r2`, and add `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation` and `zfs-assert-root-greptimedb-noautosnap` oneshots in the existing pattern.
- Modify `modules/machines/nixos/magnetite/disko.nix`: add the `root/greptimedb` dataset with mountpoint `/var/lib/greptimedb`, `quota = "16G"`, `reservation = "12G"` and `com.sun:auto-snapshot = "false"`.
- Add `modules/checks/greptimedb-envelope.nix`: the R7.1 check and its mutants.
- Clan vars generator `greptimedb-users` on `magnetite`: `runtimeInputs` openssl; users `admin:rw`, `collector:wo`, `perses:ro` and `regulator:ro`; files `users` (owner `greptimedb`, mode `0400`, `restartUnits = [ "greptimedb.service" ]`), `admin-password` (mode `0400`), `collector-password` (mode `0400`, `restartUnits` naming the ADR-003 ingress collector unit), `perses-password` (mode `0400`, `restartUnits = [ "perses.service" ]`), and `regulator-password` (mode `0400`).
- Perses on `magnetite`: the plain NixOS module `modules/nixos/perses.nix` specified in ADR-002, with ADR-002's plugin-subset envelope, imported by `magnetite` and not a clan service role.
- Clan vars generators `greptimedb-r2` and `greptimedb-r2-export`: specified in ADR-006.
- The `otel-collector` clan service files and its `otel-ca` and `otel-cert` generators: listed in ADR-003.
- No flake input, no overlay, no `pkgs/by-name` entry, and no clan inventory instance for the store.

## Questions for the human gate

Q1 Keep the store on `magnetite` despite RK3 having fired? Recommended: yes, with the containment above; the alternative `cinnabar` concentrates mesh control, name resolution and telemetry on one half-sized host.
Q2 Reach 1.2.1 through the root-pin bump rather than an overlay or `-bin`, without delaying first deployment on 1.1.4 (ADR-001 Q1)? Recommended: yes; the alternative is a 34-minute source build or a redundant first-party package.
Q3 Are `MemoryHigh = 3G` and `MemoryMax = 4G` acceptable as the store's share of `magnetite`? Recommended: yes, revised only by R7.2 evidence; a larger ceiling eats into the free memory the evaluator needs, a smaller one risks scan failures on dashboards.
Q4 Should the store die first under host OOM (`OOMScoreAdjust = 500`), ahead of the ADR-003 `ingress` collector (`OOMScoreAdjust = 300`) and `nix-daemon` workers? Recommended: yes; the collector survives to queue, and the alternative lets a host OOM fail CI to keep telemetry ingesting.
Q5 Is a 16 GiB dataset with 4 GiB read and write caches acceptable instead of the roughly 10 GB default cache floor? Recommended: yes; larger caches reduce R2 reads but enlarge the reservation on a pool with a starvation history.
Q6 Should restart-on-rotation remain after a `v1.3` release reaches the pin? Recommended: yes, because `LoadCredential` snapshots at start; the alternative reads the secret path directly and drops credentials-directory isolation.
Q7 Should a local `admin:rw` user exist for the schema and export oneshots? Recommended: yes, root-owned and loopback-only; the alternative runs those tasks with the collector, Perses or regulator credential, whose modes forbid them.
Q8 Should the store's phase-2 memory work wait for the incident note's phase-2 `MemoryLow` and oomd measurements? Recommended: no, ship the store's own ceiling now and fold it into that work when it lands; the alternative blocks the store on measurements with no scheduled date.
