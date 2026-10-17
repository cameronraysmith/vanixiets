---
title: "greptimedb"
---

## Purpose

GreptimeDB is the store: it durably holds fleet, dev-loop and agent-harness telemetry and answers OTLP writes, PromQL queries and SQL queries over it (ADR-001 Decision).
It also serves the dashboard layer, the Perses dashboard its release build embeds, at `/dashboard/`, with dashboards stored through `/v1/dashboards` (ADR-002 Decision; `components/perses.md`).
It runs as one standalone process on `magnetite`, with its SST substrate in the existing Cloudflare R2 bucket `sciexp` (ADR-006 Decision, ADR-007 Decision).
Its daily Parquet export to the lakehouse seam is a separate component, `components/parquet-export.md`, that runs inside this process.

## Decisions realized

- ADR-001 Decision: the open build of GreptimeDB, standalone, consumed as `greptimedb-bin`, a first-party package of the upstream release tarball, and never from a prerelease.
- ADR-001 Decision: `greptimedb-bin` is the intended package because the tarball embeds the dashboard ADR-002 adopts; `pkgs.greptimedb` is acceptable only if it carries that dashboard.
- ADR-001 Decision and Q1: the first deployment uses `v1.2.1`.
- ADR-001 Decision and Q6: the `v1.3.x` line is adopted only when a stable `v1.3` release is published, through `greptimedb-bin`'s `update.sh`, and not through an overlay.
- ADR-001 Decision and Q3: alerting is external to the store, so no enterprise-gated trigger DDL is relied on.
- ADR-001 Decision: anonymous usage reporting to `telemetry.greptimestats.com` is disabled.
- ADR-001 Q5: the unconditional flownode in standalone is accepted.
- ADR-004 Decision: three databases, `fleet` at 30 days with the `fleet` logs table at 14 days, `devloop` at 365 days and `agent` at 90 days.
- ADR-004 Decision: ADR-004's `schema.nix` owns the attribute allow-list, the metric label bans and the `devloop` column allow-list with each table's primary key and time index; the store holds what the collector admits.
- ADR-006 Decision: the store's `[storage]` section is `type = "S3"` with `bucket = "sciexp"` and `root = "projects/vanixiets/observability/store/"`, authenticated by the long-lived Object Read & Write token held as the clan var `greptimedb-r2` (ADR-006 Q6, Q9).
- ADR-006 Decision: no lifecycle rule covers the store prefix, because retention is the store's own per-database and per-table TTL.
- ADR-006 Decision: every table uses the flat SST format, and no table may set `sst_format` to the legacy value.
- ADR-006 Q7: local `File` storage on the dedicated dataset is the fallback if the R2 stanza fails its first deployment.
- ADR-007 Decision and Q1: placement on `magnetite` inside an explicit memory and disk containment.
- ADR-007 Decision and Q3, Q4, Q5: the unit limits, memory knobs, dataset quota and reservation, and cache caps listed under Placement and Configuration surface.
- ADR-007 Decision: HTTP on loopback; gRPC bound to `127.0.0.1:4001` because `v1.2.1` cannot disable it; from S6 the API listener on `127.0.0.1:4006` for the dashboard vhost; every other listener disabled; the event recorder's event list empty.
- ADR-007 Decision and Q7: one `greptimedb-users` generator with four users, `admin:rw`, `collector:wo`, `perses:ro` and `regulator:ro`.
- ADR-007 Decision and Q6: credential rotation restarts the store, and restart-on-rotation stays after a `v1.3` release is deployed.
- ADR-007 Decision: the store is a plain NixOS module imported by `magnetite`, not a clan service role.
- ADR-008 Decision items 1 to 3: authentication on every store request, read/write separation by user mode, and loopback-only network placement.

## Placement

- Host: `magnetite` only (ADR-007 Decision).
- Unit: `greptimedb.service`, running as the static system user and group `greptimedb`, not `DynamicUser` (ADR-007 Decision).
- Unit limits: `MemoryHigh = "3G"`, `MemoryMax = "4G"`, `MemorySwapMax = "0"`, `OOMScoreAdjust = 500`, `Restart = "on-failure"`, `RestartSec = 30` and `StartLimitIntervalSec = 0` (ADR-007 Decision).
- Local state: the ZFS dataset `zroot/root/greptimedb` mounted at `/var/lib/greptimedb`, with `quota = 16G`, `reservation = 12G` and `com.sun:auto-snapshot = false`, asserted by boot-time oneshots (ADR-007 Decision).
- Dataset oneshots: `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation` and `zfs-assert-root-greptimedb-noautosnap` (ADR-007 Implementation surface).
- Schema oneshot: `greptimedb-schema.service`, ordered after the store reports ready (ADR-007 Decision).
- Regulator: `greptimedb-envelope.service` and `greptimedb-envelope.timer`, hourly (ADR-007 R7.2).
- Export: `greptimedb-export.service` and `greptimedb-export.timer`, specified in `components/parquet-export.md` (ADR-006 Decision).
- Under host-wide memory exhaustion the store is the second OOM victim, after the evaluator at `oom_score_adj` 900 and ahead of the ADR-003 `ingress` collector at 300, `nix-daemon` workers at 250 and PostgreSQL at 0 or lower (ADR-007 Rationale, Consequences).

## Interfaces

Listener:

- HTTP on `127.0.0.1:4000`; no firewall port is opened (ADR-007 Decision).
- gRPC on `127.0.0.1:4001`, held on loopback because `v1.2.1` has no setting that disables it (ADR-007 Context, Decision).
- From S6, the API listener on `127.0.0.1:4006`, enabled by `http.enable_api_server = true`, serving only `/v1` and `/dashboard` to the dashboard vhost (ADR-002 Decision; ADR-007 Decision).
- The embedded dashboard at `/dashboard/`, and the dashboards API `GET /v1/dashboards`, `POST /v1/dashboards/{name}` and `DELETE /v1/dashboards/{name}`, whose saves and deletes the store rejects for `ro` users (ADR-002 Context).
- OTLP ingest at `/v1/otlp/v1/{metrics,traces,logs}`, HTTP with protobuf only, since all three handlers reject JSON and no OTLP/gRPC service exists at `v1.2.1` (ADR-001 Context).
- PromQL at `/v1/prometheus/api/v1`, including `/query` and `/query_range`; the Prometheus `/metadata` route is absent at 1.2.1 (ADR-001 Context, ADR-009 Context).
- SQL over HTTP at `/v1/sql` (ADR-002 Context).
- `/ready`, read by the envelope probe after start (ADR-006 R6.4).
- Prometheus remote read and write at `/v1/prometheus/{read,write}`, enabled because `v1.2.1` registers the PromQL query API only together with them (`GreptimeTeam/greptimedb@179ff8e50:src/frontend/src/server.rs:130-158`); loopback-only and authenticated, and only `collector` (`wo`) and `admin` (`rw`) can write (ADR-007 Decision, charter v13).
- Disabled: MySQL, PostgreSQL, OpenTSDB, InfluxDB and the Jaeger query API (ADR-007 Decision).
- Every path under `/v1/`, including the OTLP routes, requires credentials once the user provider is configured, and loopback is not trusted because every local UID on `magnetite`, including two worker accounts, can reach it (ADR-007 Context, ADR-008 Context and Decision item 1).
- A database is selected by the caller through `x-greptime-db-name` or `db`, so a database is a label, not an access boundary (ADR-008 Context).

Upstream:

- The ADR-003 `ingress` collector on `magnetite` is the only writer, through one `otlp_http` exporter per database with endpoint `http://127.0.0.1:4000/v1/otlp`, the header `x-greptime-db-name`, the header `x-greptime-otlp-metric-promote-resource-attrs` listing ADR-004's resource allow-list, and `basicauth` with the `collector` password (ADR-003 Decision items 10 and 15).
- While the store is below 1.3.0 the ingress metrics pipeline converts exponential histograms to explicit-bucket histograms with `convert_exponential_histogram_to_histogram` (ADR-001 Decision, ADR-003 Decision item 11).

Downstream:

- The dashboard layer: from S6, nginx on `magnetite` proxies the vhost's `/dashboard/` and `/v1/` to `http://127.0.0.1:4006` with `Authorization` overwritten by the `perses` credential; the embedded dashboard's `promql-default` and `sql-default` datasources query `/v1/prometheus` and `/v1/sql` (ADR-002 Decision).
- The dashboard reconcile oneshot `perses-dashboards.service` on `magnetite` writes and deletes dashboards through `/v1/dashboards` with a `rw` credential whose holder is open (ADR-002 Q9).
- `fleet-alert.service` on `magnetite`: PromQL instant queries to `http://127.0.0.1:4000/v1/prometheus/api/v1/query` against `fleet` as the `regulator` user, with a 10 s per-query timeout (ADR-009 Decision item 1).
- `otel-envelope` (ADR-003 R3.2, ADR-004 R4.2), `devloop-reconcile` (ADR-005) and `greptimedb-envelope` (ADR-007 R7.2) read as `regulator` (ADR-009 governs the holder list).
- `greptimedb-schema` and `greptimedb-export` act as `admin` (ADR-007 Decision).
- DuckDB consumers read only the Parquet export, never the store's SSTs (ADR-006 Decision).

Store users, from the `greptimedb-users` generator (ADR-007 Decision):

| User | Mode | Holders |
|---|---|---|
| `admin` | `rw` | `greptimedb-schema`, `greptimedb-export` (ADR-007 Decision) |
| `collector` | `wo` | the ADR-003 `ingress` collector (ADR-003 Decision item 10) |
| `perses` | `ro` | nginx on `magnetite` from S6, injecting it into dashboard readers' requests (ADR-002 Decision) |
| `regulator` | `ro` | `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope`, `fleet-alert.service` (ADR-009 Decision item 1 and Implementation surface) |

No worker account and no worker-run process holds any store credential (ADR-008 Decision).

Credentials consumed by the store:

- The `users` file of the `greptimedb-users` generator, through `LoadCredential` and `static_user_provider:file:` at the unit's credentials directory (ADR-007 Decision).
- The `env` file of the `greptimedb-r2` generator, through `EnvironmentFile`, carrying `GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID` and `GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY` (ADR-006 Implementation surface, ADR-007 Decision).

Egress:

- The store makes no outbound connection other than to the R2 endpoint `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` (ADR-001 E1.4, ADR-006 Context).

Failure notification:

- `greptimedb-schema`, `greptimedb-export`, `greptimedb-envelope` and the three dataset oneshots set `OnFailure=observability-notify@%n.service`, the notifier of ADR-003 with delivery per ADR-009 (ADR-003 Q9, ADR-007 Decision, ADR-009 Decision item 11).
- `StoreQueryFailing` in `fleet-alert.service` reports a store that does not answer queries (ADR-009 Decision item 6).

## Configuration surface

- Add `pkgs/by-name/greptimedb-bin/{package.nix,update.sh}`: the upstream checksummed `greptime-linux-amd64-v1.2.1.tar.gz` on `x86_64-linux` only, `null` on other systems, `autoPatchelfHook`, `mainProgram = "greptime"`, `passthru.embedsDashboard = true`, and `apps.update-greptimedb-bin` on every system, running `update.sh` directly (ADR-001 Implementation surface, ADR-007 Decision and Implementation surface).
- No new flake input, no overlay and no clan inventory instance (ADR-001 Implementation surface, ADR-007 Implementation surface).
- Add `modules/nixos/greptimedb.nix`: `flake.modules.nixos.greptimedb` with `services.greptimedb.{enable,package,settings,databases,export}`, TOML generation, the `greptimedb` user and group, `greptimedb.service` with the unit limits and `LoadCredential` for the users file, `EnvironmentFile` for the R2 env file, `greptimedb-schema.service`, the ADR-006 export service and timer, `greptimedb-envelope.service` and `.timer`, and the assertions R1.1, R1.2, R1.4 and R6.4 (ADR-007 Implementation surface, ADR-001 Implementation surface, ADR-006 Implementation surface).
- Generated TOML memory knobs: `global_write_buffer_size = "256MB"`, `max_in_flight_write_bytes = "128MB"` with policy `wait`, `memory_pool_size = "512MB"`, `scan_memory_limit = "512MB"` with `scan_memory_on_exhausted = "fail"`, `experimental_compaction_memory_limit = "256MB"`, `max_background_compactions = 2`, `max_background_flushes = 2`, `max_concurrent_queries = 8`, `page_cache_size = "256MB"`, `sst_meta_cache_size = "64MB"`, and 32 MB each for the vector, selector-result, range-result and prefilter-result caches (ADR-007 Decision).
- Generated TOML caches: the write cache and the read cache each capped at 4 GiB (ADR-007 Decision).
- Generated TOML storage: `type = "S3"`, endpoint `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, `region = "auto"`, `enable_virtual_host_style = false`, `disable_ec2_metadata = true`, `bucket = "sciexp"` and `root = "projects/vanixiets/observability/store/"` (ADR-006 Context and R6.4).
- Generated TOML listeners: HTTP at `127.0.0.1:4000`, every other server disabled, `user_provider` set, `enable_telemetry = false` and an empty event-recorder event list, `event_recorder.event_types = [ ]` (ADR-007 Decision).
- `greptimedb.service` `ExecStartPre`: writes the sha256 of `$CREDENTIALS_DIRECTORY/users` to `/run/greptimedb/loaded-users.sha256`, mode `0444`, for R7.4 (ADR-007 R7.4).
- `greptimedb-schema.service`: idempotently creates `fleet`, `devloop` and `agent` with TTL defaults of 30, 365 and 90 days and sets the `fleet` logs table TTL to 14 days (ADR-007 Decision, ADR-004 Implementation surface).
- Modify `modules/machines/nixos/magnetite/default.nix`: import `greptimedb`, set `services.greptimedb`, declare the `greptimedb-users` and `greptimedb-r2` generators beside `omnigraph-r2`, add the three `greptimedb` dataset oneshots, and give these three and the six existing `zfs-assert-*` and `zfs-set-*` oneshots `OnFailure=observability-notify@%n.service` (ADR-007 Implementation surface, ADR-009 Implementation surface).
- Modify `modules/machines/nixos/magnetite/disko.nix`: add the `root/greptimedb` dataset with mountpoint `/var/lib/greptimedb`, `quota = "16G"`, `reservation = "12G"` and `com.sun:auto-snapshot = "false"` (ADR-007 Implementation surface).
- Add `modules/checks/greptimedb-envelope.nix`: regulator R7.1 and its mutants (ADR-007 Implementation surface).
- Clan vars generator `greptimedb-users` on `magnetite`: `runtimeInputs` openssl; files `users` (owner `greptimedb`, mode `0400`, `restartUnits = [ "greptimedb.service" ]`), `admin-password` (mode `0400`), `collector-password` (mode `0400`, `restartUnits` naming the ADR-003 ingress collector unit), `perses-password` (mode `0400`, no consumer in S1, `restartUnits = [ "nginx.service" ]` from S6), `regulator-password` (mode `0400`, no `restartUnits`) and the public `users-sha256` (`secret = false`, the sha256 of `users`); the three non-admin password files are written with `printf '%s'` (ADR-007 Decision and Implementation surface).
- Clan vars generator `greptimedb-r2` on `magnetite`: hidden prompts `access-key` and `secret-key` for an R2 token with Object Read & Write on `sciexp`, `persist = true`, per-file `deploy = false`, rendered to an `env` file, `restartUnits = [ "greptimedb.service" ]`, following `omnigraph-r2` (ADR-006 Implementation surface).
- `modules/terranix/cloudflare.nix`: no bucket resource and no lifecycle rule for the store prefix (ADR-006 Implementation surface).

## Operating envelope and regulator

| Envelope | Regulator | Source |
|---|---|---|
| E1.1 version and dashboard: stable `MAJOR.MINOR.PATCH`, and the package serves the embedded dashboard; `greptimedb-bin` is the package, and `pkgs.greptimedb` qualifies only if it carries the dashboard | R1.1, amended under charter v11: evaluation-time assertion on `cfg.package.version` and `cfg.package.passthru.embedsDashboard`, with enumerated mutants an `overrideAttrs` at `1.3.0-beta.2` and the pinned `pkgs.greptimedb`; runtime case in S1's container test `vmTests.x86_64-linux.greptimedb-pipeline`: `GET http://127.0.0.1:4000/dashboard/` returns 200 | ADR-001 |
| E1.2 histogram compatibility: below `1.3.0`, every collector pipeline exporting metrics to the store converts exponential histograms | R1.2: evaluation-time assertion over the store version and the magnetite collector configuration, with a mutant that removes the statement | ADR-001 |
| E1.3 edition: no configuration path depends on trigger DDL, `UNDROP TABLE`, the recycle bin, `purge_table` or tracked flow writes | R1.3: none automated; the open build fails closed, recorded as such by the human gate | ADR-001 |
| E1.4 egress: no outbound connection other than to R2 | R1.4: evaluation-time assertion that the TOML sets `enable_telemetry = false`, with a mutant that omits the key | ADR-001 |
| E6.2 substrate size: sum of `sst_size` over `information_schema.region_statistics` under 50 GiB | R6.2: the `greptimedb-envelope` probe queries it over the loopback HTTP SQL endpoint and fails above the bound | ADR-006 |
| E6.3 readable format: no table has `sst_format` set to the legacy format | R6.3: the probe queries `create_options` in `information_schema.tables`; negative control is a scratch legacy-format table | ADR-006 |
| E6.4 R2 reachability: the store writes and lists its manifest objects on R2 | R6.4: `/ready` after start, checked by the probe, plus an evaluation-time assertion over the S3 stanza, with mutants dropping `disable_ec2_metadata` and setting `root` to the empty string | ADR-006 |
| E7.1 configuration: unit limits, every memory knob, every listener including gRPC on loopback, disabled protocols, `user_provider`, `enable_telemetry = false`, and `greptimedb.service` in the users-file generator's `restartUnits` at every version, because restart-on-rotation stays after `v1.3` (ADR-007 Q6) | R7.1: flake check `modules/checks/greptimedb-envelope.nix` with one mutant per clause, including one removing `restartUnits` | ADR-007 |
| E7.2 runtime memory: cgroup `memory.stat` `anon` below `MemoryHigh`, `memory.events` `high`, `oom_kill` and `max` not increasing within one store invocation, and no kernel OOM kill or automatic restart between invocations; `memory.peak` is not bounded, because it counts page cache and never decreases within an invocation | R7.2: hourly `greptimedb-envelope.timer` oneshot comparing `anon` with `GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES` and reading the `memory.events` counters against a baseline keyed by `InvocationID`, and across invocations the journal's `MESSAGE_ID=fe6faa94e7774663a0da52717891d8ef` entries for `greptimedb.service` and its `NRestarts`, failing on breach, and running R6.1 to R6.4 | ADR-007 |
| E7.3 disk: `zroot/root/greptimedb` used below 80% of quota, quota and reservation at declared values | R7.3: boot-time `zfs set` oneshots with `OnFailure=`, plus the envelope oneshot reading `zfs get -Hp used,quota,reservation` | ADR-007 |
| E7.4 credential freshness: the running store loaded the users file currently deployed | R7.4: the envelope oneshot compares `/run/greptimedb/loaded-users.sha256` with the generator's public `users-sha256` and fails when they differ or either is missing | ADR-007 |
| ADR-004 budget and TTLs | R4.2: `otel-envelope` compares each database's and the `fleet` logs table's `ttl` option against ADR-004's table, and checks the per-database cardinality and volume bounds | ADR-004 |

A failed regulator oneshot is a failed systemd unit whose `OnFailure=` notifier reaches a human, so the store needs no alerting component of its own (ADR-007 R7.2).
A store that stops answering raises `StoreQueryFailing` after 3 min in the ADR-009 evaluator, which freezes every other alert instance (ADR-009 Decision item 6).

## Failure prevented

- Standalone instead of distributed: three additional units, each with its own memory floor, on a host that has OOM-killed twice (ADR-001).
- The no-prerelease version rule: a beta store without published artifacts becoming a fleet dependency through an overlay (ADR-001).
- Packaging the upstream release tarball: a first-party Rust build of the store entering the closure operator on the hosts that have run out of memory, while keeping the embedded dashboard (ADR-007).
- The dashboard clause of R1.1: a package switch that silently removes the dashboard layer and the dashboards API (ADR-001).
- The histogram conversion: silent loss of every exponential-histogram series (ADR-001).
- Disabling usage reporting and the event recorder: an undeclared outbound connection from the host holding agent-session telemetry, and an unrequested 90-day table (ADR-001, ADR-007).
- External alerting: a design that silently depends on an enterprise-only feature and reopens RK1 (ADR-001).
- Memory knobs and `MemoryMax`: the store sizing itself from `magnetite`'s RAM and competing with nixbot's evaluation (ADR-007).
- `MemorySwapMax = 0`: the store's footprint moving into the uncharged zram pool (ADR-007).
- `OOMScoreAdjust = 500`: a host OOM killing `nix-daemon` workers ahead of the store and failing CI (ADR-007).
- Dedicated dataset with quota and reservation: WAL and cache growth starving `/nix`, `/` or `/home`, the 2026-06-10 failure (ADR-007).
- Disabled listeners, gRPC held on loopback, and credentials on loopback: worker accounts on `magnetite` reaching wire protocols no consumer uses, any store listener leaving the host, or the store read anonymously (ADR-007, ADR-008).
- `restartUnits` on the users file: a rotated credential leaving the store authenticating against the superseded file (ADR-007).
- Legacy-format check: a table whose tags are unrecoverable outside the store entering the export (ADR-006).
- No lifecycle rule on the store prefix: a delete-by-age rule removing SSTs and manifests the store still references (ADR-006).
- Keeping the store out of the clan inventory: an inventory instance whose roles relate nothing (ADR-007).

## Deployment acceptance items

- The R2 stanza has not been exercised against a live bucket, and R6.4 makes its first failure visible at deploy time; on failure the store moves to local `File` storage and the dataset quota is raised to hold the SSTs (ADR-006 Rationale, Consequences, Q7).
- The `object-read-only` scope and the two observability prefixes have not been checked against R2 (ADR-006 Consequences).
- The bucket-wide 7-day multipart-abort rule is harmless only while no store upload stays open that long, and GreptimeDB's upload duration on R2 is unmeasured (ADR-006 Consequences).
- GreptimeDB documents no total-RSS formula, so whether the store's anonymous memory stays under the 3 GiB `MemoryHigh` without throttling is what R7.2 measures (ADR-007 Rationale).
- The 7.89 GiB minimum `MemAvailable` during a nixbot evaluation comes from an uncommitted measurement, and the regulator, not the figure, is relied on (ADR-007 Context, Rationale).
- R7.2 is shown able to fail by running it once with the anonymous-memory threshold set below the observed value and recording the failed unit in the implementing change (ADR-007 R7.2).
- R6.3's negative control is a scratch table created with the legacy option during the implementing change (ADR-006 R6.3).
- The E6.2 bound rests on an estimate whose log volume is unmeasured (ADR-006 E6.2).
- GreptimeDB's default deduplication of non-append tables is assumed to collapse the CI attribute rows that ADR-005's five-minute cursor overlap re-reads, and the reconciliation counts distinct `(build_id, attr, finished_at)` either way (ADR-005 Consequences).
- Store-side query semantics for alert rules are covered by `RuleSignalMissing` within 30 min of deploy (ADR-009 Consequences).

## Deferred

- `v1.3.x`: adopted when a stable `v1.3` release is published and `greptimedb-bin`'s `update.sh` takes it, at which point R1.2 no longer requires the collector's exponential-histogram conversion and tracks its removal; restart-on-rotation stays because `LoadCredential` snapshots credentials at start (ADR-001 Consequences, ADR-007 Q6).
- Local `File` storage: applied only if the R2 stanza fails its first deployment (ADR-006 Q7).
- Phase-2 memory work: the store's ceiling ships now and is folded into the incident note's phase-2 `MemoryLow` and oomd work when it lands (ADR-007 Q8).
- API listener `127.0.0.1:4006`: enabled in S6 with the dashboard vhost, not in S1 (ADR-002 Decision).
- Store-enforced per-person read partitioning: not available in the open build, and not required under ADR-008's shared read zone (ADR-001 Q4).
