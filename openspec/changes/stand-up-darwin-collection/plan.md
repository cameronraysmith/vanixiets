# Darwin collection on stibnite (S5) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** stibnite stores memory, per-process memory, `disk0` I/O, `/System/Volumes/Data` fill, launchd job state, disk health, its collector's self-telemetry and its deploy records in `fleet` and `devloop` under `host_name="stibnite"` through magnetite's mTLS ingress; a darwin `otel-envelope` regulates its delivery and posts its own failure notices; the four darwin rules report a stopped, failed or looping launchd job and a stale probe; and stibnite's sleep raises nothing; landed as four pull requests, magnetite's deploys and stibnite's activations (Linear CAM-72).

**Architecture:** `flake.lib.observabilityHosts` gains `platform` and stibnite's row; the clan `otel-collector` agent role gains a `darwinModule` that declares the generators on every darwin row and imports `flake.modules.darwin.otel-collector-agent` where `collect` is true.
The fragment runs five launchd jobs: `otelcol` as `_otelcol`, `otelcol-process` as root with no listener, node_exporter with only `textfile`, `otel-host-probe` every 60 s, and `otel-envelope` every 300 s wrapped by the platform-neutral notifier `observability-notify-run`; their configurations and scripts come from `flake.lib` functions, so the gating `x86_64-linux` check `otel-collector-darwin` validates and tests them without evaluating a darwin configuration.
The evaluator chooses each rule's expected hosts by platform, gains the four darwin rules, and restarts a pending instance's time after a freeze, fleet-wide.

**Tech Stack:** nix flakes with flake-parts and import-tree; nix-darwin `bb0b90db` launchd daemons and `services.prometheus.exporters.node`; clan-core `dbae2101` vars with sops-nix's darwin module; `otelcol-contrib` 0.155.0; smartmontools 7.5; `writeShellApplication` over `/bin/launchctl`, `smartctl`, `jq`, `awk`, `curl` and coreutils; jq and Python for the evaluator and its reference model.

**Spec:** `openspec/changes/stand-up-darwin-collection/` — `design.md` (D1–D13, "Requirement applicability", "Migration Plan"), `specs/`, `tasks.md`, `brainstorm.md` (O1–O11), `proposal.md`; the decision records under `docs/notes/development/observability/` (ADR-003 items 21 to 25, ADR-004:95-100 and :121-123, ADR-008 item 4, ADR-009:131-134) and the components `otel-collector`, `host-probes` and `fleet-alert`.

## Global Constraints

- Repository: `$REPO` is the repository root, jj-colocated; never relocate `@`; commit each plan task as changes off `main@origin` per the repository's jj workflow; Tasks 2 and 3 form pull request 1, Task 5 Step 2 is pull request 2, Task 6 pull request 3 and Task 7 pull request 4, each landing through the merge queue before the next is enqueued.
- Pull request 1's implementation starts only after Task 1 Step 4: the omnigent session's edits to `modules/clan/services/otel-collector/flake-module.nix` and `schema.nix` have landed, and this change's commits rebase onto them (O9); this change touches those two files only in the hunks Tasks 2, 3 and 6 name.
- After creating or renaming any file, run `jj st --no-pager >/dev/null` before any `nix` command reads the tree.
- Concurrent implementation subagents each get their own `git worktree add` copy, or run in sequence; no `jj workspace add` is used.
- Commit messages, pull-request titles, bodies and comments carry no slice name, charter version, decision, finding, requirement or task code and no pull-request ordinal; ADR numbers, file paths, `CAM-72` and GitHub pull-request numbers are allowed.
- Before every commit run `nix fmt` and keep its log; a tree failing `nix fmt -- --fail-on-change` is not pushed.
- Evidence: `<command> 2>&1 | tee logs/s5-evidence/<item>-<slug>-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`, filters after the `tee`; `logs/` is git-ignored; no credential value in any repository file or log.
- Commands on magnetite run as `ssh magnetite.zt 'bash -c '"'"'…'"'"''` or with a quoted heredoc to `bash -s`, because its login shell is zsh; local commands on stibnite run under `/bin/bash`, with `/bin/date`, `/bin/launchctl` and `/usr/bin/sudo`; zsh scripts use `rc`, never `status`; every jq filter tolerates a missing field (`// empty`, `// 0`).
- Nix-managed outputs are verified by `nix eval`, `nix build`, or the delivered path after activation, never by reading source; each step says which.
- Evaluation cost: every new or changed check records `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/<check>-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath` and `jq '.gc.totalBytes, .cpuTime'` of the stats file against 536,870,912 B before and after its task; a figure over that stops the task.
- Every check clause relates two independently defined values, named in the step before its mutant is written; a relation within one host is an assertion in the darwin fragment, shown failing by an `extendModules` override, never a check clause; each mutant runs only the case it must fail.
- Every regulator (check clause, assertion, fixture leg, wrapper case) is written before the code it judges and seen failing; every runtime clause has a negative control seen failing.
- Every script lists every binary it calls in `runtimeInputs`, except the darwin system binaries `/bin/launchctl`, `/bin/ps` and `/usr/bin/curl` (through `ntfy-send`), which it calls by absolute path; the Linux check stubs them by an injected path.
- import-tree loads every `.nix` file under `modules/` as a flake-parts module; fixtures and scripts use other extensions.
- Pins: `otelcol-contrib` 0.155.0, smartmontools 7.5, node_exporter 1.12.1, read at the root pin (`nix eval --raw .#darwinConfigurations.stibnite.pkgs.path`); vendor behaviour is read there before depending on it and cited `path:line`.
- Vendored-tool probes run the consumer's exact argument list (schema `plan` instruction): the probe calls `smartctl -j -H -A <device>` and `/bin/launchctl print system/org.nixos.<label>`; the agent's plist calls `otelcol-contrib --config <store path>`; Task 1 Step 3 records each list as run.
- Store: HTTP `http://127.0.0.1:4000` on magnetite; PromQL `GET /v1/prometheus/api/v1/query` and `query_range` with `x-greptime-db-name`; `regulator` (`ro`) for every read, its password from a file, never on an argument list.
- Addresses: the ingress is `[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` = `flake.lib.hosts.magnetite.zt` = `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`.
- Shared vars: a reader is added only with `CLAN_NO_COMMIT=1 clan vars fix stibnite --generator <otel-ca|ntfy-alerter>`; `clan vars generate` runs only on `otel-cert`; after every vars step the sha256 of `vars/shared/otel-ca/ca.crt/value` and of the decrypted `ntfy-alerter` token (`clan vars get magnetite ntfy-alerter/token | sha256sum`, never printed) equal the previous step's, and the step stops otherwise.
- Deploys: from `$DEPLOY` = `$REPO/../vanixiets-worktrees/deploy`, created once with `git -C $REPO worktree add --detach $DEPLOY origin/main` and refreshed before each deploy with `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`; magnetite and cinnabar only after `nixbot-logs queue` prints `Queue is empty`, by exactly `clan machines update <machine> 2>&1 | tee logs/<machine>-$(date +%Y%m%d-%H%M%S).log`; stibnite by exactly `just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log` in `$DEPLOY`, with the operator present (O1), and only after `logs/s5-evidence/recent-activation.sh` finds no other activation of stibnite since the step's previous read or within the last hour, because another session activated stibnite at 2026-11-05T23:26:45Z (Task 4 Step 1); never from the jj join.
- Every edit of stibnite's row in `flake.lib.observabilityHosts` is followed by magnetite's deploy, because the evaluator reads the table from magnetite's closure; every deploy or activation step ends by recording every post since its start from `sudo journalctl -u fleet-alert -u 'observability-notify@*' --since <start>` on magnetite and `/var/lib/otel-envelope/notify.log` on stibnite, each with its cause.
- Scratch tree: before stibnite's flag flips, its collecting configuration is evaluated in `$SCRATCH` = `$REPO/../vanixiets-worktrees/scratch`, a throwaway `git worktree add --detach $SCRATCH <commit>` in which `modules/lib/observability-hosts.nix` drops stibnite's `collect = false`; nothing is committed from it, and it is removed with `git worktree remove --force $SCRATCH` after each use.
- stibnite: nothing outside steps marked **[operator]** activates, sleeps or restarts stibnite or any of its launchd jobs; every other step runs read-only commands on it; no activation runs from a commit that has the role's `darwinModule` without the vars step's files (design D5 "Deploy order").
- Logs of launchd jobs: launchd opens `StandardOutPath` and `StandardErrorPath` as the job's `UserName`, so each job logs into a directory its own account owns (design D2).
- Queues (bytes sizer, `file_storage` at `/var/lib/opentelemetry-collector/queue`): stibnite's `otlp_http/ingress` 400 MiB and `otlp_http/ingress-logs` 16 MiB, as every non-ingress agent.
- Envelope on stibnite: agent limiter 150/30 MiB; `otelcol-process` limiter 64/16 MiB; C5 fails above 256 MiB of physical footprint for `otelcol` and 128 MiB for `otelcol-process` (O5), read from `/usr/bin/top`'s MEM field because the resident size also counts the mapped binary's file-backed pages; the envelope finishes inside its 300 s interval.
- Linear: the orchestrator binds CAM-72 and posts its transitions per `openspec-linear-sync`; no plan step mutates Linear.
- Prose files keep one sentence per line.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Lib | `flake.lib.observabilityHosts.<host>` gains `platform : "nixos" \| "darwin"` (default `"nixos"` in the `agent` helper); `stibnite = agent [ ] // { platform = "darwin"; notifiedUnits = [ "otel-envelope" ]; smartDevices = [ "disk0" ]; collect = false; }`, the `collect = false` removed by pull request 2 | Task 2 |
| Assertion | in `modules/clan/inventory/services/otel-collector.nix`: each row's `platform` equals `modules/clan/inventory/machines.nix`'s `machineClass` | Task 2 |
| Role | `otel-collector` agent role `perInstance.darwinModule`, on every darwin row whatever its `collect`: the `_otelcol` account (uid and gid 536, `users.knownUsers`, `users.knownGroups`, home `/var/empty`, shell `/usr/bin/false`); generators `otel-ca`, `otel-cert` (`key.pem` owner and group `_otelcol`, mode `0400`, `neededFor = "services"`, no `restartUnits`), `ntfy-alerter` (token owner `_otelcol`, mode `0400`); imports `flake.modules.darwin.otel-collector-agent` where `collect` is true | Task 2 |
| Lib | `flake.lib.otelCollectorDarwin { hostName; certFile; keyFile; caFile; } → { agent; process; targets; exporters; }`, attrsets from `flake.lib` data only; `targets = [ { job = "node"; url = "http://127.0.0.1:9100/metrics"; } { job = "otelcol"; url = "http://127.0.0.1:8888/metrics"; } ]`; `exporters = [ "otlp_http/ingress" "otlp_http/ingress-logs" ]` | Task 2 |
| Lib | `flake.lib.otelHostProbe pkgs { labels; devices; ownerAliases; textfileDir; launchctl ? "/bin/launchctl"; }` → `writeShellApplication` `otel-host-probe`, writing `launchd.prom` and `smartctl.prom` by write-then-rename; a missing `last exit code` is 0 after a jetsam idle exit and -1 otherwise | Task 2 |
| Lib | `flake.lib.otelHostProbeLabels { launchdLabels; daemonLabels; }` → the allow-listed labels among a host's daemon labels, in `modules/lib/otel-collector-darwin.nix`, read by the fragment and judged by the check | Task 2 |
| Lib | `flake.lib.observabilityNotifyRun pkgs { label; host; topic ? "fleet-alerts"; tokenFile; stateDir; logFile; minIntervalSec ? 900; }` → `writeShellApplication` `observability-notify-run`, run as `observability-notify-run -- <command…>`, appending each `FAILED` to `logFile`: `/var/lib/observability-notify/failed.log` on NixOS (unchanged), `/var/lib/otel-envelope/notify.log` on darwin | Task 3 |
| Lib | `flake.lib.otelEnvelope` gains `darwinMemory ? null` (`{ launchctl; top; limits = { "org.nixos.otelcol" = 268435456; "org.nixos.otelcol-process" = 134217728; }; }`) and reads `STATE_DIRECTORY` from the environment; clause `C5 memory` | Task 3 |
| Fragment | `flake.modules.darwin.otel-collector-agent` at `modules/darwin/otel-collector-agent.nix`: daemons `otelcol`, `otelcol-process`, `otel-host-probe` (`StartInterval = 60`, `_prometheus-node-exporter`, logging to `/var/lib/prometheus-node-exporter/otel-host-probe.log`), `otel-envelope` (`StartInterval = 300`, `_otelcol`); `services.prometheus.exporters.node` on `127.0.0.1:9100` with only `textfile` at `/var/lib/prometheus-node-exporter/textfile`; directories `/var/lib/opentelemetry-collector/queue`, `/var/lib/otel-envelope`, `/var/log/otelcol` owned by the role's `_otelcol`; `EnvironmentVariables.OTEL_CERT_SHA256` on `otelcol`; the darwin alias assertion over `omnigent-host-<owner>` daemons | Tasks 2, 3 |
| Assertions | in the fragment: 24 h queue ≥ `24 * 60 * flake.lib.otelCollectorSchema.fleetBytesPerMinute`; queues' sum < 512 MiB; every listener on loopback; no daemon the fragment declares sets `StartCalendarInterval` (the existing `harmonia-gc` and `nix-cleanup-gcroots` calendars are outside its scope, design D8); every `omnigent-host-<owner>` daemon has an alias (Task 2); `launchdKeptAlive` equals the allow-listed daemons with evaluated `KeepAlive = true` (Task 6) | Tasks 2, 6 |
| Schema | `flake.lib.otelCollectorSchema` gains `darwinNodeExporterKeep` (ADR-004:95-96) and `launchdLabels` (ADR-004:121) in Task 2; in Task 6 `launchdLabels` gains `org.nixos.otel-envelope`, and `launchdKeptAlive` (the allow-listed labels whose evaluated `KeepAlive` is `true`, read by the rules) is added beside it | Tasks 2, 6 |
| Check | `checks.x86_64-linux.otel-collector-darwin` at `modules/checks/otel-collector-darwin.nix`, fixtures under `modules/checks/otel-collector-darwin/` without `environment` blocks, stubs passed as `pkgs // { … }`; prints `ok: <case>` and `mutant <name> rejected`; mutants `nodeListenEmpty`, `seventhIdentityAttribute`, `processEndpoint`, `diskIncludeAll`, `exporterAddressOther`, `labelDotUnescaped`, `aliasDropped`, `pidWritten`, `missingExitCodeAsZero`, `idleExitAsFailure`, `postEveryFailure` | Tasks 2, 3 |
| Check | `checks.x86_64-linux.otel-envelope` gains the darwin cases and mutant `c5WrongPid` | Task 3 |
| Fixture legs | `fleet-alert`, each `name` starting with its identifier: `pendingAcrossFreeze`, `pendingAfterWake`, `linuxSelectorDarwinOnly`, `stibniteNotCollecting` (Task 3); `darwinSignalMissing`, `keptAliveStopped`, `envelopeUnloaded`, `envelopeFailedNotReported`, `harmoniaFailedReported`, `restartLoop`, `probeStale`, `nvmeExpectsStibnite`, `stibniteSilent` (Task 6) | Tasks 3, 6 |
| Rules | `flake.lib.fleetAlertRules` derives `nixosHosts`, `darwinHosts`, `smartHosts`; rules `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop`, `HostProbeStale` with design D9's expressions | Tasks 3, 6 |
| Transition | `transition.jq` and `model.py`: a pending instance unfrozen on this run restarts `activeSince` at this run | Task 3 |
| Evidence | `logs/s5-evidence/`; `logs/s5-evidence/window.env` holds `STIBNITE_ACTIVATE_EPOCH`, `MAGNETITE_DEPLOY_EPOCH`, `CINNABAR_DEPLOY_EPOCH`, each from `/bin/date -u +%s`; `recent-activation.sh` guards every stibnite activation | Tasks 4, 5 |

## Task map

| Plan task | `tasks.md` items | Pull request | Deploy |
|---|---|---|---|
| Task 1: Plan review, baselines, rehearsal and the omnigent gate | 1.1–1.4 | planning pull request | none |
| Task 2: Host table, certificates, renderers and the darwin fragment | 2.1–2.7 | 1 | vars committed in it |
| Task 3: The notifier wrapper, the darwin envelope and the alert plumbing | 3.1–3.8 | 1 | — |
| Task 4: Deploying pull request 1 | 4.1–4.3 | — | magnetite, then stibnite **[operator]**, then cinnabar |
| Task 5: stibnite's watched activation | 5.1–5.4 | 2 (Step 2) | stibnite **[operator]**, then magnetite |
| Task 6: The darwin rules | 6.1–6.6, 6.1 at least 24 h after 5.2 | 3 | magnetite, then stibnite **[operator]** |
| Task 7: Documentation | 7.1–7.4 | 4 | none |
| Task 8: Acceptance | 8.1 after 5.4; 8.2 after 5.4; 8.3–8.5 after 6.6; 8.6–8.8 after 6.6 | none | none |
| Task 9: Close-out and integration verification | 9.1–9.6, 10.1, and §11 for applied review findings | close-out pull request | none |

Steps marked **[operator]**: 4.2, 5.1, 5.2, 6.6, 8.2, 8.3, 8.4, 8.5, 8.6.

Rollback reverses the order: pull request 3's revert and a magnetite deploy remove the darwin rules; restoring stibnite's `collect = false` and activating stibnite with the operator present stops its jobs, leaving its queue on disk, followed by a magnetite deploy so the evaluator stops expecting it; reverting pull request 1 and deploying magnetite removes the row and returns the evaluator's pending-time rule; the vars stay committed and unused.

---

## Task files

Each task lives in its own file so that one implementer reads only its task.

- [Task 1: Plan review, baselines, rehearsal and the omnigent gate](plan/task-1.md)
- [Task 2: Host table, certificates, renderers and the darwin fragment](plan/task-2.md)
- [Task 3: The notifier wrapper, the darwin envelope and the alert plumbing](plan/task-3.md)
- [Task 4: Deploying pull request 1](plan/task-4.md)
- [Task 5: stibnite's watched activation](plan/task-5.md)
- [Task 6: The darwin rules](plan/task-6.md)
- [Task 7: Documentation](plan/task-7.md)
- [Task 8: Acceptance](plan/task-8.md)
- [Task 9: Close-out and integration verification](plan/task-9.md)
