---
title: "ADR-003: Collection topology"
---

## Status

Proposed

## Context

Charter D3 asks for one collection topology: per-host agent versus central gateway, what a nix-darwin host can run, ZeroTier-only versus public ingress, and transport authentication.

The fleet is ten machines: six NixOS (cinnabar, electrum, galena, scheelite, magnetite, pyrite) and four darwin (blackphos, stibnite, rosegold, argentum) (`cameronraysmith/vanixiets@109c67346:modules/clan/inventory/machines.nix`).
Five of the ten are intermittent, and the darwin four have no `deploy.targetHost`, so a pull-only gateway misses them (`research/otel-collector-topology.md` F4, F5).
Three of the darwin machines are other people's primary laptops (`research/otel-collector-topology.md` Questions).

All three candidate agents are in the root pin (`nixpkgs_10` at `ac1faec44836`): `opentelemetry-collector-contrib` 0.155.0, `grafana-alloy` 1.17.1 and `vector` 0.59.0, and all three have `aarch64-darwin` outputs on cache.nixos.org (`research/otel-collector-topology.md` R2, R4).
nix-darwin has no module for any of them, so every candidate needs a first-party `launchd.daemons` unit (`research/otel-collector-topology.md` R5, R6).
On stibnite, a contrib `host_metrics` pipeline measured a peak memory footprint of 88 MB and 392 data points per scrape (`research/otel-collector-topology.md` R10).
launchd cannot enforce a process-tree memory ceiling, so a darwin collector's memory bound must be internal to the process (`research/otel-collector-topology.md` F12, F15).

GreptimeDB serves OTLP only over HTTP at `/v1/otlp/v1/<signal>`, protobuf only, with no OTLP gRPC trace or logs service in any release (`research/greptimedb.md` R4, R5, C2).
No released GreptimeDB accepts bearer tokens; the usable credential is HTTP Basic (`research/otel-collector-topology.md` C1).
GreptimeDB has no server-side client-certificate verification, so mTLS can terminate only in front of it (`research/otel-collector-topology.md` F27, F28; `research/greptimedb.md` R30).
GreptimeDB 1.1.4 and 1.2.1 silently discard OTLP exponential histograms (`research/greptimedb.md` R7).
The open build authenticates but authorizes nothing beyond a per-user `rw`/`ro`/`wo` mode (`research/telemetry-security-and-tenancy.md` R1, R2).

The mesh is one flat trust zone and now includes two unmanaged Android members (`research/otel-collector-topology.md` R18; `research/telemetry-security-and-tenancy.md` F34).
A fleet mTLS CA already exists as the `nix-grpc-ca` clan var, issuing each `nix-builders` member a certificate whose CN is the machine name (`research/otel-collector-topology.md` R20).
nix-grpc-daemon grants the `trusted` role, which is store-root-equivalent on the builder, to any certificate from that CA whose CN names a dispatcher (`cameronraysmith/vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:160-175`).
magnetite has been OOM-killed twice by evaluation overlap (`research/otel-collector-topology.md` R21).

Existing scrape targets on magnetite: gitea at `127.0.0.1:3002/metrics`, niks3 at `127.0.0.1:5752/metrics`, nixbot only through `/run/nixbot/web.sock` behind nginx (`research/fleet-emitter-inventory.md` updated emitter table).
Their public `/metrics` locations now admit only loopback and the ZeroTier /64 (`cameronraysmith/vanixiets@02432c594:modules/lib/nginx-metrics-location.nix`).
nginx `stub_status` is served at `http://127.0.0.1/nginx_status` (`research/fleet-emitter-inventory.md` R14).
zerotierone 1.16.0 serves `localhost:9993/metrics` behind a bearer token in `metricstoken.secret`, and from 1.16.1 metrics default to off unless `allowMetrics` is set (`research/fleet-emitter-inventory.md` R13).
nix-grpc-daemon metrics are off by default, and on magnetite and pyrite the daemon idle-exits after 600 s, resetting its counters (`research/fleet-emitter-inventory.md` R4).

Host-level signals each answer a failure this fleet has had: magnetite's host-wide OOM kills of 2026-09-27 and 2026-10-01 left no record of which process grew, two `omnigent-host-*` units on magnetite restart-looped about 3,200 times overnight on 2026-10-15 unnoticed, and magnetite has a storage-exhaustion history (charter W2).
The `host_metrics` `process` scraper at 0.155.0 selects processes only by `include` and `exclude` name filters with `strict` or `regexp` matching, and has no top-N option (`open-telemetry/opentelemetry-collector-contrib@795558312:receiver/hostmetricsreceiver/internal/scraper/processscraper/config.go:20-21`, `:58-62`).
It emits one resource per process carrying `process.pid`, `process.parent_pid`, `process.command`, `process.command_line`, `process.executable.path` and `process.owner` by default, each of which can be disabled (`open-telemetry/opentelemetry-collector-contrib@795558312:receiver/hostmetricsreceiver/internal/scraper/processscraper/metadata.yaml:18-57`).
It runs on Linux, Windows, macOS and FreeBSD (`open-telemetry/opentelemetry-collector-contrib@795558312:receiver/hostmetricsreceiver/README.md:60`).
The contrib `systemd` receiver is alpha for metrics, unsupported on darwin, selects units by a `units` pattern list, and at 0.155.0 emits `systemd.unit.state` once per active state, `systemd.service.cpu.time`, and `systemd.service.restarts` from the `NRestarts` property, the last disabled by default (`open-telemetry/opentelemetry-collector-contrib@795558312:receiver/systemdreceiver/metadata.yaml:9`, `:14`, `:44`, `:55-69`; `open-telemetry/opentelemetry-collector-contrib@795558312:receiver/systemdreceiver/README.md:36-39`).
Per-unit cgroup memory, `systemd.service.memory.usage`, first appears in that receiver at tag `v0.160.0` and is absent from `v0.155.0` through `v0.159.0` (local tag inspection of `open-telemetry/opentelemetry-collector-contrib`, 2026-10-15).
contrib has no ZFS or SMART receiver, so those signals need a Prometheus exporter scraped by the `prometheus` receiver.
The root pin packages `prometheus-node-exporter` 1.12.1, `prometheus-zfs-exporter` 2.4.1 and `prometheus-smartctl-exporter` 0.14.0 with `services.prometheus.exporters` NixOS modules whose `listenAddress` defaults to `0.0.0.0` (`NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/prometheus/exporters.nix:209-211`).
node_exporter's `zfs` collector reads `/proc/spl/kstat/zfs` and emits ARC statistics, per-dataset objset series and `node_zfs_zpool_state{zpool,state}`, and its `vmstat` collector exposes the kernel's `oom_kill` count (`prometheus/node_exporter@6044da783:collector/zfs_linux.go:62-70`, `:401-423`; `prometheus/node_exporter@6044da783:collector/vmstat_linux.go:36`, `:45`).
zfs_exporter reports pool health, size, allocation, free space and fragmentation by running `zpool`, reports no ARC statistics, and enables per-dataset collectors by default (`pdf/zfs_exporter@50f93a806:collector/pool.go:10-12`; `pdf/zfs_exporter@50f93a806:collector/dataset.go:201-203`).
smartctl_exporter exports per-`device` `smart_status`, `critical_warning`, `media_errors`, `percentage_used` and `available_spare`, plus a `smartctl_device` info series labelled with `serial_number` (`prometheus-community/smartctl_exporter@ef5c03de0:metrics.go:33-52`, `:150-182`, `:214`), and its NixOS module grants `CAP_SYS_RAWIO` and `CAP_SYS_ADMIN` (`NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/prometheus/exporters/smartctl.nix:52-61`).
Every NixOS machine has one ZFS pool, `zroot` (`cameronraysmith/vanixiets@a04fcf7c8:modules/machines/nixos/magnetite/disko.nix:35-36`, and the same block in each other NixOS machine's `disko.nix`).
magnetite and cinnabar are KVM guests whose disks are a virtual `QEMU HARDDISK`, and the other NixOS machines except pyrite use 512-byte cloud disks, so SMART data there describes emulation rather than media (orchestrator host inspection, 2026-10-15; `cameronraysmith/vanixiets@a04fcf7c8:modules/machines/nixos/pyrite/disko.nix:116-118`).
pyrite is bare metal with Apple NVMe namespaces `nvme0n1` and `nvme0n2` on the single controller `nvme0` (orchestrator host inspection, 2026-10-15).
stibnite is darwin with APFS, so it has no ZFS pool and no systemd.
zerotierone also emits per-peer `zt_peer_latency` histograms and `zt_peer_path_count`, `zt_peer_packets` and `zt_peer_packet_errors` labelled by peer `node_id` (`zerotier/ZeroTierOne@899352e38:node/Metrics.cpp:110-114`; `zerotier/ZeroTierOne@899352e38:node/Peer.cpp:52-54`).
GreptimeDB keeps as labels only a fixed list of resource attributes (`service.*`, `cloud.*`, `k8s.*`, `deployment.*`, `container.name`), which excludes `host.name`, unless the request header `x-greptime-otlp-metric-promote-resource-attrs` names more, `;`-separated (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/otlp/metrics.rs:60-80`, `:269-271`; `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http/extractor.rs:175-179`).
Its default metric-name translation, `UnderscoreEscapingWithSuffixes`, replaces dots with underscores and appends unit and `_total` suffixes (`GreptimeTeam/greptimedb@179ff8e50:src/session/src/protocol_ctx.rs:83`; `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/otlp/metrics/translator.rs:104-131`).

## Decision

Run `opentelemetry-collector-contrib` 0.155.0 from the root nixpkgs pin as one per-host agent on every in-scope host, and give magnetite's agent the additional ingress role as the only holder of a store credential.

1. Every in-scope host runs one agent: the NixOS `services.opentelemetry-collector` module with `package = pkgs.opentelemetry-collector-contrib`, and on darwin a first-party `launchd.daemons.otelcol` running as a dedicated `_otelcol` user, wrapped behind `/bin/wait4path /nix/store` and `KeepAlive`, after the `nix-builders` precedent (`research/otel-collector-topology.md` R6).
2. In scope initially: the six NixOS machines and stibnite; blackphos, rosegold and argentum join only after their primary users consent (Q3).
3. Each agent listens for local emitters on `127.0.0.1:4318` (OTLP/HTTP) only; that receiver is wired into the traces and metrics pipelines and into no logs pipeline, so OTLP log records are rejected (see ADR-008).
4. Each agent collects `host_metrics` at a 60 s interval; NixOS agents also read `journald` restricted to the unit allow-list of ADR-004, and every agent tails `/var/log/deploy-record.jsonl` with the `filelog` receiver for the deploy record of ADR-005.
5. Each NixOS agent scrapes zerotierone at `localhost:9993/metrics` with the token delivered by `LoadCredential`, and `allowMetrics = true` is set explicitly in zerotierone's `localConf` so an upgrade past 1.16.0 does not silently stop the emitter.
6. magnetite's agent also scrapes gitea at `127.0.0.1:3002`, niks3 at `127.0.0.1:5752`, nixbot through a new loopback-only nginx server on `127.0.0.1:9180` that proxies `/metrics` to `/run/nixbot/web.sock`, and nginx through the `nginx` receiver at `http://127.0.0.1/nginx_status`; it also hosts the on-host PostgreSQL reader of ADR-005.
7. Every agent applies the redaction stages of ADR-008 and the signal allow-list of ADR-004 before any exporter, stamps `host.name` and a routing attribute naming the target database, and exports with `otlp_http` to `https://magnetite.zt:4318` presenting a client certificate.
8. Every agent's exporter uses a `sending_queue` backed by the `file_storage` extension, and every pipeline begins with `memory_limiter`.
9. magnetite's agent carries the ingress role: a second OTLP/HTTP receiver bound to magnetite's ZeroTier address on port 4318, opened on `zt+` only, requiring client certificates from the `otel-ca` CA through `tls.client_ca_file` (`open-telemetry/opentelemetry-collector@41da2fbd7:config/configtls/README.md:147`).
10. The ingress routes by the database attribute with the `routing` connector to one `otlp_http` exporter per GreptimeDB database, each with endpoint `http://127.0.0.1:4000/v1/otlp`, the header `x-greptime-db-name`, and the `basicauth` extension's `client_auth` reading the `collector` password, a write-only (`wo`) store user (`research/greptimedb.md` R26, R27; ADR-007).
11. The ingress metrics pipeline applies the `transform` function `convert_exponential_histogram_to_histogram` while the store is below 1.3.0 (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:processor/transformprocessor/README.md:475-479`; ADR-001).
12. Agent-to-ingress authentication uses a new clan-vars CA, `otel-ca`, and per-machine `otel-cert`, not `nix-grpc-ca`.
13. Transport is ZeroTier only; no public ingress exists, and nothing except magnetite's ingress listens beyond loopback.
14. nix-grpc-daemon metrics and macOS unified logging are not collected in this decision (Q6, Q7).
15. Every ingress `otlp_http` exporter sends `x-greptime-otlp-metric-promote-resource-attrs` listing every resource key of ADR-004's allow-list that GreptimeDB does not promote by default, so `host.name`, `systemd.unit.name` and `process.executable.name` survive as the labels `host_name`, `systemd_unit_name` and `process_executable_name`.
16. Per-process memory, NixOS agents only: a second `host_metrics` receiver runs the `process` scraper at 60 s over all processes with `process.pid`, `process.parent_pid`, `process.command`, `process.command_line`, `process.executable.path` and `process.owner` disabled at the source, so the only resource attribute left is `process.executable.name`, and only `process.memory.usage` enabled.
    Its pipeline merges same-named processes with `groupbyattrs` compaction and a `metricstransform` `aggregate_labels` sum (`open-telemetry/opentelemetry-collector-contrib@795558312:processor/groupbyattrsprocessor/README.md:27`; `open-telemetry/opentelemetry-collector-contrib@795558312:processor/metricstransformprocessor/README.md:107-110`), then a `filter` drops every summed point below 64 MiB, so a series exists only for an executable that holds real memory.
17. systemd unit state, NixOS agents only: the `systemd` receiver at 60 s with `scope: system`, `units` set to ADR-004's systemd unit allow-list, `systemd.service.restarts` enabled and `systemd.service.cpu.time` disabled.
    A `transform` stage rewrites each `omnigent-host-<owner>.service` unit name to `omnigent-host-<alias>.service`, where `<alias>` comes from an explicit owner-to-alias attrset in ADR-004's `schema.nix`, so adding or removing an owner never renames another owner's series (Q12).
18. Storage and OOM, NixOS agents only: `services.prometheus.exporters.node` on `127.0.0.1:9100` with `--collector.disable-defaults --collector.zfs --collector.vmstat --collector.vmstat.fields=^oom_kill$`, scraped by the agent's `prometheus` receiver at 60 s with a `metric_relabel_configs` keep-list of ADR-004's node_exporter metric names; the agent also enables `system.linux.memory.available` in the memory scraper.
19. Disk health, pyrite only: `services.prometheus.exporters.smartctl` on `127.0.0.1:9633` with `devices = [ "/dev/nvme0" ]`, scraped at 60 s with a keep-list of ADR-004's smartctl metric names that excludes the `smartctl_device` info series; the KVM and cloud guests run no SMART exporter because their disks are emulated.
20. Both exporters set `listenAddress = "127.0.0.1"` and `openFirewall = false`, and the agent's scrape configuration names only `127.0.0.1` targets; the existing zerotierone scrape gains a `metric_relabel_configs` drop of `zt_peer_.*`.
21. stibnite's agent collects none of items 16 to 19: the `process` scraper runs on macOS but stibnite is a personal workstation whose process names are an application-usage record (Q10), the `systemd` receiver does not run on darwin, APFS has no ZFS pool state, and SMART on its internal SSD prevents no failure this fleet has had.

### Future extensions (not adopted)

These were considered on 2026-10-15 and are not part of this decision; each names the trigger that would justify adopting it and what adopting it requires.

(5) Continuous profiling.
Trigger: a magnetite memory or CPU incident in which `process_memory_usage_bytes` names the executable but not the code path, for example `nix-eval-jobs` growth that per-attribute `eval_alloc_bytes` (ADR-005) does not localize.
The OpenTelemetry eBPF profiler is Linux-only, implements the alpha OTel Profiles signal, and ships as a collector receiver in the separate `otelcol-ebpf-profiler` distribution rather than in `otelcol-contrib` (`open-telemetry/opentelemetry-ebpf-profiler@3f72c9a34:README.md:3`, `:8`, `:47-48`).
No profiling receiver is in the contrib 0.155.0 build manifest (`open-telemetry/opentelemetry-collector-contrib@795558312:cmd/otelcontribcol/builder-config.yaml`), and the root pin packages no eBPF profiler, only `parca-agent` and `pyroscope`.
GreptimeDB's OTLP router at `main` registers only `/v1/metrics`, `/v1/traces` and `/v1/logs`, so it does not ingest the profiles signal (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http.rs:1536-1538`).
Adopting it requires a profiles-capable store or a second backend such as Pyroscope or Parca, a packaged profiler distribution, a privileged eBPF unit on each profiled host, and a decision on whether stack symbols from agent workers are content under ADR-008.

(6) Laptop battery, thermal and sleep-wake state on stibnite and pyrite.
Trigger: an incident in which a laptop's thermal throttling, battery wear or sleep-wake cycle explains lost builds, stale deploy records, or queue replay gaps that host metrics do not explain.
No receiver metadata in contrib 0.155.0 mentions battery or thermal state (local search of `receiver/*/metadata.yaml` at `open-telemetry/opentelemetry-collector-contrib@795558312`), whereas node_exporter 1.12.1 has `powersupplyclass` collectors for Linux and darwin, `hwmon` and `thermal_zone` for Linux, and `thermal` for darwin (`prometheus/node_exporter@6044da783:collector/powersupplyclass_linux.go`, `:collector/powersupplyclass_darwin.go`, `:collector/hwmon_linux.go`, `:collector/thermal_darwin.go`).
Adopting it requires adding those collectors to item 18's loopback node_exporter on pyrite, a first-party launchd unit for a loopback node_exporter on stibnite, a source for sleep-wake events such as `pmset -g log` that no listed collector reads, and consent framing, because sleep-wake times are a personal-activity record.

(7) Per-host ZeroTier peer latency and path state.
Trigger: a cross-host failure, such as remote-build dispatch or agent-to-ingress export, attributed to mesh path degradation, relay fallback, or peer flapping.
zerotierone already emits it (`zerotier/ZeroTierOne@899352e38:node/Metrics.cpp:110-114`), and item 20 drops it because `node_id` takes one value per peer, including roots and transient peers, and each `zt_peer_latency` histogram is 13 series per peer.
Adopting it requires a keep-list restricting `node_id` to the fleet's member ids from the ZeroTier inventory, keeping only `zt_peer_path_count` and the latency histogram, and an ADR-004 budget increase computed per host from the member count.

## Rationale

Per-host agents are required, because a gateway cannot pull from five intermittent hosts or push-unreachable darwin machines, and because redaction must run on the emitting host under a system account no worker controls (`research/telemetry-security-and-tenancy.md` refresh, Bearing on D8 and D3).
Direct export from every agent to the store would put a store password on every host, including laptops belonging to other people, against a store that cannot authorize per database (`research/otel-collector-topology.md` reconciliation).
Making magnetite's own agent the ingress gives one store credential, on the host that already runs the store, without a second collector process or a second host in the delivery path.
The store then binds loopback only, so its query surface is never on the mesh for ingest purposes, which matches ADR-007.
mTLS at the ingress is the authentication that composes in clan vars: the ingress needs only the public CA certificate, whereas per-host Basic credentials would require aggregating every machine's secret into one htpasswd file on magnetite.
A separate CA is required because a certificate from `nix-grpc-ca` with CN equal to a dispatcher's machine name is a trusted remote-build credential, so a collector-readable copy of such a key would widen who holds store-root-equivalent build authority.
`otelcol-contrib` is chosen over vector and grafana-alloy because it alone carries `redaction`, `transform` with the exponential-histogram conversion, `basicauth`, `file_storage`, `journald`, `filelog` and `sqlquery` in one binary, and because the NixOS module validates generated configuration with `otelcol validate` by default (`research/otel-collector-topology.md` R7, C7).
The contrib distribution, not the core default, is required for `basicauth`, `file_storage`, `journald` and `redaction` (`research/otel-collector-topology.md` C7).
ZeroTier-only transport reuses the existing `zt+` firewall idiom and the cognee no-public-bind predicate, whereas the only public ingress shape, `sso-gateway`, is redirect-based and disabled (`research/otel-collector-topology.md` F18, F21; `research/telemetry-security-and-tenancy.md` F18).
The 88 MB measured footprint is not disqualifying for a darwin agent (`research/otel-collector-topology.md` R10).
Summing process memory per executable name and dropping points below 64 MiB answers which process grew without naming processes in advance: an include-list misses an unexpected grower, the pinned scraper has no top-N, and per-unit cgroup memory needs a collector at or above `v0.160.0`.
Process identity attributes are disabled at the source rather than redacted downstream, because command lines can carry secrets and prompt content and a disabled attribute never enters collector memory.
The systemd receiver is limited to an allow-list because `systemd.unit.state` costs eight series per unit, so every unit on every host would dominate the fleet budget, whereas the allow-list covers the units with an incident or a regulator role.
The loopback exporters are not the rejected node_exporter alternative: that alternative made node_exporter the fleet-wide agent behind remote pull from a central scraper, whereas here the exporter binds `127.0.0.1`, runs only the collectors named, and is read by the local agent, which still buffers and pushes, so an intermittent host loses nothing and no new mesh listener or transport exists.
node_exporter's `zfs` collector is chosen over zfs_exporter because it reports ARC size, which competes for memory on the host that OOMs, and the `oom_kill` count from the same process, by reading kstat files rather than spawning `zpool` on every scrape.
Pool free space already arrives through `system.filesystem.usage`, because on ZFS a dataset's available space is the pool's free space less any quota or reservation, so the root dataset's mount reports it; magnetite's `zroot/root/nix` mount instead reports its 250G quota headroom (`cameronraysmith/vanixiets@a04fcf7c8:modules/machines/nixos/magnetite/default.nix:239`).
SMART is collected only on pyrite because it is the only NixOS machine whose disk is physical.

## Rejected alternatives

- Central gateway only, scraping hosts: misses intermittent and push-unreachable darwin hosts and cannot redact before data leaves the host.
- Direct export from every agent to the store: a store password on up to ten hosts against a store that authorizes nothing per database.
- Separate gateway collector on cinnabar: adds a hop and makes cinnabar a precondition for ingest while the store on magnetite remains the single point anyway.
- Separate gateway process on magnetite beside the agent: a second unit on a memory-constrained host with no failure prevented that the agent's ingress role does not already prevent.
- `grafana-alloy` 1.17.1: Loki-shaped journald path, no build-time config validation in its NixOS module, and a second configuration language for the same OTel components.
- `vector` 0.59.0: no GreptimeDB trace sink, no macOS log source, no exponential-histogram conversion, and no fail-closed attribute allow-list primitive equivalent to `redaction`.
- Core `otelcol` distribution: lacks `basicauth`, `file_storage`, `journald` and `redaction`.
- Public OTLP ingress: no off-mesh emitter is in scope and the existing public gateway cannot serve OTLP clients.
- Bearer-token authentication to the store: no released GreptimeDB accepts it.
- HTTP Basic from agents to the ingress: needs every machine's secret aggregated on magnetite.
- Reusing `nix-grpc-ca` for telemetry: a dispatcher-CN certificate from that CA is a trusted build credential.
- Prometheus `node_exporter` plus pull scraping: pull fails on intermittent hosts and adds a second agent per host; the loopback exporters of items 18 and 19 are a different shape (see Rationale).
- zfs_exporter for ZFS: no ARC statistics, a `zpool` subprocess on every scrape, and per-dataset series enabled by default.
- Include-list of process names: misses the process that grows unexpectedly, which is the case the OOM kills left unexplained.
- Per-unit cgroup memory from the `systemd` receiver: absent at the pinned 0.155.0 (Q11).
- All systemd units: eight series per unit across every unit on six hosts exceeds the fleet budget (Q13).
- SMART on the KVM and cloud guests: their disks are emulated, so the data describes no media.
- OTLP gRPC export: GreptimeDB serves no OTLP gRPC traces or logs.

## Consequences

Every in-scope host gains one long-running collector, and darwin hosts gain a first-party launchd unit and a dedicated user.
magnetite's collector becomes a dependency of all ingest; while magnetite is down, agents buffer to disk and replay.
Agents on other hosts never hold a store credential; a compromised host can write telemetry as any host through the ingress, because the ingress does not bind certificate CN to the stamped `host.name`.
Local emitters on a host reach the agent over unauthenticated loopback, so any local UID can inject telemetry attributed to that host, and person attribution is emitter-claimed rather than enforced (see ADR-008).
The Android mesh members cannot write, because they hold no `otel-ca` certificate.
The `.zt` name `magnetite.zt` depends on cinnabar's dnsmasq (`research/otel-collector-topology.md` R19); agents queue while resolution fails.
nixbot's metrics need a new loopback nginx server block, which is a change to `modules/nixos/nixbot.nix`.
The darwin agent's configuration is check-bound only through nixbot's best-effort darwin checks (`research/otel-collector-topology.md` C5), so the configuration validation check below evaluates the darwin configuration text on `x86_64-linux` to make it gating.
The `routing` connector, `sqlquery`, `journald` and `redaction` for logs are alpha components (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:connector/routingconnector/metadata.yaml`, `:receiver/journaldreceiver/metadata.yaml:9`, `:processor/redactionprocessor/metadata.yaml:13-14`).
nixpkgs' collector lags upstream by eight minor releases (`research/otel-collector-topology.md` R3); this decision accepts the pinned 0.155.0 (Q8).
Every NixOS host gains a loopback `prometheus-node-exporter` unit, and pyrite gains a `prometheus-smartctl-exporter` unit holding `CAP_SYS_RAWIO` and `CAP_SYS_ADMIN`.
The `systemd` receiver is alpha and `systemd.service.restarts` is at development stability (`open-telemetry/opentelemetry-collector-contrib@795558312:receiver/systemdreceiver/metadata.yaml:9`, `:62`); it counts automatic restarts only, not `systemctl restart`.
Per-process series are bounded by the memory floor rather than by a count, so a host with many large executables can exceed the per-host envelope, which R4.2 of ADR-004 detects; summed resident memory double-counts shared pages.
A failing unit outside the systemd allow-list is not seen through the store.
No pool capacity or fragmentation series exists; pool free space is read from the root dataset's filesystem series.
Adding an Omnigent owner requires adding an alias to `schema.nix`, and ADR-004's R4.1 fails the build until it is added.
Whether pyrite's Apple NVMe controller answers smartctl's health log is unverified until acceptance (Q15).

## Operating envelope and regulator

Envelope, agent on a non-ingress host: `memory_limiter` at 150 MiB with a 30 MiB spike allowance; on NixOS additionally `MemoryMax = 256M`; on darwin the internal limiter is the only bound.
Envelope, ingress on magnetite: `memory_limiter` at 384 MiB, `MemoryMax = 512M`, and `OOMScoreAdjust = 300`.
Under host memory exhaustion the kernel selects the store (`OOMScoreAdjust = 500`, ADR-007) first and the ingress collector second, so the collector survives the store's death and queues, while still dying before PostgreSQL, nix-daemon and every other service at a score of 0 or lower.
Envelope, buffering: each agent's `file_storage` queue absorbs at least 24 h of that host's output and stays below 512 MiB on disk.
Envelope, freshness: every in-scope host that is online delivers host metrics to the store within 5 min of collection.
Envelope, exposure: no collector listener binds outside loopback except the ingress receiver on magnetite's ZeroTier address, and no exporter binds outside loopback.
Envelope, host signals per NixOS host: at most 30 per-process series, at most 30 allow-listed units at nine series each, 16 node_exporter series, and on pyrite 10 smartctl series, inside ADR-004's fleet budget.
Envelope, exporters: `prometheus-node-exporter` and `prometheus-smartctl-exporter` each run with `MemoryMax = 64M`.

Regulator R3.1, deterministic, build time: a flake check `checks.x86_64-linux.otel-collector-config` runs `otelcol-contrib validate` over the generated configuration of every agent, darwin included, and asserts with the cognee predicate (`cameronraysmith/vanixiets@109c67346:modules/nixos/cognee.nix:26-27`) that every receiver endpoint is loopback or ZeroTier-prefixed.
It also asserts that every `prometheus` receiver target is `127.0.0.1`, that both exporters set `listenAddress = "127.0.0.1"` and `openFirewall = false`, that the `process` scraper disables the six process identity attributes of item 16, and that the `systemd` receiver's `units` equal the allow-list in `schema.nix`.
It is shown able to fail by four mutants run at acceptance: an unknown component key, a receiver endpoint of `0.0.0.0:4318`, an exporter `listenAddress` of `0.0.0.0`, and `process.command_line` enabled.
The NixOS module's own `otelcol validate` remains in force for NixOS hosts (`research/otel-collector-topology.md` R7).

Regulator R3.2, runtime: a systemd timer `otel-envelope` on magnetite queries the store each 5 min, as the read-only `regulator` store user of ADR-007, for per-host last-seen time of host metrics, for `up` of every declared exporter target on each online host, and for the collectors' own `otelcol_exporter_queue_size`, `otelcol_exporter_send_failed_*` and `memory_limiter` refusal counters, and fails the unit when any declared bound is breached.
It is shown able to fail at acceptance by stopping one online host's agent and observing the unit fail within 10 min, and by stopping one host's `prometheus-node-exporter` and observing the same.

Failure notification, owned by this record for every regulator and oneshot unit of the observability decisions: `otel-envelope` (this record), `devloop-reconcile` (ADR-005), and `greptimedb-envelope`, `greptimedb-export` and `greptimedb-schema` (ADR-007) each set `OnFailure=` to a shared notifier unit `observability-notify@%n.service` that posts the failed unit's name and host to the existing ntfy on cinnabar (Q9).
ADR-009 defines the notifier's delivery topic, authentication and deduplication.
The notifier is the only path from a failed regulator to a human; the unit-state series of item 17 are written to the store, and alerting over them belongs to ADR-009.
It is shown able to fail at acceptance by the R3.2 stopped-agent test producing a ntfy message naming `otel-envelope.service`.

## Failure prevented

- Per-host agent: telemetry from intermittent and darwin hosts that no pull reaches is lost, and content leaves the host before redaction.
- Ingress role on magnetite's agent: a store password on every host, and a mesh-reachable store listener that unmanaged mesh members can probe.
- mTLS with `otel-ca`: an unmanaged mesh member or a host outside the fleet writes into the store.
- Separate CA: a telemetry key becomes a trusted remote-build credential on the builders.
- Loopback-only local receiver with no logs pipeline: a worker's ungated OTLP log records reach the store.
- `file_storage` queue: data is lost while magnetite is down or OOM-killed, or while a laptop is offline.
- `memory_limiter`, `MemoryMax` and `OOMScoreAdjust`: the collector contributes to a magnetite OOM, dies before the store and so stops queueing, or survives ahead of PostgreSQL (`research/otel-collector-topology.md` R21).
- Exponential-histogram transform: histogram data is silently discarded by GreptimeDB below 1.3.0.
- Explicit `allowMetrics`: an upgrade past zerotierone 1.16.0 silently removes the mesh-health signal.
- Loopback nginx block for nixbot: nixbot's metrics have no scrape path, because its public location denies magnetite's public address.
- R3.1: a configuration that does not parse or that binds publicly ships to a host, including a darwin host whose check is non-gating.
- R3.2 and the notifier: a host silently stops delivering, queues grow until data is dropped, or any observability regulator or oneshot fails, with nobody told.
- Per-process memory with a floor: the next magnetite OOM again leaves no record of which executable grew.
- Process identity attributes disabled at the source: a command line carrying a secret or prompt content reaches collector memory or the store.
- systemd unit state and restart counts: a unit restart-loops thousands of times overnight unnoticed, as two `omnigent-host-*` units did on 2026-10-15.
- Alias rewrite of `omnigent-host-<owner>` units: a person's name becomes a metric label value.
- node_exporter `zfs` and `vmstat`: a degraded or suspended pool, ARC pressure, or an OOM kill is visible only on the host's console or kernel log, which is not collected.
- smartctl on pyrite: wear or media errors on the fleet's only physical disk go unseen until the pool degrades.
- Loopback-only exporters: a new unauthenticated metrics listener appears on the mesh.
- `zt_peer_.*` drop: per-peer series grow with every peer the node contacts.
- Promote header: GreptimeDB drops `host.name`, so every host's series merge into one.

## Implementation surface

- Add `modules/clan/services/otel-collector/flake-module.nix`: clan service `otel-collector` with roles `agent` and `ingress`, a `nixosModule` and a `darwinModule` per role, the `zt+` firewall opening for 4318 on the ingress, and the generators below (shape per ADR-007).
- Add `modules/clan/inventory/services/otel-collector.nix`: one instance, `agent` on cinnabar, electrum, galena, scheelite, magnetite, pyrite and stibnite, `ingress` on magnetite, and the `agent` role setting `smartDevices = [ "/dev/nvme0" ]` on pyrite.
- In the `agent` role's NixOS module: the `process` and `systemd` receivers, the alias `transform`, the `groupbyattrs`, `metricstransform` and `filter` stages of item 16, `services.prometheus.exporters.node` per item 18, `services.prometheus.exporters.smartctl` when the role option `smartDevices` (default `[ ]`) is non-empty, the `prometheus` receiver scrape configurations with their keep-lists from `schema.nix`, and the `zt_peer_.*` drop on the zerotierone scrape.
- In the `ingress` role: the `x-greptime-otlp-metric-promote-resource-attrs` header on every `otlp_http` exporter, generated from the resource allow-list in `schema.nix`.
- Add `modules/checks/otel-collector-config.nix`: regulator R3.1.
- Add the `otel-envelope` service and timer to the `ingress` role's NixOS module: regulator R3.2.
- Add the `observability-notify@` template unit to the `ingress` role's NixOS module, and `OnFailure=observability-notify@%n.service` on `otel-envelope`; ADR-005 and ADR-007 set the same `OnFailure=` on their units.
- Modify `modules/nixos/nixbot.nix`: a loopback-only nginx server on `127.0.0.1:9180` proxying `/metrics` to the nixbot socket.
- Modify `modules/clan/inventory/services/zerotier.nix` or the zerotier NixOS configuration it applies: `services.zerotierone.localConf.settings.allowMetrics = true`.
- No flake input is added; `opentelemetry-collector-contrib` comes from the root `nixpkgs` input.
- Clan vars generator `otel-ca`: `share = true`, `files."ca.key".deploy = false`, `files."ca.crt".secret = false`, openssl P-256 self-signed CA, after `nix-grpc-ca` (`cameronraysmith/vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:106-120`).
- Clan vars generator `otel-cert`: per machine, depends on `otel-ca`, CN the machine name, `extendedKeyUsage=clientAuth` on agents and additionally `serverAuth` with the ZeroTier address as IP SAN and `magnetite.zt` as DNS SAN on magnetite, key owned by `_otelcol` on darwin and consumed by `LoadCredential` on NixOS.
- Consumed, not created here: the `collector-password` and `regulator-password` files of ADR-007's `greptimedb-users` generator, read by the ingress and by `otel-envelope` through `LoadCredential` (the ingress through a `${file:...}` reference).

## Questions for the human gate

1. Q1: Is the ingress role on magnetite's agent acceptable rather than a separate gateway? Recommended: yes; the alternative adds a process or a host to every delivery path.
2. Q2: Reuse `nix-grpc-ca` or mint `otel-ca`? Recommended: mint `otel-ca`; reuse makes a telemetry key a trusted remote-build credential for dispatcher CNs.
3. Q3: Are blackphos, rosegold and argentum telemetry subjects? Recommended: no until each primary user consents; the alternative collects host data from other people's laptops without consent.
4. Q4: Are the Android ZeroTier members telemetry subjects? Recommended: no, they are refused by mTLS; the alternative needs a certificate path for unmanaged devices.
5. Q5: Is a darwin agent acceptable while nixbot's darwin checks are non-gating? Recommended: yes, with R3.1 validating darwin configuration on `x86_64-linux`; the alternative requires a gating darwin builder first.
6. Q6: Enable nix-grpc-daemon `metricsListen` and disable its idle exit? Recommended: no; its per-RPC logfmt line already reaches journald, and the alternative keeps an idle daemon resident on magnetite.
7. Q7: Collect macOS unified logging with the alpha `macos_unified_logging` receiver? Recommended: no in this decision; the alternative ships an alpha receiver over a log stream with no content allow-list.
8. Q8: Accept the pinned collector 0.155.0 against upstream 0.163.0? Recommended: yes, take upgrades through pin bumps; the alternative carries an override derivation.
9. Q9: How does a failed regulator or oneshot unit notify a human? Recommended: `OnFailure=observability-notify@%n.service` on `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope`, `greptimedb-export` and `greptimedb-schema`, posting to the existing ntfy on cinnabar, with topic, authentication and deduplication per ADR-009; the alternative leaves those failures visible only in `systemctl --failed`.
10. Q10: Run the `process` scraper on stibnite? Recommended: no; stibnite has no OOM history and its process names record which applications its user runs; the alternative stores that record for every reader of `fleet`.
11. Q11: Bound per-process metrics by a 64 MiB floor over per-executable sums, rather than an include-list or per-unit cgroup memory? Recommended: yes at 0.155.0, and revisit per-unit memory when the pin reaches `v0.160.0`; the include-list alternative misses unexpected growers, and the cgroup alternative needs an override derivation.
12. Q12: Rewrite `omnigent-host-<owner>.service` to `omnigent-host-<alias>.service` from an explicit owner-to-alias attrset in `schema.nix`? Recommended: yes, which keeps ADR-004's ban on person identifiers and keeps each worker's series stable when owners change; the alternative admits the verbatim unit names, so each owner's name becomes a label value in `fleet`.
13. Q13: Restrict the `systemd` receiver to an allow-list? Recommended: yes; the alternative, every `*.service` unit, sees failures of any unit but costs eight series per unit on every host.
14. Q14: node_exporter with only `zfs` and `vmstat` on loopback, rather than zfs_exporter? Recommended: yes, for ARC and `oom_kill`; the alternative adds pool capacity and fragmentation but loses ARC and spawns `zpool` each scrape.
15. Q15: Collect SMART on pyrite only, from `/dev/nvme0`? Recommended: yes, and remove the exporter if acceptance shows the Apple controller returns no health log; the alternative collects emulated SMART data from virtual disks.
