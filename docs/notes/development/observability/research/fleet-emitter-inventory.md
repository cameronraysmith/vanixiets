---
title: Fleet emitter inventory and incident-derived SLO candidates
status: research v1
date: 2026-09-18
sources:
  - cameronraysmith/vanixiets@da74672e5
  - NixOS/nixpkgs@85f62611f
  - nix-darwin/nix-darwin@4cff07de7
  - Mic92/nixbot@4a961da96
  - Mic92/niks3@5476ddf07
  - Mic92/gitea-mq@d362abdb9
  - nix-community/buildbot-nix@daf88afb8
  - kanidm/kanidm@8d4465fa2
  - oauth2-proxy/oauth2-proxy@c5529b42b
  - ModernRelay/omnigraph@a625748c8
  - omnigent-ai/omnigent@beb043a64
  - topoteretes/cognee@38eece5bb
---

# Fleet emitter inventory and incident-derived SLO candidates

## Findings

F1.
The nineteen modules under `modules/nixos/` are `app`, `buildbot`, `cognee`, `docker`, `gitea`, `gitea-actions-runner`, `gitea-mq`, `hm-sops-bridge`, `k3s-server`, `kanidm`, `matrix`, `niks3`, `nixbot`, `nvidia`, `omnigent`, `omnigent-host`, `omnigraph`, `sso-gateway` and `zerotier-mss-clamp`.

F2.
Thirteen of them reach a machine through `magnetite`'s import list: `hm-sops-bridge`, `niks3`, `buildbot`, `nixbot`, `gitea-mq`, `gitea`, `sso-gateway`, `gitea-actions-runner`, `docker`, `kanidm`, `matrix`, `omnigraph` and `app` (`cameronraysmith/vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:28-60`).

F3.
`nvidia` reaches only `scheelite`, `zerotier-mss-clamp` reaches `cinnabar` and every `peer`-tagged NixOS machine through the clan zerotier service, and `app` additionally reaches all four darwin machines (`cameronraysmith/vanixiets@da74672e5:modules/clan/inventory/services/zerotier.nix:12-27`).

F4.
`cognee` and `k3s-server` are defined but imported by no machine and no clan role, so their telemetry surface is zero by deployment rather than by design; `cognee` is nonetheless already registered at the SSO gateway and given a ZFS dataset (`cameronraysmith/vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:150-156`).

F5.
`omnigent` and `omnigent-host` reach machines only through the in-flight clan inventory service, with the server on `magnetite` and hosts on `magnetite`, `pyrite` and `stibnite` (`cameronraysmith/vanixiets@da74672e5:modules/clan/inventory/services/omnigent.nix:47-101`).

### What each deployed service can emit today without code changes

| Module | Host | Telemetry available today | Upstream mechanism | Exporter in pinned nixpkgs | Citation |
|---|---|---|---|---|---|
| gitea | magnetite | Prometheus `/metrics`, already enabled, and unauthenticated | `metrics.ENABLED = true`; `TOKEN` is set only when `metricsTokenFile` is non-null | native, none needed | `cameronraysmith/vanixiets@da74672e5:modules/nixos/gitea.nix:126`; `NixOS/nixpkgs@85f62611f:nixos/modules/services/misc/gitea.nix:712-713` |
| nixbot | magnetite | Prometheus `/metrics`, unauthenticated by upstream design, 15 s cached | FastAPI route rendering gauges from Postgres | native, none needed | `Mic92/nixbot@4a961da96:nixbot/nixbot/web/metrics.py:167-180` |
| niks3 | magnetite | Prometheus `/metrics`, unauthenticated, with histograms | `promhttp` registry on the service mux, no `RequireScope` wrapper | native, none needed | `Mic92/niks3@5476ddf07:server/server.go:302`; `Mic92/niks3@5476ddf07:server/metrics.go:22-38` |
| kanidm | magnetite | OTLP traces, logs and metrics over gRPC, currently unset | `otel_grpc_endpoint` config key, feature disabled when absent | native OTLP, none needed | `kanidm/kanidm@8d4465fa2:server/core/src/config.rs:348-349` |
| matrix (synapse) | magnetite | Prometheus, available but not enabled | `settings.enable_metrics` plus a `metrics` listener type | native, none needed | `NixOS/nixpkgs@85f62611f:nixos/modules/services/matrix/synapse.nix:828`, `:512` |
| matrix (livekit) | magnetite | Prometheus, reachable only by setting a freeform key | `prometheus_port` through the module's freeform settings | native, none needed | `NixOS/nixpkgs@85f62611f:nixos/modules/services/networking/livekit.nix:66-68` |
| matrix (coturn) | magnetite | nothing without an `extraConfig` line | only the module's raw `extraConfig` escape exists | none; a coturn exporter is absent from the exporters tree | `NixOS/nixpkgs@85f62611f:nixos/modules/services/networking/coturn.nix:311` |
| sso-gateway | magnetite | Prometheus, available but not enabled | `--metrics-address` on the bespoke oauth2-proxy unit | native, none needed | `oauth2-proxy/oauth2-proxy@c5529b42b:pkg/apis/options/legacy_options.go:490`; `cameronraysmith/vanixiets@da74672e5:modules/nixos/sso-gateway.nix:452-453` |
| buildbot | magnetite | journald logs only | no Prometheus surface anywhere in buildbot-nix | none; scraping would go through the buildbot REST API and `prometheus-json-exporter` | absence verified across `nix-community/buildbot-nix@daf88afb8` |
| gitea-mq | magnetite | journald logs only | none | none | absence verified across `Mic92/gitea-mq@d362abdb9` |
| gitea-actions-runner | magnetite | journald logs only | no metrics option in the pinned module | none | `cameronraysmith/vanixiets@da74672e5:modules/nixos/gitea-actions-runner.nix:177-190` |
| omnigraph | magnetite | structured `tracing` events to journald with numeric fields | `tracing_subscriber::fmt` with `RUST_LOG` filter, no OTLP layer and no metrics endpoint | none; ingestion is log-side | `ModernRelay/omnigraph@a625748c8:crates/omnigraph-server/src/lib.rs:1677-1678`; `:crates/omnigraph/src/table_store.rs:2012-2018` |
| docker | magnetite | nothing; only `enable` and `storageDriver` are set | daemon metrics need an explicit `metrics-addr` | none in the exporters tree | `cameronraysmith/vanixiets@da74672e5:modules/nixos/docker.nix:18-22` |
| hm-sops-bridge | magnetite | no telemetry surface: activation-time only, no unit | activation script failure is visible to the deploying operator | not applicable | `cameronraysmith/vanixiets@da74672e5:modules/nixos/hm-sops-bridge.nix:1-12` |
| app | magnetite, 4 darwin | no telemetry surface: an interactive `nh os switch` wrapper | terminal output only | not applicable | `cameronraysmith/vanixiets@da74672e5:modules/nixos/app.nix:78-81` |
| zerotier-mss-clamp | cinnabar, peers | no telemetry surface: a fixed-MSS packet rule with no counter | nftables rule, no counters declared | none | `cameronraysmith/vanixiets@da74672e5:modules/nixos/zerotier-mss-clamp.nix:1` |
| nvidia | scheelite | nothing today; `nvidia-persistenced` state only | none configured | `prometheus-nvidia-gpu-exporter` and `prometheus-dcgm-exporter` both exist | `NixOS/nixpkgs@85f62611f:nixos/modules/services/monitoring/prometheus/exporters/nvidia-gpu.nix`; `:pkgs/by-name/pr/prometheus-dcgm-exporter` |
| omnigent, omnigent-host | magnetite, pyrite, stibnite | OTel metric publisher exists in the code but the derivation omits every exporter | `ServerMetricsOtelPublisher` plus a periodic publish task, no-op without an SDK | native OTLP once the `tracing` extra is packaged | `omnigent-ai/omnigent@beb043a64:omnigent/server/app.py:1335-1336`, `:1466-1469`; `cameronraysmith/vanixiets@da74672e5:pkgs/by-name/omnigent/package.nix:63` |
| cognee | not deployed | OTLP available behind the upstream `tracing` extra | `opentelemetry-exporter-otlp-proto-{grpc,http}` | native OTLP once the extra is packaged | `topoteretes/cognee@38eece5bb:pyproject.toml:185-189` |
| k3s-server | not deployed | kubelet and apiserver Prometheus endpoints exist by construction; `metrics-server` is disabled | port 10250 is documented as the kubelet metrics and exec API | native, none needed | `cameronraysmith/vanixiets@da74672e5:modules/nixos/k3s-server/networking.nix:22-23`; `:modules/nixos/k3s-server/default.nix:86-89` |

F6.
`nixbot`'s series are exactly the quantities the 2026-09-02 audit measured by hand: `queue_depth`, `builds_oldest_active_age_seconds`, `eval_duration_seconds_sum`/`_count`, `work_queue` and `work_queue_oldest_age_seconds` by kind and status, `effects` by owner and status, `scheduled_effect_lag_seconds`, and `upload_queue_depth`/`_retrying`/`_oldest_age_seconds` per uploader (`Mic92/nixbot@4a961da96:nixbot/nixbot/web/metrics.py:49-162`).

F7.
Every nixbot series is a gauge, including the duration pairs, so the endpoint yields means and never quantiles (`Mic92/nixbot@4a961da96:nixbot/nixbot/web/metrics.py:34-35`).

F8.
`niks3` by contrast registers real histograms for HTTP and GC duration alongside gauges for cache objects, logical bytes, pending closures and database connections, and counters for skipped paths and skipped NAR bytes (`Mic92/niks3@5476ddf07:server/metrics.go:22-38`).

F9.
Three of these endpoints are already publicly reachable over TLS with no authentication, because each service's vhost proxies `/` wholesale: gitea at `git.scientistexperience.net` (`cameronraysmith/vanixiets@da74672e5:modules/nixos/gitea.nix:131-134`), nixbot at `nixbot.scientistexperience.net` (`Mic92/nixbot@4a961da96:nixosModules/nixbot.nix:1213-1215`; `cameronraysmith/vanixiets@da74672e5:modules/nixos/nixbot.nix:81`), and niks3 at `niks3.scientistexperience.net` (`Mic92/niks3@5476ddf07:nix/nixosModules/niks3.nix:812-813`; `cameronraysmith/vanixiets@da74672e5:modules/nixos/niks3.nix:90-91`).

F10.
nixbot's upstream aggregates by status only and never labels by project precisely so that the unauthenticated endpoint leaks no private repository names, which is an upstream-declared containment property rather than an accident (`Mic92/nixbot@4a961da96:nixbot/nixbot/web/metrics.py:1-4`).

F11.
Host-level Linux signals need nothing new: the pinned nixpkgs ships exporter modules for `node`, `systemd`, `postgres`, `nginx`, `zfs`, `smartctl`, `process`, `script` and `json`, and `prometheus-node-exporter` is at 1.12.1 (`NixOS/nixpkgs@85f62611f:pkgs/by-name/pr/prometheus-node-exporter/package.nix:11`).

F12.
nix-darwin already ships a node-exporter module realized as `launchd.daemons.prometheus-node-exporter` running as a dedicated `_prometheus-node-exporter` user, so darwin node metrics require no bespoke unit (`nix-darwin/nix-darwin@4cff07de7:modules/services/monitoring/prometheus-node-exporter.nix:30`, `:98-119`).

F13.
That module removes `openFirewall`, `firewallFilter` and `firewallRules` with the message that no nix-darwin equivalent exists, so reachability on a darwin host is a network-topology question rather than a module option (`nix-darwin/nix-darwin@4cff07de7:modules/services/monitoring/prometheus-node-exporter.nix:24-26`).

F14.
The `systemd` exporter has no darwin counterpart: unit state, restart counts and timer last-success are Linux-only signals, and nix-darwin exposes launchd job state through no module at all.

F15.
launchd also lacks the aggregate limits whose breach is the Linux signal: this repository records that `NoNewPrivileges` has no launchd analogue and that `MemoryHigh` and `MemoryMax` have no process-tree equivalent, so per-process RSS is not a cgroup limit (`cameronraysmith/vanixiets@da74672e5:docs/notes/development/omnigent/deployment-plan.md:377-378`).

F16.
On darwin the consequential host signal is the unified log rather than a file: the syspolicyd Gatekeeper adjudication that this repository blames for a lockup is emitted by a system daemon and appears in no journald-shaped stream (`cameronraysmith/vanixiets@da74672e5:modules/devshells/default.nix:38-45`).

### SLO candidates derived from documented events

F17.
Evaluation queue wait: the audit measured fifteen evaluations in forty-five minutes, a ceiling of about twenty per hour, and states that a human pull request arriving behind one full automated cycle waits 3 h 08 m before its own evaluation begins (`cameronraysmith/vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:108-112`).
SLI: time from build row creation to `started_at`, available as `nixbot_builds_oldest_active_age_seconds` and `nixbot_queue_depth`.

F18.
Verdictless evaluation: build 168 consumed the full 3600 s timeout and then failed permanently, spending an hour of the sole evaluator to produce no verdict, and an eval-cgroup overrun raises `EvalOOMError` and fails the pull request outright (`:98`, `:55-57`).
SLI: fraction of evaluations terminating in timeout or `EvalOOMError`, from `nixbot_builds{status}`.

F19.
Substituter fan-out: about 85% of a healthy evaluation's wall clock is a single park on the nix-daemon socket, and an all-miss path costs roughly 1.27 s across the nine configured substituters (`:37`, `:44-47`).
SLI: per-endpoint narinfo miss latency and the daemon-socket wait share of `nixbot_eval_duration_seconds_sum`.

F20.
Pool starvation: on 2026-06-10 `/nix` consumed the entire 304 G pool and wedged every dataset, which is why the 250 G quota and the `/` and `/home` reservations exist (`cameronraysmith/vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:225-227`).
SLI: `zroot/root/nix` used against quota and free pool bytes, from the `zfs` exporter.

F21.
Orphaned sandboxes: a nix-daemon ENOSPC crash loop orphaned 201 sandboxes holding 232 GiB on 2026-06-10 under the 7 d default reaper, which the 1 d tmpfiles rule now overrides (`:321-326`).
SLI: count and bytes under `/nix/var/nix/builds` older than one day.

F22.
Root accumulation: 938 buildbot gcroots pinned the store in the 2026-06-10 incident, and output roots have no upstream expiry at all (`cameronraysmith/vanixiets@da74672e5:modules/nixos/buildbot.nix:206-210`).
SLI: gcroot count by family and age.

F23.
Dependent-unit permanent failure: on 2026-05-22 postgres panicked on ENOSPC and gitea hit systemd's default five-restarts-in-ten-seconds cap and was marked permanently failed, which is why `StartLimitIntervalSec` is zeroed and `RestartSec` forced to 30 s (`cameronraysmith/vanixiets@da74672e5:modules/nixos/gitea.nix:176-182`).
SLI: per-unit restart count and time in failed state, from the `systemd` exporter.

F24.
Maintenance-timer silence: `nix-gc` and `nix-optimise` fired on 63 of 63 retained journal days with real frees, and the audit names the journal's 2026-07-01 retention floor as the reason June cannot be proven either way (`docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:210-214`).
SLI: last-success age and bytes freed per run, which also removes the retention-window blind spot.

F25.
Readiness versus liveness: `omnigraph-server` opens every dataset before binding its listener and implements no `sd_notify` handshake, so systemd reports the unit active for that whole window while the port still refuses connections (`cameronraysmith/vanixiets@da74672e5:modules/nixos/omnigraph.nix:286-294`).
SLI: probe-confirmed readiness latency against the derived `TimeoutStartSec` budget.

F26.
Credential-rotation staleness: systemd snapshots `LoadCredential` at unit start, so a rotation without a restart leaves the running service holding the superseded value, which is why `restartUnits` names both `kanidm.service` and `matrix-synapse.service` (`cameronraysmith/vanixiets@da74672e5:modules/nixos/kanidm.nix:98-103`).
SLI: on-disk secret mtime against unit start time.

F27.
Gatekeeper adjudication storms: roughly twenty non-Apple binary execs per shell entry, across every worktree, contributed to a syspolicyd lockup; a minute-interval poll that began failing silently did the same on 2026-09-03; and a Sparkle auto-install on 2026-09-03 compounded a Logi Options+ lockup by forcing a full Gatekeeper re-assessment (`cameronraysmith/vanixiets@da74672e5:modules/devshells/default.nix:38-45`; `:modules/home/ai/moshi/default.nix:171-175`; `:modules/darwin/system-defaults/custom-user-prefs.nix:39-43`).
SLI: non-Apple exec adjudications per minute per darwin host, obtainable only from the unified log.

F28.
launchd slow respawn: with an unreadable token file the darwin worker launcher refuses to start and launchd respawns it every 30 s under `ThrottleInterval`, where the Linux unit would stop (`cameronraysmith/vanixiets@da74672e5:modules/home/ai/devin/worker.nix:49-57`).
SLI: per-job respawn rate and last exit status, for which no exporter exists.

F29.
Silent success: bun's fetch on linux-x64 hangs on keep-alive reuse to the Cloudflare API and wrangler exits 0 with no Worker Version ID produced and no error, diagnosed on 2026-04-22 (`cameronraysmith/vanixiets@da74672e5:modules/docs/deploy.sh:122-130`).
SLI: presence of a version identifier in the deploy result, because exit status is not evidence here.

F30.
Cache-invisible loss: niks3 counts store paths skipped for exceeding the maximum NAR size expressly so operators can see how much data never reaches the cache, and the audit's 29,244-path deduplicated union is what a cold evaluation then pays for (`Mic92/niks3@5476ddf07:server/skipped_uploads.go:14-15`; `docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:157`).
SLI: `skippedPaths` and `skippedNarBytes` rate against upload-queue depth.

F31.
Gate weakening: gitea-mq prefers the non-empty forge-required list, and the module states that an empty forge list must not silently weaken the landing gate, so the fallback list must match all three contexts (`cameronraysmith/vanixiets@da74672e5:modules/nixos/gitea-mq.nix:21-27`).
SLI: the required-context set observed at landing time, compared against the declared three.

F32.
Connection leak: the cognee role carries a 30 s `idle_in_transaction_session_timeout` as defense-in-depth against idle-in-transaction connection leaks, so the failure it guards is a known shape rather than a hypothesis (`cameronraysmith/vanixiets@da74672e5:modules/nixos/cognee.nix:209-222`).
SLI: idle-in-transaction session count and age, from the `postgres` exporter.

### Structurally unobservable from outside the machine

F33.
Four classes cannot be observed from a scrape or a log shipped off-host as configured today.
The darwin Gatekeeper lockup class (F27) lives in the unified log, which no journald-shaped pipeline reads, and a locked-up syspolicyd degrades the very exec path an exporter would need.
The activation-time modules `hm-sops-bridge` and `app` own no unit and no port, so their failures exist only in the deploying operator's terminal (F1 table).
`zerotier-mss-clamp` declares no nftables counters, so a clamp that stops matching presents as remote-host flakiness rather than as a local fault.
The silent-success and gate-weakening classes (F29, F31) are correctness failures whose processes exit 0, so no availability signal distinguishes them from success.

## Bearing on decisions

D3.
The evidence points toward a per-host agent on NixOS and a per-host agent on darwin rather than a scrape-only gateway, because two of the four unobservable classes are host-local log or exec phenomena that a central scraper cannot reach.
nix-darwin's existing node-exporter launchd daemon (F12) removes the main objection to putting an agent on the four darwin machines, but its removed firewall options (F13) mean reachability is a ZeroTier-topology decision.
This reverses if a unified-log source turns out to be absent from every pinned collector, in which case darwin telemetry degrades to node metrics plus launchd-agent file logs and the agent buys much less.

D4.
Scope should start from what already exists rather than from a semantic-convention wish list: three Prometheus endpoints are live today (F9), kanidm needs one config key for OTLP (table), and synapse, livekit and oauth2-proxy each need one option.
Cardinality is bounded on the metrics side by upstream choices already made for us: nixbot aggregates by status and never by project (F10), and omnigent deliberately uses low-cardinality route templates.
The gauge-only shape of nixbot's endpoint (F7) means any latency SLO stated as a percentile is unsatisfiable from that source, which is a schema constraint discovered from source rather than assumed; it reverses only if upstream adds histograms.

D5.
Dev-loop instrumentation is substantially already emitted rather than to be written: `nixbot_queue_depth`, `builds_oldest_active_age_seconds`, `eval_duration_seconds_*`, `work_queue*`, `effects*`, `scheduled_effect_lag_seconds` and `upload_queue_*` (F6) cover the three findings of the 2026-09-02 audit directly, and niks3 covers the cache side with histograms (F8).
The strongest argument for the store existing at all is F17 through F19: the audit's central numbers were obtained by hand, at the cost of a disclosed boundary breach, and are all now standing series.
This reverses only if scraping those endpoints proves to cost more than the aggregation cache absorbs, which upstream already mitigated with a 15 s cache.

D7.
Packaging work is smaller than the charter's W5 store question suggests on the emitter side: no exporter needs writing for Linux hosts, postgres, nginx, ZFS, GPU or the three native endpoints, and the only two packaging items are the omnigent and cognee `tracing` extras (table).
Placement is constrained by F20 through F22: `magnetite` is the host whose documented failures are storage-exhaustion failures, so a store co-located there must carry its own quota and reservation, not merely a retention policy.

D8.
Access control has an immediate finding independent of the store choice: three unauthenticated Prometheus endpoints are already public (F9), and only nixbot's is documented as deliberately label-sanitized (F10).
The gitea and niks3 endpoints have no such upstream statement, so gitea repository or user labels and niks3 cache inventory are currently world-readable pending a check of their label sets.
This is a tightening argument regardless of D1, and it reverses only if the label sets turn out to be aggregate-only on inspection.

## Flags

W3 is too strong as written.
No observability module, exporter, collector or dashboard exists in `modules/`, which is the claim's substance, but the fleet is not at zero emission: gitea's Prometheus endpoint is enabled in this repository's own configuration (table), and nixbot and niks3 ship native endpoints that our vhosts already expose publicly (F9).
The accurate statement is that the fleet has zero collection and three unintended public metrics endpoints.

Upstream-versus-configuration disagreement on gitea.
The nixpkgs module writes a metrics `TOKEN` only when `metricsTokenFile` is non-null, and this repository sets `metrics.ENABLED = true` without that file, so the practical effect of the enabling line is an unauthenticated endpoint rather than a protected one.
Nothing in the module's comment records that consequence.

The omnigent packaging gap contradicts an optimistic reading of upstream.
Upstream carries a first-class OTel metrics publisher and a periodic publish task, and its own comment notes that server performance metrics use the no-op API when tracing is off; this repository's derivation takes `opentelemetry-api` and none of the OTLP exporters, so the publisher is inert as deployed.

A2's regulator cannot resolve the nixpkgs citations as specified.
The repository's `nixpkgs` input is a tarball node from `releases.nixos.org`, not a git node, so `git cat-file -e` has no checkout to run in unless a nixpkgs clone is provisioned for the audit.

A4's regulator false-positives on this repository's own tree.
The pattern `/home/` matches every citation of a path under `modules/home/`, and F27 and F28 cite three such files, so a literal `/home/` grep flags repository-relative paths that contain no machine-local component.
The pattern needs anchoring to a leading slash at line start or to `/home/<user>` shapes, or A4 will reject correct artifacts.

Absences, reported explicitly.
There is no Prometheus or OTLP surface anywhere in buildbot-nix or gitea-mq, verified across both checkouts.
`coturn` and `docker` have no exporter in the pinned exporters tree.
node_exporter, livekit, coturn and act_runner are absent locally, so their darwin collector sets and their metrics flags were read from nixpkgs modules and not from upstream source.
The incident corpus contains exactly one note, so F20 through F24 draw on module comments and machine configuration for events the notes tree does not record.

## Questions

Q1.
Does any pinned collector read the macOS unified log?
F16 and F27 make the Gatekeeper class the highest-value darwin signal, and none of `opentelemetry-collector-contrib`, `vector` or `alloy` is present locally to check for a unified-log source, so this was not resolved by inference.

Q2.
Which collectors does node_exporter actually implement on aarch64-darwin at 1.12.1?
The nix-darwin module exists and accepts `enabledCollectors`, but the upstream collector matrix could not be read from source.

Q3.
Should the three already-public `/metrics` endpoints be closed behind the SSO gateway, moved to a ZeroTier-only listener, or left open because their label sets are aggregate-only?
This is an access decision with a live exposure attached, and it belongs to D8 rather than to this inventory.

Q4.
Are `cognee` and `k3s-server` intended to be deployed, or are they retained as unimported definitions?
Their rows are "no telemetry surface by non-deployment", and whether they enter the D4 scope depends on an intent this repository does not state.
