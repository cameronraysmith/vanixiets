# External watch of the alert path (CAM-76) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** cinnabar's `fleet-deadman` pings a healthchecks.io check after each run that found the alert path working, with magnetite's heartbeat in its window, so that an outage of cinnabar, ntfy, caddy, the mesh path or the dead-man itself emails the operator within 15 min of the last accepted ping, without passing through cinnabar; landed as two pull requests and one cinnabar deploy, accepted by stopping ntfy on cinnabar and the evaluator on magnetite (Linear CAM-76; ADR-009 Q5).

**Architecture:** `flake.lib.fleetDeadmanPing` is a small `writeShellApplication` that reads a curl configuration file on stdin and requires the answer `OK`; `flake.lib.fleetAlertDeadman` takes it as `ping` and calls it as its last step when the poll held a heartbeat.
The option `services.fleet-alert.deadman.pingConfigFile` wires the credential through `LoadCredential`, and cinnabar sets it from the per-machine clan vars generator `fleet-deadman-ping`, whose hidden prompt the operator fills.
`checks.x86_64-linux.fleet-alert` gains `deadmanPingRehearsal` (R9.6) and `pingTransport`, each with mutants; the check's period, grace and email live in healthchecks.io's web interface.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan vars generators with prompts; `writeShellApplication` over `curl`, `jq` and coreutils; Python 3 `http.server` stand-ins in the build sandbox; healthchecks.io's Pinging API.

**Spec:** `openspec/changes/watch-the-alert-path-externally/` — `design.md` (D1–D8, W1–W9, O1–O6), `specs/`, `tasks.md`, `brainstorm.md`, `proposal.md`; ADR-009 and `components/fleet-alert.md` under `docs/notes/development/observability/`.

## Global Constraints

- Repository: `$REPO` is the repository root, jj-colocated; never relocate `@`; commit each plan task as changes off `main@origin` per the repository's jj workflow; Tasks 2 and 3 form pull request 1 and Task 5 pull request 2, each landing through the merge queue before the next is enqueued.
- After creating or renaming any file, run `jj st --no-pager >/dev/null` before any `nix` command reads the tree.
- Commit messages, pull-request titles, bodies and comments carry no decision, finding, requirement or task code and no pull-request ordinal; they name what the change does; ADR numbers, file paths, `CAM-76` and GitHub pull-request numbers are allowed.
- Before every commit run `nix fmt` and keep its log; a tree failing `nix fmt -- --fail-on-change` is not pushed.
- Evidence: `<command> 2>&1 | tee logs/cam76-evidence/<item>-<slug>-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`, filters after the `tee`; `logs/` is git-ignored.
- The ping URL is a bearer credential: no agent reads, prints, logs or commits it in plaintext; only the operator handles it, in healthchecks.io's interface and at the hidden prompt; logs record the check's name, never its URL.
- Remote commands run as `ssh <host>.zt 'bash -c '"'"'…'"'"''` or with a quoted heredoc to `bash -s`, because login shells are zsh; journals are read with `sudo journalctl`; on stibnite dates use `/bin/date`.
- Nix-managed outputs are verified by `nix eval`, `nix build`, or the delivered path after activation, never by reading source; each step says which.
- Evaluation cost: every change to `checks.fleet-alert` records `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath` and `jq '.gc.totalBytes, .cpuTime'` of the stats file against 536,870,912 B before and after its task; a figure over that stops the task.
- Every check leg relates two independently defined values, the stand-ins' recorded requests and the leg's written expectation; a relation within one host is an assertion, shown failing by an `extendModules` override.
- Every regulator (leg, mutant, assertion) is written before the code it judges and seen failing; every runtime clause has a negative control seen failing.
- import-tree loads every `.nix` file under `modules/` as a flake-parts module; stand-ins and scripts use other extensions.
- Deploys: from the deploy worktree `$DEPLOY` = `$REPO/../vanixiets-worktrees/deploy`, refreshed before each deploy with `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` (created once with `git -C $REPO worktree add --detach $DEPLOY origin/main` if absent); only after `nixbot-logs queue` prints `Queue is empty`; by exactly `clan machines update cinnabar 2>&1 | tee logs/cinnabar-$(date +%Y%m%d-%H%M%S).log`, run in `$DEPLOY`, with no wrapper script.
- Vars: `fleet-deadman-ping` is per-machine on cinnabar; it is generated only by the operator, with `clan vars generate cinnabar --generator fleet-deadman-ping`; no other generator is regenerated.
- healthchecks.io: one check, schedule "simple", period 5 min, grace 10 min, email integration to an address whose mail is not hosted on the fleet (O2, O5); the dead-man's timer stays `*:0/5 UTC`.
- Linear: CAM-76's transitions are the orchestrator's, per `openspec-linear-sync`; no task here touches Linear.
- Prose files keep one sentence per line.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Lib | `flake.lib.fleetDeadmanPing pkgs { curl ? lib.getExe pkgs.curl }` → `writeShellApplication` named `fleet-deadman-ping`; reads `FLEET_DEADMAN_PING_CONFIG`; prints `fleet-deadman: external ping accepted` and exits 0 only when the answer is exactly `OK`; otherwise prints `fleet-deadman: external ping answered '<answer>', expected OK` or `fleet-deadman: external ping failed` and exits 1 | Task 2 |
| Lib | `flake.lib.fleetAlertDeadman pkgs { ntfySend; ping ? null; transition ? transitionJq; }`; with `ping` set, after the post loop: ping when `heartbeats > 0`, else print `fleet-deadman: no heartbeat in the last <window>; no external ping` | Task 2 |
| Option | `services.fleet-alert.deadman.pingConfigFile` (`nullOr str`, default `null`); when set: `ping = lib.getExe (fleetDeadmanPing pkgs { })`, `LoadCredential` gains `external-ping:<path>`, environment gains `FLEET_DEADMAN_PING_CONFIG = "%d/external-ping"`, and the assertion that the path does not start with `builtins.storeDir` | Task 2 |
| Generator | `fleet-deadman-ping` on cinnabar: prompt `ping-url` (`hidden`, `persist = true`), file `ping-url` (`deploy = false`), file `curl-config` (secret, `url = "<URL>"`), `runtimeInputs = [ pkgs.gnugrep ]`, the pattern `^https://hc-ping\.com/[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$` | Task 3 |
| Stand-in | `modules/checks/fleet-alert/ping_stub.py --answer <body> --port-file <file> --log <file>`; logs `<METHOD> <path> body=<bytes>` per request; answers 200 with `<body>` | Task 2 |
| Check parts | `deadmanPingRehearsal`, mutants `deadmanPingFirst` and `pingAcceptsAny200`; `pingTransport`, mutant `pingOnArgv`; both in `checks.fleet-alert`'s `passthru` and its build | Task 2 |
| Evidence | `logs/cam76-evidence/` | all |

## Task map

| Plan task | `tasks.md` items | Pull request | Deploy |
|---|---|---|---|
| Task 1: Plan review and baselines | 1.1–1.2 | planning pull request | none |
| Task 2: The ping step, the dead-man and R9.6 | 2.1–2.5 | 1 | — |
| Task 3: The generator, the operator's steps and pull request 1 | 2.6–2.8 | 1 | vars committed in it |
| Task 4: Deploy and acceptance | 3.1–3.2, 4.1–4.4 | none | cinnabar |
| Task 5: Documentation and decision records | 5.1–5.3 | 2 | none |
| Task 6: Close-out and integration verification | 6.1–6.3, 7.1 | close-out pull request | none |

Rollback: the operator pauses the check in healthchecks.io first, so the rollback sends no email; then a pull request unsets `pingConfigFile` on cinnabar and cinnabar is deployed from it; the vars stay committed and unused, and the check is deleted once the rollback is final.

---

## Task files

Each task lives in its own file so that one implementer reads only its task.

- [Task 1: Plan review and baselines](plan/task-1.md)
- [Task 2: The ping step, the dead-man and R9.6](plan/task-2.md)
- [Task 3: The generator, the operator's steps and pull request 1](plan/task-3.md)
- [Task 4: Deploy and acceptance](plan/task-4.md)
- [Task 5: Documentation and decision records](plan/task-5.md)
- [Task 6: Close-out and integration verification](plan/task-6.md)
