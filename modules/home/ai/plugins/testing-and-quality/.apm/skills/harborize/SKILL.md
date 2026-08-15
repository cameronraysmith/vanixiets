---
name: harborize
version: 0.2.1
description: Compile an existing agent skill, a plugin of skills, or several co-present
  plugins into a complete, runnable evaluation package — Harbor task + SkillsBench/BenchFlow
  task package, verifier, oracle, condition lattice, run manifest, and analysis scripts.
  Use whenever the user wants to evaluate, benchmark, verify, stress-test, or measure the
  quality, performance, efficacy, or interaction effects of one or more SKILL.md-based
  skills or plugins across models and agent harnesses, or asks to "harborize" a skill,
  turn skill-creator eval artifacts into Harbor/BenchFlow tasks, or design paired
  with-skill/no-skill experiments. Do not use for authoring or improving the skill that
  is the subject of the evaluation (use skill-creator) or for authoring generic Harbor
  tasks unrelated to skills (use Harbor's create-task). Revising harborize itself between
  evaluation rounds is in scope and is what this skill's own versioning exists for.
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
6. Determine the unit structure.
   The unit of ablation is the skill, materialized from the deployed tree; this is settled, so state it rather than asking.
   A plugin unit is a derived aggregate — the union of its member skills' deployed directories — resolved through an explicit plugin-membership map from skill name to plugin name, shipped beside the census.
   The map is required because the deployed tree is flat: one directory per skill, no plugin directories and no `.apm/` paths, so membership cannot be recovered from directory structure.
   Depart from the skill unit only to screen a marketplace at plugin granularity before paying for skill-level resolution, and record the departure and its reason in the package README.
   Record the unit set 𝒫.

If the user gave a plugin or marketplace identifier rather than a path, resolve it first; for apm marketplaces, consume via the apm CLI and compose the deployed tree.
Both trees matter and the census reports both.
The deployed tree is the evaluation subject, because it is what a harness actually loads — 172 skill directories at the current vanixiets state, against 129 first-party source skills.
The first-party source tree is the refactor subject, because that is the only place a fix can be written.
Selection-competition simulation runs over the deployed field, which is about a third larger, because the source field omits the 43 deployed skills that belong to no first-party plugin and that compete for the same trigger surface.
Run it over the source field and it is computed over a smaller set of competing descriptions than the one a harness presents; how much interference that omits is what stage 2 measures rather than something the ratio establishes.
If no SKILL.md is found at the path, stop and ask.

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

Reward shape decides which downstream metrics exist, and both runners fail silently rather than warn.
Harbor computes pass@k only when every trial carries exactly one reward key whose value is 0 or 1; an extra key, or a value strictly between, returns an empty result and the metric disappears with no message (harbor `src/harbor/utils/pass_at_k.py`).
BenchFlow's `bench eval compare-lift` defines `passed` as `reward == 1.0` (benchflow `src/benchflow/eval_lift.py:31-33`), so partial credit contributes nothing to its headline pass rate and surfaces only in mean reward.
The rule: default to a single binary reward key, and pay for a graded rubric only when partial credit is the estimand rather than a convenience.
When the rubric wins, either write the per-criterion detail into `/logs/artifacts` and keep the reward channel binary, or take graded rewards knowingly, report means with bootstrap intervals as `references/lattice-design.md` describes, and state in the package README that pass@k and BenchFlow's pass rate are unavailable for that task.

Subjective contracts reduce to a mechanical check wherever one exists; a judge is for the residue.
Exactly one judge-validation package is a hard gate before any judge-based stratum enters a budget.
The gate is warranted by how little the surrounding ecosystem leans on judges: all 87 tasks shipped in SkillsBench declare `verifier.type: test-script` and none uses a judge.
The acceptance bar adopted here for a judge criterion is a human-labeled validation set of roughly 6 to 12 submissions spanning pass, fail, partial, borderline, plausible-but-wrong and polished-but-unsupported, plus demonstrated agreement with the human labels and stability across runs.
Build that one package, clear that bar, and only then price judge-graded tasks into a design.
If the gate fails, the subjective stratum falls back to structural proxies: does the produced artifact exhibit the convention, checkable by grep or AST, in place of a judgment of its quality.

The verifier environment is an explicit fork per task, recorded in the package README with its justification.
Harbor's own default is `shared`; declaring `[verifier.environment]` at all implies `separate`.
`separate` is the only setting that hides grading logic, expected outputs and any judge API key from the agent under test, which is the literal implementation of the non-triviality invariant.
It costs machinery: separate mode sets `skip_tests_upload=True` (harbor `src/harbor/trial/trial.py:618`), Harbor therefore never uploads `tests/`, and the verifier image must already own `/tests/test.sh` (harbor `src/harbor/verifier/verifier.py:96-103`).
A verifier Dockerfile is therefore mandatory; its build context is the task's `tests/` directory (harbor `src/harbor/trial/trial.py:694-702`), so `tests/Dockerfile` can COPY the test scripts to `/tests/`.
Setting `docker_image` in `[verifier.environment]` is what defeats it: a prebuilt image is used and the Dockerfile is skipped, so a stock image such as `python:3.12-slim` runs without ever owning `/tests/test.sh`, and every trial then fails permanently, because the absent reward file raises `RewardFileNotFoundError`, which sits in Harbor's default no-retry list (harbor `src/harbor/models/job/config.py:289-300`).
The same base image is fine when it arrives through `tests/Dockerfile`, which is what builds it.
The same applies past the script to everything it calls: Harbor uploads nothing into that image, so a wrapper invoking `uvx` in an image with no uv reaches the identical dead end.
Install the verifier's tooling at image build time and call it directly, which also keeps the verifier environment runnable with no network; `references/emitters.md` carries the Dockerfile.
`shared` runs the verifier in the agent's own environment and is required when the check must inspect mutable in-place state rather than a produced artifact.
It leaks, because everything in `tests/` is then visible to the agent, so a shared-mode task depends entirely on the non-triviality audit below to stay honest.
Two of the three packages this skill emitted in iteration 1 required shared mode.

Defaults, always:
- Agent env `network_mode = "no-network"` unless the task genuinely needs the
  network; verifier env `"public"` only if a judge or fetch is required. Both
  prerequisites in Phase 3 apply to that default before it can be relied on.
- Prefer exact-set assertions (the full expected commit-message list, the
  complete file inventory) over negative greps for forbidden substrings —
  negative patterns are brittle against paraphrase and reward wording
  avoidance rather than the property.
- Verifier reads only final state and declared artifacts — path-free. If you
  need process evidence (e.g., selection evals), fingerprint it into artifacts
  (a skill's bundled script leaving a characteristic output) rather than
  parsing transcripts.

Non-triviality audit, mandatory:

```
scripts/audit_leakage.py --task <task-pkg> --skills <skill-dir> [<skill-dir> ...]
```

Both are required named options; the script declares no positionals, so a mis-ordered path is rejected rather than absorbed into the skill list.
Three heuristics run: quoted literals of eight characters or more taken from `verifier/` or `tests/` and found anywhere in skill content, token Jaccard above 0.6 between the oracle and any skill-bundled script, and files byte-identical across the two trees.
Exit 0 means every check that could run raised no flag, exit 1 means at least one flag was raised and the review gate fails, and exit 2 means the audit could not run — a bad invocation, a missing task package, a skill directory with no SKILL.md, or no verifier sources.
Exit 2 is separated from exit 0 deliberately: every check searches for evidence of leakage, so a mistyped path finds nothing and would otherwise read as a clean package that was never examined.
A check whose inputs are absent, such as check 2 before the oracle exists, is reported as skipped rather than passed.
It does not check that the verifier runs in a separate environment; that is the fork above and is audited by reading `task.toml`.
If it fires, redesign the task by parameterizing inputs, or accept that the skill is answer-keying and the measurement is void.

## Phase 3 — Environment and oracle

Two prerequisites hold before authoring, and both surface as failures that read as authoring errors.

Harbor's `network_mode = "no-network"` is rejected at environment start when the Docker daemon's kernel lacks `CONFIG_NFT_FIB_INET`.
The kernel probe is `environments/docker/docker.py:113-117`; on failure `_enable_egress_control` goes false (`:188-193`), which zeroes `capabilities.disable_internet` (`:289-293`), and `environments/base.py:772-781` then raises "network_mode='no-network' is not supported by ... environment".
Probe a new daemon before authoring anything:

```
docker run --rm alpine sh -c 'zcat /proc/config.gz | grep NFT_FIB_INET'
```

Expect `CONFIG_NFT_FIB_INET=y` or `=m`.
Harbor's own probe passes when `/proc/config.gz` is absent, so the hand probe is stricter than Harbor is: an absent config file means unknown here and supported there.

claude-code's install fetches from the network during agent setup, which the agent-phase network policy does not cover.
`install()` at `claude_code.py:425-449` curls `https://downloads.claude.ai/claude-code-releases/bootstrap.sh` (or npm-installs on Alpine) unless the image already carries the requested version.
`_prepare` runs `_setup_agent` at `trial.py:408-414` with no policy wrapper, while only `_run_agent_phase` (`trial.py:465-469`) and the verifier phases enter `_phase_network_policy`.
So a no-network claude-code cell fails during agent install, and at the reward level that failure is indistinguishable from an injection failure.
Bake the agent into the environment image at a pinned version, which makes `_installed_claude_satisfies_version` return early and never reach the fetch.

- `environment/Dockerfile`: task dependencies only — never the solution, never
  the skills. Skills are injected at runtime per condition; baking them in
  destroys the on/off toggle.
- Oracle (`oracle/solve.sh`; the export lands it at `solution/solve.sh`, so
  write it once): a script that actually solves the task. It must pass the
  verifier 100% — run it 5× before anything else counts. The oracle may
  consult the skill's content while you write it; the point is inhabitation,
  not independence.
- Generate fixtures (repos, datasets, broken states) with a dedicated
  python script COPY'd and RUN in the Dockerfile — never nested shell
  heredocs, whose escaping is fragile and whose failures are silent. Freeze
  content invariants (tree hashes, checksums) at build time, before any
  agent touches the environment.
- Test the environment interactively (`harbor task start-env ... -i`) before
  writing the oracle; missing deps surface here.

## Phase 4 — Dual emission

Author BenchFlow-native, then derive the Harbor head into a separate sibling
directory with `bench tasks export`. The two heads cannot share a directory:

```
<task-id>/                 # authored; the source of truth
├── task.md                #   YAML frontmatter (schema 1.3 vocab) + body
├── environment/           #   Dockerfile only; skills/ stays EMPTY
│   └── skills/            #   (dir(C) lives outside the package)
├── oracle/solve.sh
└── verifier/              #   test.sh + checks.py/judge.toml
                           #   + Dockerfile when the verifier runs separate

<task-id>-harbor/          # generated; never hand-edited
├── task.toml              #   [task], [verifier], [environment]
├── instruction.md         #   from task.md's body
├── environment/           #   copied verbatim
├── solution/solve.sh      #   from oracle/
├── tests/                 #   from verifier/
└── compatibility/export-report.json
```

```
bench tasks export <task-id> <task-id>-harbor --target harbor
```

Three independent validators force the split.
BenchFlow's `--level publication-grade` rejects a `task.toml` or `instruction.md` beside `task.md` (benchflow `_utils/task_authoring/structural_checks.py:208-212`) and rejects `solution/` in favour of `oracle/` (`:218-222`).
SkillsBench's corpus gate forbids exactly `instruction.md`, `task.toml`, `solution` and `tests` (skillsbench `.github/scripts/validate_tasks.py:21-26`), which is the set Harbor requires.
All 87 tasks under skillsbench `tasks/` are native, with zero `task.toml` and zero `solution/`, as are the 14 under `tasks-extra/`.
The export also refuses a destination overlapping its source in either direction (benchflow `task/export.py:242-251`), so the Harbor head is a sibling and never a subdirectory.

Re-export after every edit to the native tree.
`references/emitters.md` holds the exact field mappings, frontmatter vocabulary, injection flags and wrapper `test.sh` for each runner.

Validate both heads before any oracle run: one static gate per head, plus one authoring-time check that spawns a metered job.

`harbor tasks check` no longer exists.
At the harbor revision recorded under instrument versioning below, `tasks` is a hidden backwards-compatible alias of the same typer app as `task`, so both spellings reach one command that prints an error and raises `SystemExit(1)` unconditionally (harbor `src/harbor/cli/tasks.py:476-487`); a pipeline that calls it fails rather than validates.
The Harbor head's static gate is schema-level and runs against the exported `<task-id>-harbor`: construct `harbor.models.task.task.Task(<task-id>-harbor)`, which parses `task.toml` through `TaskConfig` and asserts `instruction.md` is present.
It verifies field names, types and enum membership, and nothing about behaviour.
It does not catch the separate-mode trap either, because `Task._validate_tests` returns early whenever a verifier environment is configured, so a separate-mode task whose verifier image has no `/tests/test.sh` passes schema validation and fails at run time.

The BenchFlow head's static gate is `bench tasks check <task-id> --level structural`, raised to `--level publication-grade` before publishing.
It validates directory layout and frontmatter against the SkillsBench schema, exits 1 with one line per issue, and executes nothing.
It runs against the authored native tree only.
Pointing publication-grade at the exported Harbor head fails by construction, because that head is the split layout the level exists to reject.

`harbor check` is the named replacement for the removed command and is a different instrument, not a drop-in substitute.
It spawns a full Harbor job that runs an LLM agent against a task-quality rubric — default `claude-code` with `claude-sonnet-4-6` — so it is metered per invocation, and its exit code reflects only whether a task errored: rubric failures are printed and ignored (harbor `src/harbor/cli/analyze.py:206-207`).
Run it once at authoring time, read the report, and keep it out of CI and out of any per-condition loop.

With both static gates clean, run the oracle under both runners.

## Phase 5 — Condition lattice and budget (ask, every time)

Conditions are subsets C ⊆ 𝒫, realized purely by which skill folders
`scripts/materialize_conditions.py` copies into the injected skills dir.
Nothing else may vary between conditions.

Injection is per runner and the two mechanisms are not interchangeable.
Harbor takes `--skill <dir>` (`--skills` is the same option, repeatable), which accepts either one skill directory or a parent of skill directories, resolves it on the host, uploads each skill into the trial environment under `/harbor/skills/<name>`, and records each skill's name, source and content digest in the trial's `lock.json`.
A bad path raises `FileNotFoundError` before any container starts.
The agent kwarg `--ak skills_dir=<path>` is a different field: a container-side path that the Claude Code adapter copies from with `cp -r <path>/* $CLAUDE_CONFIG_DIR/skills/ 2>/dev/null || true`, so a host path passed there copies nothing, the run still exits 0, and every condition silently collapses to C = ∅.
BenchFlow takes `--skills-dir <dir>`, a host path validated on the host and mounted into the sandbox at `/skills`, with `--skill-mode no-skill` for C = ∅.
Field-level detail is in `references/emitters.md`.

Uploading and registering are separate steps, and the gap between them holds a whole class of silent nulls.
Harbor uploads the skills for every agent, and of the 39 agents its factory registers, 22 read the injected directory and 17 ignore it with no error, no warning and no log line.
`scripts/design_matrix.py` carries the consuming set as `HARBOR_SKILL_CONSUMING_AGENTS` and refuses to emit a manifest for a `cells.json` naming anything else, including any `acp:` shorthand, since `factory.py:167-175` routes those through the non-consuming `acp` adapter.
That refusal is the only cheap gate for this class: it runs before any container starts, and nothing written after a run distinguishes a non-consuming adapter from a working one.
Per-adapter destinations differ as well, so no single canary assertion covers a grid; `references/emitters.md` carries the destination table and the cells where Harbor and BenchFlow do not agree on where skills land.

One free delivery gate exists, on the BenchFlow arm.
`bench eval run --agent oracle --skill-mode with-skill --skills-dir <dir(C)>` runs the whole deployment path with no model call and asserts in the container that the skill catalogue at each discovery path matches the catalogue the host counted, raising `experiment_fidelity/skill_deployment_missing` on a mismatch.
Run it once per distinct dir(C) shape before any metered batch.
Harbor has no free equivalent, because every adapter's registration copy is built in `run()` rather than `setup()` and `--install-only` skips the agent run.

Present the menu with arithmetic filled in — runs = |C| × k × cells — and let the user choose.
Cost every figure at metered API rates.
Subscription-authenticated cells are permitted for interactive exploration and are never used for a run batch whose numbers are reported: metered costing is robust to the unresolved credential-use-policy question in either direction, and a subscription cell confounds the measurement independently, because rate-limit throttling is nondeterministic and single-account auth caps concurrency.
Enforcing that rule takes an explicit environment scrub rather than merely withholding a flag.
Claude Code and Codex gate subscription auth behind `CLAUDE_FORCE_OAUTH` and `CODEX_FORCE_AUTH_JSON`, but Pi injects `ANTHROPIC_OAUTH_TOKEN` whenever the variable is present (`pi.py:102-105`), so a Pi cell in a reported batch must declare `ANTHROPIC_OAUTH_TOKEN=""` in its `env` block or run from a shell where it is unset.
No per-run cost figure exists yet, so derive one from a calibration batch before presenting any budget table.
Do not silently default:

1. **Paired marginals** — C = {∅} ∪ {{u} : u ∈ 𝒫}; |C| = n+1. Measures each
   unit's solo efficacy E({u}) − E(∅). No interactions.
2. **Marginals + targeted pairs** — add {u,v} for pairs with overlapping
   trigger surface (description keyword/intent overlap — the near-miss
   structure predicts interference). Yields second differences Δ_uv for the
   pairs most likely to be nonzero.
3. **Foldover** — ∅, the n singletons, the n complements of singletons, and 𝒫;
   |C| = 2n+2 for n ≥ 3. It yields a solo marginal and a leave-one-out
   marginal per unit, whose gap aggregates every higher-order interaction
   involving that unit without separating them. It has no defining relation
   and carries no resolution claim, and from n ≥ 4 it contains no two-element
   subsets, so no Δ_uv comes out of it.
4. **Full factorial** — 2^n. Only for n ≤ 3 or when someone else pays.

Add "everything on" (C = 𝒫) to options 1 and 2 when the deployment reality is
all-units-loaded — that is the condition users actually live in, and
non-monotonicity means it cannot be inferred from marginals. Options 3 and 4
already contain it.

`scripts/design_matrix.py` emits `conditions.json`, a run manifest of shell
commands per (condition × cell × trial), and `jobs.json` recording where each
job will land. It carries whatever concurrency and environment variables each
cell declares in `cells.json` and knows nothing about authentication pools;
which cells may appear in a batch whose numbers are reported is the metered-rate
rule above. k ≥ 3.
It refuses outright on one thing only, the non-consuming Harbor adapter above,
and it sets `HARBOR_TELEMETRY=0` on every Harbor line unless a cell overrides
it, for the reason given in Phase 6.

Selection-competition evals (does the RIGHT unit win when many are loaded) are
**off by default**. Offer them once when |𝒫| > 1; if accepted, see the
selection-evals section of `references/lattice-design.md` for the artifact-
fingerprint pattern.

## Phase 6 — Run and analyze

Run oracle everywhere first; then the manifest.

`scripts/collect_rewards.py --conditions design/conditions.json --harbor-jobs runs/harbor --benchflow-jobs runs/bench --out results.json` walks both runners' job trees and emits the `{condition, cell, task, trial, reward}` rows the analyzer reads.
Those two roots are what `design_matrix.py --jobs-root runs` lays down, and `design/jobs.json` records the same mapping in the `{runner, cell, condition, path}` shape `--job-index` consumes when a job name cannot carry its condition.
It refuses rather than guesses: an unresolvable condition, an ambiguous reward dict, unscored rollouts with no `--errors-as` choice, or a failed injection check all exit 2.
The Harbor injection check reads each trial's `lock.json`, whose `skills` list carries a content digest per skill, and falls back to the requested `config.agent.skills` only when a trial wrote no lock; the BenchFlow check requires a non-null `effective_skills_dir` under `with-skill` rather than trusting `skill_mode` alone.

Read that check for what it proves, which is resolution and request, not delivery.
`_write_trial_lock` runs inside `Trial.__init__` at harbor `trial.py:104`, before `_resolve_injected_skills` at `:107` and long before `_upload_injected_skills` at `:411`, and `_build_agent_skill_locks` (`models/job/lock.py:462-475`) calls only host-side functions.
So a populated `lock.json` says the paths resolved on the host and pins their digests, and says nothing about what reached the container.
It stays fully populated through an upload failure, a permissions failure, or an adapter that never reads the injected directory, and a 17-adapter batch that delivered nothing writes a clean lock and passes this check.
The check is one-sided: a disagreement proves the lattice did not vary as designed, and agreement proves only that the request and the host-side resolution matched.
Delivery is covered before the run instead, by the adapter allowlist and the BenchFlow oracle canary in Phase 5.

Harbor's own telemetry is a third surface not to consume in analysis.
`telemetry.py:239` sets `uses_skills=any(agent.skills for agent in config.agents)` from the requested list, never consulting the effective directory or the adapter, so it classifies a voided run as skill-bearing.
The emitted manifest sets `HARBOR_TELEMETRY=0` (`telemetry.py:40`, `:45`) rather than publishing that classification.

Feed `results.json` to `scripts/analyze_lattice.py`:

- Ê(C) per cell. The reward type is read off each task's own data: a task
  whose rewards all lie in {0,1} is binary and gets a Wilson interval on its
  pass rate, any other value in [0,1] makes it graded and it gets a
  task-clustered bootstrap percentile interval on the mean, and a cell mixing
  the two is refused as an input error rather than pooled. A cell carrying
  one task gets point estimates with the bootstrap intervals suppressed.
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
next-actions checklist. Census both trees before proposing any dynamic
evaluation, source first, because the deployed run needs the source run to
resolve plugin membership over a flat tree:

```
scripts/census.py --root <plugins-dir> --out src-census.json
scripts/census.py --root ~/.claude/skills --out dep-census.json \
  --membership-from src-census.json
```

Without `--membership-from`, every skill in the flat deployed tree resolves to
the `<external>` sentinel and the derived plugin units disappear. The skill
bundles a source census at `census.json` that can stand in for the first
invocation; check its `provenance` block against the tree in front of you
before relying on it.

Two stages of that program are named and not yet built.
Both are static, near-free and 100-percent coverage, which is why they gate all container spend.
`lint` is a per-skill static pass: YAML-parse the frontmatter, score description quality against the trigger methodology, list environment couplings for remediation, and check progressive-disclosure structure.
`selection-sim` is the same shape one level up: simulate everything-on triggering across the full deployed description set and adjudicate the flagged competition pairs, with no container and no task execution.
Neither exists in `scripts/` at instrument version 0.2.1, so read the stage ordering as a plan rather than as inherited implementation, and do not go looking for a script that is not there.

## Instrument versioning

This skill is the instrument, and results are comparable only within one version of it.
`0.1.0` is the as-authored baseline, `0.2.0` was the contract-repair round, and `0.2.1` corrects the claims in it that landed on the wrong side of the container boundary; the frontmatter `version` field is the authority and `CHANGELOG.md` records what moved between them.
Stamp the instrument version into every package README and every results file, and index evaluation results by it so a cross-version comparison has to be made deliberately.
Do not modify the instrument while an evaluation is being authored or run.
Revising harborize itself is in scope and is the intended path for defects found mid-round: record the defect, finish the round, then apply the change and bump the version.

Every upstream claim here is anchored to a revision, because the 0.1.0 text cited a harbor command that has since been removed and a benchflow flag that does not exist.
Versions 0.2.0 and 0.2.1 were both written against harbor at `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow at `d30527b82027a416e72014920cdf43a534967ad3`, and skillsbench at `9a1f4dd5f7659f75707435da3ce854b6e48321d1`, read from the local clones under `~/ghq/github.com/`.
Those clones sit at their own HEAD rather than at a project-wide pin, so re-read any cited file and line before relying on it.

## Review gate

Before handing anything over, audit the package against
`references/algebraic-invariants.md` — one line per invariant, pass/fail, in
the package README. A package failing truncation, inhabitation, non-triviality,
or coupling is not done, whatever else works.
