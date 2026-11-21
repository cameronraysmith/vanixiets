---
linear_story_id: 3cc8a6d7-aa5b-41df-8a34-a32575e16241
linear_story_identifier: CAM-111
linear_story_title: "Evaluate nixbot builds with iets"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-111/evaluate-nixbot-builds-with-iets
linear_story_state: In Progress
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: In Progress
last_synced_at: 2026-11-18T21:23:12Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-18T20:15:34Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; issue created in project nixbot-herculesci-cicd at Todo, description seeded from this proposal, one comment posted" }
  - { at: "2026-11-18T20:44:39Z", transition: "description-sync", outcome: "posted", note: "description re-synced from this proposal after the capacity-gate and memory-budget revision; Linear reported state In Progress, ahead of the local phase (no [x] in tasks.md), left unreconciled" }
  - { at: "2026-11-18T21:23:12Z", transition: "Todo->In Progress", outcome: "skipped", note: "T2 apply; the operator had already moved CAM-111 to In Progress after approving the pre-apply alignment gate (2026-11-18); the first [x] in tasks.md now matches it, so no write was needed" }
---

## Why

nixbot's evaluation of vanixiets takes about 150 s and 410-430 s of CPU per push, and it is the largest draw on magnetite's memory.
A shadow benchmark on magnetite ran nixbot's exact command line through iets and got identical results for all 295 checks with about a third of the CPU.
The swap fits the evaluator setting nixbot already exposes, but iets fails a whole evaluation where nix-eval-jobs retries a killed worker, and nothing today records an evaluation's memory peak, so the switch must be measured before, during and after.

## What Changes

**A record of every nixbot evaluation**
- From: nixbot keeps an evaluation's duration and per-attribute counters, and nothing records how close an evaluation came to its memory ceiling, whether the kernel killed part of it, or which evaluator ran.
- To: a fifth patch on nixbot logs one structured record per evaluation (evaluator and version, workers, per-worker memory limit, wall, user and system time, the evaluation's memory peak against its ceiling, kernel kills, the evaluator's own kill messages, exit status), which the collector copies into a new dev-loop table, the daily reconcile checks, and the dev-loop view charts.
- Reason: the decisions to switch, to keep iets, and to give it room all rest on these numbers; the stock records collected until the switch are the reference for the switched week.
- Impact: non-breaking; one more dev-loop table and chart. buildbot's and `nix-fast-build --remote`'s evaluations are not recorded.

**A memory budget for magnetite**
- From: the fleet stores magnetite's ZFS cache, swap use, available memory and large processes, but not how much memory each service holds or how much RAM compressed swap itself uses.
- To: a small probe on magnetite reports each competing service's current and peak memory and compressed swap's footprint every minute, charted beside the evaluation record and summarised with the baseline week.
- Reason: when an evaluation needs more room, the operator has to see which services, caches and swap it is competing with.
- Impact: non-breaking; about 60 more series on magnetite.

**nixbot's evaluator**
- From: nixbot evaluates with its own patched nix-eval-jobs behind the host evaluation lock.
- To: after a paired replay of about twenty already-evaluated commits under both evaluators inside nixbot's real sandbox (design D13; the operator's Q69 of 2026-11-19 made it the only gate), nixbot evaluates with iets behind the same lock, through a minimal package exposing iets as `nix-eval-jobs` with nixbot's own Nix grafted on; nothing else on any host changes.
- Reason: about 3x less evaluation CPU at identical results, without the shared writable cache of Mic92/nixbot#255 or a fleet-wide shim.
- Impact: non-breaking for results; one more flake input. A worker killed for memory fails the whole evaluation instead of being retried. A failing evaluation is rebuilt, then answered as capacity or fixed forward (an iets pin); reverting one line to the stock package is the last rung, taken only when merges are blocked (operator Q88, 2026-11-21).

**Capacity decisions instead of a keep-or-revert threshold**
- From: 6 workers × 3072 MiB, chosen from 2026-09 measurements under nix-eval-jobs, and no rule for what happens when an evaluation outgrows its room.
- To: magnetite's first job is to be the best nixbot server. An evaluation above 90 % of its memory ceiling or at 20 GiB, or a kernel kill, triggers an operator decision taken in order of cost: tune the evaluator, reclaim memory on magnetite (ZFS cache cap, zram, per-service limits), move other services off magnetite, or resize it. The last two are the operator's, outside this change.
- Reason: a 3x faster evaluator is worth giving room to, within what the operator will pay for and maintain; reverting it for lack of memory that can be found more cheaply would optimise the wrong thing.
- Impact: none until the trigger fires. The replay fired it once, so the switch lands at 5 × 3072, D9's first rung (design D10).

## Capabilities

### New Capabilities
- `build-service-evaluator` (stratum: `behavioral`): which evaluator the build service runs, that a change of evaluator keeps every attribute's derivation, that it is made only on measured evidence, that insufficient headroom opens a capacity decision, that magnetite's memory budget is measured beside every evaluation, that a change of evaluator can be reverted with one change as the last rung of an escalation ladder, and that the evaluation still runs one at a time and without building during evaluation.
- `build-service-evaluator-interface` (stratum: `interface`): the iets flake input, the minimal `nix-eval-jobs` package and its grafted `nix` passthru, the lock-wrapped override of `services.nixbot.packages.nix-eval-jobs`, the evaluation-record patch and the record's fields, magnetite's memory-budget probe and its node_exporter keep-list entries, and the checks that pin them. Trust boundary: nixbot, the kernel's cgroup and zram counters and the evaluators produce what is recorded, and this machine only declares and reads them; nothing here guarantees iets evaluates any expression as Nix does, only that the configured parity comparisons, the canary and the recorded measurements behave as stated.

### Modified Capabilities
- `devloop-collection` (stratum: `behavioral`): every evaluation the build service runs is kept in the dev-loop history as one dev-loop record.
- `devloop-collection-interface` (stratum: `interface`): the `journald/nixbot-eval` receiver, the `eval_run` table and pipeline in the one allow-list, and the reconcile's daily comparison of evaluation records with nixbot's journal. Trust boundary unchanged: nixbot produces the lines and this machine only reads them.
- `fleet-dashboard` (stratum: `behavioral`): the dev-loop view also shows each evaluation's memory peak against its ceiling and its duration, beside magnetite's memory budget.
- `world-assumptions` (stratum: `world`): new assumptions on iets' evaluation limits and cache-status path, its handling of a killed worker against nix-eval-jobs', the evaluators' silence about worker recycling, nixbot's evaluation sandbox and cgroup lifecycle, and the collector's lack of per-unit memory beside what the kernel reports; the designation table gains the evaluation's worker, memory ceiling and memory peak, a memory budget, the file-system cache, a capacity decision, and an evaluation as a dev-loop event.

## Impact

- `flake.nix`, `flake.lock`: an `iets` input without `follows`.
- `modules/nixos/nixbot.nix`: a fifth nixbot patch and a unit environment value naming the evaluator, then the evaluator override; `modules/lib/nix-eval-lock.sh` and magnetite's kill-order assertion change in comments only.
- `modules/clan/services/otel-collector/schema.nix` (the `eval_run` table, `memoryBudgetUnits`, five node_exporter keep-list names), `modules/nixos/devloop-collection.nix`, `devloop-reconcile`, magnetite's memory-budget probe and node_exporter textfile collector, `modules/nixos/perses/resources/dashboard-devloop.json`, and the `devloop-ingest` and `devloop-queries` checks.
- magnetite only, apart from the shared keep-list, whose new names no other host produces. cache.numtide.com is already a fleet substituter (`lib/caches.nix:8`).
- Upstream: nothing is filed to iets (operator decision, 2026-11-18); the record patch may be offered to Mic92/nixbot as a follow-up.
