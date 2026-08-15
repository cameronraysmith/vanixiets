# Condition lattice, budgets, estimators, selection evals

## Units and conditions

𝒫 is the set of ablation units.
A condition C ⊆ 𝒫 is realized by materializing exactly the skill folders that C denotes into dir(C) with `scripts/materialize_conditions.py`, and by nothing else.

The unit of ablation is the skill, materialized from the deployed tree — what a harness actually reads.
A plugin unit is a derived aggregate: the union of its member skills' folders, resolved through an explicit membership map from skill name to plugin name that `scripts/census.py` emits alongside the census.
The derivation is forced by the shape of the deployed tree.
It is flat, one directory per skill, with no plugin directories and no `.apm/` paths, so a plugin unit has no directory to point at and cannot be resolved by walking the filesystem.
Source trees that do carry plugin directories still resolve structurally, and `materialize_conditions.py` keeps that path for them.

The census runs over both trees and reports both.
The deployed tree is the evaluation subject; the first-party source tree is the refactor subject.
A stage-2 selection-competition simulation must run over the deployed field, which is about a third larger than the first-party source field, or it understates interference by that margin.

Realization differs per runner and the difference is load-bearing.
BenchFlow takes `--skills-dir <dir(C)>` as a host path, validates it on the host, and uploads it into the container, so a wrong path fails loudly.
Harbor takes `--skill <dir>` (also spelled `--skills`) as a host path, accepting either one skill directory or a root whose immediate children are all skill directories, so a single flag pointing at dir(C) covers the whole condition; it resolves each skill per trial and SHA-pins it into the trial's `lock.json`.
Harbor rejects a root holding any child directory without a SKILL.md, which is why `materialize_conditions.py` refuses to reuse a destination containing anything else.
Harbor's `skills_dir` agent kwarg is a container-side path consumed inside the container, and passing a host path through `--ak skills_dir=` fails silently and collapses every condition to the empty condition.

## Budget menu (present with numbers filled in)

runs(design) = |C| × k × cells.
State this with the user's actual n, k and cells.

Every budget figure is costed at metered API rates.
Subscription-authenticated cells are permitted for interactive exploration and are never used for a run batch whose numbers are reported.
There are two reasons.
Costing as metered is robust to an unresolved question about credential-use policy in either direction, so the budget does not have to be redone if the answer changes.
Subscription cells also confound the measurement independently, because rate-limit throttling is nondeterministic and single-account authentication caps concurrency, which makes wall-clock and retry behavior part of the condition.

No per-run cost figure exists yet, anywhere in this skill or its history.
One must come from a calibration batch — a handful of runs on the intended cell, with the token and dollar totals read off the runner — before any budget table is presented.
Do not present a budget table with an invented number in it.

| design | \|C\| | estimands |
|---|---|---|
| paired marginals | n+1 | E({u})−E(∅) ∀u |
| + targeted pairs | n+1+p | above + Δ_uv for selected pairs |
| + everything-on | +1 | E(𝒫) — deployment condition |
| foldover | 2n+2 for n ≥ 3, min(2n+2, 2ⁿ) below | solo and leave-one-out marginals ∀u |
| full factorial | 2^n | complete E; Möbius attribution |

The foldover is ∅, the n singletons, the n complements of singletons, and 𝒫.
It gives two contrasts per unit: the solo marginal E({u})−E(∅) and the leave-one-out marginal E(𝒫)−E(𝒫∖{u}).
The gap between those two contrasts aggregates every higher-order interaction involving u, without separating them.
The design has no defining relation, so it carries no resolution and supports no claim that main effects are clear of two-way aliasing; a resolution claim requires a generator table the implementation does not have.
It collapses to the full factorial for n ≤ 3, where the complements of the singletons are the two-element subsets and every condition is already covered, and it saves runs only from n ≥ 4.
Deduplication makes |C| smaller than 2n+2 below n = 3: two units give four conditions rather than six, and one unit gives two rather than four.
At n ≥ 4 it contains no two-element subsets, so no second difference can be computed from it — Δ_uv needs {u}, {v} and {u,v} all present — which makes it the wrong choice when interactions are the question at exactly the sizes where it saves anything.

## Targeted-pair selection

Rank pairs by trigger-surface overlap between unit descriptions and pick p pairs from the top of that ranking plus any the user names.
Interference concentrates where descriptions compete for the same intents, which is the near-miss structure; synergy concentrates where one unit's outputs are another's inputs.

The ranking is computed from the census rather than assembled by hand.
`design_matrix.py --from-census <census.json> --top-pairs <p>` scores every pair of the design's own units by description-token Jaccard, unioning member tokens for a derived plugin unit, adds the top p as conditions, and writes the full ranking with the census provenance to `design/selection.json`.
Pass the deployed tree's census, for the reason given under units above.
Pairs the user names through `--pairs` are added on top and are not subject to the cutoff.

The census's own printed overlap tables are a display slice, not a significance threshold.
The figure of 16 flagged pairs is the top 8 intra-plugin rows plus the top 8 inter-plugin rows, both cutoffs defaulting to 8 through `census.py --top-intra` and `--top-inter` and recorded in the census's `provenance.top_intra` and `provenance.top_inter`, and it ranks over all skills rather than over the units of a particular design.
It says nothing about where overlap stops being meaningful.
Choose p from the budget and the shape of the ranking, and state the Jaccard at the cutoff next to the number of pairs bought.

## Estimators

The reward type selects the interval, and `analyze_lattice.py` reads it off the data per task, because the type is a property of that task's verifier rather than something the design declares.
A task whose observed rewards all lie in {0, 1} is binary and gets a Wilson 95% interval on its pass rate.
A task with any other value in [0, 1] is graded and gets a bootstrap percentile interval on the mean, resampling tasks.
A Wilson interval is never reported for a graded mean, because Wilson assumes a Bernoulli count and a mean of partial credit is not one.
A cell that mixes binary and graded tasks is refused rather than pooled, and a reward outside [0, 1] is refused, both as input errors rather than as wider intervals.
Report the binarized-at-threshold view alongside the graded view when the user wants comparability with pass rates, and state the threshold next to every number it produced.

Contrasts are computed the same way for both types.
Take per-(task, trial) paired differences, then bootstrap over tasks, because tasks are the exchangeable unit and trials within a task are correlated.

The cluster bootstrap needs at least two distinct tasks to have anything to resample.
Below that every replicate is the same sample and the percentile interval collapses to a point, so `analyze_lattice.py` reports the point estimate and marks the interval unavailable rather than printing a zero-width interval that reads as certainty.
Phase 1 proposes 1 to 3 tasks per unit, so a single-task cell is ordinary and a package built that way carries no task-level interval on any contrast; its README must not claim one.
A binary cell still gets its Wilson interval on E, because Wilson is computed over trials rather than tasks, and that interval treats trials as independent Bernoulli draws, which is a separate approximation from the clustering the bootstrap respects.

Keys missing from either arm of a contrast are dropped from both, and the analyzer reports how many keys each arm contributed and how many were dropped, so the coupling invariant can be evidenced from its output.
Neither Harbor nor BenchFlow exposes a per-trial seed at the revisions this skill pins, so the coupling is exact at the task level and positional within a task: replicate k aligns with replicate k across conditions.

Report normalized gain (Hake), (E_C − E_∅)/(1 − E_∅), alongside absolute deltas so cells with different baselines are comparable.
Report per-cell first, and pool across cells only with an explicit note that cells are not exchangeable.

The runners' own headline numbers respond to reward shape and will disagree with the estimators above if that goes unnoticed.
Harbor computes pass@k only when every trial carries exactly one reward key valued 0 or 1, so a multi-dimensional Reward Kit rubric silently disables it.
BenchFlow's `eval compare-lift` defines a pass as `reward == 1.0`, so partial credit is invisible in its pass-rate row and appears only in its mean-reward row.

## Interaction reading

Δ_uv < 0 (interference): likely trigger competition, context pollution, or convention conflict.
Diagnose by inspecting which unit's fingerprints appear in artifacts of failing {u,v} runs.
Δ_uv > 0 (synergy): composition tasks confirm; check the pipeline direction.
Either way the marginal story is incomplete — surface Δ next to marginals, never hide it in an appendix.

## Selection-competition evals (opt-in)

Purpose: with many units loaded, does the right one act?
This is a property of the description set and the harness triggering policy jointly, a different object than task efficacy, so keep it in separate tasks.
The loaded set is the deployed set, for the reason given under units above.

Pattern:
1. Task instruction targets exactly one unit's contract, without naming it.
2. All units in C are loaded (typically C = 𝒫).
3. Verifier checks task success and provenance: the expected unit's bundled script leaves a characteristic, hard-to-fake artifact (a stamped metadata field, a deterministic intermediate file, a format only that script emits).
   Provenance stays a final-state check, never transcript parsing.
4. Report P(correct-unit-selected) and P(success | selected) separately; the product recovers the composite, the factors localize the failure.

Fingerprints must be side effects the skill's script already produces, or a one-line addition to the bundled script made in the evaluated skill copy used for all conditions equally.
A verifier-only expectation the agent could not produce violates inhabitation, and a per-condition edit violates grade discipline.

## Trigger evals at the lattice level

skill-creator's trigger methodology (should/should-not, near-misses) lifts to the lattice: for each unit, should-trigger prompts where that unit should win over the others present, and should-not prompts targeting a sibling unit's contract.
These are cheap, since they observe which skill loads without executing a task, and are worth running before spending task-execution budget.
A unit that never wins selection will show zero marginal efficacy for reasons that have nothing to do with its content.
