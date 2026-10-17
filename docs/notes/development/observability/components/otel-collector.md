---
title: "otel-collector"
---

## Purpose

The otel-collector component moves telemetry from every in-scope host to the store on magnetite.
It runs one `opentelemetry-collector-contrib` 0.155.0 agent per in-scope host, gives magnetite's agent the ingress role, and runs a separate root process collector on darwin hosts (ADR-003).
It is the only content boundary and the only path into the store (ADR-008).
It also runs the runtime regulator `otel-envelope` and hosts the shared failure notifier template `observability-notify@` (ADR-003, ADR-009).

## Decisions realized

- ADR-003 Decision items 1 to 2: one agent per in-scope host, the six NixOS machines and stibnite, from the root nixpkgs pin, with blackphos, rosegold and argentum joining only after their primary users consent (ADR-003 Q3).
- ADR-003 item 3: a local OTLP/HTTP receiver on `127.0.0.1:4318` wired only into traces and metrics pipelines, so OTLP log records are rejected.
- ADR-003 item 4: `host_metrics` at 60 s, `journald` on NixOS restricted to ADR-004's unit allow-list, and `filelog` on `/var/log/deploy-record.jsonl` for ADR-005's deploy record.
- ADR-003 item 5: the zerotierone scrape at `localhost:9993/metrics` with its token through `LoadCredential`, and `enableMetrics = true` set explicitly.
- ADR-003 item 6: magnetite's agent scrapes gitea, niks3, nixbot through a loopback nginx server and nginx `stub_status`, and hosts ADR-005's PostgreSQL reader.
- ADR-003 items 7 and 8: redaction and allow-list stages before every exporter, `host.name` and routing-attribute stamping, mTLS export to `https://magnetite.zt:4318`, a `file_storage`-backed `sending_queue`, and `memory_limiter` first in every pipeline.
- ADR-003 items 9 to 13: the ingress receiver on magnetite's ZeroTier address with client certificates from `otel-ca`, `routing` by database to one `otlp_http` exporter per GreptimeDB database as the `collector` (`wo`) user, the exponential-histogram transform while the store is below 1.3.0, and ZeroTier-only transport.
- ADR-003 item 15: the `x-greptime-otlp-metric-promote-resource-attrs` header on every ingress exporter, so `host.name`, `systemd.unit.name` and `process.executable.name` survive as labels.
- ADR-003 items 16 to 18 and 20 to 22: the collector-side host signals, namely per-process memory, systemd unit state and restarts, available memory and paging, the `prometheus` receiver scrapes of the loopback exporters, the `zt_peer_.*` drop, darwin `disk` and `filesystem` bounds, and the darwin root `otelcol-process` collector; the exporters and the darwin probe are `components/host-probes.md`.
- ADR-003 R3.1, R3.2 and the failure notifier (ADR-003 Q9), as corrected by the 2026-10-15 conflict resolution: the `observability-notify@` template belongs to the `agent` role on every in-scope NixOS host, cinnabar included, and its delivery discipline is ADR-009 item 11.
- ADR-004: the attribute, metric-name, journald-field and `devloop` column allow-lists and label bans applied in the collector from one `schema.nix`, the per-host value caps `schema.nix` declares, and regulators R4.1 and R4.2.
  No collector stage at contrib 0.155.0 caps the number of distinct process names, so the 30-name bound is observed at S1's deployment and regulated at runtime by R4.2 from S4; `schema.nix` carries no `process.maxNames` until a consumer exists (charter v16).
- ADR-008 Decision items 3 to 5: the mesh-facing ingress as the only telemetry listener beyond loopback, collectors under accounts outside every worker UID, and the six collector content stages.
- ADR-008 R8.1, R8.2 and R8.3.

## Placement

- Agent hosts: cinnabar, electrum, galena, scheelite, magnetite, pyrite and stibnite (ADR-003 Implementation surface).
- NixOS unit: `opentelemetry-collector.service` from the NixOS `services.opentelemetry-collector` module with `package = pkgs.opentelemetry-collector-contrib`, running as `DynamicUser` (ADR-003 item 1; ADR-008 Decision item 4; ADR-005 Assumptions).
- Ingress: magnetite's own `opentelemetry-collector.service`, which carries the second OTLP receiver and the store exporters (ADR-003 item 9).
- Darwin agent: `launchd.daemons.otelcol`, launchd label `org.nixos.otelcol`, running as the dedicated user `_otelcol`, wrapped behind `/bin/wait4path /nix/store` with `KeepAlive` (ADR-003 item 1; ADR-004 launchd job allow-list).
- Darwin process collector: `launchd.daemons.otelcol-process`, launchd label `org.nixos.otelcol-process`, running as root with no receiver endpoint and no collector telemetry listener (ADR-003 item 22; ADR-008 Decision item 4).
- Regulator: `otel-envelope.service` and its timer on magnetite, in the `ingress` role (ADR-003 Implementation surface).
- Notifier: the `observability-notify@` template unit in the `agent` role's NixOS module on every in-scope NixOS host, cinnabar included (ADR-003 Q9 as corrected; ADR-009 item 11).
  The units that set `OnFailure=observability-notify@%n.service` are `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope`, `greptimedb-export`, `greptimedb-schema`, `fleet-alert.service` and `fleet-deadman.service`, and magnetite's six existing and ADR-007's three `zfs-assert-*` and `zfs-set-*` oneshots (ADR-003 Q9 as corrected; ADR-007; ADR-009 item 11).

## Interfaces

Listeners:

- `127.0.0.1:4318`, OTLP/HTTP, on every agent, for local emitters; wired into traces and metrics only (ADR-003 item 3).
- `[${flake.lib.hosts.magnetite.zt}]:4318`, OTLP/HTTP with TLS and required client certificates through `tls.client_ca_file`, on magnetite only, opened on `zt+` only, binding before zerotierone settles through magnetite's existing `net.ipv6.ip_nonlocal_bind = 1` (ADR-003 item 9; `cameronraysmith/vanixiets@f55c27adb:modules/machines/nixos/magnetite/default.nix:469-471`; `open-telemetry/opentelemetry-collector@41da2fbd7:config/configtls/README.md:147`).
- `otelcol-process` has no listener (ADR-003 item 22).

Upstream emitters and scrape targets:

- omp on human accounts, OTLP/HTTP metrics to `127.0.0.1:4318` (ADR-005 signal 4); see `components/devloop-exporters.md`.
- `otelcol-process` on darwin, OTLP/HTTP to the local agent's `127.0.0.1:4318`, routed by `service.name` `otelcol-process` into the agent's `host_metrics` pipeline (ADR-003 item 22).
- zerotierone at `localhost:9993/metrics` on every NixOS agent, bearer token from `metricstoken.secret` through `LoadCredential` (ADR-003 item 5).
- On magnetite: gitea at `127.0.0.1:3002`, niks3 at `127.0.0.1:5752`, nixbot through a new loopback-only nginx server on `127.0.0.1:9180` proxying `/metrics` to `/run/nixbot/web.sock`, and nginx through the `nginx` receiver at `http://127.0.0.1/nginx_status` (ADR-003 item 6).
- On every NixOS agent: node_exporter at `127.0.0.1:9100`; on pyrite also smartctl_exporter at `127.0.0.1:9633`; on darwin agents node_exporter at `127.0.0.1:9100` serving the probe's textfiles (ADR-003 items 18, 19, 23); see `components/host-probes.md`.
- On magnetite: the `sqlquery` receiver over nixbot's PostgreSQL and the gitea-mq `journald` receiver of ADR-005; see `components/devloop-exporters.md`.

Downstream:

- Every agent exports with `otlp_http` to `https://magnetite.zt:4318`, presenting its `otel-cert` client certificate (ADR-003 item 7).
- The ingress routes by the `vanixiets.database` resource attribute with the `routing` connector to one `otlp_http` exporter per database, `fleet`, `devloop` and `agent`, each with endpoint `http://127.0.0.1:4000/v1/otlp` and header `x-greptime-db-name`, and removes `vanixiets.database` before export (ADR-003 item 10; ADR-004 convention item 5).
- The store is `components/greptimedb.md`.

Credentials consumed:

- `otel-ca` clan vars generator: `ca.crt` on every agent and as the ingress `tls.client_ca_file` (ADR-003 item 12).
- `otel-cert` clan vars generator: per-machine client certificate and key, owned by `_otelcol` on darwin and delivered by `LoadCredential` on NixOS (ADR-003 Implementation surface).
- `collector-password` of ADR-007's `greptimedb-users` generator, read by the ingress's `basicauth` extension through `client_auth.password_file` at `/run/credentials/opentelemetry-collector.service/collector-password`, delivered by `LoadCredential` (ADR-003 item 10, Implementation surface; ADR-007).
  Build-time validation does not open `password_file` (`open-telemetry/opentelemetry-collector-contrib@v0.155.0:extension/basicauthextension/config.go:50-60`), so it needs no placeholder credential; the one `validateConfigOverrides` entry removes the zerotierone scrape job's `authorization`, because the prometheus receiver's validation stats its `credentials_file` (`open-telemetry/opentelemetry-collector-contrib@v0.155.0:receiver/prometheusreceiver/config.go:211-231`).
  Its `restartUnits` names the ingress collector unit, and rotation restarts that unit at every store version, including after GreptimeDB 1.3, because `LoadCredential` snapshots the file at unit start (ADR-007 Q6; ADR-008).
- `regulator-password` of the same generator, read by `otel-envelope` through `LoadCredential` (ADR-003 Implementation surface; ADR-007).
- zerotierone's `metricstoken.secret`, through `LoadCredential` (ADR-003 item 5).
- The `alerter` ntfy token from ADR-009's `ntfy-alerter` generator, used by the `observability-notify@` template (ADR-009 items 11 and 13).
- `otelcol-process` holds no credential (ADR-008 Decision item 4).

## Configuration surface

- Add `modules/clan/services/otel-collector/flake-module.nix`: clan service `otel-collector` with roles `agent` and `ingress`, a `nixosModule` and a `darwinModule` per role, the `zt+` firewall opening for 4318 on the ingress, and the `otel-ca` and `otel-cert` generators (ADR-003; ADR-007).
  From S1 the same file defines the plain NixOS modules `flake.modules.nixos.otel-collector-agent` and `flake.modules.nixos.otel-collector-ingress`, which the two roles import.
- In that file's `agent` role NixOS module: the `process` and `systemd` receivers, the omnigent-host alias `transform`, the `groupbyattrs`, `metricstransform` and 64 MiB `filter` stages, the `paging` scraper with `system.paging.operations` and `system.paging.faults` disabled, `system.linux.memory.available` enabled, the `prometheus` receiver scrape configurations with keep-lists from `schema.nix`, and the `zt_peer_.*` drop on the zerotierone scrape (ADR-003 items 16 to 18 and 20, Implementation surface; ADR-004).
- In that file's `agent` role NixOS module: the `observability-notify@` template unit, which calls `pkgs.ntfy-send` against `ntfy.zt`, and the option `services.observability-notify.units`, a list of unit names without `.service`, for each of which the module sets `OnFailure=observability-notify@%n.service` and the `RESOLVED` `ExecStartPost=` and `ExecStopPost=` hooks (ADR-003 Q9 as corrected; ADR-009 items 10 and 11).
  The module also sets the collector's `RestartSec = 5s` and `StartLimitIntervalSec = 0`, so five quick start failures cannot leave it failed for good (charter v14).
- In that file's `agent` role darwin module: `launchd.daemons.otelcol`, the `_otelcol` user, item 21's `disk` and `filesystem` settings, `launchd.daemons.otelcol-process` as root with item 22's configuration, and the agent's `prometheus` receiver scrape of `127.0.0.1:9100` with the darwin keep-list from `schema.nix` (ADR-003 items 21 to 23, Implementation surface).
- In that file's `ingress` role: the second OTLP receiver's endpoint built from `config.flake.lib.hosts.magnetite.zt`, the `routing` connector and per-database exporters, the `convert_exponential_histogram_to_histogram` transform, the promote-resource-attributes header generated from `schema.nix`, and the `otel-envelope` service and timer with `OnFailure=observability-notify@%n.service` (ADR-003 items 9 to 11 and 15, Implementation surface; `open-telemetry/opentelemetry-collector-contrib@aaf5045a2:processor/transformprocessor/README.md:475-479`).
- In the same flake module: the ADR-008 collector content stages, the absence of a logs pipeline on the local OTLP receiver, and the R8.2 ownership assertions for `otel-cert` (ADR-008 Implementation surface).
- The collector configuration builds its `redaction`, `filter`, `transform` and `resource` stages from `schema.nix` (ADR-004 Implementation surface).
- Add `modules/clan/services/otel-collector/schema.nix`, a flake-parts module defining `flake.lib.otelCollectorSchema`: the attribute allow-list, omp metric-name allow-list, per-signal `devloop` column allow-list with primary keys and time indexes, never-stored list, journald, systemd and launchd allow-lists, the Omnigent owner-to-alias attrset `ownerAliases = { cameron = "owner-1"; janettesmith = "owner-2"; }`, the exporter keep-lists, the enabled `paging` and memory scraper metrics, the label bans, the signal-to-database map, and the R4.2 budget numbers (ADR-004 Implementation surface; ADR-003 item 17).
- Add `modules/clan/inventory/services/otel-collector.nix`: one instance, `agent` on cinnabar, electrum, galena, scheelite, magnetite, pyrite and stibnite, `ingress` on magnetite, and `smartDevices` on pyrite and stibnite (ADR-003 Implementation surface).
- Add `modules/checks/otel-collector-config.nix`: regulator R3.1 with its recorded `launchctl print` fixtures (ADR-003).
- Add `modules/checks/otel-redaction.nix`: regulator R8.1 with the R4.1 fixtures, reading `schema.nix` (ADR-004; ADR-008).
- Add the R4.2 and R8.3 queries to `otel-envelope` (ADR-004; ADR-008).
- Modify `modules/nixos/nixbot.nix`: a loopback-only nginx server on `127.0.0.1:9180` proxying `/metrics` to the nixbot socket (ADR-003 Implementation surface).
- Modify `modules/clan/inventory/services/zerotier.nix` or the zerotier NixOS configuration it applies: `services.zerotierone.localConf.settings.enableMetrics = true` (ADR-003 Implementation surface); S1 sets it in the `agent` role's NixOS module.
- Modify `modules/lib/omnigent-environment.nix` to add `OTEL_` to the reserved worker-environment prefixes, and `modules/checks/omnigent-environment.nix` to add an `OTEL_` policy mutant (ADR-008 Q4).
- Flake inputs: none added; `opentelemetry-collector-contrib` comes from the root `nixpkgs` input (ADR-003 Implementation surface).
- Clan vars generator `otel-ca`: `share = true`, `files."ca.key".deploy = false`, `files."ca.crt".secret = false`, openssl P-256 self-signed CA, after `nix-grpc-ca` (`cameronraysmith/vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:106-120`).
- Clan vars generator `otel-cert`: per machine, depends on `otel-ca`, CN the machine name, `extendedKeyUsage=clientAuth` on agents and additionally `serverAuth` with `flake.lib.hosts.magnetite.zt` as IP SAN and `magnetite.zt` as DNS SAN on magnetite (ADR-003 Implementation surface).
- Consumed, not created here: `greptimedb-users` (ADR-007) and `ntfy-alerter` (ADR-009).

## Operating envelope and regulator

Envelopes (ADR-003):

- Agent on a non-ingress host: `memory_limiter` at 150 MiB with a 30 MiB spike allowance; on NixOS additionally `MemoryMax = 256M`; on darwin the internal limiter is the only bound.
- Darwin `otelcol-process`: `memory_limiter` at 64 MiB with a 16 MiB spike allowance; launchd bounds none of its memory.
- Ingress on magnetite: `memory_limiter` at 384 MiB, `MemoryMax = 512M` and `OOMScoreAdjust = 300`, so under host memory exhaustion the kernel selects the evaluator at 900 first, then the store at 500, then the ingress, ahead of nix-daemon workers at 250 and PostgreSQL and every other service at 0 or lower.
- Buffering: each agent's `file_storage` queue absorbs at least 24 h of that host's output and stays below 512 MiB on disk.
  On magnetite the three ingress exporters share one `file_storage` directory with `sizer: bytes` queues of 400 MiB for `fleet` and 48 MiB each for `devloop` and `agent`; R3.1 asserts that their sum is below 512 MiB and that the `fleet` queue holds 24 h at an assumed, unmeasured 256,000 bytes per minute, which S1's deployment measures.
- Freshness: every in-scope host that is online delivers host metrics to the store within 5 min of collection.
- Exposure: no collector listener binds outside loopback except the ingress receiver on magnetite's ZeroTier address, and no exporter binds outside loopback.
- Host signals per NixOS host: at most 30 per-process series, at most 40 allow-listed units at nine series each, 16 node_exporter series, 2 paging series per swap device, and on pyrite 10 smartctl series.
- Host signals per darwin host: at most 30 per-process series, at most 30 allow-listed launchd jobs at six series each, 8 SMART series per device, 3 textfile metadata series and 1 `up` series.

Envelopes (ADR-004, ADR-008):

- The ADR-004 budget table: `fleet` at most 8,000 active series and at most 200 distinct values per label key per metric, except `process_executable_name` at 30 values per agent host and `systemd_unit_name` at 40 values per NixOS agent host; `agent` at most 2,000 active series; journald at most 100 MB per host per day, provisional; `devloop` at most 100,000 rows per day.
- Every stored attribute key is on ADR-004's allow-list, no stored log record originates from OTLP or from a unit outside the unit allow-list, and no store credential file is readable by a worker UID (ADR-008).

Regulators:

- R3.1, deterministic, build time: `checks.x86_64-linux.otel-collector-config` asserts with the cognee predicate that every receiver endpoint is loopback or ZeroTier-prefixed, and asserts the scrape-target, exporter, ingress, unit-cap, darwin node_exporter, `otelcol-process`, probe-label and darwin scraper clauses of ADR-003 R3.1 (`cameronraysmith/vanixiets@109c67346:modules/nixos/cognee.nix:26-27`); the agent module asserts the six process identity attributes off and node_exporter's `openFirewall = false` (charter v16).
- The NixOS module's own `otelcol validate` validates NixOS hosts' configurations when they build, and from S5 the check validates darwin agents' (ADR-003 R3.1).
- R3.2, runtime: `otel-envelope` on magnetite queries the store every 5 min as `regulator` for per-host last-seen time of host metrics, `up` of every declared exporter target on each online host, `otelcol_exporter_queue_size`, `otelcol_exporter_send_failed_*` and `memory_limiter` refusal counters, and fails on any breach; last-seen time fails only for always-on hosts, currently cinnabar and magnetite (ADR-003).
- R4.1, deterministic, build time: R8.1's check also feeds ADR-004's banned-label, unknown-key, `omp.agent.*.count`, `omnigent-host-cameron` journald, process-identity, unit-name, launchd-label, `/Volumes/` mountpoint and `serial_number` fixtures, and fails evaluation when an enabled Omnigent worker has no entry in the owner-to-alias attrset (ADR-004).
- R4.2, runtime: `otel-envelope` also queries active series, maximum distinct label values per metric, per-host distinct values of `process_executable_name`, `systemd_unit_name` and `launchd_label`, rows ingested in 24 h, journald bytes per host, and each database's and the fleet logs table's `ttl`, and fails on any breach (ADR-004).
- R8.1, deterministic, build time: `checks.x86_64-linux.otel-redaction` runs each agent's processor stages between an `otlpjsonfile` receiver and a `file` exporter over canary fixtures and asserts the canary is absent, the positive controls are present, and no logs pipeline consumes the local OTLP receiver (ADR-008).
- R8.2, deterministic, evaluation time: every `greptimedb-users` and `otel-cert` file is owned by a non-worker account with mode `0400`, the store's HTTP bind is loopback, and the omnigent-environment oracle rejects an `OTEL_` name (ADR-008).
- R8.3, runtime: `otel-envelope` lists every table's columns from `information_schema.columns` and fails on any `agent`, `devloop` or `fleet` log-table column outside its ADR-004 allow-list (ADR-008).
- Failure notification: `otel-envelope` sets `OnFailure=observability-notify@%n.service`, which posts once per failure episode and once on recovery to `fleet-alerts` (ADR-003 Q9; ADR-009 item 11).
- The `regulator` (`ro`) user is held by `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope` and `fleet-alert.service` (ADR-007; ADR-008; ADR-009 item 1).

## Failure prevented

- Per-host agent: telemetry from intermittent and darwin hosts that no pull reaches is lost, and content leaves the host before redaction (ADR-003).
- Ingress role on magnetite's agent: a store password on every host, and a mesh-reachable store listener that unmanaged mesh members can probe (ADR-003).
- mTLS with `otel-ca`: an unmanaged mesh member or a host outside the fleet writes into the store (ADR-003).
- Separate CA: a telemetry key becomes a trusted remote-build credential on the builders (ADR-003).
- Loopback-only local receiver with no logs pipeline: a worker's ungated OTLP log records reach the store (ADR-003; ADR-008).
- `file_storage` queue: data is lost while magnetite is down or OOM-killed, or while a laptop is offline (ADR-003).
- `memory_limiter`, `MemoryMax` and `OOMScoreAdjust`: the collector contributes to a magnetite OOM, dies before the store and so stops queueing, or survives ahead of PostgreSQL (ADR-003).
- Exponential-histogram transform: histogram data is silently discarded by GreptimeDB below 1.3.0 (ADR-003).
- Explicit `enableMetrics`: an upgrade past zerotierone 1.16.0 silently removes the mesh-health signal (ADR-003).
- Loopback nginx block for nixbot: nixbot's metrics have no scrape path (ADR-003).
- Process identity attributes disabled at the source: a command line carrying a secret or prompt content reaches the store (ADR-003).
- Alias rewrite of `omnigent-host-<owner>` units: a person's name becomes a metric label value (ADR-003; ADR-004).
- Root `otelcol-process`: the darwin process scraper silently records 0 bytes for every process it may not inspect (ADR-003).
- `zt_peer_.*` drop: per-peer series grow with every peer the node contacts (ADR-003).
- Promote header: GreptimeDB drops `host.name`, so every host's series merge into one (ADR-003).
- Collector content stages and the journald unit filter: prompt, tool or repository content reaches a store every admitted reader can query (ADR-008).
- Reserved `OTEL_` prefix: a role setting enables an emitter content gate fleet-wide (ADR-008).
- R3.1: a configuration that does not parse or that binds publicly ships to a host, including a darwin host whose check is non-gating (ADR-003).
- R3.2 and the notifier: a host silently stops delivering, queues grow until data is dropped, or an observability regulator or oneshot fails with nobody told (ADR-003).
- R4.1 and R4.2: a banned label or content key ships, or an emitter upgrade introduces an unbounded label or a TTL drifts (ADR-004).
- R8.1, R8.2 and R8.3: content ships through configuration, a credential becomes worker-readable, or content reaches the store through an unmodelled path (ADR-008).

## Deployment acceptance items

- R3.1 fails on each of three mutants, a receiver endpoint of `0.0.0.0:4318`, an exporter `listenAddress` of `0.0.0.0` and a darwin node_exporter `listenAddress` of the empty string, and the agent's assertion fails with `process.command_line` enabled (ADR-003).
- R3.2 fails within 10 min after one online host's agent is stopped (ADR-003).
- The stopped-agent test produces a ntfy message naming `otel-envelope.service` (ADR-003 failure notification).
- R4.1 fails when the label-ban stage is deleted from the generated configuration (ADR-004).
- R4.2 fails after one synthetic metric with 300 distinct values of one label is pushed into `fleet` (ADR-004).
- R8.1 fails with the canary in the output under `allow_all_keys: true` and under removal of the journald unit filter (ADR-008).
- R8.2 fails under a mutant that sets a worker as owner of `collector-password` (ADR-008).
- R8.3 fails after one span with a disallowed attribute is written through an administrative credential (ADR-008).
- `magnetite.zt` resolves through cinnabar's dnsmasq, and agents queue while resolution fails (ADR-003 Consequences).
- On darwin the process scraper reads each process's argument vector into collector memory before the disabled attributes discard it (ADR-003 Consequences).

## Deferred

- blackphos, rosegold and argentum run no agent until each primary user consents (ADR-003 Q3).
- nix-grpc-daemon metrics are not collected; its `metricsListen` stays off and its idle exit stays on (ADR-003 Q6).
- macOS unified logging through the alpha `macos_unified_logging` receiver is not collected in this decision (ADR-003 Q7).
- Collector versions advance only through root-pin bumps against upstream 0.163.0 (ADR-003 Q8).
- Per-unit cgroup memory is revisited when the pin reaches `v0.160.0` (ADR-003 Q11).
- The `convert_exponential_histogram_to_histogram` transform applies only while the store is below 1.3.0 (ADR-003 item 11; ADR-001).
- No omnigent worker account receives an OTLP endpoint or credential in this slice; enabling worker telemetry requires revising ADR-008 (ADR-008 Q3; ADR-004 Q5).
- Omnigent telemetry enters `agent` under the same allow-list only after its package carries the `tracing` extra (ADR-004).
- Continuous profiling and per-host ZeroTier peer latency and path state would change this component's agents; both are ADR-003 future extensions (5) and (7), recorded with their triggers in `components/host-probes.md`.
