---
title: "host-probes"
---

## Purpose

The host-probes component exposes the host signals that the collector cannot read itself, on loopback only, for the local agent to scrape.
On NixOS it is a loopback node_exporter for ZFS and the kernel OOM-kill count on every agent host, and a loopback smartctl_exporter for NVMe health on pyrite (ADR-003 items 18 and 19).
On darwin it is the `otel-host-probe` launchd job, which writes launchd job state and SMART health as Prometheus textfiles, and a loopback node_exporter that serves only those textfiles (ADR-003 items 23 and 24).
The collector-side host signals, namely per-process memory, systemd unit state, paging, available memory and the darwin `disk` and `filesystem` bounds, are `components/otel-collector.md`.

## Decisions realized

- ADR-003 item 18: `services.prometheus.exporters.node` on `127.0.0.1:9100` on every NixOS agent host with only the `zfs` and `vmstat` collectors and `--collector.vmstat.fields=^oom_kill$`, scraped at 60 s with ADR-004's node_exporter keep-list (ADR-003 Q14).
- ADR-003 item 19: `services.prometheus.exporters.smartctl` on `127.0.0.1:9633` on pyrite only, with `devices = [ "/dev/nvme0" ]`, scraped at 60 s with ADR-004's smartctl keep-list, which excludes the `smartctl_device` info series, and granting the `smartctl-exporter-access` group its ACL on each device in a privileged `ExecStartPre=` before start, because the module's udev rule grants it only on an `add` event, which a switch does not replay (ADR-003 Q15; charter v23).
- ADR-003 item 20: both NixOS exporters set `listenAddress = "127.0.0.1"` and `openFirewall = false`, and the agent's scrape configuration names only `127.0.0.1` targets.
- ADR-003 item 23: `launchd.daemons.otel-host-probe` runs every 60 s as `_prometheus-node-exporter`, runs `launchctl print system/<label>` for each label both on ADR-004's launchd allow-list and in the host's evaluated `launchd.daemons`, and atomically replaces `launchd.prom` (ADR-003 Q16).
- ADR-003 item 23: nix-darwin's `services.prometheus.exporters.node` serves only the `textfile` collector on `127.0.0.1:9100`, scraped at 60 s with ADR-004's darwin keep-list.
- ADR-003 item 24: the same probe runs the root pin's `smartctl -j -H -A` on each device in the host's `smartDevices` entry of `flake.lib.observabilityHosts` and atomically replaces `smartctl.prom` under smartctl_exporter's metric names, so pyrite's and stibnite's series share names and rules (ADR-003 Q15, Q18; charter v23).
- ADR-003 item 25: darwin hosts collect no ZFS, `oom_kill`, available-memory or paging series.
- ADR-004: the node_exporter, smartctl_exporter, launchd and darwin textfile keep-lists, the launchd job allow-list, the owner-to-alias attrset, the kept-alive job set, and the label bans on `serial_number` and launchd `pid`.
- ADR-007: the exporters and darwin daemons belong to the `otel-collector` clan service's `agent` role, not to any machine module.

## Placement

- NixOS, every agent host (cinnabar, electrum, galena, scheelite, magnetite, pyrite): `prometheus-node-exporter.service` from the root pin's `services.prometheus.exporters.node` module (ADR-007; `NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/prometheus/exporters/node.nix:23`).
- NixOS, pyrite only: `prometheus-smartctl-exporter.service` from the root pin's `services.prometheus.exporters.smartctl` module, which grants `CAP_SYS_RAWIO` and `CAP_SYS_ADMIN` (ADR-007; `NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/prometheus/exporters/smartctl.nix:52-61`).
- The KVM and cloud guests run no SMART exporter, because their disks are emulated (ADR-003 item 19).
- darwin, stibnite: `launchd.daemons.otel-host-probe` with `StartInterval = 60` and `UserName = "_prometheus-node-exporter"` (ADR-003 Implementation surface).
- darwin, stibnite: nix-darwin's node_exporter, launchd label `org.nixos.prometheus-node-exporter`, running as `_prometheus-node-exporter` through `script` behind `/bin/wait4path` with `KeepAlive` (ADR-003 Context; ADR-004 launchd job allow-list; `nix-darwin/nix-darwin@4cff07de:modules/services/monitoring/prometheus-node-exporter.nix:35-42`, `:98-119`).
- Textfile directory: `/var/lib/prometheus-node-exporter/textfile`, holding `launchd.prom` and, when `smartDevices` is non-empty, `smartctl.prom` (ADR-003 items 23 and 24).
- `smartDevices`, from each host's entry in `flake.lib.observabilityHosts`, empty by default: `[ "/dev/nvme0" ]` on pyrite and `[ "disk0" ]` on stibnite (ADR-003 Implementation surface; charter v23).

## Interfaces

- `127.0.0.1:9100`, Prometheus text, node_exporter on every NixOS agent host and on stibnite (ADR-003 items 18 and 23).
- `127.0.0.1:9633`, Prometheus text, smartctl_exporter on pyrite (ADR-003 item 19).
- Downstream: the local agent's `prometheus` receiver, at 60 s, with `metric_relabel_configs` keep-lists from `schema.nix`; `up` is kept and `scrape_*` series are dropped for these targets (ADR-003 items 18, 19, 23; ADR-004).
- ADR-009's `LocalExporterDown` reads these targets' `up` under the job names `node` and `smartctl` (ADR-009 rule table).
- Inputs read on NixOS: node_exporter's `zfs` collector reads `/proc/spl/kstat/zfs`, and its `vmstat` collector reads the kernel's `oom_kill` count (`prometheus/node_exporter@6044da783:collector/zfs_linux.go:62-70`; `prometheus/node_exporter@6044da783:collector/vmstat_linux.go:36`, `:45`).
- Inputs read on darwin: `/bin/launchctl print system/<label>` and `smartctl -j -H -A disk0` (ADR-003 items 23 and 24).
- Credentials: none; the probe needs no root, and smartctl_exporter's capabilities come from its NixOS module (ADR-003 Context).

Series written (ADR-004 keep-lists):

- node_exporter, NixOS: `node_zfs_zpool_state` with labels `zpool` and `state`, `node_zfs_arc_size`, `node_zfs_arc_c`, `node_zfs_arc_c_min`, `node_zfs_arc_c_max`, `node_zfs_arc_hits`, `node_zfs_arc_misses`, `node_zfs_arc_memory_throttle_count` and `node_vmstat_oom_kill`.
- smartctl, pyrite and stibnite: `smartctl_device_smart_status`, `smartctl_device_critical_warning`, `smartctl_device_media_errors`, `smartctl_device_percentage_used`, `smartctl_device_available_spare`, `smartctl_device_available_spare_threshold`, `smartctl_device_num_err_log_entries` and `smartctl_device_temperature`, with labels `device` and `temperature_type`; stibnite writes `device="disk0"` and `temperature_type="current"`; the store appends `_total` to the six the exporter declares counters, every one but `smart_status` and `temperature` (ADR-004 item 7).
- launchd, darwin: `launchd_job_state{launchd_label, launchd_state}` with `launchd_state` one of `running`, `not_running`, `unloaded` and `other`; `launchd_job_last_exit_code{launchd_label}`; and `launchd_job_runs_total{launchd_label}`.
- Textfile metadata, darwin: `node_textfile_mtime_seconds` with label `file`, and `node_textfile_scrape_error`.

Probe output rules (ADR-003 item 23):

- A label that `launchctl` cannot find is written with state `unloaded`.
- Each `org.nixos.omnigent-host-<owner>` label is written as `org.nixos.omnigent-host-<alias>` from the owner-to-alias attrset in `schema.nix`, `flake.lib.otelCollectorSchema.ownerAliases = { cameron = "owner-1"; janettesmith = "owner-2"; }` (ADR-003 item 17).
- `pid` is never written.
- `(never exited)` is written as exit code 0, and any exit-code field that is not an integer as -1.

Launchd job allow-list (ADR-004): `org.nixos.nix-daemon`, `org.nixos.nix-grpc-daemon`, `org.nixos.harmonia-gc`, `org.nixos.nix-cleanup-gcroots`, `org.nixos.sops-install-secrets`, `org.nixos.dnscrypt-proxy`, `org.nixos.otelcol`, `org.nixos.otelcol-process`, `org.nixos.prometheus-node-exporter` and `org.nixos.omnigent-host-*`.
`schema.nix` renders the jobs whose evaluated `serviceConfig.KeepAlive` is `true` for ADR-009's `LaunchdJobNotRunning` rule (ADR-004).

## Configuration surface

- In `modules/clan/services/otel-collector/flake-module.nix`, `agent` role NixOS module: `services.prometheus.exporters.node` per ADR-003 item 18, `services.prometheus.exporters.smartctl` with item 19's device ACL step and its `--smartctl.path` wrapper, which removes the exporter's `--log=error` from each smartctl call (charter v26), when `smartDevices` is non-empty, and the agent's `prometheus` receiver scrape configurations with their keep-lists from `schema.nix` (ADR-003 Implementation surface).
- In the same file, `agent` role darwin module: nix-darwin's `services.prometheus.exporters.node` with `listenAddress = "127.0.0.1"` and `--collector.disable-defaults --collector.textfile --collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile`; `launchd.daemons.otel-host-probe` as a `pkgs.writeShellApplication` over `/bin/launchctl`, the root pin's `smartmontools` and `jq`, generated from `schema.nix`, writing by write-then-rename; and the agent's scrape of `127.0.0.1:9100` with the darwin keep-list (ADR-003 items 23 and 24, Implementation surface).
- In `modules/lib/observability-hosts.nix`, `flake.lib.observabilityHosts`: each host's `smartDevices`, `[ "/dev/nvme0" ]` on pyrite and, from S5, `[ "disk0" ]` on stibnite, which the `agent` role reads (ADR-003 Implementation surface; charter v23).
- In `modules/clan/services/otel-collector/schema.nix`: the node_exporter, darwin textfile and smartctl_exporter keep-lists, the launchd job allow-list, the owner-to-alias attrset and the kept-alive job set (ADR-004 Implementation surface).
- In `modules/checks/otel-collector-config.nix`: R3.1's exporter and probe assertions and the recorded `launchctl print` fixtures (ADR-003).
- In `modules/checks/otel-redaction.nix`: R4.1's `launchd_job_state` alias fixture and `smartctl_device` `serial_number` fixture (ADR-004).
- Packages: `prometheus-node-exporter` 1.12.1, `prometheus-smartctl-exporter` 0.15.0, which logs `version=0.15.0` on pyrite (2026-11-01), and `smartmontools` 7.5 from the root pin (ADR-003 Context; `NixOS/nixpkgs@ac1faec4:pkgs/by-name/sm/smartmontools/package.nix:103`).
- Flake inputs: none added (ADR-003 Implementation surface).
- Clan vars generators: none (ADR-003; ADR-007).

## Operating envelope and regulator

Envelopes (ADR-003):

- Exporters on NixOS: `prometheus-node-exporter` and `prometheus-smartctl-exporter` each run with `MemoryMax = 64M`.
- Darwin host-signal processes: the probe finishes within its 60 s interval and node_exporter runs only the `textfile` collector; launchd bounds none of their memory (`research/otel-collector-topology.md` F12, F15).
- Host signals per NixOS host: 16 node_exporter series, and on pyrite 10 smartctl series, inside the per-host figure that also counts the collector's process, unit and paging series.
- Host signals per darwin host: at most 30 allow-listed launchd jobs at six series each, 8 SMART series per device, 3 textfile metadata series and 1 `up` series.
- Exposure: no exporter binds outside loopback.

Regulators:

- R3.1, deterministic, build time, in `checks.x86_64-linux.otel-collector-config`: every `prometheus` receiver target is `127.0.0.1`; both NixOS exporters set `listenAddress = "127.0.0.1"` and `openFirewall = false`; darwin node_exporter's `listenAddress` is `127.0.0.1` with only the `textfile` collector enabled; the probe's label list equals the launchd allow-list in `schema.nix` intersected with the host's `launchd.daemons` (ADR-003).
- R3.1 also runs the probe's parser over recorded `launchctl print` output from stibnite, one running job, one with `last exit code = 78`, one `org.nixos.omnigent-host-cameron` and one reply for an unloaded label, and asserts the expected `launchd_job_*` lines with the alias label, the `unloaded` state and no `pid` (ADR-003).
- R3.2, runtime: each host's own `otel-envelope` probes the scrape targets its collector declares and fails when one does not answer `GET` with 200 within 10 s on two consecutive runs (ADR-003; charter v23).
- R4.1, deterministic, build time: the launchd alias and `serial_number` fixtures leave no owner name and no `serial_number` in the output (ADR-004).
- R4.2, runtime: the ingress host's `otel-envelope` fails when a host exceeds 30 `launchd_label` values (ADR-004; charter v23).
- Alerting over these series is ADR-009's: `ZfsPoolUnhealthy`, `HostOOMKill`, `NvmeCriticalWarning`, `NvmeWearHigh`, `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop`, `HostProbeStale` and `LocalExporterDown`, with `RuleSignalMissing` detecting a renamed or vanished series; see `components/fleet-alert.md`.

## Failure prevented

- node_exporter `zfs` and `vmstat`: a degraded or suspended pool, ARC pressure, or an OOM kill is visible only on the host's console or kernel log, which is not collected (ADR-003).
- node_exporter rather than zfs_exporter: no ARC statistics, and a `zpool` subprocess on every scrape (ADR-003 Q14).
- smartctl on pyrite and the probe's SMART read on stibnite: wear or media errors on the fleet's physical disks go unseen until the disk fails or the pool degrades (ADR-003).
- No SMART on the KVM and cloud guests: emulated data that describes no media (ADR-003).
- launchd job state on darwin: a repo-managed job exits non-zero, stops, or relaunches repeatedly unnoticed, as `org.nixos.omnigent-host-cameron` exited 78 on stibnite on 2026-10-15 (ADR-003).
- Textfile through node_exporter: a dead probe is exposed through `node_textfile_mtime_seconds`, and no new listener or exporter code exists (ADR-003 Rationale).
- Owner-to-alias rewrite in the probe: a person's name enters `fleet` as a launchd label value (ADR-004).
- Loopback-only exporters: a new unauthenticated metrics listener appears on the mesh (ADR-003).

## Deployment acceptance items

- pyrite's Apple NVMe controller answers smartctl's health log on `/dev/nvme0`; if it does not, pyrite's exporter is removed (ADR-003 Q15).
- `RuleSignalMissing` reports a missing `smartctl_device_critical_warning_total` for pyrite within 30 min of deploy if pyrite reports host memory but no SMART series (ADR-009).
- `_prometheus-node-exporter` reads `disk0`'s health log on stibnite, as `nobody` did on 2026-10-15 (ADR-003 Q18).
- `launchctl print` encodes a signal termination as an integer, or the probe writes -1 for it (ADR-003 Q18; ADR-003 item 23).
- A `darwin-rebuild switch` with a changed `otelcol` plist on stibnite fires neither `LaunchdJobFailed` nor `LaunchdJobNotRunning` (ADR-009).
- R3.2 fails within 10 min after one host's `prometheus-node-exporter` is stopped (ADR-003).
- R3.1 fails on a darwin node_exporter `listenAddress` of the empty string and on an exporter `listenAddress` of `0.0.0.0` (ADR-003).
- The `launchctl print` output format is not API, so a macOS update can break parsing; R3.1's fixtures catch a parser change and `RuleSignalMissing` catches a format change (ADR-003 Consequences).

## Deferred

These are ADR-003's future extensions for host signals, not adopted on 2026-10-15; each carries the trigger that would justify it and what adopting it requires (ADR-003 Decision, "Future extensions (not adopted)").

- (5) Continuous profiling.
  Trigger: a magnetite memory or CPU incident in which `process_memory_usage_bytes` names the executable but not the code path, for example `nix-eval-jobs` growth that per-attribute `eval_alloc_bytes` (ADR-005) does not localize.
  Requires: a profiles-capable store or a second backend such as Pyroscope or Parca, a packaged profiler distribution, a privileged eBPF unit on each profiled host, and a decision on whether stack symbols from agent workers are content under ADR-008.
  The OpenTelemetry eBPF profiler ships in the separate `otelcol-ebpf-profiler` distribution, no profiling receiver is in the contrib 0.155.0 build manifest, and GreptimeDB's OTLP router does not ingest the profiles signal (`open-telemetry/opentelemetry-ebpf-profiler@3f72c9a34:README.md:3`; `open-telemetry/opentelemetry-collector-contrib@795558312:cmd/otelcontribcol/builder-config.yaml`; `GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http.rs:1536-1538`).
- (6) Laptop battery, thermal and sleep-wake state on stibnite and pyrite.
  Trigger: an incident in which a laptop's thermal throttling, battery wear or sleep-wake cycle explains lost builds, stale deploy records, or queue replay gaps that host metrics do not explain.
  Requires: node_exporter 1.12.1's `powersupplyclass`, `hwmon` and `thermal_zone` collectors on pyrite's loopback node_exporter and its `powersupplyclass` and `thermal` collectors on stibnite's, a source for sleep-wake events such as `pmset -g log` that no listed collector reads, and consent framing, because sleep-wake times are a personal-activity record (`prometheus/node_exporter@6044da783:collector/powersupplyclass_darwin.go`; `prometheus/node_exporter@6044da783:collector/thermal_darwin.go`).
- (7) Per-host ZeroTier peer latency and path state.
  Trigger: a cross-host failure, such as remote-build dispatch or agent-to-ingress export, attributed to mesh path degradation, relay fallback, or peer flapping.
  Requires: a keep-list restricting `node_id` to the fleet's member ids from the ZeroTier inventory, keeping only `zt_peer_path_count` and the latency histogram, and an ADR-004 budget increase computed per host from the member count; today the agent drops `zt_peer_.*` (ADR-003 item 20; `zerotier/ZeroTierOne@899352e38:node/Metrics.cpp:110-114`).
- blackphos, rosegold and argentum run no probe and no exporter until each primary user consents (ADR-003 Q3).
