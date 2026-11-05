# Brainstorm: collect stibnite's host metrics on darwin over mTLS (S5, CAM-72)

## Background

Slice S5 of the fleet observability implementation brings stibnite, the operator's aarch64-darwin workstation, into collection (`docs/notes/development/observability/architecture/reference-architecture.md:273-275`).
It realizes ADR-003 items 21 to 25 for darwin, ADR-004's darwin signals, ADR-008 item 4's darwin accounts and ADR-009's four darwin rules, through the components `otel-collector` and `host-probes`.
S5 follows S4, whose ingress it reports to, and CAM-76 and CAM-73 are done: charter v27 records that the external watch unblocks CAM-72, and CAM-73's closing comment of 2026-11-05 says CAM-72 may start, because stibnite appears in `fleet-hosts` once its collector writes under its own `host_name`.
Classification under `skill://brainstorming`: architectural, because S5 adds the first non-NixOS collector, the first launchd regulator, the first darwin reader of a fleet secret, and a darwin form of the failure notice that every later darwin host will reuse.

Abbreviations used below: `OBS` is `docs/notes/development/observability/`; A3, A4, A8 and A9 are ADR-003, ADR-004, ADR-008 and ADR-009 under `OBS/decisions/`; CH is `OBS/charter.md`; RA is `OBS/architecture/reference-architecture.md`; HP and OC are `OBS/components/host-probes.md` and `OBS/components/otel-collector.md`; S4 is the archived change `openspec/changes/archive/2026-11-02-stand-up-linux-fleet-collection/`, and S4-R6 its `retrospective.md` §6.
FM is `modules/clan/services/otel-collector/flake-module.nix`, SC is `modules/clan/services/otel-collector/schema.nix`, HT is `modules/lib/observability-hosts.nix`, RN is `modules/nixos/fleet-alert/rules.nix`, TJ is `modules/nixos/fleet-alert/transition.jq`, ON is `modules/nixos/observability-notify.nix` and OE is `modules/lib/otel-envelope.nix`.
CAM-72's four acceptance criteria are AC1 to AC4 in the order Linear lists them.
Upstream sources are cited at the revisions this repository pins: root `nixpkgs` (`flake.lock` node `nixpkgs_10`) at `3a32588c`, `nix-darwin` (`nix-darwin_2`) at `bb0b90db`, `clan-core` at `dbae2101`, `opentelemetry-collector-contrib` at `v0.155.0`, `shirou/gopsutil` at `v4.26.5` and smartmontools at `RELEASE_7_5`.

Inputs gathered on 2026-11-05:

- `linear issue view CAM-72`, its comment of 2026-11-02 carrying the suspend-and-resume gate, and CAM-73's comment of 2026-11-05.
- The decision records, components and main specs, read for what they already decide about darwin.
- The repository at `origin/main` `f3beacfbf`: the collector service, the host table, the evaluator, the notifier, the checks, stibnite's machine module and the darwin precedents.
- The pinned collector, gopsutil, smartmontools, nix-darwin and clan-core sources, and the local `launchd.plist(5)` and `launchctl(1)` manual pages.
- Read-only probes on stibnite on 2026-11-05, recorded under "Found while preparing".

## Status of the decisions

The operator answered the eleven questions `design.md` put on 2026-11-05, each as recommended, with the corrections recorded below; question `Q<n>` became decision `O<n>`.
Decisions the decision records already make, or that follow from the evidence, are marked as the orchestrator's.

- Decision (O1, decided by the operator, 2026-11-05): stibnite is activated with `just activate` at the machine.
- Decision (O2, decided by the operator, 2026-11-05): a platform-neutral notifier wrapper posts darwin's envelope notices directly to `fleet-alerts`.
  The credential is not new: stibnite becomes the seventh reader of the existing shared generator `ntfy-alerter`, whose readers today are cinnabar, electrum, galena, magnetite, pyrite and scheelite, added with `clan vars fix` and never regenerated.
  ntfy's access entries on cinnabar are `alerter:fleet-*:rw` and `*:fleet-*:ro`, and an anonymous POST to a `fleet-*` topic from stibnite over ZeroTier returned 403 on 2026-11-05, so the token is required; this is recorded as a world assumption, and the trust boundary states that a compromised stibnite could post to any `fleet-*` topic, as pyrite can today.
- Decision (O3, decided by the operator, 2026-11-05): a pending instance's `for` restarts at the first run after a freeze, fleet-wide, and the fixture timeline failing on current code lands first.
- Decision (O4, decided by the operator, 2026-11-05): `LaunchdJobNotRunning` also fires for an allow-listed job that is not loaded, `LaunchdJobFailed` excludes the labels in `notifiedUnits`, and ADR-004's allow-list gains `org.nixos.otel-envelope`.
- Decision (O5, decided by the operator, 2026-11-05): darwin's envelope gains C5, failing above 256 MiB resident for `otelcol` and 128 MiB for `otelcol-process`, with the thresholds revisited from the 24 h measurement before pull request 3.
- Decision (O6, decided by the operator, 2026-11-05): the suspend gate is one lid-closed sleep of at least 30 min after at least an hour of collection, with the operator present, followed by one natural overnight sleep read from the logs.
- Decision (O7, decided by the operator, 2026-11-05): AC2 stops `org.nixos.nix-grpc-daemon` for 15 min, after confirming no build is dispatched to stibnite.
- Decision (O8, decided by the operator, 2026-11-05): `flake.lib.observabilityHosts` gains `platform`, compared with the inventory's `machineClass` by an assertion.
- Decision (O9, decided by the operator, 2026-11-05): the specs, tasks and plan are written now; pull request 1's implementation waits until the session upgrading omnigent has landed its edits to the collector's `flake-module.nix` and `schema.nix`, and rebases onto them.
- Decision (O10, decided by the operator, 2026-11-05): the change is bound to CAM-72, and CAM-72's AC3 names the root collector's memory as a measurement bounded by C5; the binding is posted by the orchestrator.
- Decision (O11, decided by the operator, 2026-11-05): `fleet-hosts` is left unchanged, with stibnite's Linux-only panels empty, and darwin panels are a follow-up.

## Grounding evidence

### What CAM-72 and the decision records ask for

- Deliverables: a darwin agent daemon under `_otelcol` and a root `otelcol-process` collector with no listener and no credential (A3 items 21 to 23, A8); an `otel-host-probe` launchd job every 60 s writing launchd job state and SMART to a textfile that a loopback node_exporter serves, with the owner alias rewrite (A3 items 24 and 25, A4); A9's darwin rules for a job not running, a non-zero exit, a restart loop and a stale probe.
- AC1: stibnite reports series distinct by `host.name`.
- AC2: stopping an allow-listed launchd job produces one notification.
- AC3: each darwin deployment acceptance item, SMART access, signal-killed reporting, `darwin-rebuild` reloads and root collector memory, is confirmed, or the decision records are amended.
- AC4: sleep and wake produce no false recovery and no repeated notification.
- CAM-72's comment of 2026-11-02 adds a gate: one suspend and resume while stibnite collects, with the operator present, reading the exporter queues, the envelope timer and the probe afterwards, because pyrite's 2 h 19 min suspend on 2026-11-02 resumed cleanly but a darwin agent under launchd resumes by a different path (S4 `verify.md:408`).
- A3 decides the darwin shape: `launchd.daemons.otelcol` as `_otelcol` behind `/bin/wait4path /nix/store` with `KeepAlive` (A3:81); the `disk` scraper on `disk0` alone without `system.disk.io_time` and `system.disk.pending_operations`, and the `filesystem` scraper on `/System/Volumes/Data` alone, both by strict match (A3:106-107); `otelcol-process` as root with only the `process` scraper, exporting to the local agent at `127.0.0.1:4318` (A3:108-109); the probe as `_prometheus-node-exporter` with `StartInterval = 60`, `launchctl print system/<label>` over the allow-list intersected with the host's evaluated daemons, and node_exporter on `127.0.0.1:9100` with only `textfile` (A3:110-112); `smartctl -j -H -A` on each `smartDevices` entry written under smartctl_exporter's names (A3:113); and no ZFS, `oom_kill`, available-memory or paging series (A3:114).
- A3's envelopes: the agent's 150 MiB limiter is darwin's only memory bound, `otelcol-process` gets 64 MiB, and launchd bounds none of their memory (A3:225-226); the darwin signal budget is 30 process series, 30 jobs at six series, 8 SMART series per device, 3 textfile series and 1 `up` (A3:233).
- A3's R3.1 for darwin asserts the loopback node_exporter, `otelcol-process`'s six disabled identity attributes and missing endpoint, the probe's label list and item 21's include lists, runs the parser over recorded `launchctl print` output, and from S5 runs `otelcol-contrib validate` over darwin configurations on `x86_64-linux` so the check gates (A3:204, :240-243).
- A3 R3.2 leaves darwin's form of `otel-envelope` to S5 (A3:245; CH v23 entry), and A3:253 places the notifier template in the agent role's NixOS module only.
- A4 fixes the launchd allow-list `org.nixos.{nix-daemon, nix-grpc-daemon, harmonia-gc, nix-cleanup-gcroots, sops-install-secrets, dnscrypt-proxy, otelcol, otelcol-process, prometheus-node-exporter, omnigent-host-*}`, the alias rewrite, and the kept-alive set as the labels whose evaluated `KeepAlive` is `true` (A4:121-123); the series `launchd_job_state`, `launchd_job_last_exit_code` and `launchd_job_runs_total` (A4:95); and stibnite's 222 series inside 6,154 of 8,000 (A4:155-160).
- A9's darwin rules: `LaunchdJobNotRunning` (10 min), `LaunchdJobFailed` (5 min), `LaunchdJobRestartLoop` (0) and `HostProbeStale` (10 min) (A9:131-134); the NVMe rules cover pyrite and stibnite (A9:126-127); a laptop's silence raises nothing and its instances freeze while it is silent (A9:102-105).
- HP's darwin acceptance items: `_prometheus-node-exporter` reads `disk0`'s health log; `launchctl print` encodes a signal termination as an integer or the probe writes -1; a `darwin-rebuild switch` with a changed `otelcol` plist fires neither `LaunchdJobFailed` nor `LaunchdJobNotRunning`; R3.1 fails on a darwin `listenAddress` of `""` (HP:107-112).
  No item measures the root collector's memory, which AC3 names.

### What S4 provides and what assumes Linux

- The agent role defines only `nixosModule`s (FM:936, :1035), and the inventory puts every row of HT into the role (`modules/clan/inventory/services/otel-collector.nix:11`); `nix-builders` is the precedent for a role with a `darwinModule` (`modules/clan/services/nix-builders/flake-module.nix:330`, `:360`, `:417`).
- The agent fragment's receivers include the `systemd` receiver (FM:394-400), `system.linux.memory.available` (FM:340), paging usage (FM:341) and a `filesystem` scraper built only from ZFS mounts (FM:350-351).
- Everything around the collector is systemd: `LoadCredential` for `otel-cert` and `otel-key` (FM:1019-1022), `MemoryMax` (FM:619), `DynamicUser` and `StateDirectory` for `otel-envelope` (FM:497-498), its timer `*:0/5 UTC` (FM:516), `OnFailure=observability-notify@%n.service` (ON:185-197) and the assertion that every notified unit's calendar names its zone (ON:124-125, :175-176).
- `otel-cert` sets `restartUnits` wherever `collect` is true (FM:982-985).
- OE needs `$STATE_DIRECTORY` and `$CREDENTIALS_DIRECTORY`, which systemd provides, and GNU `date` from its `runtimeInputs` (OE:93-96, :329-333, :382).
- HT has no stibnite row (HT:23-55); every row is `collect = true`, and its header says a new host enters with `collect = false` until its watched first deploy (HT:1-7).
- RN's expected hosts are every collecting host, and the NVMe rules' those with `smartDevices` (RN:49-51); `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy` and the two systemd rules read series darwin never writes (RN:97-125; A3 item 25).
  No launchd rule and no `HostProbeStale` exists.
- `RuleSignalMissing` fires for a selector only when no host returns it and at least one of its expected hosts reports memory (TJ:88-95), and an always-on host's silence only for hosts with `alwaysOn` (TJ:96-100); `budget_hosts` already holds `stibnite: 3` (TJ:38).
- The ingress accepts any certificate `otel-ca` signed, at TLS 1.3, on magnetite's ZeroTier address (FM:779-790); there is no allow-list of client names, and the certificate's CN is not bound to the stamped `host.name` (A3:199; `openspec/specs/fleet-ingress-interface/spec.md:177-185`).
- S4's B3 budget clause counts `launchd_label` per host and passes while no such column exists (OE:206-215; S4 `review.md:177`).
- The evaluator reads HT from magnetite's own closure, so a change to a row changes alerting only when magnetite deploys (S4 design D6; S4 `review.md` F5).

### What darwin offers in this repository and at the pins

- stibnite is a clan machine of class `darwin` with tags `darwin workstation laptop controller` (`modules/clan/inventory/machines.nix:99-108`), not a clan ZeroTier peer but an external member (`modules/clan/inventory/services/zerotier.nix:18`), and not in the `otel-collector` instance.
- Its operator activates it locally with `just activate`, which runs `nix run .#darwin -- <host> .` (`justfile:93-109`); the docs also name `clan machines update stibnite` (`docs/development/architecture/architecture.md:205`), and the two disagree.
- nix-darwin at `bb0b90db` has no `services.opentelemetry-collector` (`modules/module-list.nix`), has `services.prometheus.exporters.node` running as `_prometheus-node-exporter` with uid 534 reserved (`modules/services/monitoring/prometheus-node-exporter.nix:81-120`; `modules/misc/ids.nix:41`, `:47`), and offers `StartInterval` and `StartCalendarInterval` among the launchd keys (`modules/launchd/launchd.nix:349`, `:359`).
- nix-darwin creates only the users and groups in `users.knownUsers` and `users.knownGroups`, each with an explicit `uid` (`modules/users/default.nix:20-26`; `modules/users/user.nix:32-35`).
- Two repository daemons already run as dedicated users: `omnigent-host-<worker>`, whose activation pre-step prepares its state and installs secrets before daemons load (`modules/darwin/omnigent-host.nix:451-494`), and `nix-grpc-daemon`, whose TLS key is a clan var owned by its user (`modules/clan/services/nix-builders/flake-module.nix:125-167`, `:382-397`).
- `modules/darwin/launchd-wait4path.nix:9-46` asserts that every `RunAtLoad` or `KeepAlive` job on a store executable waits for `/nix/store`.
- clan vars reach darwin through sops-nix's darwin module (`clan-core@dbae2101:nixosModules/flake-module.nix:13`); a file's group defaults to `wheel` on darwin, and `restartUnits` throws there: "The restartUnits option is not supported on Darwin systems" (`clan-core@dbae2101:modules/clan/export-modules/generic-generator.nix:167`, `:193-208`).
- darwin empties `/run` at boot and `sops-install-secrets` reinstalls the secrets at load, which is why `nix-grpc-client-identity` recreates its symlinks at load (`modules/clan/services/nix-builders/flake-module.nix:29-30`, `:66-79`).
- stibnite reads no fleet secret today: `vars/shared/ntfy-alerter/token/machines/` lists the six NixOS hosts only, and `vars/per-machine/stibnite/` holds `nix-grpc-cert`, `nix-remote-build` and `omnigent-cameron-keychain`.
- `ntfy-send` on darwin calls `/usr/bin/curl`, because "Endpoint security software on Darwin blocks ad-hoc signed (Nix store) binaries from TCP connections over ZeroTier" (`pkgs/by-name/ntfy-send/package.nix:5-8`), a note written on 2026-03-10 in `02c01646b`.
- nixbot evaluates `aarch64-darwin` (`modules/nixos/nixbot.nix:93-105`), and every `checks.aarch64-darwin` attribute is `ignoreFailure` (`modules/checks/nixbot-best-effort-darwin.nix:28-29`; `OBS/decisions/ADR-005-dev-loop-instrumentation.md:29`).
- stibnite already writes `/var/log/deploy-record.jsonl` through `flake.modules.darwin.deploy-record` (`modules/system/deploy-record.nix:115-131`); the file held 10 lines, mode 0644, on 2026-11-05.

### What the pinned collector does on darwin

- The collector is `opentelemetry-collector-contrib` 0.155.0 with `CGO_ENABLED = 0` (`NixOS/nixpkgs@3a32588c:pkgs/tools/misc/opentelemetry-collector/releases.nix:18`, `:102`), evaluated for stibnite at `/nix/store/xxczsys7g0m26da9wbsv5y10ai5qp3wb-otelcol-contrib-0.155.0`; gopsutil reaches IOKit and libSystem through purego, so cgo is not needed (`gopsutil@v4.26.5:internal/common/common_darwin.go:13`, `:31`).
- `systemd` receiver: its `start` returns an error off Linux (`contrib@v0.155.0:receiver/systemdreceiver/scraper_nonlinux.go:22-24`), so the agent's current pipelines cannot start on darwin.
- `memory`: only `used`, `free` and `inactive`, and `system.linux.memory.available` is a no-op (`.../memoryscraper/memory_scraper_others.go:16-20`, `:28-29`).
- `paging`: usage reports zeros, because darwin's `VirtualMemory` sets no swap fields (`.../pagingscraper/pagefile_others.go:10-20`; `gopsutil@v4.26.5:mem/mem_darwin.go:38-63`).
- `disk`: whole IOMedia disks through IOKit; `pending_operations` is always 0 (`gopsutil@v4.26.5:disk/disk_darwin.go:161-189`, `:318-325`).
- `filesystem`: supported, and `include_virtual_filesystems` is ignored on darwin, which returns every `getfsstat` mount (`.../filesystemscraper/filesystem_scraper_unix.go:4`; `gopsutil@v4.26.5:disk/disk_darwin.go:21-30`).
- `process`: supported; disk I/O is skipped on darwin, and memory needs `proc_pidinfo` rights over the process, which a non-root collector lacks for other users' processes (`.../processscraper/process_scraper.go:346-349`; `gopsutil@v4.26.5:process/process_darwin.go:323-326`, `:500-537`).
- `load`, `network` and `system` work; `network` forks `netstat` and `lsof` (`gopsutil@v4.26.5:net/net_darwin.go:175-181`; `net/net_unix.go:25-55`).
- `file_storage` uses bbolt's `flock` on darwin, released when the process dies (`etcd-io/bbolt@v1.5.0:bolt_unix.go:18-35`).
- The fleet's exporters retry without limit (`max_elapsed_time = "0s"`), so the give-up check never fires (`opentelemetry-collector@v0.155.0:exporter/exporterhelper/internal/retry_sender.go:82-85`, `:116`); Go's timers do not advance while macOS sleeps (`golang/go#66870`), so tickers and backoffs resume after wake `[INFERENCE]`.
- `prometheus-smartctl-exporter` is Linux-only (`NixOS/nixpkgs@3a32588c:pkgs/by-name/pr/prometheus-smartctl-exporter/package.nix:39`), while smartmontools 7.5 builds for darwin (`pkgs/by-name/sm/smartmontools/package.nix:103`).
- smartctl on macOS reaches NVMe through `IONVMeSMARTInterface` and passes through only Identify and Get Log Page, so no self-test runs on an Apple SSD (`smartmontools@RELEASE_7_5:smartmontools/os_darwin.cpp:64`, `:587-602`).
- node_exporter 1.12.1 runs on darwin with `textfile` among its collectors (`prometheus/node_exporter@v1.12.1:README.md:164`), and nix-darwin's module listens on every address unless `listenAddress` is set.

### launchd across sleep and clock changes

- `StartInterval`: "If the system is asleep during the time of the next scheduled interval firing, that interval will be missed due to shortcomings in kqueue(3)" (`launchd.plist(5)`, macOS 26.7.1, lines 441-445).
- `StartCalendarInterval`: "Unlike cron which skips job invocations when the computer is asleep, launchd will start the job the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon wake from sleep" (lines 456-459).
  Its fields are Minute, Hour, Day, Weekday and Month, with no zone key, so it is local time `[INFERENCE]`; the manual says nothing of clock or zone changes.
- On stibnite the calendar jobs are `harmonia-gc` daily at 03:15 and `nix-cleanup-gcroots` on Sunday at 03:30, local time in `America/New_York` (`nix eval` of `darwinConfigurations.stibnite.config.launchd.daemons`, 2026-11-05).
- `launchctl print` is not API (`launchctl(1)`), and `launchctl list` prints a negative status for a job killed by a signal.

### Found while preparing (stibnite, 2026-11-05)

- stibnite runs macOS 26.7.1 (25G241) on an Apple M5 Pro; its internal disk is `disk0`, an `APPLE SSD AP4096Z` of 4.0 TB, and `/System/Volumes/Data` is 19% used.
- smartctl 7.5 from the pin (`/nix/store/21p1xkzwm9g1cc6yldx8jppixz1vhmsg-smartmontools-7.5`), with the probe's own argument list `-j -H -A disk0`, exited 0 as `crs58` and as `nobody`, with protocol `NVMe`, `smart_status.passed = true` and an `nvme_smart_health_information_log` carrying `critical_warning` 0 and `percentage_used` 0.
  `_prometheus-node-exporter` itself is still unread, because the account does not exist yet.
- A store-built curl 8.22.0 reached the ingress at `[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` over ZeroTier and was refused at the handshake with `tlsv13 alert certificate required`, as `/usr/bin/curl` was.
- `launchctl print system/org.nixos.nix-daemon` printed `state = running`, `runs = 3`, `pid` and `last exit code = 0`; `launchctl print system/org.nixos.nix-cleanup-gcroots` printed `state = not running` and its calendar; a label that is not loaded printed `Could not find service`.
- `launchctl list` showed `com.apple.progressd` with status `-9`, and `launchctl print gui/501/com.apple.progressd` printed `last exit reason = JETSAM_REASON_MEMORY_IDLE_EXIT` and no `last exit code` line.
- `pmset -g` reports `sleep 1`, `standby 1`, `hibernatemode 3` and `powernap 1`; the power log holds 132 `Sleep`, 137 `Wake` and 124 `DarkWake` entries for 2026-11-03 and 92, 98 and 87 for 2026-11-04.
- stibnite's evaluated launchd daemons are `activate-system`, `dnscrypt-pin-dns`, `dnscrypt-proxy`, `harmonia-gc`, `nix-cleanup-gcroots`, `nix-daemon`, `nix-grpc-client-identity`, `nix-grpc-daemon`, `omnigent-host-cameron` and `sops-install-secrets`; `dnscrypt-proxy`, `nix-daemon` and `nix-grpc-daemon` have `KeepAlive = true`, and `omnigent-host-cameron` has `KeepAlive.SuccessfulExit = false`.
- Accounts with uid 441, 450, 460, 501, 502, 530, 535 and 551 exist on stibnite, so 536 is free for `_otelcol`.
- stibnite's zone is `America/New_York`, and its ZeroTier is the macOS ZeroTier One application, outside nix-darwin.

### Contradictions found

- C1, endpoint security: `ntfy-send`'s note says darwin blocks store binaries from TCP over ZeroTier, while a store-built curl reached the ingress's handshake from stibnite on 2026-11-05; the collector is a store-built Go binary, so its own connection is the observation that decides it.
- C2, the darwin notifier: A3 R3.2 leaves darwin's envelope to S5 and A3:253 places the notifier in the NixOS module, so no path posts a darwin failure notice, and launchd has no `OnFailure`.
- C3, certificate restarts: `otel-cert` sets `restartUnits` wherever `collect` is true (FM:982-985), which clan-core throws on darwin.
- C4, expected hosts by platform: RN expects every collecting host for rules whose series only Linux writes, while A3 item 25 says darwin writes none of them.
- C5, sleep and pending alerts: TJ keeps a frozen instance unchanged, and `advance` fires a pending instance once `now - activeSince` reaches its `for` (TJ:104-125, :177-178).
  The store answers a sleeping host's last sample for its 300 s lookback (S4 `retrospective.md` §5), so a condition that becomes true in that window, such as `HostProbeStale`'s `time() - node_textfile_mtime_seconds > 300`, starts a pending instance; at wake the first evaluation that still sees the pre-sleep mtime fires it, although the condition never held for 10 min while stibnite was awake.
  A9 item 17's freeze prevents a false recovery and a repeated post, AC4's two named failures, but not this false firing.
- C6, a signal-killed job: A3 item 23 maps a non-integer exit code to -1, while a job killed by jetsam printed a `last exit reason` and no `last exit code` line at all.
- C7, root collector memory: AC3 names it, while A3:226 says launchd bounds none of the darwin processes' memory and no HP item measures it.
- C8, the deploy method: `justfile` activates stibnite locally, while four documents name `clan machines update stibnite`.
- C9, the dashboard: CAM-73's comment says stibnite appears without a change to any view, while `fleet-hosts` reads `system_linux_memory_available_bytes` and `node_zfs_*` (`modules/nixos/perses/resources/dashboard-fleet-hosts.json:74`, `:131`, `:326`, `:366`), which stibnite never writes; stibnite appears in the host variable with those panels empty.

## Decision chain

### D1. Where the darwin agent lives

Options: a `darwinModule` on the existing agent role importing a first-party darwin fragment; a general nix-darwin `services.opentelemetry-collector` module written for this repository; a home-manager agent under the operator's account.

Decision (orchestrator, from A3:81 and A3:290): the agent role gains a `darwinModule` that imports `flake.modules.darwin.otel-collector-agent`, a fragment in its own file.

- The fragment renders the agent's configuration from the same `flake.lib.otelCollectorSchema` keep-lists as the NixOS fragment, without the `systemd` receiver, `system.linux.memory.available` or the paging scraper, with item 21's `disk` and `filesystem` scrapers and a loopback OTLP receiver for `otelcol-process`.
- `launchd.daemons.otelcol` runs `otelcol-contrib` as `_otelcol` (uid and gid 536) behind `/bin/wait4path`, with `KeepAlive = true` and its `file_storage` queue under `/var/lib/opentelemetry-collector/queue`, prepared by an activation pre-step after the omnigent precedent.
- A separate file keeps the darwin work clear of FM and SC, which another session may edit while it upgrades omnigent; FM gains only the role's `darwinModule` and the darwin guard on `restartUnits`, and SC gains the darwin keep-lists and the launchd allow-list.
- Rejected: a general nix-darwin module, which would add option surface no second consumer needs; a home-manager agent, which runs only while the operator is logged in and could not run `otelcol-process` as root.

### D2. The per-process collector and the probe

Decision (orchestrator, from A3 items 22 to 24): `launchd.daemons.otelcol-process` as root with only the `process` scraper and no listener; `launchd.daemons.otel-host-probe` as `_prometheus-node-exporter` with `StartInterval = 60`; nix-darwin's node_exporter on `127.0.0.1:9100` with only `textfile`.

- Root is required because `proc_pidinfo` reads nothing for another user's process (`gopsutil@v4.26.5:process/process_darwin.go:323-326`; A3:158-165).
- The probe's parser writes -1 when the `last exit code` line is missing, and stores no `last exit reason`, whose free text would be an unbounded label value (C6).
- The probe writes SMART under the names the store gives smartctl_exporter's counters on pyrite, and the rules pull request waits until the names are read from the store (S4-R6, first candidate).

### D3. The certificate and the secrets on darwin

Decision (orchestrator, from C3 and A3:299): the darwin module declares `otel-cert` with the NixOS module's generator script, no `restartUnits`, and the key owned by `_otelcol` with mode 0400.

- The plist's `EnvironmentVariables` carries the sha256 of the certificate's committed public value, so a reissue changes the plist and nix-darwin reloads the job; the key is reissued only with its certificate (S4 O10).
- The collector waits for the key's sops path with `/bin/wait4path`, because `/run` is empty at boot until `sops-install-secrets` runs.
- The vars step generates stibnite's `otel-cert`, and `clan vars fix` adds stibnite as a reader of `otel-ca` and `ntfy-alerter`, with the hashes of `ca.crt` and the decrypted token checked before and after (S4 D1).
- The ingress needs no change: it accepts any `otel-ca` certificate, and no client allow-list exists to extend.

### D4. Darwin's `otel-envelope` and its failure notices (Q2, Q5)

Options for the notice: the envelope posts its own `FAILED` and `RESOLVED` through a notifier wrapper; the envelope only exits non-zero and `LaunchdJobFailed` reports it through the store; a second launchd job that polls the first one's state.

Recommended (Q2): a platform-neutral notifier wrapper, `observability-notify-run <label> -- <command>`, factored from ON's posting and episode logic, that runs the command, posts `FAILED <label> on <host>` to `fleet-alerts` when a run fails after a pass, posts `RESOLVED` when a run passes after a failure, and keeps ON's 900 s rate limit.

- The envelope runs as `launchd.daemons.otel-envelope` with `StartInterval = 300` as `_otelcol`, wrapped by the notifier, with `STATE_DIRECTORY` set in its plist and the alerter token read by `ntfy-send` from `NTFY_TOKEN_FILE`.
- Reporting through the store alone is circular: the envelope exists to see the export path fail, and a failed path carries no `LaunchdJobFailed`.
- A polling job adds a unit whose own failure needs a regulator.
- The envelope's clauses are OE's C1 to C4 with the darwin targets and exporters; the ingress host's R4.2 is unchanged.

Q5: launchd bounds no memory, so should darwin's envelope add a C5 that fails when `otelcol` exceeds 256 MiB or `otelcol-process` 128 MiB of resident memory, the NixOS `MemoryMax` analogues?
Recommended: yes, read with `ps -o rss=` of the job's pid from `launchctl print`; acceptance records both processes' resident memory over the 24 h capture and after the suspend gate, which answers AC3's root-collector item (C7).

### D5. The host table and the rules (Q3, Q4, Q8)

Decision (orchestrator, from A3:288 and S4 D6): stibnite's row has `smartDevices = [ "disk0" ]`, `alwaysOn = false` and `notifiedUnits = [ "otel-envelope" ]`, the labels that post their own notices; it enters with `collect = false`, and its own pull request sets `collect = true` immediately before its watched deploy.

Q8: how does a rule know a host's platform (C4)?
Recommended: a `platform` field in HT, `"nixos"` by default and `"darwin"` on stibnite, compared at evaluation with the inventory's `machineClass`, two independently defined values; the Linux-only rules expect the `nixos` hosts, the launchd rules and `HostProbeStale` the `darwin` hosts, and the file-system, NVMe and `LocalExporterDown` rules every collecting host that writes their series.

Q4: should `LaunchdJobNotRunning` also fire for an allow-listed label the probe writes as `unloaded`, and should `LaunchdJobFailed` exclude the labels in `notifiedUnits`, as `SystemdUnitFailed` excludes notified units?
Recommended: yes to both, with `org.nixos.otel-envelope` added to A4's allow-list; an evaluated job that is not loaded is never correct, and an envelope that posts its own `FAILED` should not be reported twice.

Q3: should a pending instance's `for` count only runs on which its host was reporting (C5)?
Recommended: yes: when an instance unfreezes, a pending instance restarts its `activeSince` at the first unfrozen run, the counterpart of `absenceFrom` for firing instances; the change lands in TJ and the reference model `modules/checks/fleet-alert/model.py` with a fixture timeline from a spec scenario first (S3-R6), and it applies to pyrite as well.

### D6. Sleep and wake

Decision (orchestrator, from the manual and the evidence above):

- Every S5 launchd job is either kept alive or uses `StartInterval`, an interval from the last firing that misses intervals during sleep and reads no calendar `[INFERENCE: the manual describes it as a kqueue interval]`; none uses `StartCalendarInterval`, so no S5 schedule depends on the wall clock or on the zone, and a darwin-fragment assertion holds that, with a mutant (S4-R6, third candidate, promoted in #3690 to `preferences-nix-development`: "a launchd `StartCalendarInterval` job has no zone field and runs on local time, so its module states how it behaves across a clock change").
- The existing calendar jobs `harmonia-gc` and `nix-cleanup-gcroots` run at local 03:15 and 03:30, outside the 01:00 to 02:00 hour the autumn change repeats and the 02:00 to 03:00 hour the spring change skips, so each runs once on a change day; their missed runs while asleep are coalesced to one run at wake.
- stibnite collects nothing while asleep, so its queue grows only while it is awake and cannot reach the ingress; a sleep of any length does not fill it.
- Power Nap's dark wakes, 87 to 124 a day, may run the collector for seconds with or without the mesh; the evaluator then sees stibnite report and unfreeze briefly, which is C5's case and Q3's fix.

### D7. Checks that gate although darwin checks are best-effort

Decision (orchestrator, from A3:204 and A3:240-243):

- Every clause that needs no darwin process runs in an `x86_64-linux` check: `otel-envelope` gains the darwin agent's cases; the probe's parser runs over recorded `launchctl print` and `smartctl` output from stibnite, including the jetsam case of C6; the darwin agent's and `otelcol-process`'s configurations are rendered by a platform-neutral `flake.lib` function, with string context discarded, and validated by the Linux `otelcol-contrib validate` of the same version; and `fleet-alert` gains darwin legs.
- Relations within stibnite, such as the 24 h queue, the loopback listeners, the label list and the absence of calendars, are darwin-fragment assertions, which every activation of stibnite evaluates before it switches, and which `checks.aarch64-darwin.darwin-stibnite` reports best-effort.
- Each changed check is measured against the 0.5 GiB budget before and after.

### D8. Deploy order and gates (Q1, Q6, Q7)

Decision (orchestrator, from the schema's Migration Plan rule and S4 D13): pull request 1 lands the code with stibnite's `collect = false`, then the vars step, then a magnetite deploy, because the row changes magnetite's closure; pull request 2 sets `collect = true`, then stibnite deploys and magnetite deploys after it; pull request 3 adds the darwin rules once stibnite's series are in the store, then magnetite deploys.

Q1: deploy stibnite by `just activate` at the machine or by `clan machines update stibnite`?
Recommended: `just activate` at stibnite, the way it is activated today; the secrets arrive through sops-nix either way, and the operator is at the machine for the suspend gate.

Q6: the suspend gate: how long, and what is read?
Recommended: with the operator present and stibnite collecting for at least an hour, one lid-closed sleep of at least 30 min, longer than the 300 s lookback plus `HostProbeStale`'s 10 min; afterwards the exporter queues drain to 0 at `127.0.0.1:8888`, `otel-envelope` and `otel-host-probe` each run within one interval of wake (`launchctl print` `runs`), the textfile's mtime is fresh, and no evaluator post or notice names stibnite from sleep until 30 min after wake; a natural overnight sleep is then read from the logs the same way.

Q7: which allow-listed job is stopped for AC2?
Recommended: `org.nixos.nix-grpc-daemon` for 15 min, booted out and loaded again, after confirming no build is dispatched to stibnite; it is kept alive, so one `[FIRING] LaunchdJobNotRunning stibnite` and its `RESOLVED` are expected, and nothing else.

## Rules adopted from the S4 retrospective and review

- An alert rule's metric names are read from the store after stibnite's probe has written once, and the rules pull request waits for that read (S4-R6, first candidate).
- A pre-deploy probe of a vendored consumer runs the consumer's exact argument list: `smartctl -j -H -A disk0` and `launchctl print system/<label>` above, and `otelcol-contrib` with the plist's exact `ProgramArguments` in the plan (S4-R6, second candidate; schema `plan` instruction).
- No S5 launchd job uses a wall-clock schedule, held by an assertion (S4-R6, third candidate).
- A table row another host's closure reads changes that host too: each pull request that edits stibnite's row is followed by magnetite's deploy (S4-R6, fourth candidate; schema design template).
- A notified job that runs clauses at two cadences keeps each cadence's verdict; darwin's envelope has one cadence, and the wrapper keeps one episode per label (S4-R6, sixth candidate).
- A regulator clause iterates over the configured set it judges: darwin's envelope renders its exporters and targets from the evaluated configuration (S4-R6, seventh candidate).
- Every alert or notice posted during a deploy window is read from the evaluator's and the notifier's journals on magnetite and from the wrapper's log on stibnite, and recorded with its cause (S4-R6; schema `tasks` rule).
- An assumption's status in `verify.md` is `configured`, `not violated` or `observed`, with its window (S4-R6; schema `verify` rule).
- A laptop's acceptance includes one suspend and resume while it collects (S4-R6; CAM-72 comment).
- Each evidence log is read whole for anomalies before the next step (S4-R6).
- A migration flag's one-shot branches are removed in the close-out: stibnite's `collect = false` row and any branch keyed to it (S4-R6; schema `tasks` rule).
- A mutant runs only the case it must fail (S4-R6).

## Left for design and the specs

- The rendered darwin configurations, the fragment's file layout and its assertions, with their two value sources each.
- The notifier wrapper's state, its rate limit and its fixture check.
- The parser's fixtures and the probe's output for each recorded `launchctl print` form.
- The per-rule expected hosts after Q8, and the fixture timeline for Q3.
- The spec deltas, the world assumptions from A61 and the designation rows.
- The cost of each changed check, before and after.
