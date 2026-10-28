---
title: "fleet-alert"
---

## Purpose

fleet-alert turns fleet conditions into human notifications (ADR-009 Decision).
It is one first-party rule evaluator, a systemd timer on `magnetite` that queries the store's Prometheus API and posts deduplicated firing and recovery messages to the existing ntfy on `cinnabar`, watched by a dead-man timer on `cinnabar` (ADR-009 Decision).
It also carries the delivery side of ADR-003's unit-failure notifier `observability-notify@%n.service`, whose topic, authentication and deduplication ADR-009 defines (ADR-003 Operating envelope and regulator; ADR-009 Decision item 11).
No new long-running process and no new listener are added (ADR-009 Decision, Implementation surface).

## Decisions realized

- ADR-009 Decision item 1 and Q1: a first-party timer evaluator, `fleet-alert.timer` every 60 s starting the oneshot `fleet-alert.service`, instead of vmalert and Alertmanager.
- ADR-009 Decision items 2 and 3: rules are declared once in Nix as Prometheus-format alerting rules with Prometheus semantics, resolving after the condition has been absent for 5 min.
- ADR-009 Decision item 4 and Q7: one `FIRING` and one `RESOLVED` per instance, a `critical` instance re-posted once per 24 h, a `warning` instance never re-posted, and an `info` instance with no `RESOLVED`.
- ADR-009 Decision item 5: memory and OOM messages carry attribution by the three executables with the largest resident memory, the host's ZFS ARC size and its swap used.
- ADR-009 Decision items 6, 7 and 17: the store freeze (`StoreQueryFailing`), the signal-presence check (`RuleSignalMissing`) and the per-host absence freeze.
- ADR-009 Decision items 8 and 9: the `fleet-heartbeat` heartbeat and the `fleet-deadman.timer` dead-man on `cinnabar` raising `AlertEvaluatorSilent`.
- ADR-009 Decision item 10: delivery to `fleet-alerts` at `https://ntfy.zt` through `ntfy-send` built from its existing script, with the `alerter` token passed through `NTFY_TOKEN_FILE` and never on a command line.
- ADR-009 Decision item 11 and ADR-003 Q9: `observability-notify@%n.service`, the module `flake.modules.nixos.observability-notify`, posts to `fleet-alerts` once per failure episode with a recovery message and logs each posted `FAILED` for R9.1.
- ADR-009 Decision items 12 and 13 and Q8: one new ntfy user `alerter` publishes on `fleet-*`, `auth-default-access` stays `read-write` for every other topic, ntfy rate-limits each mesh client as its own visitor, a flake check validates the provisioning strings, and the cutover takes three deploys.
- ADR-009 Q2: the `fleet-alerts` subscribers are the human's phone and desktop, subscribing anonymously with read-only access.
- ADR-009 Decision item 14: the weekly end-to-end test `WeeklyPipelineTest`.
- ADR-009 Decision item 15 and Q6: one dev-loop rule, slice S2's 24 h slow-burn `warning` when more than 10% of pull-request builds in the trailing 24 h waited over 1 h to start, above a minimum build count, and no other CI or merge-queue rule (charter v22).
- ADR-009 Decision item 16 and Q9: host absence alerts only through `RuleSignalMissing` for a host on the evaluator's always-on list, magnetite and cinnabar from S4, which a host joins only by an edit of `flake.lib.observabilityHosts` when it becomes permanently provisioned, and never for stibnite, pyrite or a cloud host provisioned on demand; ADR-003's R3.2 has no per-host last-seen clause (charter v23).
- ADR-009 Q10: `LaunchdJobFailed` fires on any non-zero last exit code of an allow-listed job, as a single-shot `warning`.
- ADR-009 Q4: the noise envelope E9.1 of 10 firings per 24 h, at most 3 from any one laptop, for the first month.
- ADR-007 Decision (credentials): the evaluator reads the store as the read-only `regulator` store user.
- ADR-003 Operating envelope and regulator: the `observability-notify@` template unit is the only path from a failed observability regulator or oneshot unit to a human.

The human gate of 2026-10-15 accepted the recommended answer of every ADR-009 question except Q5, which is deferred (see Deferred).

## Placement

- `magnetite`: `fleet-alert.timer` and `fleet-alert.service`, with `StateDirectory = "fleet-alert"` holding `/var/lib/fleet-alert/state.json` (ADR-009 Decision items 1 and 4, Implementation surface).
- `cinnabar`: `fleet-deadman.timer` and `fleet-deadman.service`, with `StateDirectory = "fleet-deadman"` holding `/var/lib/fleet-deadman/state.json` (ADR-009 Decision item 9, Implementation surface).
- `cinnabar`: the existing ntfy-sh 2.28.0 on `[::1]:2586` behind caddy as `https://ntfy.zt` (`cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/cinnabar/ntfy.nix:4-9`, `cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/cinnabar/caddy.nix:29-32`).
- Every in-scope NixOS host, `cinnabar` included: the `observability-notify@` template unit in the module `flake.modules.nixos.observability-notify`, which the `agent` role of the `otel-collector` clan service imports and `cinnabar` imports directly from S3, before it runs a collector in S4; it calls `ntfy-send` against `ntfy.zt` and keeps per-unit stamp files and a log of posted `FAILED` messages under `/var/lib/observability-notify` (ADR-003; ADR-009 Decision item 11).
- Store account: the GreptimeDB user `regulator` with mode `ro` (ADR-007 Decision; ADR-009 Decision item 1).
- ntfy account: the ntfy user `alerter`, the only publisher on `fleet-*` topics (ADR-009 Decision item 12).
- Module: `flake.modules.nixos.fleet-alert` with options `services.fleet-alert.evaluator`, enabled on `magnetite`, and `services.fleet-alert.deadman`, enabled on `cinnabar` (ADR-009 Implementation surface).

## Interfaces

- Upstream (store): PromQL instant queries to `http://127.0.0.1:4000/v1/prometheus/api/v1/query` against the `fleet` database as the `regulator` store user, with a 10 s per-query timeout (ADR-009 Decision item 1; `GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:1350-1351`); from S2 each rule declares its `database` and `language`, and SQL rules, such as the dev-loop rule over `devloop`, go to `/v1/sql` (ADR-009 Decision items 1 and 15, charter v22).
- Signal names are ADR-003's and ADR-004's as PromQL-visible in the `fleet` database, where the agent-stamped `host.name` appears as the label `host_name` (ADR-009 Decision, Initial rule set).
- Downstream (delivery): HTTPS publish to the ntfy topic `fleet-alerts` at `https://ntfy.zt`, titled `[FIRING|RESOLVED] <alert> <host>`, with ntfy priority `high` for `critical`, `default` for `warning` and `low` for `info` (ADR-009 Decision item 10).
- Client: `pkgs.ntfy-send`, the `pkgs/by-name/ntfy-send` package slice S1 adds from the existing `ntfy-send.sh`, with the title and priority passed as curl `-H` arguments and the `alerter` token read from the file named by `NTFY_TOKEN_FILE`, which curl receives as an `Authorization: Bearer` header from a file or stdin rather than its argument list, inheriting the helper's `curl -sfk -m 5` convention for caddy's internal TLS (ADR-009 Decision item 10, Delivery evidence).
- Heartbeat: every completed evaluation, including one that raised `StoreQueryFailing`, publishes a minimum-priority message to the ntfy topic `fleet-heartbeat` (ADR-009 Decision item 8).
- Dead-man poll: `fleet-deadman.service` polls `http://[::1]:2586/fleet-heartbeat/json?poll=1&since=10m` on `cinnabar` (ADR-009 Decision item 9).
- Dead-man precondition: before polling, `fleet-deadman.service` performs an anonymous publish to `fleet-heartbeat` on `[::1]:2586` and fails if it is accepted (ADR-009 Operating envelope R9.4).
- Unit-failure input: units with `OnFailure=observability-notify@%n.service` post one message per failure episode, and each notified unit's `ExecStartPost=` and `ExecStopPost=` hooks post one `RESOLVED` and remove the stamp when the unit next starts or exits successfully, so an episode also ends after an automatic restart; a per-unit `last-failed` timestamp suppresses a new episode's `FAILED`, and its `RESOLVED`, within 15 minutes of the last posted `FAILED`, so a persistent crash loop yields one pair, then at most one new pair per 15 minutes per unit, and restart-rate detection is `SystemdUnitRestartLoop`'s (ADR-009 Decision item 11).
- Units notified through `observability-notify@`: `otel-envelope` (ADR-003), `devloop-reconcile` (ADR-005), `greptimedb-envelope`, `greptimedb-export` and `greptimedb-schema` (ADR-007), `fleet-alert` and `fleet-deadman` (ADR-009), magnetite's six existing `zfs-assert-*` and `zfs-set-*` oneshots (`modules/machines/nixos/magnetite/default.nix:193-263`) and ADR-007's three new `greptimedb` dataset oneshots (ADR-003; ADR-009 Decision item 11).
- ntfy access: `auth-access` grants `alerter:fleet-*:rw` and `*:fleet-*:ro`, so anonymous mesh members, including phones, can subscribe but cannot publish to `fleet-alerts` or `fleet-heartbeat` (ADR-009 Decision item 12).
- ntfy rate limiting: `behind-proxy: true`, `proxy-trusted-hosts` set to caddy's `::1` and `visitor-prefix-bits-ipv6: 128`, so each mesh client is its own visitor even though every ZeroTier member shares one /64, and no host is exempt (ADR-009 Decision item 12, Delivery evidence).
- Message content: host, unit, mountpoint, pool and process names, and no agent or user content, readable by every mesh member including the two Android members (ADR-009 Consequences; ADR-008).
- Store upstream: `components/greptimedb.md`; signal producers: `components/otel-collector.md` and `components/host-probes.md`.
- Credentials consumed:
  - `regulator-password` of the `greptimedb-users` generator of ADR-007, delivered to `fleet-alert.service` through `LoadCredential`; it needs no `restartUnits` because its consumers are timer-driven oneshots that load it at each start (ADR-007 Decision; ADR-009 Decision item 13, Implementation surface).
  - `token` of the `ntfy-alerter` generator, delivered through `LoadCredential` to magnetite's evaluator, to the `observability-notify@` template unit and to cinnabar's dead-man; the notifier's `ExecStartPost=` and `ExecStopPost=` resolve hooks run as root inside each notified unit and read the token's clan vars path through `NTFY_TOKEN_FILE` (ADR-009 Decision items 11 and 13).
  - `ntfy-env` of the per-machine `ntfy-alerter-env` generator on `cinnabar`, consumed by ntfy through `services.ntfy-sh.environmentFile` as `NTFY_AUTH_USERS` and `NTFY_AUTH_TOKENS` (ADR-009 Decision item 13, Implementation surface).

### Initial rule set

The table is ADR-009's initial rule set.
`<kept-alive labels>` is the set of allow-listed labels whose evaluated `KeepAlive` is `true`, rendered from `schema.nix` (ADR-004).
`<notified units>` is the set of units named in `services.observability-notify.units`, so `SystemdUnitFailed` never repeats a failure the notifier reports (ADR-009 Decision, Rationale).
Slice S3 ships `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown` and `WeeklyPipelineTest`, whose signals S1 already stores in `fleet`, with the internal `StoreQueryFailing`, `RuleSignalMissing` and `AlertEvaluatorSilent`; the filesystem, NVMe, launchd and `HostProbeStale` rules land with S4 and S5, which bring their series (ADR-009 Decision).

| Rule | Signal (PromQL) | Threshold | For | Severity | Failure it prevents |
|---|---|---|---|---|---|
| `HostMemoryPressure` | `((sum by (host_name) (system_linux_memory_available_bytes) + sum by (host_name) (node_zfs_arc_size - node_zfs_arc_c_min)) / (sum by (host_name) (system_memory_usage_bytes{state="used"}) + sum by (host_name) (system_linux_memory_available_bytes)) < 0.10) or (sum by (host_name) (system_paging_usage_bytes{state="used"}) / sum by (host_name) (system_paging_usage_bytes) > 0.85)`; the denominator is `used` plus available memory because, queried on magnetite on 2026-10-18, that sum returned 32860241920 bytes, exactly `MemTotal`, while the sum over all six `state` values counts reclaimable slab twice and returned 42.44 GB | available below 0.10, or swap used above 0.85 | 5 min | warning | the 2026-09-27 and 2026-10-01 OOM build-up on magnetite, which filled RAM and zram together, passes unseen, with no record of which process was growing |
| `HostOOMKill` | `increase(node_vmstat_oom_kill[10m]) > 0`; the comparison is part of the expression because, queried on magnetite on 2026-10-18, the bare `increase` returned one series of value 0, and the evaluator treats every returned series as firing | above 0 | 0 | critical | an OOM kill on any host, including on magnetite the kills ADR-007 orders as the nixbot evaluator at `oom_score_adj` 900, then the store at 500, then the `ingress` collector at 300, is noticed only by its downstream effects |
| `FilesystemFillingWarn` | `sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes) > 0.85` | above 0.85 | 15 min | warning | magnetite's pool or a quota-bounded dataset fills, the 2026-06-10 storage starvation, or stibnite's APFS container, reported at `/System/Volumes/Data` and holding its `/nix`, fills |
| `FilesystemFull` | `sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes) > 0.95` | above 0.95 | 5 min | critical | writes fail on `/nix`, `/`, `/home` or `/var/lib/greptimedb`, or on stibnite's Nix store and user data |
| `ZfsPoolUnhealthy` | `node_zfs_zpool_state{state!="online"} == 1` | any series | 1 min | critical | a degraded, faulted, suspended or unavailable `zroot` on any NixOS host runs on until the next failure loses data |
| `NvmeCriticalWarning` | `smartctl_device_critical_warning != 0` on pyrite and stibnite | not 0 | 0 | critical | a laptop's NVMe reports spare exhaustion, temperature, read-only or reliability degradation and the laptop loses data without warning |
| `NvmeWearHigh` | `smartctl_device_percentage_used > 90` on pyrite and stibnite | above 90 | 1 h | warning | a laptop's SSD reaches rated endurance without a replacement planned |
| `SystemdUnitRestartLoop` | `increase(systemd_service_restarts_total[15m]) > 5`; the comparison is part of the expression because, queried on magnetite on 2026-10-18, the bare `increase` returned 27 series, one per unit, all of value 0 | above 5 | 0 | warning | the 2026-10-15 overnight loop of about 3,200 `omnigent-host` restarts on magnetite |
| `SystemdUnitFailed` | `systemd_unit_state{systemd_unit_active_state="failed", systemd_unit_name!~"(<notified units>)[.]service"} == 1`; the literal dot is `[.]` because, queried on magnetite on 2026-10-18, GreptimeDB 1.2.1 rejected `\.` with `unknown escape sequence '.'` in both double-quoted and backtick strings, and `[.]` needs no escape in PromQL, JSON or YAML | any series | 5 min | warning | an allow-listed service stops and stays stopped with nobody told, outside the units ADR-003's notifier already covers |
| `LocalExporterDown` | `up{job=~"node\|smartctl"} == 0`, with presence selector `up{job="node"}`, because, queried on magnetite on 2026-10-18, bare `up` carried six jobs and so stays present when the `node` job disappears | any series | 10 min | warning | one host's loopback exporter dies and that host's OOM, ZFS, SMART or launchd rules go blind while the fleet-wide presence check stays satisfied |
| `LaunchdJobNotRunning` | `launchd_job_state{launchd_state="running", launchd_label=~"<kept-alive labels>"} == 0` | any series | 10 min | warning | a kept-alive darwin job such as `org.nixos.nix-daemon` or `org.nixos.nix-grpc-daemon` is stopped or unloaded, as a store-path job started before the Nix store mounted stays inactive (`cameronraysmith/vanixiets@eee06596a:modules/darwin/launchd-wait4path.nix:1-5`) |
| `LaunchdJobFailed` | `launchd_job_last_exit_code != 0` | any series | 5 min | warning | the 2026-10-15 exit 78 of `org.nixos.omnigent-host-cameron` on stibnite, or a failed `harmonia-gc` run, passes unnoticed |
| `LaunchdJobRestartLoop` | `increase(launchd_job_runs_total[15m]) > 5` | above 5 | 0 | warning | a darwin job relaunches in a loop, the launchd form of the 2026-10-15 `omnigent-host` loop on magnetite |
| `HostProbeStale` | `time() - node_textfile_mtime_seconds > 300 or node_textfile_scrape_error == 1` | any series | 10 min | warning | stibnite's probe dies or writes an unreadable file, and its last launchd and SMART values keep every darwin rule quiet |
| `StoreQueryFailing` | evaluator-internal: store HTTP query error or timeout, one instance per database | any rule query on that database fails | 3 min | critical | the store, which ADR-007 ranks as the host-OOM victim after the nixbot evaluator, is down or one database cannot be read, and every rule on that database is silently blind |
| `RuleSignalMissing` | evaluator-internal: the rule's presence selector, the bare metric name of its expression except `LocalExporterDown`'s `up{job="node"}` | no series while at least one expected host reports host memory | 30 min | warning | a collector or schema change renames or drops a metric, or a macOS update breaks the probe's `launchctl print` parsing, and a rule can never fire again |
| `AlertEvaluatorSilent` | cinnabar dead-man: messages on `fleet-heartbeat` | none in 10 min | 0 | critical | magnetite, the evaluator or the magnetite-to-cinnabar path is down and no alert can be sent |
| `WeeklyPipelineTest` | `count(count by (host_name) (system_memory_usage_bytes))` | evaluated Mondays 09:00 to 09:05 only | 0 | info | the delivery path is broken and the absence of alerts is mistaken for health |

The attribution query for `HostMemoryPressure` and `HostOOMKill` is `topk(3, process_memory_usage_bytes{host_name="<host>"})` together with `node_zfs_arc_size{host_name="<host>"}` and `sum(system_paging_usage_bytes{host_name="<host>", state="used"})` (ADR-009 Decision).
No pool-capacity rule exists, because ADR-003 collects no pool allocation metric (ADR-009 Decision).
Collector liveness, queues and send failures stay with ADR-003's `otel-envelope` regulator R3.2 and reach a human through `observability-notify@`, so no rule duplicates them, and host absence is item 16's `RuleSignalMissing` (ADR-009 Decision; charter v23).

## Configuration surface

Files to add (ADR-009 Implementation surface):

- `modules/nixos/fleet-alert.nix`: `flake.modules.nixos.fleet-alert` with options `services.fleet-alert.evaluator` and `services.fleet-alert.deadman`; the evaluator script as a `pkgs.writeShellApplication` over `curl` and `jq` after the `ntfy-send` precedent (`pkgs/by-name/ntfy-send/package.nix`), posting through `pkgs.ntfy-send` from slice S1 rather than a package built in the module, with its per-instance transition as a pure jq function; `fleet-alert.service` and `.timer` with `StateDirectory = "fleet-alert"`, `LoadCredential` for the `regulator-password` of ADR-007 and the `alerter` token, `MemoryMax = 64M` and `TimeoutStartSec = 50s`; `fleet-deadman.service` and `.timer` with `StateDirectory = "fleet-deadman"`; and the R9.5 assertion.
- `modules/nixos/fleet-alert/rules.nix`: the rule table as Prometheus-format rules with presence selectors and their expected hosts, annotation queries, the `WeeklyPipelineTest` window, the kept-alive launchd labels read from ADR-004's `schema.nix` and the `SystemdUnitFailed` exclusion rendered from `services.observability-notify.units`, rendered to JSON for the evaluator and YAML for `promtool`; S3 adds the rules S1's signals feed, and S4 and S5 add the rest.
- `modules/checks/fleet-alert.nix`: regulator R9.2 with its fixtures, mutants and the Hypothesis property test of the jq transition function, using `promtool` from the `cli` output of the root pin's `prometheus` package (`NixOS/nixpkgs@ac1faec44836:pkgs/by-name/pr/prometheus/package.nix:210`, root node `nixpkgs_10`).
- A flake check validating the rendered `NTFY_AUTH_*` strings before deploy: the token matches `^tk_[-_A-Za-z0-9]{29}$`, the password hash has bcrypt's shape, and every `auth-access` entry names a provisioned user (ADR-009 Decision item 13).

Files to modify:

- `modules/machines/nixos/magnetite/default.nix`: import `fleet-alert` and enable the evaluator, and add `onFailure = [ "observability-notify@%n.service" ]` to the six existing `zfs-assert-*` and `zfs-set-*` oneshots and to ADR-007's three new ones (ADR-009 Implementation surface).
- `modules/machines/nixos/cinnabar/ntfy.nix`: set `auth-access` to `alerter:fleet-*:rw` and `*:fleet-*:ro`, set `behind-proxy`, `proxy-trusted-hosts` and `visitor-prefix-bits-ipv6`, set `services.ntfy-sh.environmentFile` to the `ntfy-alerter-env` generator's `ntfy-env` file, import `fleet-alert` with the dead-man enabled, and import `observability-notify` (ADR-009 Implementation surface).
- The `observability-notify@` template unit, extracted from the `agent` role's NixOS module of the `otel-collector` clan service into `flake.modules.nixos.observability-notify` with the option `services.observability-notify.units` unchanged: post to `fleet-alerts` with the `alerter` token, keep the per-unit stamp, append each posted `FAILED` with its timestamp, unit and host to a log under `/var/lib/observability-notify`, and add the `ExecStartPost=` and `ExecStopPost=` recovery hooks to each notified unit (ADR-003; ADR-009 Implementation surface).
- `pkgs/by-name/ntfy-send`: when `NTFY_TOKEN_FILE` is set, send `Authorization: Bearer` with the token read from that file, without placing it on curl's argument list (ADR-009 Implementation surface).

The cutover takes three deploys and leaves no window in which a publish is refused: `cinnabar` first provisions `alerter` and its token with no access entries, `magnetite` then deploys the notifier and evaluator posting with the token, and `cinnabar` finally adds `auth-access`, after which R9.4's anonymous-publish probe confirms the refusal (ADR-009 Decision item 13).

Flake inputs: none, and no overlay, no new long-running service and no new listener (ADR-009 Implementation surface).

Clan vars generators:

- `ntfy-alerter`, `share = true`, declared on `magnetite` and `cinnabar`: `runtimeInputs` `ntfy-sh`; one file, `token` (secret, a `tk_`-prefixed token from `ntfy token generate`, mode `0400`, written with `printf '%s'`), deployed on every machine that declares it (ADR-009 Implementation surface).
- `ntfy-alerter-env`, per machine, declared on `cinnabar` only, `dependencies = [ "ntfy-alerter" ]`: `runtimeInputs` `ntfy-sh` and openssl; reads `$in/ntfy-alerter/token`, generates a password discarded after hashing, and writes `ntfy-env` (secret, `NTFY_AUTH_USERS=alerter:<bcrypt hash from ntfy user hash>:user` and `NTFY_AUTH_TOKENS=alerter:<token>`, `restartUnits = [ "ntfy-sh.service" ]`); a shared generator cannot deploy a file to one machine only, because clan-core refuses shared generators whose files differ between machines (ADR-009 Implementation surface).
- Consumed, not created here: `greptimedb-users` `regulator-password` (ADR-007 Implementation surface).

## Operating envelope and regulator

The envelopes and regulators below are ADR-009's.

| Envelope | Statement | Regulator | Shown able to fail by |
|---|---|---|---|
| E9.1, noise | at most 10 `FIRING` messages per rolling 24 h across the fleet in steady state, of which at most 3 come from any one laptop host, at most one `FIRING` per alert instance per firing episode, and at most one re-post per `critical` instance per 24 h; a laptop's absence contributes none by construction | R9.1: the evaluator counts the `FIRING` messages it and the notifier sent in the last 24 h, from its own state file and the notifier's log of posted `FAILED` messages, and on breach posts one `AlertBudgetExceeded` message per 24 h naming the rule and host with the most firings; the breach triggers a reviewed threshold change, not an automatic suppression | the R9.2 fixture leg that fires 11 synthetic instances and asserts that exactly one `AlertBudgetExceeded` message is posted, and a leg that fires 4 synthetic instances on stibnite and asserts the same |
| E9.2, evaluator semantics | a condition that holds for `for` produces one `FIRING`; a further evaluation with the condition still holding produces none; the condition's absence for 5 min produces one `RESOLVED`; a store error on one database produces `StoreQueryFailing` for that database after 3 min and no `RESOLVED` for any other instance on that database, while instances on databases that answer resolve as usual; a firing instance on a host whose `system_memory_usage_bytes` disappears produces no `RESOLVED` until that host reports again; a presence selector with no series for 30 min while an expected host reports produces `RuleSignalMissing`, and the same gap while every expected host is silent produces none; every rule expression parses as PromQL | R9.2, deterministic, build time: flake check `checks.x86_64-linux.fleet-alert` runs `promtool check rules` over the rendered rules file, then runs the evaluator in the build sandbox against a loopback fixture server that replays canned `/v1/prometheus/api/v1/query` responses and records every ntfy POST, and asserts the E9.2 sequence and the E9.1 budget leg | enumerated mutants: one removing the state file write so the second evaluation re-posts, one setting a rule's `for` to 0, one dropping the state freeze so a store error emits `RESOLVED`, one dropping the absence freeze so a silent host's instance emits `RESOLVED`, and one malformed expression that `promtool` rejects; each must produce a non-empty failure list |
| E9.3, liveness of the alert path | every 10 min window contains at least one `fleet-heartbeat` message while magnetite is up, and a silence of 10 min produces `AlertEvaluatorSilent` within the next 5 min | R9.3, runtime: the cinnabar dead-man regulates the evaluator, and `WeeklyPipelineTest` regulates the whole path, whose absence on a Monday is observed by the human, which charter A8 accepts as recorded human judgment | at acceptance, stopping `fleet-alert.timer` on magnetite and observing `AlertEvaluatorSilent` within 15 min, then starting it and observing `RESOLVED` |
| E9.4, delivery authorization | an anonymous publish to `fleet-alerts` or `fleet-heartbeat` is refused, an `alerter` publish is accepted, and an anonymous publish to any host-named topic is still accepted | R9.4: a `fleet-deadman` precondition step that, before polling, performs an anonymous publish to `fleet-heartbeat` on `[::1]:2586` and fails the unit, and so notifies through ADR-003's notifier, if that publish is accepted | at acceptance, removing the `*:fleet-*:ro` entry and observing the unit fail |
| E9.5, resources | `fleet-alert.service` runs under `MemoryMax = 64M` and `TimeoutStartSec = 50s`, so one run cannot overlap the next and cannot add to a magnetite memory incident | R9.5: an evaluation-time assertion in the module that both limits are set | a mutant that drops `MemoryMax` |

The R9.2 fixture check is the gating regulator, because `vmTests` run only on pyrite's kvm lane and do not gate on nixbot (ADR-009 Test-lane evidence, Rejected alternatives).
Beside its mutants, the check runs a property-based test: Hypothesis generates query timelines and compares the jq transition function's posts and state with a small Python reference model of pending, firing and resolved instances, the store freeze, the host freeze and the re-post cadence (ADR-009 Operating envelope R9.2).

## Failure prevented

These are ADR-009's Failure prevented entries.

- The evaluator and rule table: each failure in the rule table's last column passes with nobody told.
- Deduplication and recovery notices: one condition produces a message every minute, the human mutes the topic, and the next real alert is lost.
- State freeze on store error: a store outage produces a burst of false recoveries and a second burst of firings.
- `RuleSignalMissing`: a metric rename makes a rule vacuous, which the CCV integrity property forbids for regulators.
- Dead-man on cinnabar: magnetite's death silences the evaluator that would have reported it.
- `alerter`-only publishing to `fleet-*`: a mesh member spoofs alerts or masks the dead-man with fake heartbeats.
- Notifier deduplication: a regulator that fails every 5 min posts 288 messages a day.
- `WeeklyPipelineTest`: a broken delivery path is read as a quiet fleet.
- R9.2 fixture check: an evaluator change that re-posts, never resolves, or fires early ships, which a VM test on the non-gating kvm lane would not stop.
- R9.5: the evaluator itself grows into magnetite's memory during an incident.

## Deployment acceptance items

- R9.3: stopping `fleet-alert.timer` on magnetite produces `AlertEvaluatorSilent` within 15 min, and starting it produces `RESOLVED` (ADR-009 Operating envelope).
- R9.4: removing the `*:fleet-*:ro` entry makes `fleet-deadman.service` fail (ADR-009 Operating envelope).
- R9.1: the R9.2 fixture legs of 11 synthetic instances and of 4 synthetic instances on stibnite each post exactly one `AlertBudgetExceeded` message (ADR-009 Operating envelope).
- Rule expressions are coupled to ADR-003's and ADR-004's deployed metric names, which only the runtime `RuleSignalMissing` detects, within 30 min of deploy, because the build-time check uses fixtures (ADR-009 Consequences).
- pyrite's NVMe SMART support through the Apple controller is unverified until acceptance; if `smartctl_device_critical_warning` never appears for pyrite while it reports host memory, `RuleSignalMissing` reports it within 30 min of deploy (ADR-009 Decision); the check runs when the NVMe rules land in S4.
- Acceptance runs `darwin-rebuild switch` with a changed `otelcol` plist on stibnite and requires that neither `LaunchdJobFailed` nor `LaunchdJobNotRunning` fires (ADR-009 Decision); the check runs when the launchd rules land in S5.
- `HostMemoryPressure` counts the ZFS ARC above `node_zfs_arc_c_min` as available on the inference that the kernel's available-memory figure omits the ARC, to be confirmed at acceptance on magnetite (ADR-009 Decision).
- The R3.2 stopped-agent test produces a ntfy message naming `otel-envelope.service` on `fleet-alerts` (ADR-003 Operating envelope and regulator; ADR-009 Decision item 11).
- The human's phone and desktop subscribe anonymously to `fleet-alerts`, and the first Monday `WeeklyPipelineTest` message arrives on the phone (ADR-009 Q2, Decision item 14).

## Deferred

- ADR-009 Q5, an external dead-man watching `cinnabar` itself, is deferred to CAM-76 and decided before S5, because until then an ntfy outage is noticed only by a missing Monday `WeeklyPipelineTest`, up to 7 days later (charter v21).
  Until then `cinnabar` is the single delivery path: while `cinnabar` or its ntfy is down no alert reaches a human, and nothing in this component detects that (ADR-009 Consequences).
  This includes an ntfy that refuses to start on a malformed `environmentFile`, which the provisioning check guards against before deploy; the residual risk is recorded against CAM-76.
  The candidate fix is an external heartbeat from a free uptime service, at the cost of a third-party dependency.
- Alertmanager adoption: triggered by E9.1 breached in two separate weeks after threshold review, or the rule set passing 30 rules; at that point vmalert loads the same Prometheus-format rules and Alertmanager posts to `fleet-alerts` through `?template=alertmanager` (ADR-009 Q3).
- Merge-queue stall rule over ADR-005's `devloop` events: not added until ADR-005 names a decision that needs it within hours (ADR-009 Q6).
- Noise envelope revision: E9.1 is revised after the first month from the counts R9.1 records (ADR-009 Q4).
