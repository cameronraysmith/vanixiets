---
linear_story_id: 3cc8a6d7-aa5b-41df-8a34-a32575e16241
linear_story_identifier: CAM-111
linear_story_title: "Evaluate nixbot builds with iets"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-111/evaluate-nixbot-builds-with-iets
linear_story_state: Todo
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: Todo
last_synced_at: 2026-11-18T20:15:34Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-18T20:15:34Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; issue created in project nixbot-herculesci-cicd at Todo, description seeded from this proposal, one comment posted" }
---

## Why

nixbot's evaluation of vanixiets takes about 150 s and 410-430 s of CPU per push, and it is the largest draw on magnetite's memory.
A shadow benchmark on magnetite ran nixbot's exact command line through iets and got identical results for all 295 checks with about a third of the CPU.
The swap fits the evaluator setting nixbot already exposes, but iets fails a whole evaluation where nix-eval-jobs retries a killed worker, and nothing today records an evaluation's memory peak, so the switch must be measured before, during and after.

## What Changes

**A record of every nixbot evaluation**
- From: nixbot keeps an evaluation's duration and per-attribute counters, and nothing records how close an evaluation came to its memory ceiling, whether the kernel killed part of it, or which evaluator ran.
- To: a fifth patch on nixbot logs one structured record per evaluation (evaluator and version, workers, per-worker memory limit, wall, user and system time, the evaluation's memory peak against its ceiling, kernel kills, the evaluator's own kill messages, exit status), which the collector copies into a new dev-loop table, the daily reconcile checks, and the dev-loop view charts.
- Reason: the decisions to switch, to keep iets, and to tune its memory limit all rest on these numbers, and the first week of them is the baseline under the current evaluator.
- Impact: non-breaking; one more dev-loop table and chart. buildbot's and `nix-fast-build --remote`'s evaluations are not recorded.

**nixbot's evaluator**
- From: nixbot evaluates with its own patched nix-eval-jobs behind the host evaluation lock.
- To: after a week of baseline and a canary inside nixbot's real sandbox, nixbot evaluates with iets behind the same lock, through a minimal package exposing iets as `nix-eval-jobs` with nixbot's own Nix grafted on; nothing else on any host changes.
- Reason: about 3x less evaluation CPU at identical results, without the shared writable cache of Mic92/nixbot#255 or a fleet-wide shim.
- Impact: non-breaking for results; one more flake input. A worker killed for memory fails the whole evaluation instead of being retried, which is accepted only if the measured headroom is comfortable. Rollback is reverting one line to the stock package.

**Memory tuning from data**
- From: 6 workers × 3072 MiB, chosen from 2026-09 measurements under nix-eval-jobs.
- To: unchanged at the switch, then tuned from the recorded peaks, with the decision and its measurements recorded.
- Reason: iets' measured peak runs 1-2.5 GiB above nix-eval-jobs' close to the service's 20 GiB throttle level.
- Impact: none until a tuning decision is made.

## Capabilities

### New Capabilities
- `build-service-evaluator` (stratum: `behavioral`): which evaluator the build service runs, that a change of evaluator keeps every attribute's derivation, that it is made only on measured evidence, that it can be reverted with one change, and that the evaluation still runs one at a time and without building during evaluation.
- `build-service-evaluator-interface` (stratum: `interface`): the iets flake input, the minimal `nix-eval-jobs` package and its grafted `nix` passthru, the lock-wrapped override of `services.nixbot.packages.nix-eval-jobs`, the evaluation-record patch and the record's fields, and the checks that pin them. Trust boundary: nixbot, the kernel's cgroup counters and the evaluators produce what is recorded, and this machine only declares and reads them; nothing here guarantees iets evaluates any expression as Nix does, only that the configured parity comparisons, the canary and the recorded measurements behave as stated.

### Modified Capabilities
- `devloop-collection` (stratum: `behavioral`): every evaluation the build service runs is kept in the dev-loop history as one dev-loop record.
- `devloop-collection-interface` (stratum: `interface`): the `journald/nixbot-eval` receiver, the `eval_run` table and pipeline in the one allow-list, and the reconcile's daily comparison of evaluation records with nixbot's journal. Trust boundary unchanged: nixbot produces the lines and this machine only reads them.
- `fleet-dashboard` (stratum: `behavioral`): the dev-loop view also shows each evaluation's memory peak against its ceiling and its duration.
- `world-assumptions` (stratum: `world`): new assumptions on iets' evaluation limits and cache-status path, its handling of a killed worker against nix-eval-jobs', the evaluators' silence about worker recycling, and nixbot's evaluation sandbox and cgroup lifecycle; the designation table gains the evaluation's worker and memory ceiling and an evaluation as a dev-loop event.

## Impact

- `flake.nix`, `flake.lock`: an `iets` input without `follows`.
- `modules/nixos/nixbot.nix`: a fifth nixbot patch and a unit environment value naming the evaluator, then the evaluator override; `modules/lib/nix-eval-lock.nix` and `.sh` unchanged.
- `modules/clan/services/otel-collector/schema.nix`, `modules/nixos/devloop-collection.nix`, `devloop-reconcile`, `modules/nixos/perses/resources/dashboard-devloop.json`, and the `devloop-ingest` and `devloop-queries` checks.
- magnetite only. cache.numtide.com is already a fleet substituter (`lib/caches.nix:8`).
- Upstream: an issue asking iets to retry killed workers; the record patch offered to Mic92/nixbot as a follow-up.
