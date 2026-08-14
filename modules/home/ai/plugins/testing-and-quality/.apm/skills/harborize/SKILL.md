---
name: harborize
description: Compile an existing agent skill, a plugin of skills, or several co-present
  plugins into a complete, runnable evaluation package — Harbor task + SkillsBench/BenchFlow
  task package, verifier, oracle, condition lattice, run manifest, and analysis scripts.
  Use whenever the user wants to evaluate, benchmark, verify, stress-test, or measure the
  quality, performance, efficacy, or interaction effects of one or more SKILL.md-based
  skills or plugins across models and agent harnesses, or asks to "harborize" a skill,
  turn skill-creator eval artifacts into Harbor/BenchFlow tasks, or design paired
  with-skill/no-skill experiments. Do not use for creating or improving the skill itself
  (use skill-creator) or for authoring generic Harbor tasks unrelated to skills
  (use Harbor's create-task).
---

# Harborize

Compile skills into measurement instruments. Input: path(s) to one or more skill
folders (each containing a SKILL.md), a plugin (a folder of skills), or several
plugins. Output: a canonical evaluation package per task, runnable under BOTH the
Harbor CLI and the BenchFlow CLI, plus a condition lattice, run manifest, and
analysis pipeline that together measure the marginal value of each unit and the
interactions between units when several share a context window.

You are building apparatus, not solving tasks. Every decision below exists to keep
the measurement valid. The algebraic invariants in
`references/algebraic-invariants.md` are the review gate — read them before
emitting anything, and audit the finished package against them.

## Phase 0 — Intake and inventory

For each input path:

1. Read the SKILL.md: frontmatter (name, description) and body. The description
   defines the *claimed contract* — the task class the skill promises to improve.
   Tasks you design must sample that class, not the skill's examples verbatim.
2. Read invocation-mode flags. `disable-model-invocation: true` marks a
   command-style skill: it is never auto-triggered, so the measured composite
   drops the trigger factor to P(correct-use ∧ success | invoked), the
   with-skill condition must invoke it the way its harness would, and it is
   excluded from selection-competition evals. Record the mode per unit.
3. Scan for environment couplings: absolute paths, `~/` references, host
   tools the skill assumes. Do not neutralize them — the container will
   expose them honestly — but record each in the package README so a failed
   run is attributable to coupling rather than content.
4. Inventory bundled resources (`scripts/`, `references/`, `assets/`). Scripts the
   skill ships are things the verifier must NOT simply re-run as its check —
   otherwise the skill contains the proof (see non-triviality, below).
5. Look for prior skill-creator artifacts: `evals/evals.json`,
   `<name>-workspace/iteration-*/`, `benchmark.json`, `feedback.json`. These are
   seeds: prompts become candidate instructions, assertions become candidate
   verifier criteria, a passing with-skill output becomes the oracle's target.
   Treat them as drafts to harden, not ground truth — inner-loop assertions were
   LLM-graded; here they must become decidable or consciously judge-graded.
6. Determine the unit structure: single skill → units = {S}; plugin → units =
   its skills; multiple plugins → ask whether the unit of ablation is the plugin
   (coarse, cheap) or the skill (fine, expensive). Record the unit set 𝒫.

If the user gave a plugin/marketplace identifier rather than a path, resolve
it first — for apm marketplaces, consume via the apm CLI and evaluate the
DEPLOYED trees (what a harness actually sees), not the source folders. A
plugin unit materializes as the union of its deployed skills. If no SKILL.md is found at the path, stop and ask.

## Phase 1 — Task derivation (with the user)

Propose 1–3 tasks per unit plus, when |𝒫| > 1, at least one *composition task*
that plausibly exercises two or more units together. For each task state: the
instruction sketch, what final state the verifier will inspect, and why the task
is hard enough that a capable agent benefits from the skill (simple one-step
tasks don't trigger skills and measure nothing). Get sign-off before building.

Rules for `instruction.md` / the task body:
- Never name the skills or say skills exist. Triggering is part of what is
  measured; naming the skill collapses P(trigger ∧ use ∧ success) to P(success).
- Harness-agnostic phrasing — the same text runs under every cell in the grid.
- State the goal and expected artifacts (paths, formats) concretely. Describe
  what done looks like, never how it will be checked.

## Phase 2 — Verifier design (the hard part)

Per task, walk the decision tree and record the choice in the package README:

- **pytest / custom shell** when success is a decidable predicate on final
  state. Exact truncation; binary `reward.txt`. Prefer this whenever honest.
- **Reward Kit** (`checks.py` + optional `judge.toml`) when there are multiple
  criteria, partial credit, or an irreducibly subjective dimension. Graded
  `reward.json`. Every criterion gets a descriptive name (skill-creator's
  assertion `text` fields translate directly).

Defaults, always:
- `[verifier] environment_mode = "separate"` — grading logic, expected outputs,
  and judge API keys live where the agent cannot see them.
- Agent env `network_mode = "no-network"` unless the task genuinely needs the
  network; verifier env `"public"` only if a judge or fetch is required.
- Prefer exact-set assertions (the full expected commit-message list, the
  complete file inventory) over negative greps for forbidden substrings —
  negative patterns are brittle against paraphrase and reward wording
  avoidance rather than the property.
- Verifier reads only final state and declared artifacts — path-free. If you
  need process evidence (e.g., selection evals), fingerprint it into artifacts
  (a skill's bundled script leaving a characteristic output) rather than
  parsing transcripts.

**Non-triviality audit (mandatory):** run
`scripts/audit_leakage.py <skills...> <task-pkg>` — it checks that no verifier
expectation is string-recoverable from skill content and that the skill does not
contain a complete solution to the instruction. If it fires, redesign the task
(parameterize inputs) or the skill is answer-keying and the measurement is void.

## Phase 3 — Environment and oracle

- `environment/Dockerfile`: task dependencies only — never the solution, never
  the skills. Skills are injected at runtime per condition; baking them in
  destroys the on/off toggle.
- Oracle (`oracle/solve.sh` ≡ `solution/solve.sh`): a script that actually
  solves the task. It must pass the verifier 100% — run it 5× before anything
  else counts. The oracle may consult the skill's content while you write it;
  the point is inhabitation, not independence.
- Generate fixtures (repos, datasets, broken states) with a dedicated
  python script COPY'd and RUN in the Dockerfile — never nested shell
  heredocs, whose escaping is fragile and whose failures are silent. Freeze
  content invariants (tree hashes, checksums) at build time, before any
  agent touches the environment.
- Test the environment interactively (`harbor task start-env ... -i`) before
  writing the oracle; missing deps surface here.

## Phase 4 — Dual emission

One canonical package, two thin metadata heads over shared content:

```
<task-id>/
├── task.md          # BenchFlow head: YAML frontmatter (schema 1.3 vocab) + body
├── task.toml        # Harbor head: [task], [verifier], [environment]
├── instruction.md   # single source; task.md body generated from it
├── environment/     #   Dockerfile (+ skills/ ONLY in the SkillsBench copy,
│   └── skills/      #   populated per-condition by materialize_conditions.py)
├── oracle/solve.sh  # = solution/solve.sh (Harbor name; emit both, same file)
└── verifier/        # = tests/ (Harbor name); test.sh + checks.py/judge.toml
```

`references/harbor-emitter.md` and `references/benchflow-emitter.md` hold the
exact field mappings, frontmatter vocabulary, and the wrapper `test.sh` for each
runner. Validate both heads: `harbor tasks check` and `bench tasks check`, then
oracle runs under both runners.

## Phase 5 — Condition lattice and budget (ask, every time)

Conditions are subsets C ⊆ 𝒫, realized purely by which skill folders
`scripts/materialize_conditions.py` copies into the injected skills dir.
Nothing else may vary between conditions.

Present the menu with arithmetic filled in — runs = |C| × k × cells — and let
the user choose. Do not silently default:

1. **Paired marginals** — C = {∅} ∪ {{u} : u ∈ 𝒫}; |C| = n+1. Measures each
   unit's solo efficacy E({u}) − E(∅). No interactions.
2. **Marginals + targeted pairs** — add {u,v} for pairs with overlapping
   trigger surface (description keyword/intent overlap — the near-miss
   structure predicts interference). Yields second differences Δ_uv for the
   pairs most likely to be nonzero.
3. **Fractional factorial** — a resolution-IV design over 𝒫 when n is
   moderate and the user wants main effects clear of pairwise aliasing.
4. **Full factorial** — 2^n. Only for n ≤ 3 or when someone else pays.

Include "everything on" (C = 𝒫) in options 2–4 when the deployment reality is
all-units-loaded — that is the condition users actually live in, and
non-monotonicity means it cannot be inferred from marginals.

`scripts/design_matrix.py` emits `conditions.json` and a run manifest of shell
commands per (condition × cell × trial) with per-auth-pool concurrency and the
subscription-auth env vars. k ≥ 3.

Selection-competition evals (does the RIGHT unit win when many are loaded) are
**off by default**. Offer them once when |𝒫| > 1; if accepted, see the
selection-evals section of `references/lattice-design.md` for the artifact-
fingerprint pattern.

## Phase 6 — Run and analyze

Run oracle everywhere first; then the manifest. Collect
`{condition, cell, trial} → reward` and feed `scripts/analyze_lattice.py`:

- Ê(C) per cell with Wilson intervals (rewards in [0,1] treated as Bernoulli
  when binary, means otherwise).
- Paired first differences per unit and, where the design supports them, second
  differences Δ_uv with sign and interval — synergy (>0), interference (<0).
- Cross-cell table: per-unit efficacy by (model × harness). Flag units whose
  benefit changes sign across cells — those failed empirical naturality and
  their portability claim is model-idiosyncratic.
- Never average unpaired conditions; every contrast shares tasks and trials.

Report deltas with intervals, absolute and normalized gain, and the run count
behind each number. Small n: say so plainly.

## Marketplace-scale work

When the subject is an entire marketplace rather than a skill or plugin,
read `references/marketplace-program.md` first — it carries the staged
program (census -> lint -> selection-sim -> stratified dynamic eval ->
refactor loop -> CI), the current state of the vanixiets engagement, and the
next-actions checklist. Run `scripts/census.py <plugins-dir>` before
proposing any dynamic evaluation.

## Review gate

Before handing anything over, audit the package against
`references/algebraic-invariants.md` — one line per invariant, pass/fail, in
the package README. A package failing truncation, inhabitation, non-triviality,
or coupling is not done, whatever else works.
