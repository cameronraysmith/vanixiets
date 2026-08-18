---
linear_story_id: fe51818e-d7f5-44a7-80c1-fa5ccc75d763
linear_story_identifier: CAM-34
linear_story_title: "Validate the harborize instrument before running any skill evaluations"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-34/validate-the-harborize-instrument-before-running-any-skill-evaluations
linear_story_state: Todo
linear_team: CAM
linear_project: skill-evaluation
last_synced_state: Todo
last_synced_at: "2026-08-15T05:17:31Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-08-15T05:17:31Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind: CAM-34 created on team CAM in project Skill evaluation at state Todo; description seeded from proposal.md Why/What Changes/Capabilities; canonical crossing comment posted" }
---

## Why

The harborize instrument emits evaluation packages and has never produced one that was shown to work.
All three iteration-1 packages failed the oracle inhabitation invariant, and the 0.2.1 repair round asserts a set of container-boundary facts about skill injection that nothing has exercised end to end.
No per-run cost figure exists either, so every budget in the staged marketplace program multiplies an unmeasured constant.
Running that program before the instrument is validated is how iteration 1 produced three unusable artifacts.
Validating it now yields a permanent injection regression test, one working mechanical package, and the cost constant every later budget depends on.

## What Changes

**Evidence for skill injection**
- From: the instrument documents where each adapter registers an injected skill and which surfaces cannot witness delivery, all read from upstream source and none exercised.
- To: an injection canary package that asserts delivery in the container, kept in the corpus permanently so a later regression in the injection path fails a task rather than silently voiding a batch.
- Reason: every silent-null class the instrument documents produces a clean run and a plausible negative result, so only a positive control distinguishes them.
- Impact: additive; a new package directory pair and a materialized condition directory.

**A validated mechanical package**
- From: three iteration-1 packages that are reference material for shape and are not cited for results.
- To: one regenerated mechanical evaluation package authored BenchFlow-native, exported to a Harbor head, passing both static gates and the oracle inhabitation invariant under both runners.
- Reason: the dual-head authoring path and the oracle rung have never been demonstrated together on a task that measures something. Separate-mode verifier machinery was in this list and has been withdrawn: at benchflow 0.7.4 a package declaring it does not launch, and Harbor's separate verifier empties the verifier log directory the package's channel depends on, so exercising it and keeping a runnable BenchFlow arm are mutually exclusive. Design decision D11 carries the evidence.
- Impact: additive; the iteration-1 packages stay where they are and are not promoted.

**A measured per-run cost**
- From: budget menus presented with `runs = |C| x k x cells` and no cost per run.
- To: one measured per-run cost constant, taken from the metered rung, recorded with the cell it was measured on and the instrument version that produced it.
- Reason: the staged program's screening figure of roughly 500 to 700 runs was scoped to one cell and never multiplied by a cost, so it is arithmetic waiting on this number.
- Impact: additive; the constant is an input to the dependent change, not a commitment to any budget.

**A cost ladder as the working order**
- From: an implicit assumption that a package is validated by running it.
- To: seven rungs run in order, six of them free of model spend, each with an exact command and an executable pass criterion, with the metered rung last and reduced to one short trial per cell.
- Reason: only the adapter registration copy requires a real agent invocation to witness; everything upstream of it is detectable at zero marginal cost.
- Impact: the prerequisites rung is currently unmet, so the ladder starts with real setup tasks rather than assumptions.

## Non-goals

These are out of scope and are named so that the apply gate's scope trigger has something to check against.
A change that grows to include any of them is not this change.

- No marketplace-wide evaluation. The staged program in `references/marketplace-program.md` stays a plan.
- No condition-lattice runs. No emitted design leaves the throwaway gate-check path: rung 1 runs `design_matrix.py` three times against `/tmp` output directories purely to exercise its adapter gate, and nothing it writes there is executed, committed or consumed by a later rung. The change's own condition set is the single canary condition directory the delivery rungs require.
- No judge-validation package. The judge gate is a hard prerequisite for any judge-based stratum and it belongs to the dependent change.
- No cost projections beyond the measured figure. The constant is reported with its measurement conditions; multiplying it into a program budget is the dependent change's work.
- No promotion of the three iteration-1 packages. They are read for shape and regenerated, never cited for results.
- No modification to the harborize instrument. Instrument versioning freezes it at 0.2.1 for the duration; a defect found mid-change is recorded and deferred to the next revision.

A larger dependent change, provisionally `marketplace-skill-evaluations`, consumes these deliverables afterward and is out of scope here.

## Capabilities

### New Capabilities

- `evaluation-package-validation`: the instrument's demonstrated ability to produce an evaluation package whose skill injection is proven end to end at each level it can fail, and whose per-run cost is measured rather than assumed. Covers the ordered cost ladder from environment prerequisites through host-side resolution and static validation to in-container delivery and adapter registration, the permanent injection canary, and the recorded cost constant.

### Modified Capabilities

<!-- No existing openspec/specs/ capability covers evaluation packages; the four existing capabilities are pyrite bare-metal install specs and are untouched. -->

## Impact

- New package pairs under the evaluation corpus at `modules/home/ai/evals/harborize/`, co-located with the first-party skill sources under `modules/home/ai/plugins/`: an authored BenchFlow-native tree per task plus a generated `<task-id>-harbor` sibling, per the dual-head layout three independent validators force. Job output goes to `logs/harborize/`, which `.gitignore:57` already excludes. Two small repository-config edits support the corpus and are named here rather than left unexplained: `.gitignore` gains `__pycache__/` and `*.pyc`, because tasks 2.3, 5.8 and section 3 run the instrument's own `scripts/*.py` and CPython writes bytecode beside them inside the frozen instrument directory — which is also why task 1.8's freeze recipe excludes that path rather than relying on the ignore; and `.gitattributes` marks `modules/home/ai/evals/harborize/*-harbor/**` `linguist-generated`, because those heads are emitted by `bench tasks export` and a marker cannot be written into them without breaking the property that the committed tree equals a fresh export. No file in the corpus carries the `.nix` extension, because `flake.nix:6` calls import-tree bare over `modules/` and every `*.nix` file there is evaluated as a flake-parts module; the constraint is enforced by an extension audit and a flake evaluation rather than by convention.
- New host prerequisites, unmet when this change was written and satisfied at rung 0: a running Docker daemon (OrbStack was stopped and the socket absent), plus `harbor` and `bench` installed from PyPI latest stable (`uv tool install harbor`, `uv tool install benchflow`; settled 2026-08-15 — installs track PyPI releases, not sha-pinned source checkouts), never by `uv sync` inside the read-only ghq reference clones, which stay reading trees for the pinned anchors.
- Upstream pins recorded and cited: harbor `ac398bbda7c4c1073461797d3b95c2455cc671b5`, benchflow `d30527b82027a416e72014920cdf43a534967ad3`, skillsbench `9a1f4dd5f7659f75707435da3ce854b6e48321d1`. All three ghq clones are shallow and sit at those HEADs rather than at released tags, so the pins are recorded in the change and every anchor is re-read at them.
- Metered spend on the final rung only, on the codex cell via the ChatGPT-subscription path (`CODEX_FORCE_AUTH_JSON=1` or `CODEX_AUTH_JSON_PATH=<path>`, settled decision of 2026-08-15, recorded in this change; supersedes the earlier claude-code first-cell choice), with `ANTHROPIC_OAUTH_TOKEN` still scrubbed on any Pi cell and `HARBOR_TELEMETRY=0` on every Harbor line. The instrument's `references/marketplace-program.md:46` supplies the auth forms and model strings and is cited only for those; it records no supersession, and design decision D3 carries the narrowing the settled decision implies.
- Unchanged: the harborize instrument at `modules/home/ai/plugins/testing-and-quality/.apm/skills/harborize/`, frozen at 0.2.1 for the duration, and the three iteration-1 packages under `~/Downloads/`.
- Touched, and previously mis-declared as unchanged: `modules/home/ai/skills/default.nix`. Its `excludedSkills` list gains eight retired `issues-beads*` names in a commit that lands inside this change's window and belongs to the beads retirement rather than to any rung here. The edit is recorded rather than reverted, and the declaration is corrected rather than left contradicting the branch.
- A limit of that exclusion, recorded because it reads wider than it is: `excludedSkills` acts on the composed `.claude/skills` tree home-manager consumes and not on marketplace publication, which is package-scoped through `apm.yml` and `.github/plugin/marketplace.json` with no skill-level exclusion at the compose or validate layer. The instrument therefore remains published inside the `testing-and-quality` plugin while being withheld from nix delivery, as do the eight `issues-beads*` skills. It is also narrower than global: `default.nix:94` and `:121` compute `allSkills // extraSkills` and `removeAttrs` never touches `extraSkills`, so an `aiSkills.extraSkillDirs` entry with a colliding leaf name would silently re-add an excluded skill. No current contributor collides.
