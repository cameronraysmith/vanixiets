---
linear_story_id: CAM-72
linear_story_identifier: CAM-72
linear_story_title: "S5: Bring stibnite into collection on darwin"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-72/s5-bring-stibnite-into-collection-on-darwin
linear_story_state: Backlog
linear_team: CAM
linear_project: fleet-observability
last_synced_state: null
last_synced_at: null
review_round: 0
max_review_rounds: 3
attempt_log: []
---

## Why

stibnite, the operator's workstation, reports nothing to the telemetry store, so a full disk, a failing SSD, a stopped `nix-daemon` or a looping launchd job on it is found by hand, and its requests to the ingress are refused for lacking a certificate.
S4 built the ingress and the agent role for NixOS, CAM-76 watches the alert path from outside, and CAM-73's dashboard selects hosts by `host_name`, so the darwin slice is the remaining host in ADR-003's scope.
This change runs a darwin agent, a root process collector, a launchd probe and a darwin `otel-envelope` on stibnite, issues it an `otel-ca` certificate, and adds the launchd rules, so stibnite's failures reach a person and its sleep raises nothing.

## What Changes

Decisions tagged `O<n>` were made by the operator on 2026-11-05, each as `design.md` recommended under the question `Q<n>` of the same number; `brainstorm.md` records each with its corrections.

**The darwin agent on stibnite**
- The `otel-collector` agent role gains a `darwinModule`, and stibnite joins `flake.lib.observabilityHosts` with `smartDevices = [ "disk0" ]`, entering with `collect = false` until its watched deploy (D1, D7).
- `launchd.daemons.otelcol` runs the agent as `_otelcol` with ADR-003 item 21's `disk0` and `/System/Volumes/Data` bounds, memory without the Linux-only series, the collector's own telemetry, the loopback node_exporter scrape and stibnite's deploy records, exporting over mTLS to `otlp/mesh` with S4's queues and retries (D1, D2).
- `launchd.daemons.otelcol-process` runs the `process` scraper as root with no listener and no credential, exporting to the agent on loopback (D3).
- `launchd.daemons.otel-host-probe` writes launchd job state and SMART into a textfile every 60 s, which node_exporter serves on `127.0.0.1:9100` with only `textfile` (D4).
- `otel-cert` is issued to stibnite without `restartUnits`, which clan throws on darwin; its key is owned by `_otelcol`, and a reissue reloads the agent through its plist (D5).

**Regulation and notices on darwin**
- `otel-envelope` runs every 5 min from `StartInterval` with `flake.lib.otelEnvelope`'s C1 to C4 over the darwin agent and a C5 bounding the two collectors' resident memory at 256 MiB and 128 MiB, since launchd bounds none (D6, O5).
- A platform-neutral notifier wrapper posts `FAILED` and `RESOLVED` for the envelope to `fleet-alerts` with the existing shared `ntfy-alerter` token, of which stibnite becomes the seventh reader through `clan vars fix`; the token is required, because ntfy refused an anonymous post to a `fleet-*` topic from stibnite on 2026-11-05 (D5, D6, O2).
- No S5 launchd job uses a calendar schedule, held by an assertion, so no S5 schedule depends on the wall clock across a clock change (D8).

**Alerting over darwin**
- The host table gains `platform`, checked against the inventory's `machineClass`, and each rule expects the hosts that write its series: the Linux-only rules the NixOS hosts, the launchd rules and `HostProbeStale` the darwin hosts, the file-system rules every collecting host and the NVMe rules pyrite and stibnite (D7, D9, O8).
- ADR-009's `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop` and `HostProbeStale` land after stibnite's series are read from the store; `LaunchdJobNotRunning` also fires for an allow-listed job that is not loaded, and `LaunchdJobFailed` excludes the jobs that post their own notices (D9, O4).
- A pending alert's `for` counts only runs on which its host reports, so a condition seen in the store's lookback before sleep cannot fire at wake without having held while the host was awake; this applies fleet-wide (D10, O3).

**Deployment**
- Pull request 1 with stibnite's `collect = false`, the vars step, and a magnetite deploy; pull request 2 sets `collect = true`, then stibnite deploys by `just activate` and magnetite deploys after it; pull request 3 adds the darwin rules, then magnetite deploys (design "Migration Plan", O1).
- Pull request 1's implementation waits until the session upgrading omnigent has landed its edits to the collector's `flake-module.nix` and `schema.nix`, and rebases onto them (O9).
- Acceptance includes one suspend and resume of stibnite with the operator present, and one stop of an allow-listed job (D12, O6, O7).

**Decision records amended through charter v29**
- From: ADR-003 R3.2 leaves darwin's envelope to S5 and ADR-003:253 places the notifier in the NixOS module only; ADR-003 item 23 maps a non-integer exit code to -1; ADR-009's `LaunchdJobNotRunning` reads kept-alive labels only; ADR-009 item 17 freezes a silent host's instances with their pending time intact; the `host-probes` component lists no measurement of the root collector's memory; `ntfy-send` says darwin blocks store binaries from TCP over ZeroTier (`pkgs/by-name/ntfy-send/package.nix:5-6`).
- To: darwin's envelope is a `StartInterval` launchd job wrapped by the notifier; a missing `last exit code` line is written 0 after a jetsam idle exit and -1 otherwise; `LaunchdJobNotRunning` adds allow-listed jobs that are not loaded; a pending instance's time counts only while its host reports; the root collector's memory is measured at acceptance and bounded by the envelope's C5; the endpoint-security note is corrected by the collector's own connection.
- Reason: launchd has no `OnFailure` and no memory bound, a jetsam-ended or signal-killed job prints no exit code, and the store's lookback lets a pre-sleep condition fire at wake.
- Impact: non-breaking; pyrite and cinnabar's dead-man evaluator, which shares the transition, gain the pending-time change too.

## Capabilities

### New Capabilities

None.
stibnite extends the existing collection, ingress and alerting capabilities; no new area of behaviour is added.

### Modified Capabilities

- `host-metrics-collection` (stratum: `behavioral`): `Each agent host contributes its own signals to the telemetry store` adds stibnite with file-system fill, disk health, per-process memory and launchd job state, and states what a darwin host does not report; `Series cardinality stays bounded` adds 30 launchd labels per host; `Stored unit names carry no owner's name` covers launchd labels; `Collection survives a telemetry store restart without losing the queued interval` holds for stibnite's queue; `A failed collection or store job notifies a person` covers the darwin collectors and envelope.
- `fleet-ingress-interface` (stratum: `interface`): `One host table declares the agent hosts and what each reports` gains `platform` and stibnite's row; `The collection CA issues each agent host one certificate` admits a darwin key owned by `_otelcol` without `restartUnits`; `Each agent exports by its role` adds the darwin agent, whose limiter is its only in-process memory bound; `otel-envelope regulates each agent from its own collector` gains its darwin form and C5; `pyrite's NVMe health is read by a loopback exporter` is renamed `A laptop's disk health is read on the host and served on loopback` and covers stibnite's probe; two requirements are added, `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile` and `No darwin collection job runs on a calendar schedule`.
  Trust boundary: as S4's, plus that stibnite's key sits on a laptop that leaves the operator's premises, that the probe trusts `launchctl print`'s unversioned text, and that root on stibnite runs `otelcol-process`; nothing here guarantees a series reaches the store end to end.
- `telemetry-store-interface` (stratum: `interface`): `Scrape targets are reached on loopback` adds the darwin node_exporter; `The collector's configuration bounds what it gathers` adds the darwin include lists and `otelcol-process`; `The telemetry store and the collector run inside a declared envelope` adds the darwin limiters and the envelope's bound; `Credentials exist only as activation-resolved files owned by non-worker users` adds `_otelcol`'s key and token; `Failure notices are posted to one topic` and `A failure episode ends at the unit's next successful start or exit` gain the wrapper; `Omnigent unit names are stored under aliases` adds launchd labels.
- `fleet-alerting` (stratum: `behavioral`): `Each known failure class on a host reaches a person as an alert` adds a stopped, failed or looping darwin job and a stale probe; `An unreachable telemetry store or a silent host freezes alerts` states that a sleeping host's condition fires only after holding while it reports.
- `fleet-alerting-interface` (stratum: `interface`): `Alert rules are rendered from one Nix source to the evaluator and to promtool` adds the four darwin rules; `Each rule's presence selector is watched` takes expected hosts by platform; `Store errors and silent hosts freeze instance state` restarts a pending instance's time after a freeze; `The alerter token travels only as a file` adds stibnite's copy, owned by `_otelcol`.
  Trust boundary: `This capability states its own trust boundary` adds that a compromised stibnite can post to any `fleet-*` topic with the alerter token, as pyrite can today (O2).
- `devloop-collection` (stratum: `behavioral`): `Every dev-loop event is recorded once and kept for a year` counts stibnite's deploys; `devloop-collection-interface` (stratum: `interface`): `Each agent host's collector ships its own deploy records` adds stibnite, and `This capability states its own trust boundary` limits "the darwin machines ship none" to the darwin machines without a collector.
- `world-assumptions` (stratum: `world`): A61 to A66 record that launchd misses `StartInterval` firings during sleep and coalesces missed `StartCalendarInterval` firings at wake (A61), the `launchctl print` fields seen on macOS 26.7.1 (A62), stibnite's SSD answering the probe's smartctl read unprivileged (A63), stibnite's sleep and dark-wake frequency (A64), a store-built binary on stibnite reaching the ingress over ZeroTier (A65), and ntfy refusing an anonymous post to a `fleet-*` topic from stibnite (A66); `Grounded vocabulary for behavioral requirements` gains the rows `darwin host`, `launchd job`, `kept-alive job`, `probe`, `sleep` and `dark wake`, and `collected host` adds stibnite.

## Impact

- New: `flake.modules.darwin.otel-collector-agent` in its own file, the platform-neutral notifier wrapper, a platform-neutral renderer of the darwin collector configurations, the probe script and its parser fixtures.
- Changed: `modules/clan/services/otel-collector/flake-module.nix` (the role's `darwinModule`, `otel-cert` without `restartUnits` on darwin), `schema.nix` beside it (the darwin keep-lists, the launchd allow-list with `org.nixos.otel-envelope`, the kept-alive set), `modules/lib/observability-hosts.nix` (`platform`, stibnite's row), `modules/nixos/fleet-alert/rules.nix` and `transition.jq` with `modules/checks/fleet-alert/model.py` (expected hosts by platform, the darwin rules, pending time after a freeze), `modules/lib/otel-envelope.nix` (the darwin form and C5), `modules/checks/otel-envelope.nix`, `modules/checks/otel-collector-config.nix` and `modules/checks/fleet-alert.nix`, and stibnite's machine module.
- Overlap: a separate session upgrading omnigent may edit the collector's `flake-module.nix` and `schema.nix`; this change keeps its darwin code in its own file and touches those two files in small, separate hunks, rebased after that session's pull request lands.
- New secrets: stibnite's `otel-cert`; stibnite becomes a reader of `ntfy-alerter` (`otel-ca` has no machine readers).
- Documentation: the charter v29 entry and the amendments above, the `otel-collector`, `host-probes` and `fleet-alert` components, the collector README and the runbook's darwin host section.
- Deployment: one vars step, in the same commit as the role, three magnetite deploys, one cinnabar deploy for the shared transition and one watched stibnite activation, the activations after pull request 1 installing only secret files that no job reads; acceptance with the operator at stibnite.
- Residual risk: `launchctl print` is not API, so a macOS update can break the parser, which the fixtures and `RuleSignalMissing` report; stibnite's jobs are observed only while it is awake; a lost laptop's key stays valid until `otel-ca` is rotated.
- Out of scope: blackphos, rosegold and argentum, which join only with their users' consent (ADR-003 Q3); darwin panels in `fleet-hosts`; macOS sleep and wake events as signals (ADR-003 future extension 6); memory pressure, swap and jetsam kills on darwin.
