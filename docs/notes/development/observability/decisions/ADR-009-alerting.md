---
title: "ADR-009: Alerting"
---

## Status

Accepted (human gate, 2026-10-15), except Q5, deferred to the end of implementation, and amended in place under charter v12 (2026-10-16): `ntfy-send` is the package `pkgs/by-name/ntfy-send`, added by slice S1, which the evaluator consumes instead of building its own

## Context

Charter D9 asks how fleet conditions become human notifications, including watching the store itself.
ADR-001 placed alerting outside the store and chose no component for it (ADR-001 Decision, Consequences, Q3).
In-database alerting is unavailable in the open build, because `CREATE`, `ALTER`, `DROP` and `SHOW TRIGGER` are enterprise-gated (`research/greptimedb.md` F40, F41).
Until this record, the only path from a fleet condition to a human is ADR-003's `observability-notify@%n.service`, which fires only when an observability regulator or oneshot unit fails and posts one message per failure with no recovery notice (ADR-003 Q9).

Four host-level failures motivate the decision, and each was visible only to someone already looking:

- magnetite was OOM-killed by overlapping evaluations on 2026-09-27 and 2026-10-01, with the kernel taking roughly 47 processes and no record of which process grew first (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:5-7`; `research/fleet-emitter-inventory.md` R16).
- On 2026-10-15 magnetite's `omnigent-host-cameron` and `omnigent-host-janettesmith` units restart-looped about 3,200 times from the 04:36 UTC deploy until stopped, after their 30-day Omnigent login grants expired, and nobody was told (`docs/notes/development/incidents/2026-10-15-omnigent-host-restart-loop.md:5-8`).
- magnetite's documented storage failures are pool exhaustion, which produced the `/nix` quota and the `/` and `/home` reservations (`research/fleet-emitter-inventory.md` F20; `cameronraysmith/vanixiets@109c67346:modules/machines/nixos/magnetite/disko.nix:41-70`).
- On 2026-10-15 stibnite's launchd job `org.nixos.omnigent-host-cameron` exited with status 78 after its login expired, and nobody was told (`docs/notes/development/incidents/2026-10-15-omnigent-host-restart-loop.md:7-8`; ADR-003 Context).

The signals these rules read are defined by ADR-003 and ADR-004: host memory, host swap usage from the `host_metrics` `paging` scraper, and the kernel OOM-kill count, per-executable resident memory bounded to 30 executables per host, systemd unit state and restart counts for allow-listed units, launchd job state, last exit code and launch counts for allow-listed darwin jobs, filesystem usage and ZFS pool state, and NVMe SMART health on pyrite and stibnite.
Every NixOS host's only swap device is `zram0`, enabled fleet-wide and widened to 150 % of RAM on magnetite (`modules/system/zram-swap.nix:10-11`; `modules/machines/nixos/magnetite/default.nix:452`), so `system_paging_usage_bytes` on those hosts is zram's logical occupancy, with `state` `used` or `free` (ADR-003 item 18).
Resident memory understates a process's footprint on these hosts: with `vm.swappiness = 100` nix-eval-jobs held about 35 % of its true footprint resident, and the zram pool holding the rest is charged to no cgroup (`docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:44-51`).
At the pins, the `process` scraper has no swap metric and the `systemd` receiver no per-unit memory metric, so swapped-out pages cannot be attributed to a process or unit from collected series (ADR-003 item 18; ADR-004).
SMART is meaningful only on the physical disks: pyrite's Apple NVMe controller exposing `nvme0n1` and `nvme0n2` (`cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/pyrite/disko.nix:53-54`) and stibnite's internal Apple SSD `disk0` (ADR-003 Context), whereas magnetite and cinnabar are Hetzner cloud VMs whose root device is a virtual `/dev/sda` (`cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/magnetite/disko.nix:8`, `cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/cinnabar/disko.nix:9`; `cameronraysmith/vanixiets@109c67346:modules/terranix/hetzner.nix:10-29`).
Of the in-scope hosts, only cinnabar and magnetite are always on: the terranix machine tables mark them `enabled = true` and electrum, galena and scheelite `enabled = false`, so those three exist only while provisioned on demand, and pyrite and stibnite are laptops that sleep and travel (`cameronraysmith/vanixiets@eee06596a:modules/terranix/hetzner.nix:11`, `:18`, `:25`; `cameronraysmith/vanixiets@eee06596a:modules/terranix/gcp.nix:32`, `:40`; `cameronraysmith/vanixiets@eee06596a:modules/clan/inventory/machines.nix:77-108`).

### Evaluator evidence

GreptimeDB 1.2.1 serves Prometheus instant and range queries at `/v1/prometheus/api/v1/query` and `/query_range` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:1350-1351`; `research/greptimedb.md` R11), and ADR-007 provides a read-only `regulator` store user for timer-driven readers.
GreptimeDB flows write continuous aggregates into a sink table (`GreptimeTeam/greptimedb@179ff8e50:src/sql/src/statements/create.rs:686`) and have no notification output, so a flow would still need a poller.
Perses 0.54.0 evaluates no rules; its roadmap lists an alert view as under consideration (`perses/perses@4c719fc1:ROADMAP.md:21-23`), and its `AlertsQuery` plugin kind is a query kind for displaying alerts, not an evaluator (`perses/perses@4c719fc1:pkg/model/api/v1/plugin/plugin.go:42`).
Prometheus in agent mode disables querying, alerting and local storage (https://prometheus.io/docs/prometheus/latest/prometheus_agent (fetched 2026-10-15)), so rule evaluation without a store needs server mode, which evaluates against its own storage.
The root pin carries `victoriametrics` 1.153.0 with `vmalert` built by default, a `services.vmalert` module, `prometheus-alertmanager` 0.33.1 and `alertmanager-ntfy` 1.2.1 with its own module (`NixOS/nixpkgs@ac1faec44836:pkgs/by-name/vi/victoriametrics/package.nix:9`, `:17`, `:39-41`; `NixOS/nixpkgs@ac1faec44836:nixos/modules/services/monitoring/vmalert.nix`; `NixOS/nixpkgs@ac1faec44836:pkgs/by-name/pr/prometheus-alertmanager/package.nix:23`; `NixOS/nixpkgs@ac1faec44836:nixos/modules/services/monitoring/prometheus/alertmanager-ntfy.nix`; root node `nixpkgs_10`).
vmalert sends notifications only to an Alertmanager-compatible endpoint named by `-notifier.url` (https://docs.victoriametrics.com/victoriametrics/vmalert (fetched 2026-10-15)), so vmalert alone cannot post to ntfy.

### Delivery evidence

cinnabar runs ntfy-sh 2.28.0 on `[::1]:2586` behind caddy as `https://ntfy.zt` (`cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/cinnabar/ntfy.nix:4-9`, `cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/cinnabar/caddy.nix:29-32`; `research/fleet-emitter-inventory.md` R12).
The NixOS module sets `auth-file` and a persistent `cache-file` by default and accepts an `environmentFile` for declarative users and tokens (`NixOS/nixpkgs@ac1faec44836:nixos/modules/services/misc/ntfy-sh.nix:86-96`, `:110-115`, root node `nixpkgs_10`).
The repository sets no `auth-default-access`, so ntfy's default of `read-write` for anonymous clients applies, and every fleet `ntfy-send` and agent hook publishes anonymously to a topic named after the local host (`cameronraysmith/vanixiets@ff2ca5c77:modules/home/tools/commands/system/ntfy-send.sh:30-34`).
`ntfy.zt` is served by caddy with `tls internal`, and `ntfy-send` reaches it with `curl -sfk -m 5`, skipping certificate verification, and passes any further arguments, such as `-H` headers, through to curl (`modules/home/tools/commands/system/ntfy-send.sh:10-15`, `:33-34`, which slice S1 moves unchanged to `pkgs/by-name/ntfy-send/ntfy-send.sh`; `modules/machines/nixos/cinnabar/caddy.nix:29-32`).
ntfy 2.14.0 added declarative users, ACL entries and tokens through `auth-users`, `auth-access` and `auth-tokens`, and ACL entries can name a provisioned user or `*` for anonymous clients (https://docs.ntfy.sh/config/ and https://docs.ntfy.sh/releases/ (fetched 2026-10-15)).
ntfy keeps published messages for `cache-duration`, 12 h by default, and serves them to `GET /<topic>/json?poll=1&since=<duration>` (https://docs.ntfy.sh/config/ and https://docs.ntfy.sh/subscribe/api/ (fetched 2026-10-15)).
From 2.14.0 ntfy also renders Alertmanager webhook payloads with the built-in `?template=alertmanager`, so Alertmanager needs no bridge to reach it (https://docs.ntfy.sh/publish/ (fetched 2026-10-15)).
The mesh is one flat trust zone that includes two unmanaged Android members (`research/otel-collector-topology.md` R18; `research/telemetry-security-and-tenancy.md` F34).

### Test-lane evidence

VM tests in this repository are `vmTests` outputs that need `/dev/kvm`, which only pyrite has, so they are not gating on nixbot (`cameronraysmith/vanixiets@ff2ca5c77:modules/machines/nixos/pyrite/default.nix:127-129`, `:485-488`).

## Decision

Fleet conditions become notifications through one first-party rule evaluator, a systemd timer on magnetite that queries the store's Prometheus API and posts deduplicated firing and recovery messages to the existing ntfy on cinnabar, watched by a dead-man timer on cinnabar.
No new long-running process is added.

1. Evaluator: `fleet-alert.timer` on magnetite fires every 60 s and starts `fleet-alert.service`, a oneshot that issues each rule's PromQL instant query to `http://127.0.0.1:4000/v1/prometheus/api/v1/query` against the `fleet` database as the `regulator` store user (ADR-007), with a 10 s per-query timeout.
2. Rules: rules are declared once in Nix as Prometheus-format alerting rules (`alert`, `expr`, `for`, `labels.severity`, `annotations`), rendered to the evaluator's configuration and to a Prometheus rules file used only by the build-time check.
3. Rule semantics follow Prometheus: an alert instance is one rule plus its result label set; it becomes firing after its condition has held on every evaluation for `for`, and resolves after the condition has been absent for 5 min.
4. Deduplication: the evaluator keeps per-instance state in `/var/lib/fleet-alert/state.json` and posts exactly one `FIRING` message when an instance becomes firing and exactly one `RESOLVED` message when it resolves; a `critical` instance that stays firing is re-posted once per 24 h, a `warning` instance is never re-posted, and an `info` instance posts no `RESOLVED` and is not counted against E9.1.
5. Attribution: a rule may name an annotation query whose result is appended to the message body; the memory and OOM rules append the three executables with the largest resident memory on the affected host, that host's ZFS ARC size and its swap used, and state in the message that resident memory omits swapped-out pages.
6. Store watch: if the store does not answer, the evaluator raises the internal instance `StoreQueryFailing`, freezes every other instance's state so no false `RESOLVED` messages are sent, and resumes normal evaluation when the store answers.
7. Signal presence: each rule declares a presence selector and the hosts expected to emit it, and a selector that returns no series for 30 min while at least one of those hosts reports `system_memory_usage_bytes` raises `RuleSignalMissing` for that rule, so a renamed or dropped metric cannot make a rule silently vacuous and a sleeping laptop cannot make it look so.
8. Heartbeat: every completed evaluation, including one that raised `StoreQueryFailing`, publishes a minimum-priority message to the ntfy topic `fleet-heartbeat`.
9. Dead-man: `fleet-deadman.timer` on cinnabar fires every 5 min and polls `http://[::1]:2586/fleet-heartbeat/json?poll=1&since=10m`; an empty result raises `AlertEvaluatorSilent` on `fleet-alerts`, with the same one-firing, one-resolved state discipline kept in `/var/lib/fleet-deadman/state.json`.
10. Delivery: all alert messages go to the ntfy topic `fleet-alerts` at `https://ntfy.zt`, titled `[FIRING|RESOLVED] <alert> <host>`, with ntfy priority `high` for `critical`, `default` for `warning` and `low` for `info`, posted through `ntfy-send` built from its existing script, with the title, priority and `alerter` token passed as curl `-H` arguments, so delivery inherits the helper's `-k` convention for caddy's internal TLS rather than adding a second client.
11. Delivery for unit failures: ADR-003's `observability-notify@%n.service` posts to the same `fleet-alerts` topic with the same credential, and gains the same discipline: it posts once per failure episode, guarded by a stamp file per unit under `/var/lib/observability-notify`, and each notified unit's `ExecStopPost=` posts one `RESOLVED` and removes the stamp when the unit next exits successfully.
    magnetite's existing `zfs-assert-*` and `zfs-set-*` oneshots (`modules/machines/nixos/magnetite/default.nix:193-263`) and ADR-007's three new `greptimedb` ones gain `OnFailure=observability-notify@%n.service`, so a dataset property that fails to apply is reported by the notifier rather than by `SystemdUnitFailed`.
12. Authentication: one new user `alerter` publishes; `auth-access` grants `alerter:fleet-*:rw` and `*:fleet-*:ro`, so anonymous mesh members, including phones, can subscribe but cannot publish to or spoof `fleet-alerts` and `fleet-heartbeat`; `auth-default-access` stays `read-write`, so every other topic and every existing `ntfy-send` caller is unchanged.
13. The `alerter` password hash and an `alerter` access token are provisioned through `services.ntfy-sh.environmentFile` as `NTFY_AUTH_USERS` and `NTFY_AUTH_TOKENS`; the token reaches magnetite's evaluator and notifier through `LoadCredential` and cinnabar's dead-man through its own `LoadCredential`.
14. Weekly end-to-end test: the rule `WeeklyPipelineTest` is evaluated only between 09:00 and 09:05 local time each Monday, queries the store for the count of hosts reporting host memory, and fires as `info`, so one message each Monday proves store, evaluator, ntfy and the subscribed phone together.
15. No CI or merge-queue rule is in the initial set, because ADR-005's decision rules are 30-day and 365-day reviews over `devloop` rows rather than conditions that need a human within minutes (ADR-005 D5-R1 to D5-R8).
16. Host absence: no rule fires because a host has stopped reporting; the silence of an always-on host, cinnabar or magnetite or a cloud host while terranix provisions it, is ADR-003's R3.2 failure and reaches a human through item 11, and the silence of a laptop, stibnite or pyrite, raises nothing.
17. Absence freeze: while a host reports no `system_memory_usage_bytes`, the evaluator freezes every instance labelled with that host, sending neither `RESOLVED` nor a re-post, and resumes normal evaluation for that host when it reports again, so a laptop's sleep neither resolves its alerts nor fires them again on wake.

Initial rule set.
Signal names are ADR-003's and ADR-004's, as PromQL-visible in the `fleet` database, where the agent-stamped `host.name` appears as the label `host_name`.
Rules over ZFS, `oom_kill`, available-memory, swap and systemd series cover the six NixOS hosts; the launchd rules and `HostProbeStale` cover stibnite and any darwin host that later consents; the filesystem, SMART and `LocalExporterDown` rules cover every host that emits their series, which for SMART is pyrite and stibnite (ADR-003).
`<kept-alive labels>` below is the set of allow-listed labels whose evaluated `KeepAlive` is `true`, rendered from `schema.nix` (ADR-004).

| Rule | Signal (PromQL) | Threshold | For | Severity | Failure it prevents |
|---|---|---|---|---|---|
| `HostMemoryPressure` | `((sum by (host_name) (system_linux_memory_available_bytes) + sum by (host_name) (node_zfs_arc_size - node_zfs_arc_c_min)) / sum by (host_name) (system_memory_usage_bytes) < 0.10) or (sum by (host_name) (system_paging_usage_bytes{state="used"}) / sum by (host_name) (system_paging_usage_bytes) > 0.85)` | available below 0.10, or swap used above 0.85 | 5 min | warning | the 2026-09-27 and 2026-10-01 OOM build-up on magnetite, which filled RAM and zram together, passes unseen, with no record of which process was growing |
| `HostOOMKill` | `increase(node_vmstat_oom_kill[10m])` | above 0 | 0 | critical | an OOM kill on any host, including on magnetite the kills ADR-007 orders as the nixbot evaluator at `oom_score_adj` 900, then the store at 500, then the `ingress` collector at 300, is noticed only by its downstream effects |
| `FilesystemFillingWarn` | `sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes)` | above 0.85 | 15 min | warning | magnetite's pool or a quota-bounded dataset fills, the 2026-06-10 storage starvation, or stibnite's APFS container, reported at `/System/Volumes/Data` and holding its `/nix`, fills |
| `FilesystemFull` | same expression as `FilesystemFillingWarn` | above 0.95 | 5 min | critical | writes fail on `/nix`, `/`, `/home` or `/var/lib/greptimedb`, or on stibnite's Nix store and user data |
| `ZfsPoolUnhealthy` | `node_zfs_zpool_state{state!="online"} == 1` | any series | 1 min | critical | a degraded, faulted, suspended or unavailable `zroot` on any NixOS host runs on until the next failure loses data |
| `NvmeCriticalWarning` | `smartctl_device_critical_warning` on pyrite and stibnite | not 0 | 0 | critical | a laptop's NVMe reports spare exhaustion, temperature, read-only or reliability degradation and the laptop loses data without warning |
| `NvmeWearHigh` | `smartctl_device_percentage_used` on pyrite and stibnite | above 90 | 1 h | warning | a laptop's SSD reaches rated endurance without a replacement planned |
| `SystemdUnitRestartLoop` | `increase(systemd_service_restarts_total[15m])` | above 5 | 0 | warning | the 2026-10-15 overnight loop of about 3,200 `omnigent-host` restarts on magnetite |
| `SystemdUnitFailed` | `systemd_unit_state{systemd_unit_active_state="failed", systemd_unit_name!~"otel-envelope.service\|devloop-reconcile.service\|greptimedb-(envelope\|export\|schema).service\|zfs-(assert\|set)-.*\.service"} == 1` | any series | 5 min | warning | an allow-listed service stops and stays stopped with nobody told, outside the observability and ZFS-property units ADR-003's notifier already covers |
| `LocalExporterDown` | `up{job=~"node\|smartctl"} == 0` | any series | 10 min | warning | one host's loopback exporter dies and that host's OOM, ZFS, SMART or launchd rules go blind while the fleet-wide presence check stays satisfied |
| `LaunchdJobNotRunning` | `launchd_job_state{launchd_state="running", launchd_label=~"<kept-alive labels>"} == 0` | any series | 10 min | warning | a kept-alive darwin job such as `org.nixos.nix-daemon` or `org.nixos.nix-grpc-daemon` is stopped or unloaded, as a store-path job started before the Nix store mounted stays inactive (`cameronraysmith/vanixiets@eee06596a:modules/darwin/launchd-wait4path.nix:1-5`) |
| `LaunchdJobFailed` | `launchd_job_last_exit_code != 0` | any series | 5 min | warning | the 2026-10-15 exit 78 of `org.nixos.omnigent-host-cameron` on stibnite, or a failed `harmonia-gc` run, passes unnoticed |
| `LaunchdJobRestartLoop` | `increase(launchd_job_runs_total[15m])` | above 5 | 0 | warning | a darwin job relaunches in a loop, the launchd form of the 2026-10-15 `omnigent-host` loop on magnetite |
| `HostProbeStale` | `time() - node_textfile_mtime_seconds > 300 or node_textfile_scrape_error == 1` | any series | 10 min | warning | stibnite's probe dies or writes an unreadable file, and its last launchd and SMART values keep every darwin rule quiet |
| `StoreQueryFailing` | evaluator-internal: store HTTP query error or timeout | any rule query fails | 3 min | critical | the store, which ADR-007 ranks as the host-OOM victim after the nixbot evaluator, is down and every other rule is silently blind |
| `RuleSignalMissing` | evaluator-internal: the rule's presence selector, the bare metric name of its expression | no series while at least one expected host reports host memory | 30 min | warning | a collector or schema change renames or drops a metric, or a macOS update breaks the probe's `launchctl print` parsing, and a rule can never fire again |
| `AlertEvaluatorSilent` | cinnabar dead-man: messages on `fleet-heartbeat` | none in 10 min | 0 | critical | magnetite, the evaluator or the magnetite-to-cinnabar path is down and no alert can be sent |
| `WeeklyPipelineTest` | `count(count by (host_name) (system_memory_usage_bytes))` | evaluated Mondays 09:00 to 09:05 only | 0 | info | the delivery path is broken and the absence of alerts is mistaken for health |

No pool-capacity rule exists, because ADR-003 collects no pool allocation metric; on ZFS the filesystem `free` state approximates pool available space, so the filesystem rules on `mountpoint="/"` also report pool fullness, and on quota-bounded datasets they report quota fullness.
The attribution query for `HostMemoryPressure` and `HostOOMKill` is `topk(3, process_memory_usage_bytes{host_name="<host>"})` together with `node_zfs_arc_size{host_name="<host>"}` and `sum(system_paging_usage_bytes{host_name="<host>", state="used"})`; per-process series are summed per executable and omit processes below 64 MiB (ADR-004), so attribution names executables, not PIDs.
Because `process_memory_usage_bytes` is resident memory only, the top three executables are ranked by the part of their footprint still in RAM, and an evaluator with most of its pages in zram can rank below a smaller process; the host's swap used is reported beside them so the message shows how much footprint the ranking cannot see, but not whose it is.
pyrite's NVMe SMART support through the Apple controller is unverified until acceptance; if `smartctl_device_critical_warning` never appears for pyrite while it reports host memory, `RuleSignalMissing` reports it within 30 min of deploy.
Whether a darwin activation that replaces a kept-alive job's plist leaves a non-zero `launchd_job_last_exit_code` or a 10 min `not_running` gap is unverified until acceptance, which runs `darwin-rebuild switch` with a changed `otelcol` plist on stibnite and requires that neither `LaunchdJobFailed` nor `LaunchdJobNotRunning` fires.

Collector liveness and per-host freshness stay with ADR-003's `otel-envelope` regulator (R3.2) and reach a human through the deduplicated notifier of item 11, so no rule duplicates them.
ZFS ARC size has no rule of its own; `HostMemoryPressure` counts the ARC above its minimum as available, because the ARC shrinks to `node_zfs_arc_c_min` under pressure while the kernel's available-memory figure does not include it `[INFERENCE: OpenZFS ARC is not page cache, so MemAvailable omits it; to be confirmed at acceptance on magnetite]`, and the ARC size is appended to memory messages as attribution.

## Rationale

The evaluator is the smallest apparatus that gives deduplication and recovery notices (C1).
It is one oneshot on an existing timer pattern, reads the store through the read-only credential that `otel-envelope` already uses, and posts through the ntfy that the fleet already runs, so it adds no daemon, no listener and no second store to magnetite, the host with the OOM history.
Deduplication and recovery need only a set of alert instances with their first-seen and last-seen times, which is a state file rather than a service.
Declaring rules in Prometheus format keeps the exit open: the same rules load unchanged into vmalert or Prometheus if the trigger for Alertmanager below fires.

The dead-man lives on cinnabar because every failure that silences the evaluator, namely magnetite down, the evaluator unit dead, or the path to ntfy broken, is visible from the ntfy host, and because ntfy's message cache already answers "was anything published in the last 10 min" without a new listener (https://docs.ntfy.sh/subscribe/api/ (fetched 2026-10-15)).
The store being down is covered without the dead-man, because the evaluator survives the store's death on magnetite by design: under ADR-007 the kernel kills the nixbot evaluator at `OOMScoreAdjust` 900 first and the store at 500 next, ahead of the `ingress` collector at 300, and the evaluator is a short-lived oneshot (ADR-007; `docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:63`).
Freezing state while the store is unreachable prevents a burst of false `RESOLVED` messages for every firing instance, followed by a burst of `FIRING` messages when the store returns.

Restricting `fleet-*` topics to the `alerter` user is required because the dead-man reads heartbeats: an anonymous publish to `fleet-heartbeat` from any mesh member would otherwise mask a dead magnetite.
Leaving `auth-default-access` at `read-write` keeps every existing anonymous `ntfy-send` and hook caller working, so the access change touches only the two new topics.

Thresholds are set where the named incident would have fired well before damage: 10% available memory leaves about 3 GiB on magnetite, a 5-in-15-min restart rule would have fired within the first quarter hour of a loop that reached about 3,200 restarts, and 85% filesystem use leaves room to act before the 95% critical.
Swap is a second term because zram's compressed pool already occupies RAM that the available-memory figure excludes, while its logical capacity can run out first: both OOMs came with zram free at 0 (`docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:26-32`).
The 0.85 swap threshold sits above the 33.68 GB, about 68 % of magnetite's 45.9 GiB zram, that one `8 x 4096` nixbot evaluation reached alone (`docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:12-14`), so a single evaluation does not fire it and an overlapping one does.
`warning` alerts are never re-posted, so a known and accepted condition costs one message rather than a daily reminder; `critical` alerts are re-posted daily because each one names data loss or blindness.
`SystemdUnitFailed` excludes the observability units and the `zfs-assert-*` and `zfs-set-*` oneshots because ADR-003's notifier already reports them through `OnFailure=` and also works while the store is down.
The launchd rules mirror the systemd pair: a not-running rule for kept-alive jobs and a launch-count loop rule at the same 5-in-15-min threshold, plus an exit-code rule because launchd's `state` does not say whether a job's last run failed, which `last exit code` does.
Laptop absence is not a fault: stibnite and pyrite sleep and travel most days, so an absence rule would fire nightly and teach the human to mute `fleet-alerts`, whereas the silence of an always-on host is already R3.2's.
The absence freeze is the per-host form of item 6's store freeze: without it every firing stibnite instance would resolve when the lid closes and fire again on wake.

## Rejected alternatives

- vmalert 1.153.0 with Alertmanager 0.33.1 posting to ntfy's `?template=alertmanager`: two daemons on magnetite to obtain grouping, silencing and inhibition that eighteen rules do not need, and vmalert compatibility with GreptimeDB's Prometheus API is unverified; adopted only on the trigger in Q3.
- vmalert alone: notifies only an Alertmanager-compatible endpoint, so it cannot post to ntfy.
- `alertmanager-ntfy` 1.2.1 as a bridge: ntfy 2.28.0 renders Alertmanager webhooks natively, so the bridge is a third process with no failure prevented.
- Prometheus server as the rule evaluator: agent mode disables alerting, and server mode evaluates against its own storage, which makes it a second store `[INFERENCE: server mode could also read GreptimeDB through Prometheus remote read, which ADR-007 disables]`.
- Grafana alerting: a second dashboard stack beside Perses, which ADR-002 rejected.
- Perses: evaluates no rules at 0.54.0.
- GreptimeDB triggers: enterprise-only (`research/greptimedb.md` F41).
- GreptimeDB flows: produce tables, not notifications, so they add a component in front of the poller this decision needs anyway.
- Folding rules into `otel-envelope`: a failed unit is one message regardless of which rule broke, with no per-instance deduplication and no recovery notice.
- One local alert timer per host posting directly to ntfy: works while the store is down, but deploys rules and an ntfy credential to seven hosts, including laptops, and duplicates what one store query answers.
- Evaluator on cinnabar reading the store over the mesh: the store binds loopback only (ADR-007), so it would need a mesh listener on the store.
- A hosted dead-man service such as healthchecks.io watching cinnabar: adds a third-party egress and account; deferred to Q5.
- A NixOS VM test as the regulator: `vmTests` run only on pyrite's kvm lane and are not gating, whereas a sandboxed fixture check runs on nixbot.
- Anonymous publishing to `fleet-*`: any mesh member could spoof alerts or mask the dead-man by publishing heartbeats.
- Rules over `devloop` merge-queue events now: no ADR-005 rule needs a human within minutes (Q6).
- Absence rules for laptops: stibnite and pyrite are silent whenever they sleep or travel, so the rule would fire on ordinary use (Q9).
- Resolving a silent host's firing instances after 5 min, as for any absent condition: a sleeping laptop would produce a `RESOLVED` and, on wake, a second `FIRING` for an unchanged condition.

## Consequences

magnetite gains one timer and one oneshot that runs every 60 s; cinnabar gains one timer and one oneshot every 5 min.
The evaluator's state file is the only alert history; past alerts are not written to the store, and ntfy's 12 h cache is the only record of sent messages.
Alerts have no silencing: a known condition is accepted by its single `warning` message, and a noisy rule is fixed by a reviewed change to its threshold, its `for`, or its exclusion list.
cinnabar is the single delivery path: while cinnabar or its ntfy is down no alert reaches a human, and nothing in this decision detects that (Q5).
magnetite reaches `ntfy.zt` through cinnabar's dnsmasq and caddy's internal TLS, so delivery inherits ADR-003's dependency on cinnabar's `.zt` resolver.
Following `ntfy-send`'s `-k`, the evaluator and notifier do not verify caddy's certificate, so the `alerter` token's confidentiality rests on ZeroTier's encryption and on cinnabar's dnsmasq answering `ntfy.zt`, as for every existing `ntfy-send` caller; trusting caddy's root certificate instead would need that certificate distributed to magnetite, which no existing caller does.
Every `fleet-alerts` message is readable by every mesh member, including the two Android members; messages carry host, unit, mountpoint, pool and process names and no agent or user content (ADR-008).
Every `fleet-*` publisher needs the `alerter` token, so ad hoc `ntfy-send` calls cannot post to `fleet-alerts`.
ADR-003's notifier changes from one message per failure to one message per failure episode plus a recovery message.
Rule expressions are coupled to ADR-003's and ADR-004's metric names, and only the runtime `RuleSignalMissing` detects a broken coupling, within 30 min of deploy; the build-time check uses fixtures and cannot see the deployed names.
A laptop that dies outright or is lost raises no alert; its user notices.
A condition on stibnite that clears while it sleeps is reported `RESOLVED` only after it wakes, and a failed calendar job such as `harmonia-gc` keeps `LaunchdJobFailed` firing until its next successful run, usually the next day.

## Operating envelope and regulator

Envelope E9.1, noise: at most 10 `FIRING` messages per rolling 24 h across the fleet in steady state, of which at most 3 come from any one laptop host, at most one `FIRING` per alert instance per firing episode, and at most one re-post per `critical` instance per 24 h; a laptop's absence contributes none by construction (items 16 and 17).
Regulator R9.1: the evaluator counts the `FIRING` messages it and the notifier sent in the last 24 h, from its own state file and the notifier's stamp files, and on breach posts one `AlertBudgetExceeded` message per 24 h naming the rule and host with the most firings; the breach is a trigger for a reviewed threshold change, not an automatic suppression, so `critical` alerts are never dropped.
It is shown able to fail at acceptance by the R9.2 fixture leg that fires 11 synthetic instances and asserts that exactly one `AlertBudgetExceeded` message is posted, and by a leg that fires 4 synthetic instances on stibnite and asserts the same.

Envelope E9.2, evaluator semantics: a condition that holds for `for` produces one `FIRING`; a further evaluation with the condition still holding produces none; the condition's absence for 5 min produces one `RESOLVED`; a store error produces `StoreQueryFailing` after 3 min and no `RESOLVED` for any other instance; a firing instance on a host whose `system_memory_usage_bytes` disappears produces no `RESOLVED` until that host reports again; a presence selector with no series for 30 min while an expected host reports produces `RuleSignalMissing`, and the same gap while every expected host is silent produces none; and every rule expression parses as PromQL.
Regulator R9.2, deterministic, build time: a flake check `checks.x86_64-linux.fleet-alert` runs `promtool check rules` over the rendered Prometheus rules file, then runs the evaluator in the build sandbox against a loopback fixture server that replays canned `/v1/prometheus/api/v1/query` responses and records every ntfy POST, and asserts the E9.2 sequence and the E9.1 budget leg.
It is shown able to fail by enumerated mutants in the check, following the mutant-asserting pattern (`research/dev-loop-signals.md` F12): one removing the state file write so the second evaluation re-posts, one setting a rule's `for` to 0 so it fires on the first evaluation, one dropping the state freeze so a store error emits `RESOLVED`, one dropping the absence freeze so a silent host's instance emits `RESOLVED`, and one malformed expression that `promtool` rejects; each mutant must produce a non-empty failure list.

Envelope E9.3, liveness of the alert path: every 10 min window contains at least one `fleet-heartbeat` message while magnetite is up, and a silence of 10 min produces `AlertEvaluatorSilent` within the next 5 min.
Regulator R9.3, runtime: the cinnabar dead-man is itself the regulator for the evaluator, and `WeeklyPipelineTest` is the regulator for the whole path, whose absence on a Monday is observed by the human, which charter A8 accepts as recorded human judgment.
It is shown able to fail at acceptance by stopping `fleet-alert.timer` on magnetite and observing `AlertEvaluatorSilent` within 15 min, then starting it and observing `RESOLVED`.

Envelope E9.4, delivery authorization: an anonymous publish to `fleet-alerts` or `fleet-heartbeat` is refused, an `alerter` publish is accepted, and an anonymous publish to any host-named topic is still accepted.
Regulator R9.4: a `fleet-deadman` precondition step that, before polling, performs an anonymous publish to `fleet-heartbeat` on `[::1]:2586` and fails the unit, and so notifies through ADR-003's notifier, if that publish is accepted.
It is shown able to fail at acceptance by removing the `*:fleet-*:ro` entry and observing the unit fail.

Envelope E9.5, resources: `fleet-alert.service` runs under `MemoryMax = 64M` and `TimeoutStartSec = 50s`, so one run cannot overlap the next and cannot add to a magnetite memory incident.
Regulator R9.5: an evaluation-time assertion in the module that both limits are set, with a mutant that drops `MemoryMax`.

## Failure prevented

- The evaluator and rule table: each failure in the table's last column passes with nobody told.
- Deduplication and recovery notices: one condition produces a message every minute, the human mutes the topic, and the next real alert is lost.
- State freeze on store error: a store outage produces a burst of false recoveries and a second burst of firings.
- `RuleSignalMissing`: a metric rename makes a rule vacuous, which the CCV integrity property forbids for regulators.
- Dead-man on cinnabar: magnetite's death silences the evaluator that would have reported it.
- `alerter`-only publishing to `fleet-*`: a mesh member spoofs alerts or masks the dead-man with fake heartbeats.
- Notifier deduplication: a regulator that fails every 5 min posts 288 messages a day.
- `WeeklyPipelineTest`: a broken delivery path is read as a quiet fleet.
- R9.2 fixture check: an evaluator change that re-posts, never resolves, or fires early ships, which a VM test on the non-gating kvm lane would not stop.
- R9.5: the evaluator itself grows into magnetite's memory during an incident.

## Implementation surface

- Add `modules/nixos/fleet-alert.nix`: `flake.modules.nixos.fleet-alert` with options `services.fleet-alert.evaluator` and `services.fleet-alert.deadman`; the evaluator script as a `pkgs.writeShellApplication` over `curl` and `jq` after the `ntfy-send` precedent (`cameronraysmith/vanixiets@ff2ca5c77:modules/home/tools/commands/system/ntfy-send.nix`), posting through `pkgs.ntfy-send`, the `pkgs/by-name/ntfy-send` package slice S1 adds, rather than a package built in the module; `fleet-alert.service` and `.timer` with `StateDirectory = "fleet-alert"`, `LoadCredential` for the `regulator-password` of ADR-007 and the `alerter` token, `MemoryMax = 64M` and `TimeoutStartSec = 50s`; `fleet-deadman.service` and `.timer` with `StateDirectory = "fleet-deadman"`; and the R9.5 assertion.
- Add `modules/nixos/fleet-alert/rules.nix`: the rule table as Prometheus-format rules with presence selectors and their expected hosts, annotation queries, the `WeeklyPipelineTest` window, and the kept-alive launchd labels read from ADR-004's `schema.nix`, rendered to JSON for the evaluator and YAML for `promtool`.
- Add `modules/checks/fleet-alert.nix`: regulator R9.2 with its fixtures and mutants, using `promtool` from the `cli` output of the root pin's `prometheus` package (`NixOS/nixpkgs@ac1faec44836:pkgs/by-name/pr/prometheus/package.nix:210`, root node `nixpkgs_10`).
- Modify `modules/machines/nixos/magnetite/default.nix`: import `fleet-alert` and enable the evaluator, and add `onFailure = [ "observability-notify@%n.service" ]` to the six existing `zfs-assert-*` and `zfs-set-*` oneshots and to ADR-007's three new ones.
- Modify `modules/machines/nixos/cinnabar/ntfy.nix`: set `auth-access` to `alerter:fleet-*:rw` and `*:fleet-*:ro`, set `services.ntfy-sh.environmentFile` to the generator's `ntfy-env` file, and import `fleet-alert` with the dead-man enabled.
- Modify the `observability-notify@` template unit of ADR-003, in the `agent` role's NixOS module on every in-scope NixOS host, cinnabar included: post to `fleet-alerts` with the `alerter` token, keep the per-unit stamp, and add the `ExecStopPost=` recovery hook to each notified unit.
- Clan vars generator `ntfy-alerter`, `share = true`, declared on magnetite and cinnabar: `runtimeInputs` `ntfy-sh` and openssl; files `token` (secret, a `tk_`-prefixed token from `ntfy token generate`, mode `0400`, written with `printf '%s'`), and `ntfy-env` (secret, `NTFY_AUTH_USERS=alerter:<bcrypt hash from ntfy user hash>:user` and `NTFY_AUTH_TOKENS=alerter:<token>`, `restartUnits = [ "ntfy-sh.service" ]`, deployed only to cinnabar).
- No flake input, no overlay, no new long-running service and no new listener.

## Questions for the human gate

1. Q1: Is a first-party timer evaluator acceptable instead of vmalert and Alertmanager? Recommended: yes; it adds no daemon to magnetite, and the alternative adds two to obtain silencing and grouping that eighteen rules do not need.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
2. Q2: Are the `fleet-alerts` subscribers the human's phone and desktop, subscribing anonymously with read-only access? Recommended: yes; the alternative requires a subscriber login on every device for messages that carry no content.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
3. Q3: What triggers adopting Alertmanager? Recommended: E9.1 breached in two separate weeks after threshold review, or the rule set passing 30 rules; at that point vmalert loads the same Prometheus-format rules and Alertmanager posts to `fleet-alerts` through `?template=alertmanager`, and the alternative keeps growing the evaluator into an Alertmanager.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
4. Q4: Is the noise envelope of 10 firings per 24 h, at most 3 from any one laptop, right? Recommended: yes for the first month, then revised from the counts R9.1 records; a higher bound tolerates the muting failure this record exists to prevent, and without the laptop sub-bound stibnite's activation and sleep churn could spend the fleet's budget.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
5. Q5: Should cinnabar itself be watched by an external dead-man service? Recommended: no for now; a cinnabar outage also takes down `.zt` resolution and the ZeroTier controller, which the human notices in ordinary use, and the alternative adds a third-party account and egress.
   Resolution: deferred to the end of implementation; candidate is an external heartbeat from a free uptime service, weighed against the third-party dependency.
6. Q6: Should a merge-queue stall rule, a `batch formed` with no `batch done` within 2 h, be added over ADR-005's `devloop` events? Recommended: no until ADR-005 names a decision that needs it within hours; the alternative alerts on a signal whose consumer is a 30-day review.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
7. Q7: Should `warning` alerts stay single-shot with no daily reminder? Recommended: yes; reminders for accepted conditions are the noise that leads to muting, and `critical` alerts keep a 24 h reminder.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
8. Q8: Is restricting publishing on `fleet-*` to the `alerter` user, while leaving every other topic anonymous read-write, acceptable? Recommended: yes; it protects the dead-man from spoofed heartbeats without changing any existing `ntfy-send` or hook caller, and the alternative of `deny-all` requires a credential on every host and agent hook.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
9. Q9: Should host absence alert only for always-on hosts, cinnabar and magnetite plus any cloud host while terranix provisions it, and never for stibnite or pyrite? Recommended: yes, with the absence freeze of item 17; the alternative fires whenever a laptop sleeps or travels.
   Resolution: recommended answer accepted at the 2026-10-15 gate.
10. Q10: Should `LaunchdJobFailed` fire on any non-zero last exit code of an allow-listed job, including calendar and run-at-load jobs? Recommended: yes, as a single-shot `warning`; the alternative watches only kept-alive jobs and misses a failed `harmonia-gc` or `sops-install-secrets` run.
    Resolution: recommended answer accepted at the 2026-10-15 gate.
