---
title: preferences-workflow-orchestration-algebra skill — design decisions
---

This note records the design decisions behind the `preferences-workflow-orchestration-algebra` skill authored under `modules/home/ai/skills/src/core/preferences-workflow-orchestration-algebra/`.
It is a working note: it captures the name, scope, four-file structure, VCS seeding, and open follow-ups so a later session can resume or revise without re-deriving the rationale.

## Name and scope

The skill is named `preferences-workflow-orchestration-algebra`, matching its directory and its SKILL.md `name` field.
Its subject is the algebraic and categorical reading of *data/pipeline* workflow orchestrators — concretely Dagster, with Flyte and Airflow as contrast points — through the Build Systems à la Carte (BSàlC) lens, together with the functional-programming and compositional-continuous-verification (CCV) discipline that closes the gaps the orchestrator does not enforce itself.

The scope boundary that mattered most during authoring is the word *workflow*.
This repository uses "workflow" pervasively for subagent orchestration DAGs (the orchestrator-mode discipline, session-plan, the diamond workflow), so the skill description had to be written to prevent mis-triggering there.
The SKILL.md `description` therefore states explicitly that the skill is "scoped to data-pipeline orchestration, not agent/subagent workflow DAGs," and the "Load when" gerund clause names only data-pipeline situations (mapping a Dagster asset graph to a free-term / store-interpreter structure, choosing between asset-based and task-based orchestrators, writing a lawful IO manager, reasoning about static-vs-dynamic dependencies, enforcing type-safe FP discipline on Dagster or Flyte pipelines in Python).

The skill deliberately does not overlap the two existing Dagster skills under `~/projects/omicslake-workspace/dagster-skills/skills/`.
`dagster-expert` owns operational APIs, the `dg` CLI, and decorator recipes; `dignified-python` owns imperative production-Python style; this skill owns the *law and structure* — the BSàlC mapping and the FP-law discipline that closes the *almost*-gaps.
SKILL.md states this three-way boundary in its "Complementarity with the sibling Dagster skills" section and defers to `dagster-expert` by reference rather than restating API symbols.

## The IO-example decision

The worked centerpiece in file 03 is a *lawful IO manager*, chosen because it is the one BSàlC component a practitioner must write themselves and therefore the one place the categorical reading converts from description into a checkable proof obligation.
The example is Lance-flavored but explicitly generalizable to any content-addressed store (substitute any pure put/get against an address).
It discharges two coherence conditions: round-trip identity (`load_input(handle_output(x)) == x`) and address determinism (the storage address is a pure function of `(AssetKey, PartitionKey)`), which together make materialization a function of the key and Dagster's caching and `DataVersion` early-cutoff correct in BSàlC's sense.
The example ships with three regulators — Hypothesis property tests over the whole input space, a runtime `@asset_check`, and nix-wrapped derivations under `checks.<system>` for the CCV closure operator — illustrating the no-leak principle (artifact plus regulator in the same commit).

## Four-file structure

The skill is four files, each with a single home for its concept so there is no developed duplication:

- `SKILL.md` — frontmatter (the only file carrying it), the thesis, the one-page BSàlC primer, the master mapping table with explicit tightness tags, the two-tag honesty discipline, brief linking summaries of what 02 and 03 add, the sibling-skill complementarity table, the Contents TOC, and cross-references. It is the lean hub.
- `01-dagster-categorical-mapping.md` — the per-primitive rationale: nine entries, each naming the exact Dagster API (verified against the Dagster source tree), the categorical target, and a tight/almost tightness verdict. This is the sole home of the mapping rationale.
- `02-asset-vs-task-spectrum.md` — the three-point Airflow → Flyte v2 → Dagster spectrum on the BSàlC constraint axis, graded by separation of definition from execution with a secondary typed-I/O axis. Sole home of the orchestrator-comparison content.
- `03-fp-discipline-and-enforcement.md` — the enforcement layer: the twelve-rule set, the basedpyright/beartype/Expression/Pydantic/Hypothesis toolchain, the CCV closure-operator backbone, the worked lawful IO manager, and the monoid/fold laws for partitioned re-materialization. Sole home of the discipline that turns *almost* into *lawful*.

The connective logic is that every *almost* in the master mapping table corresponds to one or more enforceable rules in 03, and 01 names which side of the free-term/interpreter split each primitive lives on.

## Tightness taxonomy decision

Dagster-to-algebra mappings carry one of two tags: *tight* (the construct genuinely is the categorical object and Dagster maintains it) or *almost* (it holds only modulo a named coherence condition Dagster does not enforce).
*Gestural* is a within-*almost* qualifier at the weakest end (the resources row), not a separate third tag.
This two-tag system is uniform across SKILL.md and file 01; the "aspirational" wording survives only in file 02 scoped to the Flyte v2 orchestrator reading, which is a distinct context from a Dagster-primitive mapping and is not a contradiction.

## VCS choice

The skill is authored on an independent jj chain seeded off the `dagster-expert-enable` commit `zxylnunv` (`feat(home/ai/claude-code): pin dagster-skills marketplace and enable dagster-expert`).
Seeding from that commit rather than from the current development join keeps the work topically adjacent to the dagster-skills enablement while remaining a single-purpose chain that is rebasable to main on its own.
The chain is not yet integrated.

## Open follow-ups

The most substantive provenance gap is the Selective rung.
The local copy of Mokhov, Mitchell and Peyton Jones, "Build Systems à la Carte" at `~/projects/planning-workspace/engineering-references/mokhov-2018-build-systems-a-la-carte/` is the ICFP 2018 version, which *predates* Selective functors.
Selective was introduced in the authors' 2019 "Selective Applicative Functors" and folded into the JFP 2020 extended version of "Build Systems à la Carte."
Every use of Selective in the skill is flagged as reconstructed from the follow-on work rather than quoted from the local source.
Obtaining the JFP 2020 extended BSàlC would let the `Applicative ⊂ Selective ⊂ Monad` placement and the Selective-flavored Dagster surfaces (`can_subset`, `AutomationCondition` gating, `PartitionMapping` selection) be cited exactly rather than reconstructed; this is worth doing if a local copy can be sourced.

The skill is authored but not yet built via home-manager or integrated.
It exists only as source files under `modules/home/ai/skills/src/core/`; it has not been built into the nix store, symlinked to any agent's skills directory, or validated by `nix eval`/`nix build`, and the seeding chain has not been rebased onto main.
A later session should run the home-manager build to confirm the directory registers via the automatic skill directory scan, then decide on integration timing.
