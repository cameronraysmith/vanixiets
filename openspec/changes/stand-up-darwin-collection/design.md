## Context

This change is slice S5 of the fleet observability implementation (RA:273-275; Linear CAM-72).
It realizes ADR-003 items 21 to 25 for darwin, ADR-004's darwin signals, ADR-008 item 4's darwin accounts and ADR-009's four darwin rules, through the components `otel-collector` and `host-probes`, on stibnite, the only darwin host in ADR-003's scope (A3:82).
`brainstorm.md` records the grounding, the contradictions C1 to C9 and the decision chain D1 to D8 with the questions Q1 to Q8; this document develops that direction, renumbers the decisions by subject, and adds Q9 to Q11.
The operator answered Q1 to Q11 on 2026-11-05, each as recommended; each question `Q<n>` cited below is decision `O<n>`, recorded with its corrections in BS "Status of the decisions", and "Open Questions" lists the answers.

Citation keys:
A3, A4, A5, A8 and A9 are ADR-003, ADR-004, ADR-005, ADR-008 and ADR-009 under `docs/notes/development/observability/decisions/`; CH is `docs/notes/development/observability/charter.md`, RA is `architecture/reference-architecture.md`, OC is `components/otel-collector.md` and HP is `components/host-probes.md` under the same directory.
BS is this change's `brainstorm.md`; S4 is `openspec/changes/archive/2026-11-02-stand-up-linux-fleet-collection/`, and S4-R6 its `retrospective.md` §6.
FM is `modules/clan/services/otel-collector/flake-module.nix`, SC is `modules/clan/services/otel-collector/schema.nix`, HT is `modules/lib/observability-hosts.nix`, OE is `modules/lib/otel-envelope.nix`, ON is `modules/nixos/observability-notify.nix`, RN is `modules/nixos/fleet-alert/rules.nix`, TJ is `modules/nixos/fleet-alert/transition.jq`, MP is `modules/checks/fleet-alert/model.py`, CC is `modules/checks/otel-collector-config.nix` and SM is `modules/machines/darwin/stibnite/default.nix`.
Upstream sources are cited at this repository's pins, listed in BS "Background".

The current state, at `origin/main` `f3beacfbf`:

- The agent role defines only `nixosModule`s (FM:936, :1035), and the inventory puts each row of HT into it (`modules/clan/inventory/services/otel-collector.nix:11`); HT has no stibnite row (HT:23-55).
- The agent fragment carries the `systemd` receiver, `system.linux.memory.available`, the paging scraper and a ZFS-only `filesystem` scraper (FM:339-400), and every surrounding mechanism is systemd's: `LoadCredential`, `MemoryMax`, `DynamicUser`, `StateDirectory`, `OnFailure` and the zone assertion on calendars (FM:497-516, :619, :1019-1022; ON:124-125, :175-197).
- `otel-cert` sets `restartUnits` wherever `collect` is true (FM:982-985), which clan-core throws on darwin (`clan-core@dbae2101:modules/clan/export-modules/generic-generator.nix:193-208`).
- RN expects every collecting host for each rule, and the NVMe rules those with `smartDevices` (RN:49-51); no launchd rule and no `HostProbeStale` exists.
- TJ freezes the instances of a host absent from `system_memory_usage_bytes` and keeps their pending time (TJ:104-125, :177-178); `budget_hosts` holds `stibnite: 3` (TJ:38).
- The ingress accepts any `otel-ca` certificate at TLS 1.3 on magnetite's ZeroTier address (FM:779-790), with no client allow-list.
- stibnite runs macOS 26.7.1 on an Apple M5 Pro with an `APPLE SSD AP4096Z` as `disk0`, in zone `America/New_York`, and sleeps about 90 to 130 times a day with as many Power Nap dark wakes (BS "Found while preparing").
- stibnite's evaluated daemons are ten, three of them kept alive, and two run on local calendars (BS "launchd across sleep and clock changes").

Facts the preparation established that shape the decisions (BS "Found while preparing"):

- The pinned smartctl 7.5 with the probe's argument list `-j -H -A disk0` exits 0 as `crs58` and as `nobody` and returns the NVMe health log.
- A store-built curl on stibnite reaches the ingress's TLS handshake over ZeroTier, against `ntfy-send`'s note (C1).
- `launchctl print` prints `state`, `runs`, `pid` and `last exit code` for a nix-darwin job, `Could not find service` for a label that is not loaded, and for a jetsam-killed job a `last exit reason` with no `last exit code` line (C6).
- The pinned collector's `systemd` receiver errors at start off Linux, its darwin `memory` scraper writes no available-memory series, its darwin `paging` scraper writes zeros, and its darwin `filesystem` scraper ignores `include_virtual_filesystems` (BS "What the pinned collector does on darwin").

Constraints that shape every decision below:

- Each check states a 0.5 GiB evaluation budget, measured with `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`; CC stood at 0.443 GiB after S4 (S4 `verify.md:330`), so it has 0.057 GiB left.
- `checks.aarch64-darwin`'s build failures are best-effort, but a darwin evaluation or assertion error fails the check before the best-effort modifier is read (`modules/checks/nixbot-best-effort-darwin.nix:22-28`; A5:29); while stibnite's `collect` is false no CI evaluation imports the darwin fragment, so a clause that must gate in pull request 1 runs on `x86_64-linux`, and the fragment's assertions are additionally evaluated with `collect` overridden to true before pull request 1 merges (A3:204).
- Each clause names its two independently defined value sources before its mutant is written, and a mutant runs only the case it must fail (S4-R6).
- A pre-deploy probe of a vendored consumer runs that consumer's exact argument list (schema `plan` instruction, promoted in #3690).
- A row of HT is read by magnetite's closure, so each pull request that edits it is followed by magnetite's deploy (schema design template, promoted in #3690).
- A human step a later observation depends on is a gated task: here the operator's presence at stibnite for its deploy, the job stop and the suspend.

Stakeholders are the operator, whose workstation stibnite is and who receives the alerts, and the later darwin hosts blackphos, rosegold and argentum, which reuse this slice's module once their users consent (A3 Q3).

## Goals / Non-Goals

**Goals:**

- stibnite stores memory, per-process memory, `disk0` I/O, `/System/Volumes/Data` fill, launchd job state, disk health, its collector's self-telemetry and its deploy records under `host_name="stibnite"` (AC1).
- Stopping an allow-listed launchd job on stibnite produces one notification (AC2).
- Each of HP's darwin acceptance items, and the root collector's memory, is observed or the decision record is amended (AC3).
- A sleep and wake of stibnite produce no false firing, no false recovery and no repeated notification, shown by one watched suspend and by the logs of natural sleeps (AC4; CAM-72 comment).
- stibnite's delivery is regulated on stibnite by a darwin `otel-envelope` whose failure reaches a person without passing through the store.

**Non-Goals:**

- blackphos, rosegold and argentum (A3 Q3).
- Darwin panels in `fleet-hosts`; stibnite appears in its host variable, and its Linux-only panels stay empty for it (C9; Q11).
- Memory pressure, swap, jetsam kills and sleep events as darwin signals (A3 item 25; A3 future extension 6).
- An always-on darwin host: stibnite's silence raises nothing (A9 item 16).
- Any change to the ingress, its certificate or its listener.

## Decisions

### Layout

New files:

| Path | Content |
|---|---|
| `modules/darwin/otel-collector-agent.nix` | `flake.modules.darwin.otel-collector-agent`: `otelcol`, `otelcol-process`, `otel-host-probe`, `otel-envelope`, node_exporter, the activation pre-step and the assertions (D2 to D6, D8); the `_otelcol` account is declared by the role's `darwinModule` (D1) |
| `modules/lib/otel-collector-darwin.nix` | `flake.lib.otelCollectorDarwin`: the agent's and `otelcol-process`'s configurations as plain attrsets from `flake.lib` data only, read by the darwin fragment and by the check (D2, D3, D13) |
| `modules/lib/otel-host-probe.nix` | `flake.lib.otelHostProbe pkgs { … }`: the probe script, its `launchctl print` and `smartctl` parsers, and the textfile writer (D4) |
| `modules/lib/observability-notify-run.nix` | `flake.lib.observabilityNotifyRun pkgs { … }`: the platform-neutral notifier wrapper (D6) |
| `modules/checks/otel-collector-darwin.nix` | `checks.x86_64-linux.otel-collector-darwin`: R3.1's darwin clauses, the rendered configurations through `otelcol-contrib validate`, the parser fixtures and the wrapper's cases (D13) |

Changed files:

| Path | Change |
|---|---|
| FM | the agent role's `darwinModule`; `otel-cert`'s `restartUnits` only on NixOS (D1, D5) |
| SC | the darwin keep-lists, A4's launchd allow-list with `org.nixos.otel-envelope`, the darwin unit names of the probe (D2, D4, D9) |
| HT | `platform`, and stibnite's row (D7) |
| RN, TJ, MP | expected hosts by platform, the four darwin rules and their exclusions, pending time after a freeze (D9, D10) |
| OE | `STATE_DIRECTORY` from the environment on darwin, and C5 under Q5 (D6) |
| ON | its posting and episode logic moved into `flake.lib.observabilityNotifyRun`, which the template calls unchanged in behaviour (D6) |
| `modules/checks/otel-envelope.nix`, `modules/checks/fleet-alert.nix` | darwin cases and legs (D6, D9, D10) |
| SM | no change beyond what the role adds; the account's uid is declared in the fragment (D2) |
| `pkgs/by-name/ntfy-send/package.nix` | the endpoint-security note corrected after D12's observation (C1) |
| the collector README, the runbook, OC, HP and `components/fleet-alert.md` | the darwin host (Migration Plan PR 4) |

launchd jobs added on stibnite:

| Label | User | Schedule | Role |
|---|---|---|---|
| `org.nixos.otelcol` | `_otelcol` (536) | `KeepAlive = true` | the agent: host metrics, self-telemetry, node_exporter scrape, deploy records, mTLS export |
| `org.nixos.otelcol-process` | root | `KeepAlive = true` | the `process` scraper only, exporting to `127.0.0.1:4318` |
| `org.nixos.prometheus-node-exporter` | `_prometheus-node-exporter` (534) | `KeepAlive = true` | `textfile` only, on `127.0.0.1:9100` |
| `org.nixos.otel-host-probe` | `_prometheus-node-exporter` | `StartInterval = 60` | `launchd.prom` and `smartctl.prom` |
| `org.nixos.otel-envelope` | `_otelcol` | `StartInterval = 300` | R3.2's C1 to C4, and C5 under Q5, wrapped by the notifier |

### Data flow

```
stibnite (darwin, launchd)                                   magnetite
otelcol-process (root): process scraper ── otlp_http ──┐
                                   127.0.0.1:4318 ◀────┘
otelcol (_otelcol):
  host_metrics memory / disk(disk0) / filesystem(/System/Volumes/Data)
  otlp (loopback) ← otelcol-process, routed into metrics/host
  prometheus: node 127.0.0.1:9100 (textfile), otelcol 127.0.0.1:8888
  file_log /var/log/deploy-record.jsonl
      │ memory_limiter 150 MiB, resource/agent (host.name=stibnite)
      ▼
  otlp_http/ingress (400 MiB), otlp_http/ingress-logs (16 MiB) ──▶ https://[magnetite.zt]:4318 (otlp/mesh)
      file_storage queue, unlimited retry, otel-cert (CN=stibnite), ca otel-ca            │
                                                                                         ▼
otel-host-probe (StartInterval 60): launchctl print system/<label>, smartctl -j -H -A disk0   fleet ◀── fleet-alert
   ─▶ /var/lib/prometheus-node-exporter/textfile/{launchd,smartctl}.prom                       (expected hosts by platform)
otel-envelope (StartInterval 300) under observability-notify-run
   reads 127.0.0.1:8888 and the declared targets ─▶ FAILED / RESOLVED ─▶ ntfy-send ─▶ https://ntfy.zt/fleet-alerts
```

### Requirement applicability for stibnite

Each row names a signal or regulator that a main requirement or an ADR places on agent hosts, whether it applies to stibnite, and why.
"Main" names the requirement in `openspec/specs/`; the spec deltas carry the outcome.

| Signal or regulator | Main requirement | stibnite | Reason |
|---|---|---|---|
| Host memory, `system_memory_usage_bytes` | host-metrics-collection `Each agent host contributes its own signals to the telemetry store` | applies, states `used`, `free`, `inactive` | darwin memory scraper (`contrib@v0.155.0:.../memoryscraper/memory_scraper_others.go:16-20`); it is also the evaluator's reporting selector |
| Available memory and `HostMemoryPressure` | same; fleet-alerting `Each known failure class on a host reaches a person as an alert` | excluded | `system.linux.memory.available` is a no-op off Linux (`memory_scraper_others.go:28-29`; A3 item 25) |
| Swap, `system_paging_usage_bytes` | same | excluded | darwin pagefile usage reports zeros (`.../pagingscraper/pagefile_others.go:10-20`; A3 item 25) |
| Per-process memory, 64 MiB floor, 30 names | same; `Series cardinality stays bounded` | applies, through root `otelcol-process` | `proc_pidinfo` needs rights over the process, and a process the collector cannot read reports a resident size of 0 without an error (`gopsutil@v4.26.5:process/process_darwin.go:477-492`; A3 item 22) |
| Process disk I/O | none | excluded | not collected on any host; skipped on darwin (`.../processscraper/process_scraper.go:346-349`) |
| systemd units, `SystemdUnitFailed`, `SystemdUnitRestartLoop` | fleet-alerting `Each known failure class…` | excluded, replaced by launchd job state | the `systemd` receiver errors at start off Linux (`.../systemdreceiver/scraper_nonlinux.go:22-24`) |
| launchd job state, the four darwin rules | A9:131-134; new in the deltas | applies, darwin only | A3 item 23; A4:95, :121-123 |
| ZFS pool and ARC, `ZfsPoolUnhealthy` | fleet-alerting `Each known failure class…` | excluded | APFS has no pool state (A3 item 25) |
| OOM kill, `HostOOMKill` | same | excluded | node_exporter's `vmstat` is Linux-only (A3 item 25); jetsam is a non-goal |
| File-system fill, `FilesystemFillingWarn`, `FilesystemFull` | host-metrics-collection; fleet-alerting | applies, `/System/Volumes/Data` only | A3 item 21; darwin ignores `include_virtual_filesystems`, so the strict include list is the only bound (`gopsutil@v4.26.5:disk/disk_darwin.go:21-30`) |
| Disk I/O on `disk0` | telemetry-store-interface `The collector's configuration bounds what it gathers` | applies, without `io_time` and `pending_operations` | A3 item 21; `pending_operations` is always 0 on darwin (`disk_darwin.go:318-325`) |
| NVMe health, `NvmeCriticalWarning`, `NvmeWearHigh` | fleet-ingress-interface `pyrite's NVMe health is read by a loopback exporter` | applies, through the probe's textfile | smartctl_exporter is Linux-only (`NixOS/nixpkgs@3a32588c:pkgs/by-name/pr/prometheus-smartctl-exporter/package.nix:39`); the probe's read exited 0 unprivileged (BS) |
| NVMe self-test | none | excluded | macOS passes through only Identify and Get Log Page (`smartmontools@RELEASE_7_5:smartmontools/os_darwin.cpp:590-605`) |
| zerotierone metrics | telemetry-store-interface `Scrape targets are reached on loopback` | excluded | stibnite's ZeroTier is the macOS application, an external member outside clan and nix-darwin (`modules/clan/inventory/services/zerotier.nix:18`); A3's darwin items name no such scrape |
| Collector self-telemetry, `otelcol` scrape | same | applies | the envelope's input and the stored history (S4 D4) |
| Loopback node_exporter | same | applies, `textfile` only, `up{job="node"}` | A3 item 23; `LocalExporterDown` expects stibnite too |
| Deploy records | devloop-collection-interface | applies | A3 item 4; the file is world-readable (BS) |
| Failure notices to `fleet-alerts` | telemetry-store-interface `Failure notices are posted to one topic` | applies, by the wrapper | D6; launchd has no `OnFailure` |
| `otel-envelope` R3.2 | fleet-ingress-interface `otel-envelope regulates each agent from its own collector` | applies, darwin form | D6 |
| `otel-envelope` R4.2 | fleet-ingress-interface `otel-envelope on the ingress host regulates the fleet budget` | not stibnite's; its B3 gains input | runs on the ingress host only; B3 counts `launchd_label` (OE:206-215) |
| Calendar zone assertion | ON:175-176 | replaced | no S5 job uses a calendar; an assertion holds it (D8) |
| `MemoryMax` | telemetry-store-interface `…run inside a declared envelope` | excluded; the limiter, and C5 under Q5 | launchd bounds no memory (A3:225-226) |
| 24 h queue relation | fleet-ingress-interface `Each agent exports by its role` | applies, as a darwin-fragment assertion | S4 design "Later slices" |
| Unit cap of 40 | host-metrics-collection `Series cardinality stays bounded` | excluded; 30 launchd labels instead | A4:160 |
| Owner alias rewrite | host-metrics-collection `Stored unit names carry no owner's name` | applies, to launchd labels | A4:122; `org.nixos.omnigent-host-cameron` runs on stibnite |
| Host absence, `alwaysOn` | fleet-alerting `A missing signal is itself reported` | excluded | a laptop's silence raises nothing (A9 item 16) |
| Freeze while silent | fleet-alerting `An unreachable telemetry store or a silent host freezes alerts` | applies, with D10's pending-time change | A9 item 17; C5 |
| Laptop alert budget of 3 | fleet-alerting `Alert volume stays within the alert budget` | applies | TJ:38 |
| Collection certificate and mTLS | fleet-ingress-interface `The collection CA issues each agent host one certificate` | applies, CN `stibnite`, key owned by `_otelcol` | D5 |
| Ingress client allow-list | fleet-ingress-interface `The ingress receiver accepts only certificate holders…` | none exists | any `otel-ca` certificate is accepted (FM:779-790; A3:199) |

### D1: The agent role on darwin, in its own file

- **Choice**: the agent role in FM gains `perInstance.darwinModule`, which declares the `otel-ca`, `otel-cert` and `ntfy-alerter` generators on every darwin row, as the NixOS module does on every NixOS row, and imports `flake.modules.darwin.otel-collector-agent` where `collect` is true.
  The fragment lives in `modules/darwin/otel-collector-agent.nix`, and the configurations it runs come from `flake.lib.otelCollectorDarwin`, so FM gains one role attribute and SC gains data, each in a hunk of its own.
- **Rationale**: `nix-builders` is the precedent for a role with both module classes (`modules/clan/services/nix-builders/flake-module.nix:324-335`, `:349-401`, `:416-417`); the inventory already routes every HT row into the role, so a darwin row needs no inventory change.
  The separate file keeps the darwin code out of FM and SC, which a session upgrading omnigent may edit at the same time (Q9).
- **Boundary**: first-party; the clan role API is vendored at `clan-core@dbae2101`.
- **Alternatives considered**: a general nix-darwin `services.opentelemetry-collector` module, rejected for option surface no second consumer needs; a home-manager agent, rejected because it runs only in the operator's session and cannot run `otelcol-process` as root (BS D1).

### D2: The darwin agent

- **Choice**: `launchd.daemons.otelcol` runs `otelcol-contrib --config <rendered>` from the root pin, `UserName = "_otelcol"`, `KeepAlive = true`, `RunAtLoad = true`, logging into a directory the activation pre-step creates for `_otelcol`, behind `/bin/wait4path /nix/store` and a wait for the `otel-cert` key's path.
  launchd opens a job's `StandardOutPath` and `StandardErrorPath` as the job's `UserName`, so each job logs into a directory its own account owns: `otelcol` and `otel-envelope` into `/var/log/otelcol` (`_otelcol`), `otelcol-process` there as root, and `otel-host-probe` into `/var/lib/prometheus-node-exporter/otel-host-probe.log`, the home of `_prometheus-node-exporter`, beside node_exporter's own log (`modules/darwin/shared-reference-tree.nix:22-23`; on stibnite each job's log file is owned by its job's account).
  `_otelcol` is uid and gid 536 in `users.knownUsers` and `users.knownGroups`, with home `/var/empty` and shell `/usr/bin/false`, as `nix-grpc-daemon` declares its account; the role's `darwinModule` declares it on every darwin row whatever its `collect`, because the secrets it owns are installed before any collector runs (D5).
  An activation pre-step, ordered as `omnigent-host`'s (`modules/darwin/omnigent-host.nix:453-475`), creates `/var/lib/opentelemetry-collector/queue`, `/var/lib/otel-envelope` and the log directory, owned by `_otelcol`, mode 0700.
  The rendered configuration:
  - `host_metrics/memory` with `memory` and A3 item 21's `disk` on `disk0` and `filesystem` on `/System/Volumes/Data`, both strict, `system.disk.io_time` and `system.disk.pending_operations` disabled; no `paging`, no `system.linux.memory.available`, no `systemd` receiver;
  - `otlp` on `127.0.0.1:4318`, HTTP only, receiving `otelcol-process` and feeding `metrics/host`, with no logs pipeline (A3:83);
  - the `node` scrape of `127.0.0.1:9100` with A4's darwin keep-list and the `otelcol` scrape of `127.0.0.1:8888` with SC's self-telemetry keep-list;
  - `file_log/deploy-record` with S2's keep-list, as on every agent host (S4 D5);
  - `resource/agent` stamping `host.name = "stibnite"` from `networking.hostName`, and S4's non-ingress exporters, queues, retry, 150 MiB limiter and 30 MiB spike, with `cert_file` and `key_file` the sops paths of `otel-cert`; no `transform/omnigent-alias`, because it rewrites `systemd.unit.name` (FM:294-297), which no darwin receiver emits, and on darwin the probe writes the owner's alias into `launchd_label` (D4).
  The fragment asserts the 24 h queue relation with SC's `fleetBytesPerMinute`, the queues' sum below 512 MiB, and every receiver and scrape endpoint on loopback except the exporters' ingress address; every daemon it declares runs behind `/bin/wait4path /nix/store` through nix-darwin's `script` or `command`, which `modules/darwin/launchd-wait4path.nix:25-31` asserts only for jobs with `RunAtLoad` or a non-false `KeepAlive`, so `otel-envelope`, an interval job, is wrapped but not asserted.
- **Rationale**: the rendered configuration is A3 items 1, 4, 21 and 25 with the Linux-only parts removed, which the pinned sources show either error or write nothing on darwin (Applicability).
  `KeepAlive = true` and launchd's 10 s throttle replace systemd's restart policy; the queue survives a restart because bbolt's lock dies with the process (`etcd-io/bbolt@v1.5.0:bolt_unix.go:18-35`).
  Waiting for the key's path covers boot, when `/run` is empty until `sops-install-secrets` runs (`modules/clan/services/nix-builders/flake-module.nix:29-30`).
- **Boundary**: vendored collector, first-party configuration; whether launchd lets a store-built Go binary reach the ingress over ZeroTier is observed at stibnite's deploy (C1; D12).
- **Alternatives considered**: running the agent as root, rejected by A8 item 4; `/run`-based state, rejected because darwin empties `/run` at boot.

### D3: `otelcol-process`

- **Choice**: `launchd.daemons.otelcol-process`, root, `KeepAlive = true`, runs a second `otelcol-contrib` whose rendered configuration has only `host_metrics/process` with A3 item 16's settings, the six identity attributes disabled, the 64 MiB `filter`, a 64 MiB limiter with a 16 MiB spike, its own telemetry switched off with `service.telemetry.metrics.level: none`, which builds no meter reader and so opens no listener (`go.opentelemetry.io/collector/service@v0.155.0:service/telemetry/otelconftelemetry/metrics.go:28-30`; the default reader is a pull exporter on `localhost:8888`, `factory.go:48-59`), and `otlp_http` to `http://127.0.0.1:4318` with an in-memory queue.
  It sets no `service.name`: no rule, panel or regulator reads one for process series, and the store would turn it into a `service_name` column on `process_memory_usage_bytes` that only stibnite's rows fill.
  The fragment asserts the six attributes disabled, no receiver endpoint and no telemetry listener, and no credential path in the configuration (A3:240; A8 item 4).
- **Rationale**: per-process memory of other users' processes needs root on darwin, and a root process without a listener confines root to the scraper (A3:158-165).
  Its failure shows as `LaunchdJobNotRunning` on `org.nixos.otelcol-process`, a kept-alive label, because `process_memory_usage_bytes` remains present from the NixOS hosts and so `RuleSignalMissing` cannot see stibnite's share missing (TJ:88-95).
- **Boundary**: vendored scraper; the process scraper forks `ps` for status on darwin (`gopsutil@v4.26.5:process/process_darwin.go:98-99`), whose cost is measured at acceptance with the root collector's memory (D12).

### D4: The probe and node_exporter

- **Choice**: nix-darwin's `services.prometheus.exporters.node` with `listenAddress = "127.0.0.1"`, `port = 9100` and `extraFlags = [ "--collector.disable-defaults" "--collector.textfile" "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile" ]`.
  `launchd.daemons.otel-host-probe` runs `flake.lib.otelHostProbe` as `_prometheus-node-exporter` with `StartInterval = 60`; each run:
  - for each label in A4's allow-list intersected with the evaluated `launchd.daemons`, selected at evaluation by `flake.lib.otelHostProbeLabels`, runs `/bin/launchctl print system/org.nixos.<name>` and writes `launchd_job_state` for the four states, `launchd_job_last_exit_code` and `launchd_job_runs_total`, with the owner rewritten to its alias, never `pid`, `(never exited)` as 0, the integer when the `last exit code` line holds one, 0 when the line is missing and `last exit reason` is a jetsam idle exit (`JETSAM_REASON_MEMORY_IDLE_EXIT`, launchd's routine reclaim of an idle on-demand job), and -1 when the line is missing with any other reason, as for a job killed by a signal, or is not an integer;
  - a label answered `Could not find service` is written in state `unloaded`, with no exit code and no runs series;
  - for each `smartDevices` entry runs the root pin's `smartctl -j -H -A <device>` and writes the smartctl_exporter series A4 keeps, `# TYPE` counter where smartctl_exporter declares one, so the store stores the `_total` names pyrite's series carry;
  - writes each file to a temporary name in the textfile directory and renames it, and finishes within 30 s.
  The probe holds no credential; its labels, devices and owner aliases are arguments rendered from SC and HT.
- **Rationale**: A3 items 23 and 24; the missing-line rule answers C6, and the `-1` keeps a signal kill visible to `LaunchdJobFailed` without an unbounded `last exit reason` label; an idle exit is written 0 because on 2026-11-05 98 of stibnite's 441 system jobs showed `last exit reason = JETSAM_REASON_MEMORY_IDLE_EXIT` with no exit-code line while healthy, and reporting it as a failure would fire `LaunchdJobFailed` on routine reclaim.
  Writing the counter types under smartctl_exporter's names makes `NvmeCriticalWarning` and `NvmeWearHigh` read one series name on both hosts; the rules pull request still waits until the names are read from the store (S4-R6, first candidate).
- **Boundary**: vendored `launchctl` text, which is not API; the parser's fixtures are recorded on stibnite at macOS 26.7.1 (D13), and a format change shows as `RuleSignalMissing` on the launchd selectors (A9:137).
- **Grounding for the plan**: the probe's two vendored calls are run before deploy with exactly these arguments, as `nobody` before `_prometheus-node-exporter` exists (BS; schema `plan` instruction); on 2026-11-05 both exited as expected and printed the same text as for the operator's account (`tasks.md` 1.3).
- **Regulation**: `otel-collector-darwin` judges the label selection against a typed fixture list of stibnite's daemon labels and the label set typed from ADR-004:121, with a mutant that leaves the label's dot unescaped, and the parser over recorded replies, among them a jetsam idle exit and a non-idle missing exit code, with a mutant that writes an idle exit as a failure.

### D5: The certificate and secrets on darwin

- **Choice**: the darwin module declares `otel-cert` with the NixOS generator's script, `dependencies = [ "otel-ca" ]`, `CN=stibnite`, `extendedKeyUsage=clientAuth`, and `files."key.pem"` with `owner = "_otelcol"`, `group = "_otelcol"`, `mode = "0400"`, `neededFor = "services"`; FM sets `restartUnits` only in the NixOS module.
  `ntfy-alerter`'s token is declared on darwin with the same shared generator, and on stibnite with `owner = "_otelcol"`, mode 0400, read by the wrapper as `NTFY_TOKEN_FILE`.
  `launchd.daemons.otelcol.serviceConfig.EnvironmentVariables.OTEL_CERT_SHA256` is the sha256 of `otel-cert`'s committed `cert.pem` value, so a reissued certificate changes the plist and nix-darwin reloads the job.
- **Rationale**: clan-core throws on `restartUnits` on darwin (C3); the certificate is public (`secret = false`), so its hash may enter the plist, and the key is reissued only with it (S4 O10).
  The ingress needs nothing: any `otel-ca` certificate is accepted, so no allow-list is extended (FM:779-790).
- **Regulation**: the vars step records the sha256 of `vars/shared/otel-ca/ca.crt/value` and of the decrypted `ntfy-alerter` token before and after, never printing the token, and stops on a change; readers are added with `CLAN_NO_COMMIT=1 clan vars fix stibnite --generator <name>` (S4 D1); `otel-ca` has no machine readers, since `ca.key` is not deployed and `ca.crt` is not secret, so its `fix` adds none.
- **Deploy order**: from the commit that adds the role's `darwinModule`, stibnite's configuration installs the shared `ntfy-alerter` token, whose encrypted file exists but is not encrypted for stibnite until the vars step, and `otel-cert`'s key resolves to `/no-such-path` until the vars step generates it; with `collect` true, evaluation throws while `cert.pem` is missing.
  The host-table row, the role and the vars are therefore one commit, and no activation of stibnite runs from a commit without the vars, because [INFERENCE] `sops-install-secrets` would fail on the undecryptable token and leave every other secret on stibnite uninstalled with it.
- **Boundary**: vendored clan vars and sops-nix darwin module; first-party ownership.

### D6: Darwin's `otel-envelope` and the notifier wrapper (Q2, Q5)

- **Choice**: ON's posting and episode logic moves into `flake.lib.observabilityNotifyRun pkgs { label; host; topic; tokenFile; stateDir; logFile; minIntervalSec = 900; }`, a `writeShellApplication` that runs its command, posts `FAILED <label> on <host>` when a run fails after a pass or a first run fails, posts `RESOLVED <label> on <host>` when a run passes after a posted failure, keeps one episode per label in its state directory, appends each `FAILED` to `logFile`, and calls `ntfy-send`, which uses `/usr/bin/curl` on darwin.
  `logFile` is `/var/lib/observability-notify/failed.log` on NixOS, unchanged, which the evaluator's alert budget reads on magnetite, and `/var/lib/otel-envelope/notify.log` on darwin.
  The NixOS template keeps its unit, `OnFailure` and hooks and calls the same posting code, so NixOS notices are unchanged.
  `launchd.daemons.otel-envelope` runs `observability-notify-run otel-envelope -- otel-envelope` as `_otelcol` with `StartInterval = 300`, `STATE_DIRECTORY=/var/lib/otel-envelope`, and the targets and exporters rendered from `flake.lib.otelCollectorDarwin`.
  The envelope's clauses on stibnite are OE's C1 to C4; under Q5 it adds C5, failing when the physical footprint of `org.nixos.otelcol` exceeds 256 MiB or of `org.nixos.otelcol-process` 128 MiB, read as the MEM field of `/usr/bin/top -l 1 -pid <pid> -stats pid,mem` (within 10 s, an unreadable field failing) for `launchctl print`'s `pid`, the NixOS `MemoryMax` analogues (FM:619).
  The footprint is the kernel's own accounting, which jetsam and Activity Monitor use, whereas the resident size that `ps -o rss=` reports also counts the mapped 357 MiB collector binary's file-backed pages; `top` is setuid root, so `_otelcol` reads root's `otelcol-process` without a privilege change, where `/usr/bin/footprint` would need root (D12's defect note; A70).
- **Rationale**: a failure the envelope sees is usually a broken export path, so a notice sent through the store would not arrive; ntfy is reached directly over the mesh as every NixOS notice is (A3:253).
  One shared posting code keeps one notice format and one rate limit fleet-wide; the wrapper is the darwin counterpart of `OnFailure` plus the `RESOLVED` hooks (ON:185-197).
  `StartInterval` needs no zone and skips sleep, and C1's and C2's two-run rule absorbs an agent restart at activation within one period, as on NixOS (S4 D7).
  launchd bounds no memory (A3:225-226), so without C5 a leaking collector on stibnite is bounded by nothing but the limiter it may be leaking past; C5 also answers AC3's root-collector item continuously (C7).
- **Regulation**: `checks.x86_64-linux.otel-envelope` gains a darwin agent case set over recorded stibnite telemetry, with the targets `node` and `otelcol` only and the exporters `otlp_http/ingress` and `otlp_http/ingress-logs`; under Q5 C5 cases with a stub `top` printing recorded `top` text (bounds at 255 and 257 MiB and 129 MiB, the `K` and `G` suffixes, the recorded 102 MiB footprint beside a 179 MiB resident size, an unreadable field, a missing row and a hung `top`), and the mutants `c5WrongPid` (another pid), `c5ReadsRss` (the resident size) and `c5UnreadablePasses`; C5's text is interpolated inline, so the NixOS envelope's script is unchanged without `darwinMemory`; `otel-collector-darwin` runs the wrapper over a recording `ntfy-send`: pass, fail, fail, pass posts exactly `FAILED` then `RESOLVED`, a second failure inside 900 s posts nothing, and a mutant that removes the episode stamp's guard, built with `minIntervalSec = 0` so the suppression interval cannot hide it, posts a second `FAILED` and must fail.
  At stibnite's deploy, stopping `org.nixos.otelcol` for two envelope periods posts one `FAILED otel-envelope on stibnite` and, after its start, one `RESOLVED` (D12).
- **Boundary**: first-party script; vendored `ntfy-send` path through `/usr/bin/curl`.
- **Alternatives considered**: reporting through `LaunchdJobFailed` alone, circular for a broken export path; a polling launchd job, rejected as a regulator that needs its own regulator (BS D4).

### D7: The host table

- **Choice**: HT's `agent` helper gains `platform = "nixos"`, and stibnite's row is `agent [ ] // { platform = "darwin"; notifiedUnits = [ "otel-envelope" ]; smartDevices = [ "disk0" ]; collect = false; }` in pull request 1, whose `notifiedUnits` replaces the helper's NixOS default with the one label that posts its own notices on darwin; pull request 2 drops `collect = false`.
  An assertion in the clan inventory's `otel-collector` instance compares each row's `platform` with `modules/clan/inventory/machines.nix`'s `machineClass` for that machine, shown failing by a scratch edit setting stibnite's `platform` to `"nixos"` (Q8).
- **Rationale**: the rules need each host's platform to choose expected hosts (C4); `platform` is static data, so RN reads it without evaluating any host, and the inventory's `machineClass` is an independently defined value, so the comparison is a relation, not a restatement.
  Setting `collect = false` first lets the vars step and magnetite's deploy happen before stibnite runs anything (HT:1-7).
  The default `"nixos"` keeps every existing row unchanged.
- **Alternatives considered**: reading `machineClass` in RN directly, rejected because RN reads `flake.lib` only and the inventory is a separate fixpoint; a per-rule host list, rejected as hand-kept lists that drift.

### D8: No calendar schedule, and clock changes

- **Choice**: every job of the darwin fragment is kept alive or uses `StartInterval`; the fragment asserts that none of its daemons sets `StartCalendarInterval`, shown failing by an `extendModules` override giving `otel-envelope` a calendar.
  The existing calendar jobs `harmonia-gc` (daily 03:15) and `nix-cleanup-gcroots` (Sunday 03:30) are observed only by exit code and runs; on a daylight-saving change day each runs once, because neither time falls in the repeated 01:00 to 02:00 hour or the skipped 02:00 to 03:00 hour, and a run missed in sleep is coalesced into one run at wake (`launchd.plist(5)` roff source lines 455-458).
- **Rationale**: the promoted rule in `preferences-nix-development` (#3690) asks each launchd calendar job to state its behaviour across a clock change; S5 adds none, and the two existing ones are stated here and in HP.
  `StartInterval` misses intervals during sleep (`launchd.plist(5)`:441-445), which is the wanted behaviour: nothing is collected while asleep.

### D9: Alerting over darwin (Q4)

- **Choice**: RN derives `nixosHosts`, `darwinHosts` and `smartHosts` from the collecting rows and sets each rule's expected hosts:

| Rules | Expected hosts |
|---|---|
| `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed` | `nixosHosts` |
| `FilesystemFillingWarn`, `FilesystemFull`, `LocalExporterDown`, `WeeklyPipelineTest` | every collecting host |
| `NvmeCriticalWarning`, `NvmeWearHigh` | `smartHosts`: pyrite, and stibnite from pull request 3, after its stored names are read |
| `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop`, `HostProbeStale` | `darwinHosts` |

  The four darwin rules are A9:131-134, with these changes under Q4:
  - `LaunchdJobNotRunning`: `launchd_job_state{launchd_state="running", launchd_label=~"<kept-alive labels>"} == 0 or launchd_job_state{launchd_state="unloaded"} == 1`, 10 min;
  - `LaunchdJobFailed`: `launchd_job_last_exit_code{launchd_label!~"<labels in notifiedUnits>"} != 0`, 5 min, so the envelope is reported once, by its own notice;
  - A4's allow-list gains `org.nixos.otel-envelope`, so a stopped or unloaded envelope is visible through the store.
  The kept-alive labels are rendered from SC and the darwin rows' evaluated `KeepAlive = true` set, as A4:123 states; a job whose `KeepAlive` is a condition set, such as `org.nixos.omnigent-host-cameron`'s `{ SuccessfulExit = false; }`, is outside it, because such a job may exit 0 and stay down legitimately, so its not running is no failure; a non-zero exit of it is still `LaunchdJobFailed`'s.
- **Rationale**: an expected host that can never write a selector would make that selector's `RuleSignalMissing` depend on another host's presence; C4.
  An allow-listed job present in the evaluated configuration but not loaded is never correct, and the probe already writes `unloaded`.
- **Regulation**: `fleet-alert` gains legs: stibnite reporting memory but no `launchd_job_state` for 30 min raises `RuleSignalMissing`; stibnite silent for 40 min with a darwin rule firing raises nothing (a new `stibniteSilent` leg, the darwin counterpart of `laptopSilentLeg`, which covers pyrite and electrum only); a kept-alive label `running` 0 for 10 min fires one `LaunchdJobNotRunning`; an `unloaded` envelope fires it; `LaunchdJobFailed` on `org.nixos.otel-envelope` posts nothing while on `org.nixos.harmonia-gc` it posts once; a Linux-only selector absent while only stibnite reports raises nothing.
  The fixture answers each rule's whole expression with label sets on the steps where its condition holds, and presence from the reporting and missing hosts (`modules/checks/fleet-alert.nix:842-888`); a leg states its condition as those steps, never as replayed metric values.
  Before pull request 3 merges, each darwin rule and the NVMe rules restricted to stibnite are replayed with `query_range` over stibnite's stored history, every would-be firing recorded with its cause, and an empty replay blocks the merge (S4-R6).
- **Boundary**: first-party rules over vendored PromQL in GreptimeDB 1.2.1; `!~` and `or` on label sets are measured on the store before merge.

### D10: A pending instance counts only reporting time (Q3)

- **Choice**: in TJ's `transition`, an instance that was frozen on the previous run and is not frozen now has its `activeSince` set to the current run if its phase is `pending`; MP gains the same rule, and the property test compares them as before.
- **Rationale**: the store answers a sleeping host's last sample for its 300 s lookback, so a time-relative condition such as `HostProbeStale` becomes true after the last sample and starts a pending instance, and the first run after wake, before the probe rewrites its file, would fire it, although the condition never held while the host was awake (C5).
  The rule mirrors `absenceFrom`, which already stops frozen time counting as absence (TJ:18-20); it applies to pyrite too, which suspends rarely (A13), and to cinnabar's `fleet-deadman`, which shares TJ, so cinnabar is deployed after pull request 1 merges.
- **Regulation**: a fixture timeline from the spec scenario lands first and fails on current TJ: stibnite reports, `HostProbeStale` becomes true at its last sample, stibnite is silent for 2 h, then reports with the condition true for 2 runs and false after; no post is expected, and today's TJ fires.
  A second timeline keeps a condition true for 11 min after wake and expects one `[FIRING]`.

### D11: Deploy records

- **Choice**: stibnite's agent ships `/var/log/deploy-record.jsonl` through `file_log/deploy-record` over `otlp_http/ingress-logs`, with the stamp and keep-list of S4 D5; at stibnite's first deploy its line count is compared with its `deploy_record` rows.
- **Rationale**: A3 item 4; `devloop-collection-interface` says the darwin machines ship none until they run collectors of their own, which this change makes false for stibnite (`openspec/specs/devloop-collection-interface/spec.md:381`).

### D12: Acceptance with the operator at stibnite (Q6, Q7)

- **Choice**, each a gated task with the operator present:
  - AC1: after the watched activation, `count by (host_name) (system_memory_usage_bytes)` includes `stibnite`, and each applicable row of Applicability has a stored series under `host_name="stibnite"`.
  - C1: `otlp_http/ingress`'s `otelcol_exporter_sent_metric_points` on `127.0.0.1:8888` grows, which shows the store-built collector reaching the ingress over ZeroTier.
  - AC2 (Q7): `org.nixos.nix-grpc-daemon` booted out for 15 min with no build dispatched to stibnite posts one `[FIRING] LaunchdJobNotRunning stibnite` and, after loading it again, its `RESOLVED`, and nothing else.
  - AC3: `_prometheus-node-exporter` reads `disk0`, shown by the stored SMART series; signal-killed reporting is observed by sending `SIGKILL` to `otelcol-process`, whose `launchd_job_last_exit_code` must read -1 and post one `[FIRING] LaunchdJobFailed stibnite` after 5 min, and then `launchctl kickstart -k system/org.nixos.otelcol-process`, whose exit on `SIGTERM` is expected to read 0 and post its `RESOLVED` `[INFERENCE: the collector shuts down cleanly on SIGTERM; the observation decides]`; an activation changing `otelcol`'s plist fires neither launchd rule; both collectors' resident memory is recorded over 24 h and after the suspend.
  - AC4 (Q6): one lid-closed sleep of at least 30 min after at least an hour of collection; afterwards the queues at `127.0.0.1:8888` drain to 0, `otel-envelope` and `otel-host-probe` each run within one interval of wake, the textfile's mtime is fresh, and no evaluator post or notice names stibnite from sleep until 30 min after wake; then a natural overnight sleep is read from the same logs.
  - Every deploy step reads `journalctl -u fleet-alert -u 'observability-notify@*' --since <deploy start>` on magnetite and the wrapper's log on stibnite, and records each post with its cause.
  - Defect found at AC1 (2026-11-06): after the watched activation C5 failed with `org.nixos.otelcol-process 178 MiB above its limit`, reading `ps -o rss=`, while `/usr/bin/footprint` printed a physical footprint of 101 MB for the same process (the agent 134 MB; the Linux agents' cgroup memory 89 MiB on pyrite and 120 MiB on magnetite); C5 now reads the footprint through `top`, because RSS counts the mapped binary's resident file-backed pages that the kernel neither charges to the process nor reclaims under jetsam.
- **Rationale**: AC1 to AC4, HP:107-112 and the CAM-72 comment; `nix-grpc-daemon` is kept alive and its absence breaks only builds dispatched to stibnite, while `dnscrypt-proxy` would break stibnite's DNS and `nix-daemon` the deploy tooling.

### D13: Checks and evaluation cost

- **Choice**: `checks.x86_64-linux.otel-collector-darwin`, a new check, renders the agent's and `otelcol-process`'s configurations from `flake.lib.otelCollectorDarwin` with `flake.lib` data only and runs the Linux `otelcol-contrib validate` of the same version over each, then asserts R3.1's darwin clauses (A3:240): node_exporter on `127.0.0.1` with only `textfile`, `otelcol-process` with the six attributes disabled and no endpoint, the probe's labels from `flake.lib.otelHostProbeLabels` over a fixture list of stibnite's daemons equal to A4's allow-list intersected with it, item 21's include lists, every endpoint loopback but the ingress address; it runs the probe's parser over recorded `launchctl print` output (a running job, exit 78, `org.nixos.omnigent-host-cameron`, a not-loaded label, a jetsam idle exit and a non-idle job without an exit-code line), each recording stripped of its `environment` blocks, and recorded `smartctl -j -H -A disk0` output, and the wrapper's cases (D6).
  Mutants, each run only against the case it must fail: node_exporter `listenAddress = ""`, a seventh identity attribute enabled, an `otelcol-process` endpoint, the ingress address changed, the disk include widened, a label dot left unescaped, a parser that drops the alias, a parser that writes `pid`, a missing exit code written as 0, an idle exit written as a failure, and a wrapper that posts on every failing run.
  Stubbed packages enter the check as `pkgs // { … }`, never `pkgs.extend`, which re-evaluates nixpkgs and, measured on 2026-11-05, more than doubled the check's evaluation cost.
  Relations within stibnite are darwin-fragment assertions (D2, D3, D8), which every activation evaluates before switching; `checks.aarch64-darwin.darwin-stibnite` fails on an evaluation or assertion error and reports only build failures best-effort, and pull request 1 additionally evaluates stibnite with `collect` overridden to true, because no CI evaluation imports the fragment before pull request 2.
- **Rationale**: nixbot's darwin builds cannot block a merge, so everything that needs no darwin process runs on `x86_64-linux` (A3:204); rendering from `flake.lib` avoids evaluating `darwinConfigurations.stibnite` inside a Linux check, whose store paths could not be realised there and whose cost would exceed the budget `[INFERENCE]`.
  The collector validates component configuration, not platform start, so a Linux binary of the same version validates the darwin text; the `systemd` receiver's darwin start error is outside validation, and its absence is asserted directly.
  CC is left unchanged in its clauses; its cost moves by about 92 KB through SC's new keys, since it has 0.057 GiB of its budget left.
- **Evaluation cost**, each measured before and after its task; a figure over 0.5 GiB stops the task:

| Check | Before | Estimate after | Source of the change |
|---|---|---|---|
| `otel-collector-darwin`, new | none | 162,481,008 B (0.151 GiB), measured on 2026-11-05 over the plan's code with `pkgs // { … }` stubs; 344,895,440 B with two `pkgs.extend` | two rendered configurations, the probe and the wrapper from `flake.lib` and the root pin's `pkgs`, the class of `otel-envelope` |
| `otel-envelope` | 157,616,512 B at `b325407984e6` (`tasks.md` 1.2) | 158,006,224 B measured on 2026-11-06 with C5 reading the footprint through `top` and its darwin cases (`logs/s5-evidence/c5-top-cost-20261106T053106Z.log`) | the darwin cases and C5 |
| `fleet-alert` | 351,940,224 B at `b325407984e6` (`tasks.md` 1.2) | 358,938,432 B measured with Task 3's legs and changes | the platform field, four rules, the TJ change and its legs |

### Spec deltas beyond the proposal's list

- `fleet-ingress-interface` `pyrite's NVMe health is read by a loopback exporter` is renamed `A laptop's disk health is read on the host and served on loopback`, covering pyrite's exporter and stibnite's probe.
- `telemetry-store-interface` `Credentials exist only as activation-resolved files owned by non-worker users` names `_otelcol`'s key and token and states that `otelcol-process` holds none.
- `world-assumptions` adds, from A61: launchd's `StartInterval` and `StartCalendarInterval` behaviour across sleep, quoted from `launchd.plist(5)`; the `launchctl print` fields observed on macOS 26.7.1, including the jetsam case; stibnite's SSD answering `smartctl -j -H -A disk0` unprivileged at smartmontools 7.5; stibnite's sleep and dark-wake frequency; a store-built binary on stibnite reaching the ingress over ZeroTier; each with a WHEN the assumption drifts scenario, and a re-read trigger when macOS's major version or smartmontools' version moves (S4-R6, fifth candidate).
  The designation table gains `darwin host`, `launchd job`, `kept-alive job`, `probe`, `sleep` and `dark wake`, and `collected host` adds stibnite.

### Decision records amended under charter v29

- A3 R3.2 and its implementation surface: darwin's `otel-envelope` is a `StartInterval` launchd job wrapped by the notifier, and the notifier's posting code is platform-neutral (D6); A3:253 follows.
- A3 item 23 and HP: a missing `last exit code` line is written 0 when `last exit reason` is a jetsam idle exit and -1 otherwise (D4; C6).
- A3 envelopes and HP: the two darwin collectors' resident memory is measured at acceptance and, under Q5, their physical footprint bounded by C5 (D6; C7).
- A4:121-123: the allow-list gains `org.nixos.otel-envelope` (D9).
- A9:131-132 and item 17: `LaunchdJobNotRunning` adds unloaded allow-listed jobs, `LaunchdJobFailed` excludes self-notifying labels, and a pending instance's time counts only while its host reports (D9, D10).
- `pkgs/by-name/ntfy-send/package.nix:5-6`: the endpoint-security note is corrected or kept according to D12's observation (C1).

### Later slices

| Slice | Touches | Rule it must keep |
|---|---|---|
| blackphos, rosegold, argentum | the darwin fragment on further hosts, after consent | each gets a row with `platform = "darwin"`, its own `otel-cert`, and the magnetite deploy after its row changes |
| S6 follow-up | darwin panels in `fleet-hosts` | they read stored series only and select by `host_name` |
| S7 | journald on the agents' logs path | darwin has no journald; `otlp` on loopback stays without a logs pipeline until ADR-008's stages exist |
| S8 | exports `devloop.deploy_record` | stibnite's rows are exported keyed by `host` like the others |

## Risks / Trade-offs

- [Risk] macOS's endpoint security, or a later macOS, blocks the store-built collector's TCP over ZeroTier, as `ntfy-send`'s note claims. → Mitigation: D12 observes the exporter's sent points at the first activation, before `collect` reaches magnetite; if blocked, the operator decides between an allow rule and signing the binary, and the queue holds the interval meanwhile.
- [Risk] A macOS update changes `launchctl print`'s text and the parser writes nothing or wrong states. → Mitigation: the fixtures record macOS 26.7.1's text, `RuleSignalMissing` reports absent launchd series within 30 min, and the world assumption's trigger is the macOS major version.
- [Risk] `otelcol-process` as root forks `ps` per process on a host with about 1,300 processes, costing CPU and memory no launchd bound limits. → Mitigation: D12 measures both; C5 under Q5 bounds memory.
- [Risk] Power Nap's dark wakes let stibnite report for seconds, unfreezing its instances briefly. → Mitigation: D10 restarts pending time at each unfreeze, and firing instances already count absence only after the first unfrozen run.
- [Risk] A lost or stolen laptop's key stays valid until `otel-ca` is rotated, and any certificate holder can write under any `host_name`. → Accepted as in S4 (S4 O10); the runbook's rotation covers stibnite.
- [Risk] The darwin fragment is evaluated by no CI check while stibnite's `collect` is false, so a broken fragment can land on `main` in pull request 1. → Mitigation: the Linux check renders and validates both configurations and runs the parser and the wrapper; pull request 1 evaluates stibnite with `collect` overridden to true; from pull request 2 on, `darwin-stibnite`'s evaluation fails on a fragment assertion, and the assertions stop stibnite's own activation before it switches.
- [Risk] Moving ON's posting code into a shared script changes NixOS notices. → Mitigation: the NixOS template calls it unchanged in arguments, and S4's notice cases in `fleet-ingress` and `otel-envelope` rerun before merge.
- [Risk] A kept-alive job that crashes and is restarted keeps a non-zero `last exit code` while it runs, so `LaunchdJobFailed` keeps firing until its next clean exit or reload. → Accepted: the post is a warning, posted once and never re-posted (TJ:1-11), and it reports a crash that did happen; the runbook names `launchctl kickstart -k` as the way to clear it after reading the cause.
- [Risk] The other session's edits to FM and SC conflict with this change's. → Mitigation: the darwin code is in its own files, FM and SC change in small hunks, and pull request 1 is rebased after that session lands (Q9).
- [Trade-off] stibnite's jobs are observed only while it is awake, so a job that fails and recovers during sleep leaves only an increase in `runs`. → Accepted (A3 Consequences).
- [Trade-off] stibnite appears in `fleet-hosts` with its Linux-only panels empty. → Accepted until a darwin view is added (Q11).

## Migration Plan

The change lands as four pull requests:

| Pull request | Contains | Deploy |
|---|---|---|
| 1 | `platform` in HT with stibnite's row at `collect = false`; the role's `darwinModule` and generators; the darwin fragment, the renderers, the probe, the wrapper and ON's refactor; OE's darwin form; `otel-collector-darwin`, the `otel-envelope` cases and the TJ change with its fixture timelines; RN's expected hosts by platform without the darwin rules | vars step, then magnetite, then stibnite's routine activation, which installs only secret files, then cinnabar for TJ |
| 2 | stibnite's `collect = false` removed, immediately before its watched activation | stibnite, then magnetite |
| 3 | the four darwin rules, A4's allow-list change and stibnite in the NVMe rules, after D9's replay | magnetite |
| 4 | the collector README, the runbook's darwin host section, OC, HP, `components/fleet-alert.md`, the charter v29 entry and the decision-record amendments, the `ntfy-send` note | none |

1. Before pull request 1's deploys, each verification command block runs once read-only on stibnite and magnetite with its interpreter named, including the probe's two vendored calls with their exact arguments and the agent's exact `ProgramArguments` against a scratch configuration with no exporter.
2. The vars step generates stibnite's `otel-cert` and adds stibnite as a reader of `ntfy-alerter` (`otel-ca` has no machine readers), with D5's hashes before and after, in the commit that adds the role (D5 "Deploy order").
3. magnetite deploys pull request 1, because HT's row and RN's expected hosts are in its closure, and cinnabar after stibnite's routine activation, because its `fleet-deadman` shares TJ; the evaluator's and the notifier's posts since each deploy start are read and recorded with causes.
4. With the operator at stibnite, pull request 2 merges and stibnite activates with `just activate` (Q1); `launchctl print` shows the five jobs, the exporter's sent points grow (C1), and stibnite's deploy-record lines equal its rows.
5. magnetite deploys pull request 2's closure, after which the evaluator expects stibnite; the posts since step 4 are read and recorded.
6. D12's AC1, AC2 and AC3 items run; the 24 h capture starts on magnetite, an always-on host.
7. D12's AC4 suspend runs with the operator present.
8. After at least one day of stibnite's series, D9's replay runs; pull request 3 merges and magnetite deploys; the posts since are read and recorded, and within 30 min no `RuleSignalMissing` names a darwin selector.
9. Close-out: every one-shot branch the migration added is listed and removed: stibnite's `collect = false` (gone in pull request 2) and any conditional keyed to a darwin row's `collect`, keeping only the role's permanent `collect` gate; the verifier writes each assumption's status as `configured`, `not violated` or `observed` with its window.

Rollback reverses the order: pull request 3's revert and a magnetite deploy remove the darwin rules; setting stibnite's `collect = false` and activating stibnite stops its jobs, leaving the queue on disk, followed by a magnetite deploy so the evaluator stops expecting it; reverting pull request 1 and deploying magnetite removes the row; the vars stay committed and unused.

## Open Questions

Each question carries the answer recommended in the first draft; the operator answered all eleven on 2026-11-05 as recommended, so each is decision `O<n>`.
O2's correction: the alerter token is not a new credential; stibnite becomes the seventh reader of the existing shared `ntfy-alerter` generator through `clan vars fix`, never regenerating it, and the token is required because ntfy's entries on cinnabar are `alerter:fleet-*:rw` and `*:fleet-*:ro`, so an anonymous POST to a `fleet-*` topic from stibnite returned 403 on 2026-11-05 (A66 in the `world-assumptions` delta).
The exposure is stated in `fleet-alerting-interface`'s trust boundary: a compromised stibnite can post to any `fleet-*` topic, as pyrite can today.
O9's answer: the specs, tasks and plan are written now, and pull request 1's implementation waits for the omnigent session's edits to the collector's `flake-module.nix` and `schema.nix` and rebases onto them.
No question remains open.

1. Q1, deploy method: activate stibnite with `just activate` at the machine, or with `clan machines update stibnite`?
   Recommended: `just activate` at stibnite, as it is activated today; the secrets arrive through sops-nix either way, and the operator is present for the gated steps (C8).
2. Q2, darwin failure notices: should a platform-neutral notifier wrapper, sharing ON's posting code, post the darwin envelope's `FAILED` and `RESOLVED` directly to `fleet-alerts`, with stibnite as a new `ntfy-alerter` reader?
   Recommended: yes; a notice through the store cannot report a broken export path (D6).
3. Q3, pending time across a freeze: should a pending instance restart its `for` at the first run after a freeze, fleet-wide?
   Recommended: yes; without it a condition seen in the store's lookback before sleep fires at wake, and the fixture timeline shows it on current code first (D10; C5).
4. Q4, the launchd rules: should `LaunchdJobNotRunning` also fire for an allow-listed job that is not loaded, should `LaunchdJobFailed` exclude the labels in `notifiedUnits`, and should A4's allow-list gain `org.nixos.otel-envelope`?
   Recommended: yes to all three (D9).
5. Q5, darwin memory bound: should darwin's envelope add C5, failing above 256 MiB of physical footprint for `otelcol` and 128 MiB for `otelcol-process`?
   Recommended: yes, with the thresholds revisited from D12's 24 h measurement before pull request 3; launchd bounds neither process (D6; C7).
6. Q6, the suspend gate: one lid-closed sleep of at least 30 min after at least an hour of collection, with D12's reads, followed by one natural overnight sleep read from the logs?
   Recommended: yes; 30 min exceeds the 300 s lookback plus `HostProbeStale`'s 10 min, so the gate exercises D10's case.
7. Q7, the job stopped for AC2: `org.nixos.nix-grpc-daemon` for 15 min, after confirming no build is dispatched to stibnite?
   Recommended: yes; it is kept alive and its absence affects only builds sent to stibnite (D12).
8. Q8, platform: add `platform` to `flake.lib.observabilityHosts`, compared with the inventory's `machineClass` by an assertion?
   Recommended: yes (D7).
9. Q9, the omnigent session: should pull request 1 wait until the session upgrading omnigent has landed its edits to FM and SC, and then rebase?
   Recommended: yes; the darwin code lives in its own files, so the wait affects only two small hunks.
10. Q10, Linear: bind this change to CAM-72 now, moving it to Todo, and amend CAM-72's AC3 to name the root collector's memory as a measurement with C5 as its bound under Q5?
    Recommended: yes, at the operator's approval of this proposal.
11. Q11, the dashboard: leave `fleet-hosts` unchanged, with stibnite's Linux-only panels empty, and file darwin panels as a follow-up?
    Recommended: yes, as CAM-73's comment intends.
