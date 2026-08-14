# Condition lattice, budgets, estimators, selection evals

## Units and conditions

𝒫 = the ablation units: skills (fine) or plugins (coarse). A condition C ⊆ 𝒫
is realized by materializing exactly the folders in C into the runtime-injected
skills directory. BenchFlow: `--skill-mode with-skill --skills-dir <dir(C)>`,
with C = ∅ as `--skill-mode no-skill`. Harbor: point the adapter's skills
registration at dir(C) (Claude Code/Codex/Pi adapters register whatever is in
the provided directory; keep the mechanism identical across cells).

When evaluating multiple plugins, default the unit to the plugin; drill into
skill-level units only inside a plugin whose plugin-level effect was large or
negative. Two-stage refinement spends runs where the first differences say the
structure is.

## Budget menu (present with numbers filled in)

runs(design) = |C| × k × cells. State this, with the user's actual n, k,
cells, and a per-run cost guess split by auth pool (subscription-window runs
vs API-billed runs).

| design | |C| | estimands |
|---|---|---|
| paired marginals | n+1 | E({u})−E(∅) ∀u |
| + targeted pairs | n+1+p | above + Δ_uv for selected pairs |
| + everything-on | +1 | E(𝒫) — deployment condition |
| fractional factorial (res-IV) | ~2^(n−q) | main effects unaliased with pairs |
| full factorial | 2^n | complete E; Möbius attribution |

Targeted-pair selection: rank pairs by trigger-surface overlap — cosine or
keyword overlap between skill descriptions, shared file-type/domain claims,
shared output conventions. Interference concentrates where descriptions
compete for the same intents (the near-miss structure); synergy where one
skill's outputs are another's inputs. Pick p pairs from the top of that
ranking plus any the user names.

## Estimators

- Binary rewards: per-condition, per-cell pass rate with Wilson 95% interval.
- Contrasts: compute per (task, trial) paired differences, then bootstrap over
  tasks (tasks are the exchangeable unit; trials within task are correlated).
- Graded rewards: means with bootstrap intervals; also report the
  binarized-at-threshold view if the user wants comparability with pass rates.
- Normalized gain (Hake): (E_C − E_∅)/(1 − E_∅) alongside absolute deltas so
  cells with different baselines are comparable.
- Report per-cell first; pool across cells only with explicit note that cells
  are not exchangeable.

## Interaction reading

Δ_uv < 0 (interference): likely trigger competition, context pollution, or
convention conflict. Diagnose by inspecting which unit's fingerprints appear
in artifacts of failing {u,v} runs.
Δ_uv > 0 (synergy): composition tasks confirm; check the pipeline direction.
Either way the marginal story is incomplete — surface Δ next to marginals,
never hide it in an appendix.

## Selection-competition evals (opt-in)

Purpose: with many units loaded, does the RIGHT one act? This is a property of
the (description set, harness triggering policy) jointly — different object
than task efficacy, so keep it in separate tasks.

Pattern:
1. Task instruction targets exactly one unit's contract, without naming it.
2. All units in C are loaded (typically C = 𝒫).
3. Verifier checks task success AND provenance: the expected unit's bundled
   script leaves a characteristic, hard-to-fake artifact (a stamped metadata
   field, a deterministic intermediate file, a format only that script emits).
   Provenance stays a final-state check — never transcript parsing.
4. Report P(correct-unit-selected) and P(success | selected) separately; the
   product recovers the composite, the factors localize the failure.

Fingerprints must be side effects the skill's script already produces or a
one-line addition to the bundled script made IN THE EVALUATED SKILL COPY used
for all conditions equally — never a verifier-only expectation the agent could
not produce (that would violate inhabitation) and never per-condition edits
(grade discipline).

## Trigger evals at the lattice level

skill-creator's trigger methodology (should/should-not, near-misses) lifts to:
for each unit, should-trigger prompts where that unit should win over the
others present, and should-not prompts targeting a sibling unit's contract.
These are cheap (no task execution — observe which skill loads) and worth
running before spending task-execution budget: a unit that never wins
selection will show zero marginal efficacy for reasons that have nothing to do
with its content.
