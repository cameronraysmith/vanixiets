---
linear_story_id: CAM-68
linear_story_identifier: CAM-68
linear_story_title: "S1: Stand up GreptimeDB on magnetite fed by magnetite metrics"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-68/s1-stand-up-greptimedb-on-magnetite-fed-by-magnetite-metrics
linear_story_state: In Progress
linear_team: CAM
linear_project: fleet-observability
last_synced_state: In Progress
last_synced_at: 2026-10-16T17:21:08Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-10-16T14:56:36Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; description seeded from this proposal" }
  - { at: "2026-10-16T17:21:08Z", transition: "Todo->In Progress", outcome: "posted", note: "first - [x] in tasks.md (1.1-1.3)" }
---

## Why

The fleet keeps no metrics history: a memory squeeze on magnetite, a unit that restarts in a loop or a ZFS pool filling up is noticed only when it breaks CI, and nothing records how close the host came.
The observability design is accepted (ADR-001 to ADR-009), and every later slice reads from or writes to its store, so the store comes first.
This change stands up that store on magnetite and feeds it magnetite's own metrics, so the first feedback loop, from a host signal to a stored and queryable series with a failure notice when the pipeline itself breaks, closes on one host before the fleet joins.

## What Changes

**A telemetry store on magnetite**
- GreptimeDB 1.2.1, standalone, reachable only on loopback, with per-user credentials (`admin`, `collector`, `perses`, `regulator`), three databases with retention (`fleet` 30 days, `devloop` 365 days, `agent` 90 days), local state on its own capped ZFS dataset and object data in the `sciexp` R2 bucket under `projects/vanixiets/observability/store/`.
- Bounded so it cannot take CI down with it: 4 GiB memory ceiling, killed before the collector and after the nixbot evaluator under memory pressure, a reduced CPU share and fixed worker pools.
- Packaged from the upstream release binary as `greptimedb-bin`, because only the upstream build embeds GreptimeDB's Perses-based web dashboard, which becomes the fleet's dashboard layer; an evaluation-time assertion requires a stable release that carries the dashboard, and the dashboard is reachable over an SSH tunnel to the loopback listener.

**magnetite's metrics, collected into it**
- The `otel-collector` clan service with both of its roles on magnetite in one process: host memory, paging and per-process memory, systemd unit state and restarts, ZFS and OOM-kill counters through a loopback node_exporter, and the `/metrics` of gitea, nixbot, niks3, nginx, ZeroTier and the store itself.
- Metrics only: no logs or traces enter the store in this change.

**Failures reported, not discovered**
- A notifier template that posts to the fleet's ntfy server, wired as `OnFailure=` on the store, its schema and envelope jobs and its ZFS jobs.
- Moved here from S3 so the slice reports its own failures from its first deployment.

**Regulators that can fail**
- Evaluation-time checks over magnetite's configuration with mutants proving each can fail, an hourly envelope job asserting memory, disk, storage format, retention and credential freshness, an on-demand container test of the whole pipeline and an on-demand VM test of the OOM kill order.

**Decision records amended in place (charter v11)**
- From: ADR-002 deploys a standalone Perses server, on the premise that the store's dashboard API first appears in v1.3.0-alpha.1; R1.1 requires `pkgs.greptimedb` and forbids a first-party package; ADR-007 disables gRPC; the notifier lands in S3.
- To: the dashboard layer is the store's embedded Perses dashboard, with standalone Perses kept as conversion and lint tooling; R1.1 requires a stable release that serves the embedded dashboard, which makes `greptimedb-bin` the intended package; gRPC binds loopback, because v1.2.1 cannot disable it; the notifier lands in S1.
- Reason: v1.2.1 already serves the dashboard API, the nixpkgs build omits the dashboard, and the v1.2.1 configuration has no gRPC switch.
- Impact: non-breaking; documentation only.

## Capabilities

### New Capabilities
- `telemetry-store` (stratum: `behavioral`): what the fleet requires of its telemetry store — that it keeps each database's series for that database's retention and no longer, that only the collector writes and only named readers read, that it stays inside a memory and disk envelope that leaves CI its capacity, that it reports no usage telemetry upstream, that it runs a stable release that serves its dashboard, and that its own failures are reported.
- `host-metrics-collection` (stratum: `behavioral`): what the fleet requires of collecting a host's metrics — which signals magnetite contributes, that each stored series names its host, that series cardinality stays bounded, that collection survives a store restart without losing the queued interval, and that a failed collection or store job notifies a human.
- `telemetry-store-interface` (stratum: `interface`): the properties at the machine's interface that discharge those requirements — listeners bound to loopback only, the per-user permission modes, the OTLP/HTTP ingest path with its database and attribute-promotion headers, the PromQL and SQL read paths, the object-storage prefix, credentials present only as activation-resolved files owned by non-worker users, and the ntfy topic the notifier posts to.
  Trust boundary: the R2 token's scope and the bucket's durability are set and provided by Cloudflare, not asserted by this machine; any root process on magnetite can reach the loopback listener; ntfy access is ZeroTier membership; nothing here guarantees a series reaches the store end to end, only that each stage's configuration and the tested pipeline behave as stated.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): assumptions are added — R2 behaves as S3-compatible object storage for GreptimeDB's client, nixpkgs channels lag GreptimeDB releases and the nixpkgs build omits the dashboard, magnetite's memory is finite and shared with the nixbot evaluator, magnetite has no `/dev/kvm`, and ntfy on cinnabar is reachable over ZeroTier — and the designation table gains the terms the new behavioral requirements use (series, database, retention, envelope).

## Impact

- New: `pkgs/by-name/greptimedb-bin` and `pkgs/by-name/ntfy-send` (moved from `modules/home/tools/commands/system/`), `modules/nixos/greptimedb.nix`, `modules/clan/services/otel-collector/` with `schema.nix`, `modules/clan/inventory/services/otel-collector.nix`, checks under `modules/checks/` and tests under `modules/vm-tests/`.
- Changed: `modules/machines/nixos/magnetite/{default,disko}.nix` (import, dataset, ZFS jobs, generators), `modules/nixos/nixbot.nix` (loopback metrics server on `127.0.0.1:9180`), `modules/apps/updates.nix`, the home-manager `ntfy-send` command, and the observability decision records, components, reference architecture and charter.
- New secrets: `greptimedb-users` (generated) and `greptimedb-r2` (prompted; an Object Read & Write token on `sciexp`, minted by hand in the Cloudflare dashboard).
- Deployment: `clan machines update magnetite`; the store creates its prefix on first write, and no bucket or lifecycle rule changes.
- Out of scope, each in a later slice: dev-loop collection (S2), the alert evaluator and dead-man (S3), other hosts and mTLS (S4), darwin (S5), Perses (S6), logs, traces and agent telemetry (S7), and the Parquet export (S8).
