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

## Refresh (2026-10-15)

Sources for this section: `cameronraysmith/vanixiets@109c67346` (`main`), the root nixpkgs input node `nixpkgs_10` at `NixOS/nixpkgs@ac1faec44` (`nixos-26.11pre1086968`), `Mic92/nixbot@3c432d593`, `Mic92/gitea-mq@9bad60d8f`, `Mic92/nix-grpc-store@8d0368860`, `Mic92/niks3@2d5a6b14e`, `nix-community/harmonia@c1be8eba7`, `nix-community/srvos@2b29c5442`, `kanidm/kanidm@547933867` (tag `v1.11.2`), `omnigent-ai/omnigent@a8676d23e` (tag `v0.18.0`), `ModernRelay/omnigraph@1523b4ab4` (tag `v0.11.0`), `matrix-construct/tuwunel@7801b8ec6` (tag `v1.9.3`) and `NousResearch/hermes-agent@d97007c32`.
Every upstream revision above is the one this repository's `flake.lock` or `pkgs/by-name` derivation pins at `main`.
nixpkgs `master` at `NixOS/nixpkgs@fe1324228` carries the same `zerotierone` 1.16.0 and moves `matrix-tuwunel` only from 1.9.3 to 1.9.4, so no row below changes against `master`.

### What changed since the original findings

R1.
The root nixpkgs input moved from `85f62611f` to `ac1faec44`, and the node that `flake.lock` names for it is now `nixpkgs_10`.
Deployed versions at that pin, read by evaluating the machine configurations: gitea 28.0.0, matrix-synapse 1.162.0, PostgreSQL 16.15, kanidm 1.11.2 (`kanidmWithSecretProvisioning_1_11`), zerotierone 1.16.0, matrix-tuwunel 1.9.3, ntfy-sh 2.28.0, caddy 2.11.7 and dnsmasq 2.93 (`cameronraysmith/vanixiets@109c67346:modules/nixos/kanidm.nix:155`).

R2.
buildbot is disabled, not removed.
#3394 wraps the whole module in `lib.mkIf config.vanixiets.buildbot.enable`, which defaults to false, and keeps its generated vars, its PostgreSQL database and its CNAME (`cameronraysmith/vanixiets@109c67346:modules/nixos/buildbot.nix:17-20`, `:36-38`).
magnetite still imports the buildbot-nix master and worker modules and the `buildbot` flake module, so the definitions remain evaluated but produce no unit (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:35-36`, `:50`).

R3.
The sso-gateway is imported but disabled on magnetite with `sso.enable = false`, so the oauth2-proxy unit whose `--metrics-address` the original table listed does not run (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:133`; `:modules/nixos/sso-gateway.nix:365`).

R4.
nix-grpc-store is a new emitter class.
The `nix-builders` clan service runs `nix-grpc-daemon` on port 50051 on five builders: magnetite and pyrite bind `[::]:50051` behind a `zt+`-only firewall rule, and stibnite, rosegold and argentum bind their ZeroTier address because nix-darwin has no per-interface firewall (`cameronraysmith/vanixiets@109c67346:modules/clan/inventory/services/nix-builders.nix:29-90`; `:modules/clan/services/nix-builders/flake-module.nix:344-345`, `:355-359`).
Upstream ships a Prometheus `/metrics` listener behind `services.nix-grpc-daemon.metricsListen`, defaulting to null, and the same option is shared by the NixOS and darwin modules (`Mic92/nix-grpc-store@8d0368860:nixos/common.nix:77-82`).
The listener is a prometheus-cpp `Exposer` with no authentication of its own, separate from the mTLS gRPC port (`Mic92/nix-grpc-store@8d0368860:src/daemon/metrics.hh:257-261`).
Its series are counters by method and certificate CN, histograms for phase, queue and build-input durations, scheduler gauges and build failures by Nix failure status (`Mic92/nix-grpc-store@8d0368860:src/daemon/metrics.hh:26-82`; `:README.md:391-407`).
Upstream states that only CA-issued CNs appear as labels, so cardinality is bounded by the number of dispatcher certificates (`Mic92/nix-grpc-store@8d0368860:README.md:407`).
Independently of the listener, the daemon writes one logfmt line per RPC to stderr carrying CN, peer, duration and byte counts (`Mic92/nix-grpc-store@8d0368860:README.md:375-389`).
On magnetite and pyrite the evaluated `idleTimeout` is 600 s, which makes the daemon socket-activated and lets it exit when idle (`Mic92/nix-grpc-store@8d0368860:nixos/server.nix:11-13`); a scrape target there therefore disappears between builds and its counters restart from zero on each activation.
No machine sets `metricsListen` today, by evaluation of magnetite, pyrite and stibnite.

R5.
harmonia-gc replaced the nixpkgs and nix-darwin garbage collectors on every host, daily at 04:00 America/New_York with a 5 min jitter on NixOS and at 03:00 through `StartCalendarInterval` on darwin (`cameronraysmith/vanixiets@109c67346:modules/system/harmonia-gc.nix:13-34`).
It emits no metrics; its result is one plain-text line of paths deleted and bytes freed on stdout plus `tracing` events on stderr (`nix-community/harmonia@c1be8eba7:harmonia-store-gc/src/bin/harmonia-gc.rs:208-211`, `:335-342`).
On NixOS that output reaches journald through the `harmonia-gc` oneshot unit (`nix-community/harmonia@c1be8eba7:nix/module.nix:238-248`).
On darwin the launchd daemon declares no `StandardOutPath` or `StandardErrorPath` in upstream or in this repository, by evaluation of stibnite, so its report is discarded (`nix-community/harmonia@c1be8eba7:nix/darwin-module.nix:40-52`).
harmonia's binary-cache server does carry a Prometheus dependency, but neither `services.harmonia-dev.cache` nor `services.harmonia-dev.daemon` is enabled on any evaluated machine (`nix-community/harmonia@c1be8eba7:harmonia-cache/Cargo.toml:54`).

R6.
gitea-mq now carries a local settle-window patch, and still exposes no metrics at the new pin (`cameronraysmith/vanixiets@109c67346:modules/nixos/gitea-mq.nix:88`).
It logs through `slog.NewTextHandler` to stderr, so its journald lines are `key=value` structured text (`Mic92/gitea-mq@9bad60d8f:cmd/gitea-mq/main.go:52-54`).
The patch adds `batch_settle` and `batch_settle_max` to the startup line and a debug-level `batch settling` line with branch and queue length (`cameronraysmith/vanixiets@109c67346:modules/nixos/gitea-mq-batch-settle.patch`).
Its HTTP mux serves `/healthz` and an HTML queue dashboard at `/` with no authentication, and the vhost `mq.scientistexperience.net` proxies `/` wholesale (`Mic92/gitea-mq@9bad60d8f:cmd/gitea-mq/main.go:174-195`; `cameronraysmith/vanixiets@109c67346:modules/nixos/gitea-mq.nix:107-110`).
Queue state is otherwise reachable only as rows in its `gitea-mq` PostgreSQL database.

R7.
nixbot moved 43 commits to `3c432d593`, and `metrics.py` is byte-identical between the two pins, so F6, F7 and F10 stand unchanged (`Mic92/nixbot@3c432d593:nixbot/nixbot/web/metrics.py:1-4`, `:167-169`).
The three local patches (`abandon-optional-attributes`, `gated-reuse-effects-summary`, `ignore-failure-dependents`) contain no metrics change.
The upstream vhost still proxies `/` wholesale to the web socket (`Mic92/nixbot@3c432d593:nixosModules/nixbot.nix:1255-1257`).
The evaluation is now sized `6 x 3072` MiB under `MemoryHigh = "20G"` (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot.nix:135-136`, `:224`).

R8.
niks3 moved 159 commits to `2d5a6b14e`; `/metrics` is still registered on the main mux without an auth wrapper and the vhost still proxies `/` (`Mic92/niks3@2d5a6b14e:server/server.go:336`; `:nix/nixosModules/niks3.nix:909-910`).
New series since the original pin: `niks3_gc_runs_total`, `niks3_gc_objects_deleted_total`, `niks3_gc_last_run_timestamp_seconds`, a `niks3_commit_duration_seconds` histogram and `niks3_commit_objects_total` (`Mic92/niks3@2d5a6b14e:server/metrics.go:94-126`).

R9.
kanidm 1.11.2 still accepts `otel_grpc_endpoint` and this repository still leaves it unset (`kanidm/kanidm@547933867:server/core/src/config.rs:349`).

R10.
omnigent is packaged at 0.18.0 and the derivation still takes `opentelemetry-api` without the SDK or any OTLP exporter (`cameronraysmith/vanixiets@109c67346:pkgs/by-name/omnigent/package.nix:8`, `:70`).
Upstream 0.18.0 creates OTel counters and histograms for database retries and skill invocations, and selects the `otlp` metrics exporter only when `OTEL_EXPORTER_OTLP_ENDPOINT` is set (`omnigent-ai/omnigent@a8676d23e:omnigent/db/metrics.py:46-47`; `:omnigent/runtime/skill_metrics.py:53-59`; `:omnigent/runtime/telemetry.py:985-987`).
The SDK and exporters ship in the upstream `all` and `tracing` extras (`omnigent-ai/omnigent@a8676d23e:pyproject.toml:148-155`, `:217`).
The server runs on magnetite at `127.0.0.1:6767` behind `omni.scientistexperience.net`, and hosts run on magnetite, pyrite and stibnite (`cameronraysmith/vanixiets@109c67346:modules/nixos/omnigent.nix:31`, `:126`, `:171`; `:modules/clan/inventory/services/omnigent.nix:47-101`).
Each NixOS worker is its own systemd unit `omnigent-host-<name>`, and magnetite runs the `cameron` and `janettesmith` workers (`cameronraysmith/vanixiets@109c67346:modules/nixos/omnigent-host.nix:337`).
On darwin each worker's launchd job writes stdout and stderr to a `service.log` file under that worker's home directory rather than to the unified log (`cameronraysmith/vanixiets@109c67346:modules/darwin/omnigent-host.nix:453-454`).

R11.
omnigraph is packaged at 0.11.0 and still has no metrics endpoint and no OTLP layer: the server installs `tracing_subscriber::fmt` and wraps the router in tower-http's `TraceLayer` (`ModernRelay/omnigraph@1523b4ab4:crates/omnigraph-server/src/lib.rs:1839`, `:1990-1992`).
It now serves unauthenticated `/healthz` and `/readyz` outside the bearer-auth layer, bound to magnetite's ZeroTier address on port 8090 (`ModernRelay/omnigraph@1523b4ab4:crates/omnigraph-server/src/lib.rs:1986-1989`; `cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:406-407`).

R12.
cinnabar's services were absent from the original table.
tuwunel's OTLP export sits behind the `perf_measurements` Cargo feature, which the nixpkgs build does not enable, so it emits journald logs only (`matrix-construct/tuwunel@7801b8ec6:src/main/Cargo.toml:166-172`).
hermes-agent's OTLP gateway-health export needs the `otlp` extra, which upstream keeps out of `all` and lazy-installs at runtime, and this repository's clan service adds no extra (`NousResearch/hermes-agent@d97007c32:pyproject.toml:425-432`).
ntfy serves Prometheus metrics only when `enable-metrics` or `metrics-listen-http` is set, and this repository sets neither (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/cinnabar/ntfy.nix:4-9`; https://docs.ntfy.sh/config/ (fetched 2026-10-15)).
caddy serves Prometheus metrics on its admin endpoint `localhost:2019/metrics` only when the Caddyfile's global options enable `metrics`, and cinnabar's global config sets only a log level (https://caddyserver.com/docs/metrics (fetched 2026-10-15)).
dnsmasq serves `.zt` DNS on cinnabar's ZeroTier addresses and has no native exporter; the root nixpkgs ships an exporter module `prometheus.exporters.dnsmasq` and the package `prometheus-dnsmasq-exporter` 0.3.0 (`cameronraysmith/vanixiets@109c67346:modules/machines/nixos/cinnabar/zt-dns.nix:20`; `NixOS/nixpkgs@ac1faec44:nixos/modules/services/monitoring/prometheus/exporters/dnsmasq.nix`).
openclaw is disabled on cinnabar (`cameronraysmith/vanixiets@109c67346:modules/clan/inventory/services/openclaw.nix:13`).

R13.
zerotierone is an emitter on every NixOS machine by default.
ZeroTier documents that versions 1.14.0 through 1.16.0 enable metrics by default at `http://localhost:9993/metrics`, authenticated by a bearer token in `metricstoken.secret`, and also write them to `metrics.prom` in the ZeroTier home directory; from 1.16.1 the default is off and `allowMetrics` in `local.conf` turns it on (https://docs.zerotier.com/metrics-monitoring/ (fetched 2026-10-15)).
magnetite and cinnabar evaluate to zerotierone 1.16.0 with a `localConf` that does not set `allowMetrics`.
The series include `zt_peer_latency` as a histogram labelled by node ID, which is bounded by fleet size.
The darwin machines run an externally installed zerotier-one whose version this repository does not pin (`cameronraysmith/vanixiets@109c67346:modules/clan/inventory/services/zerotier.nix:15`, `:26`).

R14.
nginx on magnetite already serves `stub_status` at `http://127.0.0.1/nginx_status`, because the srvos nginx mixin sets `statusPage` by default (`nix-community/srvos@2b29c5442:nixos/mixins/nginx.nix:12`; `NixOS/nixpkgs@ac1faec44:nixos/modules/services/web-servers/nginx/default.nix:1544-1546`).

R15.
PostgreSQL on magnetite listens on `localhost` only and serves six databases: `gitea`, `niks3`, `nixbot`, `gitea-mq`, `omnigent` and `matrix-synapse`, by evaluation of `services.postgresql`.
No PostgreSQL exporter is configured; the root nixpkgs ships `prometheus-postgres-exporter` 0.20.1.

R16.
The incident corpus now holds two notes.
The new note records two host-wide kernel OOMs on magnetite, on 2026-09-27 and 2026-10-01, each caused by nixbot's evaluation overlapping a second `nix-eval-jobs` evaluation until RAM and zram were both full (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:5-6`, `:32`).
The OOM killer took roughly 47 processes on 2026-09-27, including nix-daemon workers and processes from an interactive session, before it reached an evaluator (`:36`).
The mitigations are a host-wide evaluation lock and MGLRU thrash protection, and `MemoryLow` floors for sshd, postgresql, kanidm, nginx and nix-daemon are recorded as deferred to a second phase (`:58-76`, `:84`).

### Updated emitter table (main at `109c67346`)

Rows the original table carries for gitea-actions-runner, docker, livekit, coturn, nvidia, cognee, k3s-server, hm-sops-bridge, app and zerotier-mss-clamp are unchanged and are not repeated; docker's evaluated `metrics-addr` is still null.

| Service | Host | Endpoint | Protocol | Auth | Notes |
|---|---|---|---|---|---|
| gitea 28.0.0 | magnetite | `127.0.0.1:3002/metrics`; public at `git.scientistexperience.net/metrics` | Prometheus | none; `metricsTokenFile` unset | `NixOS/nixpkgs@ac1faec44:nixos/modules/services/misc/gitea.nix:717`; `cameronraysmith/vanixiets@109c67346:modules/nixos/gitea.nix:102`, `:107-111` |
| nixbot | magnetite | `/run/nixbot/web.sock` `/metrics`; public at `nixbot.scientistexperience.net/metrics` | Prometheus, gauges only, 15 s cache | none, by upstream design | R7 |
| niks3 | magnetite | `127.0.0.1:5752/metrics`; public at `niks3.scientistexperience.net/metrics` | Prometheus with histograms | none | R8 |
| gitea-mq | magnetite | `127.0.0.1:8092` `/healthz` and HTML dashboard; public at `mq.scientistexperience.net` | no metrics; `key=value` text logs to journald | none | R6 |
| nix-grpc-daemon | magnetite, pyrite (`[::]:50051`, `zt+` only, socket-activated); stibnite, rosegold, argentum (ZeroTier address) | `/metrics` on `metricsListen`, unset on every host | Prometheus when set; logfmt access log per RPC always | none on the metrics listener; mTLS on gRPC | R4 |
| harmonia-gc | every NixOS and darwin machine | none | plain-text result line plus `tracing` text | not applicable | darwin output discarded; R5 |
| kanidm 1.11.2 | magnetite | `127.0.0.1:8443` behind nginx | OTLP gRPC available, `otel_grpc_endpoint` unset | not applicable | R9 |
| matrix-synapse 1.162.0 | magnetite | `127.0.0.1:8008` | Prometheus available; evaluated `enable_metrics = false` | not applicable | original row stands |
| sso-gateway (oauth2-proxy) | magnetite | none; `sso.enable = false` | none running | not applicable | R3 |
| omnigraph 0.11.0 | magnetite | ZeroTier address `:8090` `/healthz`, `/readyz` | journald `tracing` text including tower-http request spans; no metrics | none on health routes; bearer elsewhere | R11 |
| omnigent server 0.18.0 | magnetite | `127.0.0.1:6767` behind `omni.scientistexperience.net` | OTLP traces and metrics in code, inert as packaged | not applicable | R10 |
| omnigent-host workers | magnetite, pyrite (systemd `omnigent-host-<name>`); stibnite (launchd) | none | journald on NixOS; a per-user `service.log` file on darwin; OTLP inert | not applicable | R10 |
| PostgreSQL 16.15 | magnetite | `localhost:5432` and unix socket | journald logs; no exporter configured | not applicable | R15 |
| nginx | magnetite | `http://127.0.0.1/nginx_status` | `stub_status` text, scrapable by `prometheus.exporters.nginx` | loopback only | R14 |
| zerotierone 1.16.0 | every NixOS machine; darwin externally installed | `localhost:9993/metrics` and `metrics.prom` file | Prometheus | bearer token `metricstoken.secret` | on by default at 1.16.0 only; R13 |
| tuwunel 1.9.3 | cinnabar | `[::1]:8008` and `127.0.0.1:8008` behind caddy `matrix.zt` | journald logs only | not applicable | R12 |
| hermes-agent | cinnabar | dashboard `127.0.0.1:18790` behind caddy `hermes.zt` | OTLP/HTTP gateway-health export needs the unpackaged `otlp` extra | not applicable | R12 |
| ntfy-sh 2.28.0 | cinnabar | `[::1]:2586` behind caddy `ntfy.zt` | Prometheus available, unset | not applicable | R12 |
| caddy 2.11.7 | cinnabar | admin `localhost:2019/metrics` | Prometheus available behind global `metrics`, unset | admin endpoint loopback | R12 |
| dnsmasq 2.93 | cinnabar | ZeroTier addresses `:53` | none native; nixpkgs exporter module exists | not applicable | R12 |
| buildbot | magnetite | none; `vanixiets.buildbot.enable = false` | none running | not applicable | R2 |

### Corrections

C1.
Supersedes F2 and the buildbot row of the original table.
buildbot is disabled behind `vanixiets.buildbot.enable` and runs no unit, while its module, vars and database are retained (R2).
F22's gcroot SLI therefore has no live source, although the retained buildbot gcroots remain on disk until removed.

C2.
Supersedes the sso-gateway row of the original table and the D4 sentence that oauth2-proxy needs one option.
The gateway is disabled, so its metrics listener is not available without first enabling the gateway (R3).

C3.
Supersedes the claim in "Absences, reported explicitly" that the gitea-mq checkout has no Prometheus or OTLP surface, by narrowing it.
That remains true at `9bad60d8f`, but gitea-mq is not silent: it emits structured `key=value` logs and serves an unauthenticated public `/healthz` and HTML dashboard (R6).

C4.
Supersedes F24's reliance on `nix-gc` and `nix-optimise` timers.
Garbage collection is now harmonia-gc on every host, its bytes-freed signal is a single text line in journald on NixOS, and on darwin the line is discarded (R5).

C5.
Supersedes D7's statement that the omnigent `tracing` extra is one of only two packaging items.
At 0.18.0 the SDK and OTLP exporters live in the `all` and `tracing` extras, and hermes-agent's `otlp` extra is a third packaging item for any agent-side OTLP (R10, R12).

C6.
Supersedes the claim that the fleet has exactly three metrics endpoints emitting today.
At `main` the three public endpoints remain, and two further emitters are live without any repository change: zerotierone's token-authenticated loopback `/metrics` on every NixOS machine and nginx's loopback `stub_status` on magnetite (R13, R14).

C7.
Supersedes "The incident corpus contains exactly one note".
It holds two, and the second records memory exhaustion on magnetite rather than storage exhaustion (R16).

C8.
Supersedes the `nixpkgs@85f62611f` citations of the original findings for every version-dependent claim; the root input is now `nixpkgs_10` at `ac1faec44` (R1).

### Reconciliation with the charter

W1 needs updating.
magnetite is still a Hetzner `cx53`, declared as 16 vCPU, 32 GB RAM and 320 GB SSD, and the 2026-10-01 note measures 30.6 GiB of usable RAM (`cameronraysmith/vanixiets@109c67346:modules/terranix/hetzner.nix:24-30`; `:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:12`).
Its running set is now Kanidm, matrix-synapse with LiveKit and coturn, Gitea, gitea-actions-runner, docker, nixbot, gitea-mq, niks3, the omnigent server and two omnigent-host workers, omnigraph, nix-grpc-daemon, nginx and PostgreSQL; buildbot is disabled, not running.
cinnabar, a Hetzner `cx43` declared as 8 vCPU and 16 GB RAM, runs tuwunel, hermes-agent, ntfy, caddy, dnsmasq and the ZeroTier controller (`cameronraysmith/vanixiets@109c67346:modules/terranix/hetzner.nix:10-16`).
The inventory is still ten machines.

W2 is now confirmed by two incidents rather than one.
The 2026-09-02 audit and the 2026-06-10 events were storage exhaustion; the 2026-09-27 and 2026-10-01 events were whole-host memory exhaustion (R16).

W3 holds for collection and is too weak for emission.
Nothing is collected, but beyond the three public endpoints zerotierone and nginx already emit on loopback, and nix-grpc-store, kanidm, synapse, ntfy and caddy each need one option (C6, table).

RK3 has fired for memory.
Its confirming observation is that incident notes record saturation on the resources a store needs, and the 2026-10-01 note records RAM and zram both exhausted with the kernel OOM killer taking roughly 47 processes across services (R16).
The current evaluator sizing leaves about 8 GB free at its measured 18.7 GB peak, which is the headroom a co-located store would draw on during an evaluation (`cameronraysmith/vanixiets@109c67346:modules/nixos/nixbot.nix:113-133`).
No `MemoryLow` floor protects any service today, so a store process would be an ordinary OOM candidate alongside PostgreSQL and kanidm (R16).
Disabling buildbot removes its master and worker from the host, but no measurement of the freed memory exists in the repository.

### Questions

Q5.
Should `metricsListen` be set on the nix-grpc-daemon builders, and if so should magnetite's daemon stop exiting after 600 s idle so that its counters persist between builds?

Q6.
Should the collector read zerotierone's bearer-token endpoint or its `metrics.prom` file, and should `allowMetrics` be set explicitly now so that an upgrade past 1.16.0 does not silently turn the emitter off?

Q7.
Does the unauthenticated public gitea-mq dashboard, which shows pull-request titles and authors for the queued repositories, belong to the D8 access decision alongside the three `/metrics` endpoints?

Q8.
Given RK3 firing for memory, should a GreptimeDB unit on magnetite carry an explicit `MemoryLow`, `MemoryMax` and `OOMScoreAdjust` as a condition of placement, or should the deferred phase-two floors for the existing services land first?

Q9.
Should darwin's harmonia-gc launchd daemon be given a `StandardOutPath` so that its bytes-freed result is recorded on darwin, where argentum reached 235 MB free on 2026-10-07 (`cameronraysmith/vanixiets@109c67346:modules/darwin/nix-settings.nix:62`)?
