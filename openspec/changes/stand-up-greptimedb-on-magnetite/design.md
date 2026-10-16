## Context

This change is slice S1 of the fleet observability implementation (`docs/notes/development/observability/architecture/reference-architecture.md`, "Implementation sequencing"; Linear CAM-68).
It stands up the telemetry store that slices S2 to S8 read from or write to, and feeds it magnetite's own metrics.
The accepted inputs are ADR-001, ADR-003, ADR-004, ADR-006, ADR-007, ADR-008 and ADR-009 under `docs/notes/development/observability/decisions/`, ADR-002 as revised in charter v11, and the `greptimedb`, `otel-collector` and `host-probes` components.
`brainstorm.md` records the decision chain (Q1 to Q8), the prior-art findings (F1 to F11) and the charter v11 amendments; this document develops that direction into the technical design.
Citations of the form A7:63 mean ADR-007 line 63, A3 means ADR-003, and so on; GC, OC and HP are the three component documents and RA is the reference architecture, all under `docs/notes/development/observability/`.

The current state on magnetite:

- magnetite is a Hetzner CX53 KVM guest with 16 vCPUs and no `/dev/kvm` (`modules/machines/nixos/magnetite/default.nix:78-79`).
- Its memory is shared with the nixbot evaluator, which a lock runs at `oom_score_adj` 900 (`modules/nixos/nix-eval-lock.nix:10`; A7:32,100).
- No metrics history exists, no unit in `modules/` sets `OnFailure=`, and `ntfy-send` exists only as a home-manager command (`modules/home/tools/commands/system/ntfy-send.nix:12-19`).
- nixbot listens only on `/run/nixbot/web.sock` and binds no TCP port (`modules/nixos/nixbot.nix:18-20`).
- The root nixpkgs pin (`ac1faec4`, `flake.lock:1399`) carries `greptimedb` 1.1.4; `nixpkgs-unstable` and `nixos-unstable` also carry 1.1.4, and 1.2.1 is on nixpkgs master only.
  The pending pin update (#3434) is held by an unrelated Hydra failure.
- The pin carries `opentelemetry-collector-contrib` 0.155.0 with the hostmetrics, systemd, prometheus and otlphttp components (S1RepoSurface §6).

Constraints that shape every decision below:

- The store must not take CI down with it: under host memory exhaustion the evaluator dies first, the store second and the collector third (A7:100,127).
- nixbot evaluates every `checks` attribute on every pull request, so any check that can flake blocks the merge queue.
- Only pyrite advertises `kvm`; magnetite advertises `nixos-test` and `uid-range` with `auto-allocate-uids` (`modules/clan/inventory/services/nix-builders.nix:28-44`).
- GreptimeDB v1.2.1 has no switch to disable gRPC, only `[grpc] bind_addr` (F5).

Stakeholders are the fleet operator, who reads the store and receives failure notices, and the later slices, which consume the interfaces S1 fixes: the database names, the ingest path and its headers, the user roles, and the notifier template.

## Goals / Non-Goals

**Goals:**

- Run GreptimeDB 1.2.1 standalone on magnetite, loopback only, with four users (`admin:rw`, `collector:wo`, `perses:ro`, `regulator:ro`) and three databases with retention (`fleet` 30 days, `devloop` 365 days, `agent` 90 days).
- Keep the store inside a memory envelope (`MemoryHigh` 3G, `MemoryMax` 4G, no swap, `OOMScoreAdjust` 500) and a disk envelope (a 16G quota and 12G reservation on its own dataset), with object data in the `sciexp` R2 bucket under `projects/vanixiets/observability/store/`.
- Collect magnetite's host, unit, process-memory, ZFS, OOM-kill and service metrics into `fleet` through one collector process that already has the shape S4 extends.
- Report every failure of the store, its schema and envelope jobs and its ZFS jobs to a human through ntfy from the first deployment.
- Back every envelope claim with a regulator that is shown able to fail: evaluation-time checks with mutants, an hourly runtime envelope, and two on-demand runtime tests.
- Amend in place the decision records that contradict the deployed shape (charter v11).

**Non-Goals:**

- A logs table, a logs pipeline or traces; the `fleet` logs table and its 14-day TTL arrive with S7 (Q4).
- Dev-loop collection (S2), the alert evaluator, the dead-man and ntfy access control (S3), other hosts, `otel-ca` and the mTLS ZeroTier ingress listener (S4), darwin (S5), the dashboard's public vhost, its API listener on 4006, dashboard provisioning and `percli lint` (S6), agent telemetry (S7), and the Parquet export with R6.1 and R6.4's export-location clause (S8).
- Bumping the root nixpkgs pin; the pin update is independent of this change.
- Creating an R2 bucket or lifecycle rule; the store creates its prefix on first write.
- Exposing any store listener beyond loopback, or opening a firewall port.

## Decisions

### Layout

New files:

| Path | Content |
|---|---|
| `pkgs/by-name/greptimedb-bin/{package.nix,update.sh}` | Upstream binary package (D1) |
| `pkgs/by-name/ntfy-send/` | The `ntfy-send` script and package, moved from `modules/home/tools/commands/system/` (D2) |
| `modules/nixos/greptimedb.nix` | `flake.modules.nixos.greptimedb`: `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.{service,timer}` and their assertions (D3 to D7, D12) |
| `modules/clan/services/otel-collector/flake-module.nix` | Clan service with `agent` and `ingress` roles, node_exporter and the `observability-notify@` template (D8 to D10) |
| `modules/clan/services/otel-collector/schema.nix` | The single source of allow-lists: systemd units, promoted resource attributes, process and node_exporter keep-lists, database names (A4:214) |
| `modules/clan/inventory/services/otel-collector.nix` | Instance with both roles on magnetite |
| `modules/checks/greptimedb-envelope.nix`, `modules/checks/otel-collector-config.nix` | Evaluation-time regulators with mutants (D11) |
| `modules/vm-tests/greptimedb-pipeline.nix`, `modules/vm-tests/greptimedb-oom-order.nix` | On-demand runtime tests (D13) |

Changed files:

| Path | Change |
|---|---|
| `modules/machines/nixos/magnetite/default.nix` | Import `greptimedb`, set `services.greptimedb`, declare `greptimedb-users` and `greptimedb-r2` beside `omnigraph-r2` (`:337-376`), add three ZFS oneshots beside the existing six (`:193-263`), and set `OnFailure=` on all nine |
| `modules/machines/nixos/magnetite/disko.nix` | Dataset `root/greptimedb` beside `root/cognee` (`:76-80`) |
| `modules/nixos/nixbot.nix` | Loopback nginx server on `127.0.0.1:9180` proxying `/metrics` to `/run/nixbot/web.sock` |
| `modules/apps/updates.nix` | `apps.update-greptimedb-bin` (`:43-81` pattern) |
| `modules/home/tools/commands/system/ntfy-send.nix` | Consumes `pkgs/by-name/ntfy-send` instead of packaging the script |
| Observability decision records, components, reference architecture, charter | Charter v11 amendments, made in the planning step and verified by a task (D14) |

Units on magnetite after deployment:

| Unit | User | Role |
|---|---|---|
| `greptimedb.service` | static `greptimedb` | The store |
| `greptimedb-schema.service` | `greptimedb` with the `admin` credential | Creates databases and sets TTLs after `/health` answers |
| `greptimedb-envelope.service` and `.timer` (hourly) | the `regulator` credential | Runtime regulator |
| `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-assert-root-greptimedb-noautosnap` | root | Boot oneshots enforcing dataset properties |
| `opentelemetry-collector.service` | `DynamicUser` | Both collector roles in one process |
| `prometheus-node-exporter.service` | module default | ZFS and `oom_kill` source on `127.0.0.1:9100` |
| `observability-notify@.service` | template | Failure notifier |

### Data flow

```
host_metrics (memory, paging)  ─┐
host_metrics (process)          ├─ agent pipelines ─ stamp host.name, vanixiets.database ─▶ forward connector
systemd receiver                │
prometheus receiver (scrapes) ──┘                                                            │
                                                                                             ▼
             ingress pipelines: memory_limiter ─ exp-histogram conversion ─ routing connector on vanixiets.database
                                                                                             │
                     ┌───────────────────────────────┬───────────────────────────────────────┤
                     ▼                               ▼                                       ▼
          otlp_http exporter (fleet)     otlp_http exporter (devloop)            otlp_http exporter (agent)
                     │  file_storage sending queue, basicauth as collector, delete vanixiets.database
                     ▼
     http://127.0.0.1:4000/v1/otlp  with x-greptime-db-name and x-greptime-otlp-metric-promote-resource-attrs
                     ▼
         greptimedb.service: WAL and caches on zroot/root/greptimedb, SSTs in R2 sciexp/projects/vanixiets/observability/store/
```

In S1 only `fleet` receives data; the `devloop` and `agent` exporters exist so that S2 and S7 add receivers and routes without restructuring the ingress.
Reads go through PromQL at `/v1/prometheus/api/v1` with the `x-greptime-db-name` header selecting the database (F9), or SQL at `/v1/sql`.

### Credential flow

| Generator | Files | Delivered as | Consumer |
|---|---|---|---|
| `greptimedb-users` (openssl, hex passwords) | `users` (owner `greptimedb`, `0400`, `restartUnits` `greptimedb.service`) | `LoadCredential=users` → `/run/credentials/greptimedb.service/users`, named by `user_provider = "static_user_provider:file:..."` in the TOML | `greptimedb.service` |
| | `admin-password` (`0400`) | `LoadCredential` | `greptimedb-schema.service` |
| | `collector-password` (`0400`, `restartUnits` `opentelemetry-collector.service`) | `LoadCredential`, read by `basicauth` through `${file:...}` | `opentelemetry-collector.service` |
| | `perses-password` (`0400`) | none in S1 | S6 |
| | `regulator-password` (`0400`, no `restartUnits`) | `LoadCredential` | `greptimedb-envelope.service` |
| `greptimedb-r2` (hidden prompts `access-key`, `secret-key`; `persist = true`; prompt files `deploy = false`) | rendered `env` with `GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID` and `GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY` (`restartUnits` `greptimedb.service`) | `EnvironmentFile` | `greptimedb.service` |

The `perses-password` file is generated now so that the users file holds its final four lines from the first deployment (A7:167); S6 decides its consumer and `restartUnits`, because under the revised ADR-002 no `perses.service` exists and the dashboard vhost's nginx injects the `perses:ro` credential instead.
No worker holds any credential (A8:91).

### Failure path

`greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service`, `opentelemetry-collector.service` and the nine `zfs-assert-*` and `zfs-set-*` oneshots set `OnFailure=observability-notify@%n.service`.
The collector's `OnFailure=` is set in the `agent` role's NixOS module beside the template; the others are set where their units are defined.
The template instance runs `ntfy-send` with the failed unit's name and the host, posting to the topic `fleet-alerts` at `https://ntfy.zt` on cinnabar (ADR-009 item 11).
It posts once per failure episode: it writes a stamp file per unit under `/var/lib/observability-notify` and skips the post while that stamp exists.
Each notified unit carries an `ExecStopPost=` hook that, when the unit next exits successfully and its stamp exists, posts one `RESOLVED` message and removes the stamp.
ntfy has no authentication (`modules/machines/nixos/cinnabar/ntfy.nix`), so ZeroTier membership is the access boundary and the notifier holds no credential.

### D1: Package GreptimeDB 1.2.1 from the upstream binary as `greptimedb-bin`

- **Choice**: `pkgs/by-name/greptimedb-bin` in the `golem-binary` shape (`pkgs/by-name/golem-binary/package.nix:23-104`): `passthru.sources.x86_64-linux = fetchurl` of `greptime-linux-amd64-v1.2.1.tar.gz` (sha256 `062d5beb13de4991c4fec201b2e5071518bf4ca8f0d52947eba757a74c2a5420`), `autoPatchelfHook` with `stdenv.cc.cc.lib`, `versionCheckHook`, `sourceProvenance = [ binaryNativeCode ]`, `mainProgram = "greptime"`, `passthru.embedsDashboard = true`, an `update.sh` that tracks stable upstream releases and `apps.update-greptimedb-bin`.
  The module's `package` option defaults to it, and R1.1 (D11) requires the deployed package to be a stable release carrying `passthru.embedsDashboard = true`.
- **Boundary**: vendored versus first-party.
  The binary is vendored and unmodified; the derivation around it is first-party.
  Checks read it through `self'.packages.greptimedb-bin`, because perSystem `pkgs` does not carry the flake overlay (`modules/checks/apps.nix:4-7`).
  The distinct `-bin` pname keeps it from silently shadowing `pkgs.greptimedb` through the overlay merge (`modules/nixpkgs/compose.nix:42`).
- **Rationale**: the upstream release tarball is built with the `servers/dashboard` feature and embeds GreptimeDB's Perses-based dashboard (v0.13.13 in v1.2.1), which the revised ADR-002 makes the fleet's dashboard layer; the nixpkgs build omits that feature (Q8).
  `greptimedb-bin` is therefore the intended package, not a stand-in until a channel carries 1.2.1.
  The `embedsDashboard` attribute records that property on the package, where an evaluation-time assertion can read it, and the container test's `/dashboard/` case (D13) shows the delivered binary serves it.
  1.1.4 and prereleases are excluded (A1:46,48).
  `KiruyaMomochi/nix` ships the same tarball with only `autoPatchelfHook` and `cc.cc.lib`.
- **Alternatives considered**: a source build with the dashboard feature, rejected because the build needs nightly Rust, a patched-in git dependency and hand-fed dashboard assets (`quentinmit/isz`, Kiruya); `pkgs.greptimedb` from a bumped pin, rejected while the nixpkgs build omits the dashboard, and acceptable under R1.1 only once it carries it; a second nixpkgs input or an overlay of nixpkgs master, rejected by A1:45-47 and A7:60; the cutover assertion first drafted, which failed evaluation once the pinned `pkgs.greptimedb` reached the deployed version, rejected because it would force the store onto a build without the dashboard.

### D2: Move `ntfy-send` to `pkgs/by-name/ntfy-send`

- **Choice**: the script and its package move from `modules/home/tools/commands/system/ntfy-send.nix` to `pkgs/by-name/ntfy-send`; the home-manager command and the notifier both consume the package.
- **Boundary**: source versus delivered.
  One source now delivers to two places, a user's profile and a system unit's `ExecStart`, so behaviour such as the `-k` TLS convention (`ntfy-send.sh:30-34`) stays identical in both.
- **Rationale**: ADR-003 and ADR-009 require the notifier to call the existing `ntfy-send` rather than a second client (A3:241; ADR-009 item 10).
- **Alternatives considered**: a second curl wrapper inside the collector module, rejected because two senders would diverge.

### D3: Store as a plain NixOS module with a static user, a memory envelope and fixed worker pools

- **Choice**: `flake.modules.nixos.greptimedb` with options `services.greptimedb.{enable,package,settings,databases}`, imported by magnetite; no clan role or inventory instance (A7:78,163,171).
  `greptimedb.service` runs as static user and group `greptimedb` with `MemoryHigh = "3G"`, `MemoryMax = "4G"`, `MemorySwapMax = "0"`, `OOMScoreAdjust = 500`, `Restart = "on-failure"`, `RestartSec = 30`, `StartLimitIntervalSec = 0` (A7:63), and a lower `CPUWeight` following cognee (`modules/nixos/cognee.nix:229-235`, `CPUWeight = 20`).
  The TOML sets `[runtime] global_rt_size = 4` and `compact_rt_size = 2` against magnetite's 16 vCPUs, the ADR-007 memory knobs (A7:64-65), `logging.dir = ""` and `enable_telemetry = false`.
  Hardening follows the static-user variant in `modules/nixos/omnigent.nix:136-153`.
  `unitConfig.RequiresMountsFor = "/var/lib/greptimedb"` makes the unit fail, and so notify, when the dataset is not mounted, instead of writing into the root dataset.
- **Rationale**: a static user owns the users credential and the dataset across restarts (A7:66).
  The kill order evaluator 900, store 500, collector 300 means a memory squeeze costs a store restart with WAL replay while the collector queues, never a CI evaluation worker (A7:100,127).
  Unbounded worker pools starved GreptimeDB's own health handler on a 192-core host in `MathisWellmann/nixos-config` (F6), so pool sizes and CPU share are set explicitly.
  `logging.dir = ""` keeps logs in the journal only.
- **Alternatives considered**: `DynamicUser`, rejected because the users file and the data directory need a stable owner; default worker pools, rejected by F6; a clan service for the store, rejected by A7:78 because only magnetite runs it.

### D4: Loopback HTTP only; gRPC bound to loopback

- **Choice**: `[http] addr = "127.0.0.1:4000"` carries OTLP, PromQL, SQL, `/health`, `/ready` and `/metrics`.
  `[grpc] bind_addr = "127.0.0.1:4001"`, with an assertion that it stays in `127.0.0.0/8`.
  MySQL, PostgreSQL, InfluxDB, OpenTSDB, Prometheus remote storage and the Jaeger query API are disabled; no firewall port opens (A7:68).
  Credentials are required on every `/v1/` path, loopback included (A8:53).
- **Rationale**: v1.2.1's configuration has no gRPC switch (F5), so binding it to loopback is the closest available setting to ADR-007's "disabled".
  The embedded dashboard is served at `/dashboard/` on the same loopback listener, so S1 opens nothing for it; the operator reaches it from a workstation over `ssh -L 4000:127.0.0.1:4000 magnetite.zt` from the first deployment (Q8).
  `http.enable_api_server`, which adds the 4006 listener serving only `/v1` and `/dashboard`, stays off until S6 sets it for the dashboard vhost.
- **Alternatives considered**: leaving gRPC at its default, rejected because the bind would then be outside any assertion; blocking on an upstream gRPC switch, rejected because it would stall S1 on an unscheduled release.

### D5: Local state on a capped ZFS dataset, object data in R2

- **Choice**: dataset `zroot/root/greptimedb` at `/var/lib/greptimedb` with `quota = "16G"`, `reservation = "12G"`, `com.sun:auto-snapshot = "false"`.
  On the installed host it is created once by hand before the first deployment, as `zroot/root/cognee` was (it exists on magnetite with no record in the repository of its creation).
  The `disko.nix` declaration is kept so a reinstall creates it.
  The boot oneshots `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation` and `zfs-assert-root-greptimedb-noautosnap`, in the pattern of `zfs-set-root-nix-quota` (`default.nix:232`), enforce the properties on every boot.
  `storage.data_home` is the dataset mount, because the WAL and caches stay local with object storage (F6).
  The `[storage]` stanza sets `type = "S3"`, `bucket = "sciexp"`, `root = "projects/vanixiets/observability/store/"`, `region = "auto"`, `enable_virtual_host_style = false`, `disable_ec2_metadata = true`, and the endpoint `omnigraph-r2` already uses (`default.nix:402`); credentials come from the environment (D6).
  Every table uses the flat SST format (A6:62).
- **Rationale**: disko applies dataset declarations only at installation, so a live pool needs a manual create, and the oneshots enforce the properties a manual create could get wrong (S1RepoSurface §3).
  `RequiresMountsFor=` on `greptimedb.service` (D3) turns a missing dataset into a unit failure rather than silent writes to the root dataset.
  Reusing the endpoint avoids a second source for the same account id (Q6).
- **Alternatives considered**: a new endpoint variable, rejected as a duplicate of a value the repository already holds; local `File` storage, kept as the fallback if R2 fails at deployment, with a quota increase (A6:85,123).

### D6: Credentials as generated files delivered through `LoadCredential` and `EnvironmentFile`

- **Choice**: the generators and delivery in the credential flow table above.
  `greptimedb-users` generates hex passwords and writes exactly four lines of the form `<user>:<mode>=<hex>`.
  `greptimedb-r2` follows `omnigraph-r2` (`default.nix:337-376`): hidden prompts for an Object Read & Write token on `sciexp`, minted by hand in the Cloudflare dashboard.
  `user_provider` stays a top-level TOML key, valid in standalone mode (F11, `src/cmd/src/standalone.rs:354,472`).
- **Boundary**: source versus delivered.
  The generator scripts are source; the values exist only as activation-resolved files and `/run/credentials/<unit>/` copies.
  This is why the collector's build-time validation needs placeholders (D8).
- **Rationale**: the users file format requires exactly one `=` per line and silently skips malformed lines (F2); base64 padding contains `=`, hex does not.
  Restart-on-rotation through `restartUnits` keeps R7.4 (store start later than users-file mtime) true after a rotation.
- **Alternatives considered**: base64 passwords, rejected by F2; one generator per user as in `cinnabar/matrix.nix:49`, rejected because the users file must be written whole from all four passwords; passing the users file through `--user-provider` on the command line, unnecessary given F11.

### D7: Schema oneshot creates databases, then alters their TTL; no logs table

- **Choice**: `greptimedb-schema.service`, ordered after `greptimedb.service`, polls `GET /health` until it answers (F7), then as `admin` runs for each database `CREATE DATABASE IF NOT EXISTS <db>` followed by `ALTER DATABASE <db> SET 'ttl'='<ttl>'`, with `fleet` 30d, `devloop` 365d and `agent` 90d.
  It creates no logs table (Q4).
- **Rationale**: `CREATE DATABASE IF NOT EXISTS ... WITH (ttl=...)` is a no-op on an existing database, so a changed TTL would never apply without the `ALTER` (F1).
  The store has no readiness notification, so the oneshot polls (F7).
- **Alternatives considered**: create-only with `WITH (ttl=...)`, rejected by F1; creating the `fleet` logs table and its 14-day TTL now (A7:82), rejected because S1 to S5 carry no logs pipeline (RA:241) and S7 creates it.

### D8: Both collector roles on magnetite in one process, joined by a `forward` connector

- **Choice**: the `otel-collector` clan service with `agent` and `ingress` roles, both assigned to magnetite in `modules/clan/inventory/services/otel-collector.nix`, following `modules/clan/services/nix-builders/flake-module.nix:283-408`.
  The two roles' NixOS fragments merge into one `services.opentelemetry-collector` configuration with `package = pkgs.opentelemetry-collector-contrib`.
  Agent pipelines export to a `forward` connector that the ingress pipelines receive from.
  The ingress runs `memory_limiter` first, `convert_exponential_histogram_to_histogram` while the store is below 1.3 (A1:49; A3:89), a `routing` connector on `vanixiets.database`, and one `otlp_http` exporter per database to `http://127.0.0.1:4000/v1/otlp` with `x-greptime-db-name` and `x-greptime-otlp-metric-promote-resource-attrs` generated from `schema.nix`.
  The promote list stays short and stable: `host.name`, `systemd.unit.name`, `process.executable.name` (A3:93).
  Each exporter authenticates with a `basicauth` client reading `collector-password` and uses a `file_storage` sending queue sized for at least 24 hours and under 512 MiB (A3:222).
  The process envelope is `memory_limiter` 384 MiB, `MemoryMax = "512M"`, `OOMScoreAdjust = 300` (A3:220).
  `validateConfigOverrides` substitutes placeholder `basicauth` credentials (F4).
- **Boundary**: source versus delivered.
  The nixpkgs module validates the rendered configuration at build time, before `/run/credentials` exists, so the validated file differs from the delivered one only in the placeholder credentials.
- **Rationale**: the NixOS module allows one collector per host, so two role instances on magnetite must share a process (Q2).
  S4 then adds only `otel-ca`, the mTLS ZeroTier receiver on the ingress fragment and the agent role on other hosts; nothing S1 deploys is restructured.
- **Alternatives considered**: O2, both roles with the notifier left in S3, rejected because S1's units would then ship without failure notification; O3, ingress only with magnetite's receivers inside it, rejected because S4 would have to split them back out into the agent role; an agent-to-ingress hop over loopback OTLP, rejected as a network hop inside one process.

### D9: Signals and scrape targets

- **Choice**: the agent role collects into `fleet`:
  - `host_metrics` at 60s: memory including `system.linux.memory.available`, and the `paging` scraper with `system.paging.usage` only (A3:98).
  - A second `host_metrics` receiver running the `process` scraper with `process.pid`, `.parent_pid`, `.command`, `.command_line`, `.executable.path` and `.owner` disabled at source, `process.memory.usage` aggregated by executable name, a filter dropping points under 64 MiB, and at most 30 names per host (A3:94-95; A4:86).
  - The systemd receiver with `units` equal to the `schema.nix` allow-list, capped at 40 units, restarts on and CPU time off (A3:96-97; A4:110,112,146).
  - A `prometheus` receiver at 60s scraping node_exporter on `127.0.0.1:9100` (`--collector.disable-defaults --collector.zfs --collector.vmstat --collector.vmstat.fields=^oom_kill$`, `listenAddress = "127.0.0.1"`, `openFirewall = false`, with the A4:88 keep-list), gitea on `127.0.0.1:3002`, niks3 on `127.0.0.1:5752`, nixbot on `127.0.0.1:9180`, nginx `stub_status`, zerotierone metrics, and GreptimeDB's own `127.0.0.1:4000/metrics`.
  - Every series carries `host.name`.
- `modules/nixos/nixbot.nix` gains a loopback nginx server on `127.0.0.1:9180` proxying `/metrics` to `/run/nixbot/web.sock`.
- **Rationale**: these are ADR-003's magnetite set (A3:83-84) plus the store, which `quentinmit/isz` scrapes (Q5).
  nixbot has no TCP listener, and scraping its public hostname from the host itself would not arrive from loopback.
  Disabling process attributes at source, rather than dropping them later, bounds cardinality before the series exist.
- **Alternatives considered**: scraping nixbot through its public vhost, rejected because the `nginxMetricsLocation` allow-list admits loopback and ZeroTier only (`modules/lib/nginx-metrics-location.nix:11-16`); SMART on magnetite, excluded because a KVM guest has no SMART devices (A3:51,100).

### D10: The failure notifier lands in S1

- **Choice**: the `observability-notify@.service` template sits in the `agent` role's NixOS module (A3:241), runs `ntfy-send` from D2 against `https://ntfy.zt`, and is the `OnFailure=` target of every unit in the failure path above.
  It ships in its final ADR-009 item 11 form: topic `fleet-alerts`, one post per failure episode guarded by the per-unit stamp file, and the `ExecStopPost=` `RESOLVED` hook on each notified unit.
  S3 adds only the `alerter` credential if it turns on ntfy access control, and does not rewrite the template.
- **Rationale**: S1's own units then report failures from their first deployment, and R7.2 needs no alerting component (A7:140).
  The collector is wired too, because a collector that stops exporting leaves the store silent with no other S1 signal to show it.
  The topic is `fleet-alerts`, the one ADR-009 item 11 fixes for unit failures, so S3 changes the credential and not the topic.
  ntfy has no authentication, so the notifier posts anonymously and holds no credential until S3; if S3 turns on access control under ADR-009 item 12, S3 must give the notifier the `alerter` credential in the same change.
- **Alternatives considered**: `OnFailure=` naming a template that does not yet exist, rejected because systemd would fail to start the missing unit silently; deferring `OnFailure=` to S3 (RA:251), rejected because S1's failures would go unreported in the meantime; a notifier without stamps or recovery posts, rejected because one condition that fails every hour would repeat until the topic is muted (ADR-009:195), and S3 would then have to rewrite the template.

### D11: Evaluation-time regulators with mutants

- **Choice**: flake checks over `self.nixosConfigurations.magnetite.config`, following `modules/checks/nixbot-wiring.nix:31-56` for reading unit configuration and `modules/checks/omnigent-environment.nix:98-118` for mutants (`assert lib.all (m: failures m != []) mutants`), gated to `x86_64-linux`:

| Id | Asserts | Mutants |
|---|---|---|
| R1.1 (amended) | The package version is stable semver (`^[0-9]+\.[0-9]+\.[0-9]+$`), and the package declares that it embeds the dashboard: `cfg.package.passthru.embedsDashboard == true`, set on `greptimedb-bin`; `pkgs.greptimedb` passes only if it carries the dashboard and declares it | a prerelease version (`1.3.0-beta.2`) via `overrideAttrs`; `package` set to the pinned `pkgs.greptimedb`, which lacks `passthru.embedsDashboard` |
| R1.2 | A store below 1.3.0 requires the exponential-histogram conversion in magnetite's collector configuration (A1:96-97) | statement removed |
| R1.4 | `enable_telemetry = false` (A1:103-104) | key omitted |
| R7.1 | The full envelope: `MemoryMax`, `MemoryHigh`, `MemorySwapMax = 0`, `OOMScoreAdjust`, every memory knob, listeners in `127.0.0.0/8`, protocols disabled, `user_provider`, `enable_telemetry = false`, `restartUnits` containing `greptimedb.service` (A7:135) | seven: drop `MemoryMax`; drop `page_cache_size`; HTTP on `0.0.0.0`; MySQL re-enabled; `user_provider` removed; `enable_telemetry` omitted; `restartUnits` removed (A7:136) |
| R6.4 (storage clause) | `disable_ec2_metadata`, `region = "auto"`, `enable_virtual_host_style = false`, `bucket`, `root` (A6:138) | drop `disable_ec2_metadata`; `root = ""` |
| R3.1 | magnetite's collector configuration validates, endpoints and scrape targets on loopback, the six process attributes off, paging usage only, systemd `units` equal to `schema.nix` (A3:229-230); queue clause: every exporter's sending queue uses `file_storage`, sized for at least 24 hours and under 512 MiB (A3:222); failure-wiring clause: every unit the failure path wires sets `OnFailure=observability-notify@%n.service`, namely `greptimedb`, `greptimedb-schema`, `greptimedb-envelope`, `opentelemetry-collector`, the three new oneshots `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation` and `zfs-assert-root-greptimedb-noautosnap`, and the six existing `zfs-assert-root-{nix,docker,podman}-noautosnap`, `zfs-set-root-nix-quota` and `zfs-set-root-{nixos,home}-reservation` (`default.nix:193-263`) | the five of A3:233 that apply without S4's ZeroTier ingress; an exporter whose sending queue lacks `file_storage`; one named unit with its `OnFailure=` dropped |
| R8.2 | `greptimedb-users` files owned by a non-worker with `0400`; store HTTP bind on loopback (A8:139); credential-holder clause: across magnetite's evaluated units, only `greptimedb-schema` loads `admin-password` (S8 adds `greptimedb-export`), only `opentelemetry-collector` loads `collector-password`, and only the regulator units load `regulator-password` (in S1, `greptimedb-envelope`) | a worker owning `collector-password` (A8:140); a second unit loading `admin-password` |
| Users file | The generator script, run in the build sandbox, emits exactly four lines each matching `<user>:(rw\|ro\|wo)=<hex>` for `admin:rw`, `collector:wo`, `perses:ro`, `regulator:ro` (F2) | a fifth line; a password containing `=` |

- **Rationale**: these properties are fixed in the configuration, so evaluation decides them without a running host, and they gate every pull request at no runtime cost.
- **Alternatives considered**: deferring R3.1 and R8.2 to unassigned slices, rejected because S1 deploys their subjects (Q3).

### D12: Hourly runtime envelope

- **Choice**: `greptimedb-envelope.timer` runs `greptimedb-envelope.service` hourly with the `regulator` credential, asserting R6.2 (sum of `sst_size` under 50 GiB), R6.3 (no legacy `sst_format`), R6.4's readiness probe, R7.2 (cgroup `memory.peak` below `MemoryHigh`, `memory.events` `oom_kill` and `max` not increasing), R7.3 (used under 80% of quota; quota and reservation hold), R7.4 (store start later than users-file mtime), and that no table carries its own TTL overriding its database's (F1).
  Every query treats an empty result or a missing table as failure; a mutant renames the queried table and must fail (F3).
- **Rationale**: these properties exist only at runtime.
  `MathisWellmann/nixos-config`'s `GreptimeDBDown` alert queries a job that does not exist and can never fire (F3).
- **Alternatives considered**: running R6.1 and R6.4's export clause now (A7:139; A6:138), rejected because the export does not exist before S8 and R6.1 fails on an empty partition (RA:266).

### D13: Test selection by what each claim needs

- **Choice**:
  - Evaluation-time (D11) covers the envelope, listeners, users file, telemetry, storage stanza and collector configuration.
  - A systemd-nspawn `containers` test (`pkgs.testers.runNixOSTest`, `nixos/lib/testing/driver-configuration.nix:68-71`), requiring `nixos-test` and `uid-range` and therefore buildable on magnetite, covers the pipeline: readiness, the schema oneshot's create and alter of TTL, the auth matrix including a `collector:wo` read answered 401, OTLP ingest through the routing connector, a PromQL read back with `x-greptime-db-name`, the systemd receiver reaching D-Bus under `DynamicUser`, a store restart (stop `greptimedb.service`, emit, start it, and read the emitted interval back), and R1.1's runtime side: `GET http://127.0.0.1:4000/dashboard/` returns 200.
  - Survival of a store restart is discharged twice: R3.1's queue clause proves the configuration persists the queue, and the container test's restart case proves the queued interval reaches the store.
  - A QEMU `nodes` test requiring `kvm` and `nixos-test` with `qemu.forceAccel`, which routes only to pyrite, covers the OOM kill order evaluator 900, store 500, collector 300.
  - Deployment on magnetite covers what needs the real host, recorded in `verify.md`: R2 works, ZFS quota and reservation are enforced, the zram paging series exists, R7.2 fails when its threshold is set below the observed peak (A7:141), `host.name` series answer through SQL and PromQL, and no log or trace tables exist.
  - Both runtime tests live in the on-demand `vmTests` lane (`modules/vm-tests/default.nix`), outside `checks`.
- **Rationale**: a container shares the host kernel, so the OOM killer in a container is the host's; only a VM can test the kill order.
  Everything else in the pipeline needs only process isolation, which nspawn gives on magnetite without KVM.
  nixbot evaluates every check attribute on every pull request, so a flaky runtime test in `checks` would block the merge queue (Q7).
  The negative-auth case also proves `user_provider` is enforced (F11).
- **Alternatives considered**: everything in one QEMU test on pyrite, rejected because it ties the whole pipeline test to the one KVM host; runtime tests in `checks`, rejected by the merge-queue risk; a post-deploy probe only, rejected because it gives no pre-merge evidence.

### D14: Charter v11 amendments in place

- **Choice**: revise ADR-002 so the dashboard layer is GreptimeDB's embedded Perses dashboard, correcting its premise that `/v1/dashboards` first appears in v1.3.0-alpha.1 (ADR-002:29, :99, :185 and research R39), and keep standalone Perses as `percli migrate` and `percli lint` tooling and as the fallback; amend R1.1 and the "no `pkgs/by-name` entry" lines of ADR-001, ADR-007 and the `greptimedb` component so the store package must be a stable release that serves the embedded dashboard, which makes `greptimedb-bin` the intended package; amend ADR-007's "gRPC disabled" to "gRPC bound to loopback"; move the `observability-notify@` template from S3 to S1 in the reference architecture's sequencing; record each in a charter v11 entry dated 2026-10-16.
  These amendments are made in the planning step, before implementation; task 7.1 verifies they are present.
- **Rationale**: the decision records must describe what is deployed; these four are the places where the deployed shape departs from accepted text.
- **Alternatives considered**: superseding ADRs, rejected because each amendment changes one clause and leaves the record's decision intact.

## Risks / Trade-offs

- [Risk] The R2 stanza is unexercised and may fail on first write (A6:31; GC:154 item a). → Mitigation: R6.4's readiness probe surfaces it; the fallback is local `File` storage with a quota increase (A6:85,123), recorded in `verify.md`.
- [Risk] The store's real peak RSS is unmeasured (A7:102). → Mitigation: R7.2 measures `memory.peak` hourly against `MemoryHigh`, and `MemoryMax` bounds the damage; the ceiling is revised only on R7.2 evidence (A7:179).
- [Risk] The systemd receiver is alpha and may not reach D-Bus under `DynamicUser`. → Mitigation: the container test asserts unit-state series arrive; on failure the collector unit gains the D-Bus access it needs.
- [Risk] `greptimedb-bin` falls behind upstream's stable releases. → Mitigation: `update.sh` and `apps.update-greptimedb-bin` track stable releases, and R1.1 rejects a prerelease.
- [Risk] A malformed users line is skipped silently and a user loses access without an error (F2). → Mitigation: hex passwords and the four-line check.
- [Risk] A regulator query that matches nothing passes vacuously (F3). → Mitigation: empty results and missing tables fail, with a renamed-table mutant.
- [Risk] Any root process on magnetite can reach the loopback listener. → Accepted: every `/v1/` path requires credentials (A8:53), and the trust boundary is stated in the proposal.
- [Risk] A ntfy outage or ZeroTier partition drops failure notices. → Accepted for S1; S3's dead-man covers loss of the alert path.
- [Trade-off] The store runs the vendor's binary rather than the nixpkgs build, because only the vendor's build embeds the dashboard. → Accepted: R1.1 asserts the dashboard is declared and the container test shows it is served; in S1 it is served only on loopback, on the same listener as the API, whose `/v1/` paths require credentials.
- [Risk, S6] The embedded dashboard runs Perses 0.53.1 (dashboard v0.13.13), while upstream Perses and dashboard v0.14.2 on GreptimeDB main run 0.54.0, so a dashboard converted or linted against 0.54 schemas may use features 0.53.1 lacks. → S6 pins `percli lint` to the schema version the deployed dashboard runs, and re-checks the pin whenever `update.sh` moves the store to a release with a newer dashboard.
- [Risk, S6] The dashboard's datasources are fixed at root-absolute `/v1/prometheus` and `/v1/sql`, it has no base-path option, and its browser requests carry the store credential. → S6 gives it a vhost of its own and has nginx overwrite `Authorization` with the `perses:ro` credential, so no password reaches the browser; converted Grafana dashboards must be rewritten to these two datasources.
- [Trade-off] gRPC listens on `127.0.0.1:4001` although ADR-007 asked for it disabled. → Accepted: v1.2.1 has no switch; the bind is asserted.
- [Trade-off] Runtime tests are not gating. → Accepted: evaluation-time regulators gate every pull request, and the runtime tests run on demand before merge and in `verify.md`.
- [Trade-off] S1 grows by the notifier, the `ntfy-send` move and the ingress fragment. → Accepted: S4 then extends rather than restructures, and S1's units are observed from their first deployment.

## Migration Plan

1. Mint an Object Read & Write token on `sciexp` in the Cloudflare dashboard.
2. Run `clan vars generate magnetite`, answering the `greptimedb-r2` prompts; `greptimedb-users` generates without input.
3. Create the dataset by hand on magnetite, once, before the first deployment: `zfs create -o mountpoint=/var/lib/greptimedb -o com.sun:auto-snapshot=false zroot/root/greptimedb`.
   This step is a task and is recorded in `verify.md`; the boot oneshots then set the quota and reservation.
4. Run the evaluation-time checks and both `vmTests` (the container test on magnetite, the OOM test on pyrite) before merge.
5. Deploy with `clan machines update magnetite`.
   The ZFS oneshots set the dataset properties, the store starts only with `/var/lib/greptimedb` mounted, the schema oneshot creates the databases, and the collector begins exporting.
6. Confirm the deployment-time items of D13 and record them in `verify.md`, including R7.2's deliberate failure producing a ntfy message.

Rollback: revert the change and redeploy magnetite.
The collector stops and the store stops; the dataset and the R2 prefix remain until removed by hand, so a re-deployment resumes from the same data.
Reverting the `ntfy-send` move restores the home-manager packaging with no state involved.

## Open Questions

None.
