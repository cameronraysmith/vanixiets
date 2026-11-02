# Linux fleet collection (S4) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every provisioned NixOS host, magnetite, cinnabar and pyrite, stores its host, process, unit, ZFS, OOM, zerotierone and file-system series in `fleet` under its own `host_name`, pyrite also its NVMe health, through magnetite's ingress on ZeroTier that refuses any client without an `otel-ca` certificate; every agent host ships its deploy records into `devloop`; `otel-envelope` regulates each agent and the fleet budget; and cinnabar's silence raises one `RuleSignalMissing` while pyrite's raises nothing; landed as four pull requests and deploys of cinnabar, magnetite and pyrite (Linear CAM-71).

**Architecture:** `flake.lib.observabilityHosts` is the one host table; the clan `otel-collector` agent role, generated for its hosts, sets each host's notified units, SMART devices, `otel-cert` and notifier token from it, and the alert rules read their always-on hosts, expected hosts and `SystemdUnitFailed` exclusion from it.
One agent fragment switches on `vanixiets.otelCollector.ingress`: on magnetite its pipelines end in the in-process `forward` connector, elsewhere in two mTLS `otlp_http` exporters to `otlp/mesh` at `[flake.lib.hosts.magnetite.zt]:4318`, each with a persistent queue.
`otel-envelope`, a 5-minute oneshot on every agent host, reads its own collector's telemetry and declared targets (R3.2), and on magnetite hourly also the store's budget (R4.2); R3.1, `otel-envelope`'s check, `fleet-alert` and the on-demand container test `fleet-ingress` regulate it before deploy.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan vars generators with openssl P-256; `otelcol-contrib` 0.155.0 (`configtls`, `file_storage`, `filesystem` scraper, prometheus receiver); nixpkgs' `services.prometheus.exporters.smartctl` (smartmontools 7.5); `greptimedb-bin` 1.2.1; `pkgs.testers.runNixOSTest` systemd-nspawn containers needing `uid-range` (magnetite); `writeShellApplication` over `curl`, `jq`, `awk` and coreutils.

**Spec:** `openspec/changes/stand-up-linux-fleet-collection/` — `design.md` (D1–D13), `specs/`, `tasks.md`, `brainstorm.md`, `proposal.md`; `logs/s4/grounding.md` (GR), `logs/s4/design-inputs.md` (DI) and `logs/s4/spike/`; the decision records under `docs/notes/development/observability/` as amended under charter v23 (ADR-003, ADR-004, ADR-009, `components/otel-collector.md`, `components/host-probes.md`).

## Global Constraints

- Repository: `$REPO` is the repository root, jj-colocated; never relocate `@`; commit each plan task as changes off `main@origin` per the repository's jj workflow; Tasks 2 and 3 form pull request 1, Task 6 pull request 2, Task 7 pull request 3, Task 8 pull request 4, each landing through the merge queue before the next is enqueued.
- After creating or renaming any file, run `jj st --no-pager >/dev/null` before any `nix` command reads the tree.
- Concurrent implementation subagents each get their own `git worktree add` copy, or run in sequence; Task 2 Steps 3 and 4 (generators and agent role) never run concurrently in one working copy (S2-R6); no `jj workspace add` is used in this repository, because flake evaluation resolves the root through git.
- Commit messages, pull-request titles, bodies and comments carry no slice name, charter version, decision, finding, requirement or task code and no pull-request ordinal; they name what the change does; ADR numbers, file paths, `CAM-71` and GitHub pull-request numbers are allowed.
- Before every commit run `nix fmt` and keep its log; a tree failing `nix fmt -- --fail-on-change` is not pushed.
- Evidence: `<command> 2>&1 | tee logs/s4-evidence/<item>-<slug>-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`, filters after the `tee`; `logs/` is git-ignored; no credential value in any repository file or log.
- Remote commands run as `ssh <host>.zt 'bash -c '"'"'…'"'"''` or with a quoted heredoc to `bash -s`, because login shells are zsh; journals are read with `sudo journalctl`; on stibnite dates use `/bin/date`; zsh scripts use `rc`, never `status`; a boot time is read as `awk '/^btime/ {print $2}' /proc/stat`, never `uptime -s`, which fails for the ssh user on cinnabar and pyrite; every jq filter tolerates a missing field (`// empty`, `// 0`).
- Nix-managed outputs are verified by `nix eval`, `nix build`, or the delivered path after activation, never by reading source; each step says which.
- Evaluation cost: every new or changed check records `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/<check>-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath` and `jq '.gc.totalBytes, .cpuTime'` of the stats file against 536,870,912 B before and after its task; a figure over that stops the task and applies design D10's remedies in order (charter v19; S2-R6).
- Every check clause relates two independently defined values, named in the step before its mutant is written; a relation within one host is an assertion in the agent fragment or host, shown failing by an `extendModules` override, never a check clause; a clause whose two values render from one Nix attribute is not written (S2-R6).
- Every regulator (check clause, assertion, container case, fixture leg) is written before the code it judges and seen failing; every runtime clause has a negative control seen failing.
- Every unit script lists every binary it calls in `runtimeInputs`, and the unit itself runs in `fleet-ingress`, not only its script (S2-R6).
- import-tree loads every `.nix` file under `modules/` as a flake-parts module; fixtures and scripts use other extensions.
- Pins: `otelcol-contrib` 0.155.0; `greptimedb-bin` 1.2.1; smartmontools 7.5; vendor behaviour is read at the pinned nixpkgs (`nix eval --raw .#nixosConfigurations.cinnabar.pkgs.path`) before depending on it and cited `path:line`.
- Store: HTTP `http://127.0.0.1:4000`; SQL `POST /v1/sql?db=<db>` with form field `sql`; PromQL `GET /v1/prometheus/api/v1/query` with `x-greptime-db-name`; `regulator` (`ro`) for every read, its password from a file (`--netrc-file`, `curl --config -`, `$CREDENTIALS_DIRECTORY`), never on an argument list.
- Addresses: `flake.lib.hosts.magnetite.zt` = `vars/shared/zerotier-ip-magnetite-zerotier/ip/value` = `fddb:4344:343b:14b9:399:930f:39db:40d2`; cinnabar's public address `49.13.68.78`.
- Shared vars: a reader of a shared generator is added only with `CLAN_NO_COMMIT=1 clan vars fix <machine> --generator <generator>`; `clan vars generate` runs only on per-machine generators (`otel-cert`), and the one first creation of `otel-ca` happens as `otel-cert`'s missing dependency on magnetite; after every vars step the sha256 of `vars/shared/otel-ca/ca.crt/value` and of the decrypted `ntfy-alerter` token (`clan vars get magnetite ntfy-alerter/token | sha256sum`, never printed) equal the previous step's, and the step stops otherwise; the token is hashed by value because `clan vars fix` re-encrypts its file for each new reader (design D1; charter v18).
- Deploys: from the deploy worktree `$DEPLOY` = `$REPO/../vanixiets-worktrees/deploy`, created once with `git -C $REPO worktree add --detach $DEPLOY origin/main` and refreshed before each deploy with `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`; only after `nixbot-logs queue` prints `Queue is empty`; by exactly `clan machines update <host> [--target-host <addr>] 2>&1 | tee logs/<host>-$(date +%Y%m%d-%H%M%S).log`, run in `$DEPLOY` (so the deploy log lands in `$DEPLOY/logs/`, git-ignored), with no wrapper script; evidence commands and `window.env` stay under `$REPO/logs/s4-evidence/`; order vars (in pull request 1), cinnabar over `root@49.13.68.78`, magnetite, pyrite over its LAN address with the operator present; rollback in reverse (design D13, Migration Plan).
- Why a separate worktree: during implementation the jj join in `$REPO` holds the next unmerged pull request, so deploying from the working copy would ship unreviewed code.
- Collection per host: `flake.lib.observabilityHosts.<host>.collect` gates the agent role's collection on that host; pull request 1 sets it true for magnetite, electrum, galena and scheelite and false for cinnabar and pyrite, so no routine deploy of either from `main` applies the agent role; each of those two gets its own one-line pull request setting `collect = true`, landed immediately before its watched deploy (Task 4 Step 2, Task 5 Step 2) (design D6, D13).
- Scratch tree: before cinnabar's and pyrite's flags flip, their agent configuration is evaluated in `$SCRATCH` = `$REPO/../vanixiets-worktrees/scratch`, a throwaway `git worktree add --detach $SCRATCH <commit>` of the commit under test (`jj log --no-graph -r @ -T commit_id` after `jj st`) in which `modules/lib/observability-hosts.nix` sets `collect = true` for cinnabar and pyrite; nothing is committed from it, and it is removed with `git worktree remove --force $SCRATCH` after each use.
- pyrite: nothing outside Task 5 may restart pyrite, its network or `zerotierone`; before Task 5 only read commands run on it.
- Queues (bytes sizer, `file_storage` at `/var/lib/opentelemetry-collector/queue`): magnetite unchanged (`fleet` 400, `agent` 48, `devloop` 4, `devloop_ci_attribute` 32, three devloop tables 4 each, total 496 MiB); other agents `otlp_http/ingress` 400 MiB and `otlp_http/ingress-logs` 16 MiB.
- Envelope: magnetite's collector `MemoryMax = "512M"`, `OOMScoreAdjust = 300`, limiter 384 MiB; other agents `MemoryMax = "256M"`, limiter 150/30 MiB, no `OOMScoreAdjust`; `otel-envelope` `MemoryMax = "64M"`, `TimeoutStartSec = "4min"`; smartctl exporter `MemoryMax = "64M"`.
- `regulator-password` holders on magnetite: `devloop-reconcile`, `fleet-alert`, `greptimedb-envelope`, and from Task 7 `otel-envelope`.
- The two `sqlquery` receivers' query text stays byte-identical, so their cursors keep their storage keys (S2-R6).
- Linear: CAM-71 moves Todo → In Progress at Task 2's first commit, In Progress → In Review when `verify.md` is written, In Review → Done at archive, per `openspec-linear-sync`, with the ledger in `proposal.md`'s front matter.
- Prose files keep one sentence per line.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Lib | `flake.lib.observabilityHosts.<host> = { collect : bool; alwaysOn : bool; notifiedUnits : [ str ]; smartDevices : [ str ]; }` for magnetite, cinnabar, pyrite, electrum, galena, scheelite, at `modules/lib/observability-hosts.nix`; `collect` true except for cinnabar and pyrite until their own pull requests; magnetite's `notifiedUnits` are GR §4's 16 plus `otel-envelope`, cinnabar's `fleet-deadman`, `opentelemetry-collector`, `otel-envelope`, every other host's `opentelemetry-collector`, `otel-envelope` (`otel-envelope` added in Task 3 Step 3); only pyrite has `smartDevices = [ "/dev/nvme0" ]`; only magnetite and cinnabar are `alwaysOn` | Task 2 |
| Options | in `collectorCore`: `vanixiets.otelCollector.ingress` (`bool`, default `false`, set `true` by `otel-collector-ingress`), `vanixiets.otelCollector.caFile` (`nullOr path`, default `null`; the CA certificate as a store path), `vanixiets.otelCollector.smartDevices` (`listOf str`, default `[ ]`) (Task 2); `vanixiets.otelCollector.envelopeBudget` (`nullOr attrs`, default `null`; `otelEnvelope`'s `budget`, set by the clan ingress role) (Task 7) | Tasks 2, 7 |
| Generators | `otel-ca` (shared; `ca.key` `deploy = false`; `ca.crt` `secret = false`, no `restartUnits`) and `otel-cert` (per machine; `key.pem` secret, `cert.pem` `secret = false`; `validation.subjectAltNames`, `validation.extendedKeyUsage`; `restartUnits = [ "opentelemetry-collector.service" ]` on both files where `collect` is true), declared by the clan agent role on every agent host | Task 2 |
| Credentials | collector credentials `otel-cert` and `otel-key` at `/run/credentials/opentelemetry-collector.service/{otel-cert,otel-key}`, loaded by the clan agent role on every agent host | Task 2 |
| Collector names | exporters `otlp_http/ingress`, `otlp_http/ingress-logs` (non-ingress hosts); receiver `otlp/mesh` (ingress); scrape jobs `otelcol`, `smartctl`; receiver `host_metrics/memory` gains scraper `filesystem`; `file_log/deploy-record`, `resource/devloop-deploy_record`, `logs/devloop-deploy_record` move to the agent fragment unchanged | Task 2 |
| Schema | `flake.lib.otelCollectorSchema.fleetBytesPerMinute = 256000` (moved from CC), `otelcolKeep` (the 8 names of design D4), `smartctlKeep` (ADR-004:91's 8 names), `systemdUnitsNotifierPattern = "observability-notify@*.service"` (excluded from the cap) | Task 2 |
| Lib | `flake.lib.devloopCollection` gains `keepAttributes`, `dropBody`, `deployRecordFile` | Task 2 |
| Lib | `flake.lib.fleetAlertRules { lib, hosts ? <flake.lib.observabilityHosts> }`; `notifiedUnits` argument removed; exclusion = union of `hosts.*.notifiedUnits` (Task 2); `RuleSignalMissing.alwaysOn` (hosts with `alwaysOn` and `collect`) and every rule's `presence[].expectedHosts` (hosts with `collect`, and `smartDevices` for the NVMe rules) from `hosts` (Task 6) | Tasks 2, 6 |
| Lib | `flake.lib.otelEnvelope pkgs { hostName; telemetryUrl ? "http://127.0.0.1:8888/metrics"; targets; ingress ? false; budget ? null; }` → `writeShellApplication` named `otel-envelope`; `targets` a list of `{ job; url; }`; `budget = { storeUrl; notifiedUnits = { <host> = [ … ]; }; databases; }` (Task 7); state `$STATE_DIRECTORY/state`, one line per series `<key> <value>`, counters carried forward from the previous state on a run without telemetry; output one line per clause `otel-envelope: <C1…C4|B1…B6> <name>: ok` or `…: FAIL <detail>`; exit 1 on any FAIL; env `OTEL_ENVELOPE_MAX_UNITS` (default 40), `OTEL_ENVELOPE_MINUTE` (default `date -u +%M`; the budget runs when it is `00`), `OTEL_ENVELOPE_FORCE_HOURLY` (`1` runs B1–B6 whatever the minute) | Tasks 3, 7 |
| Clauses | `C1 telemetry`, `C2 targets`, `C3 queue`, `C4 loss` (design D7); `B1 active-series`, `B2 label-values`, `B3 per-host`, `B4 notifier-instances`, `B5 devloop-rows`, `B6 ttl` (design D8) | Tasks 3, 7 |
| Units | `otel-envelope.service`, `otel-envelope.timer` on every agent host; `prometheus-smartctl-exporter.service` where `smartDevices` is non-empty | Tasks 2, 3 |
| Checks | `checks.x86_64-linux.otel-envelope` at `modules/checks/otel-envelope.nix`, fixtures `modules/checks/otel-envelope/*.prom`, prints `ok: <case>` and `mutant <name> rejected` | Task 3 |
| R3.1 | `otel-collector-config`: loopback clause `R3.1: an endpoint off loopback other than otlp/mesh, or otlp/mesh not on magnetite's assigned address`; mutants `meshWildcard`, `secondMeshReceiver`, `ztAddressOther`; logs clause admits `otlp/mesh`; failure-wiring policy gains `otel-envelope`, mutant `envelopeNotNotified`; unit-cap and alias clauses with `systemdUnitsOverCap`, `ownerWithoutAlias` removed | Tasks 2, 3 |
| R8.2 | `greptimedb-envelope`: ownership clause covers `otel-cert`'s `key.pem`, mutant `workerOwnsOtelKey` (Task 2); magnetite's holder assertion adds `otel-envelope` (Task 7) | Tasks 2, 7 |
| Fixture legs | `fleet-alert`: `twoHostExclusionLeg` (Task 2); `cinnabarSilentLeg`, `laptopSilentLeg`, `nvmeExpectsPyriteLeg`, `notCollectingLeg`, `filesystemLeg`, `nvmeLeg`, runtime mutant `alwaysOnMagnetiteOnly` (Task 6) | Tasks 2, 6 |
| Container test | `vmTests.x86_64-linux.fleet-ingress` at `modules/vm-tests/fleet-ingress.nix`, data under `modules/vm-tests/fleet-ingress/`; one container `store` with the ingress collector (`opentelemetry-collector.service`), a second agent collector `agent-collector.service` with electrum's rendered non-ingress configuration and `host.name` `electrum`, the store and schema job, `otel-envelope.service` for each, `services.observability-notify.units` and a `tokenFile` set in the container; cases `refusal`, `delivery`, `backPressure`, `lossControls`, `crashLoop`, `longRun` (10 runs), `absentClientCa` (Task 3), `budget` (Task 7) | Tasks 3, 7 |
| Evidence | `logs/s4-evidence/`; `logs/s4-evidence/window.env` holds `CINNABAR_DEPLOY_EPOCH`, `MAGNETITE_RECEIVER_EPOCH`, `PYRITE_DEPLOY_EPOCH`, each from `/bin/date -u +%s` | Tasks 4, 5 |

## Task map

| Plan task | `tasks.md` items | Pull request | Deploy |
|---|---|---|---|
| Task 1: Plan review, baselines and rehearsal | 1.1–1.3 | planning pull request | none |
| Task 2: Host table, certificates and the agent by role | 2.1–2.10 | 1 | vars committed in it |
| Task 3: `otel-envelope` and `fleet-ingress` | 3.1–3.5 | 1 | — |
| Task 4: Deploying to cinnabar and magnetite | 4.1–4.6 | cinnabar's `collect` pull request in 4.2 | cinnabar, then magnetite |
| Task 5: pyrite, with the operator present | 5.1–5.4 after Task 4; 5.5–5.6 after 6.7; 5.7 a day after 5.2 | pyrite's `collect` pull request in 5.2 | pyrite |
| Task 6: Rules over the fleet | 6.1–6.7 | 2 | magnetite |
| Task 7: The fleet budget | 7.1–7.6 | 3 | magnetite |
| Task 8: Documentation | 8.1–8.4 | 4 | none |
| Task 9: Acceptance | 9.1 after 4.5; 9.2–9.3 after 6.7; 9.4 any time after 5.4 | none | none |
| Task 10: Close-out and integration verification | 10.1–10.5, 11.1, and §12 for applied review findings | close-out pull request | none |

Rollback reverses the deploy order: pull request 3's revert stops R4.2; pull request 2's restores magnetite as the only always-on and expected host; pull request 1 is undone by setting pyrite's and cinnabar's `collect` back to false and deploying each (pyrite with the operator present, cinnabar over `root@49.13.68.78`), each agent's queue left on disk, then by reverting pull request 1 with `vars/` kept and deploying magnetite; the vars stay committed and unused.

---

## Task files

Each task lives in its own file so that one implementer reads only its task.

- [Task 1: Plan review, baselines and rehearsal](plan/task-1.md)
- [Task 2: Host table, certificates and the agent by role](plan/task-2.md)
- [Task 3: `otel-envelope` and `fleet-ingress`](plan/task-3.md)
- [Task 4: Deploying to cinnabar and magnetite](plan/task-4.md)
- [Task 5: pyrite, with the operator present](plan/task-5.md)
- [Task 6: Rules over the fleet](plan/task-6.md)
- [Task 7: The fleet budget](plan/task-7.md)
- [Task 8: Documentation](plan/task-8.md)
- [Task 9: Acceptance](plan/task-9.md)
- [Task 10: Close-out and integration verification](plan/task-10.md)
