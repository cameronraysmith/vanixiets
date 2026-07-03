---
name: openspec-bdd-bridge
description: Keep the OpenSpec spec encoding and the Gherkin feature encoding aligned as one acceptance layer for a change whose delta specs carry behavioral requirements. Load under an OpenSpec change to lay out and align delta specs with their .feature files before apply, to route each requirement through the atdd-outer-loop Gate 1 so only behavioral requirements become committed scenarios, and to reconcile the correspondence before archive.
---

# OpenSpec and BDD bridge

This skill is the single substantive home for the correspondence between an OpenSpec change's delta specs and the Gherkin `.feature` files that witness its behavior.
It is invoked under an OpenSpec change whose delta specs carry behavioral requirements, to keep the OpenSpec spec encoding and the Gherkin encoding aligned as one acceptance layer rather than two independently drifting artifacts.
When a change has no delta specs, or its delta specs carry no behavioral requirements, this skill no-ops and there is nothing to align.

The carrier gate that defers here is the pre-apply spec-and-feature alignment sub-gate in the agentic-planning-development-workflow router; see ../agentic-planning-development-workflow/references/board-and-gates.md#spec-and-feature-alignment-pre-apply for where this skill sits on the board.

## Two encodings of one acceptance layer

An OpenSpec delta spec and a Gherkin feature file are two encodings of the same acceptance layer, and this skill maintains the translation between them.

OpenSpec delta specs encode a requirement as a `### Requirement:` heading whose statement uses SHALL or MUST, followed by one or more `#### Scenario:` blocks with exactly four hashtags.
Each scenario lists its steps as `- **WHEN**` and `- **THEN**` bullets; the canonical OpenSpec convention omits an explicit GIVEN and folds any precondition into the WHEN.
Gherkin `.feature` files encode the same behavior as GIVEN-WHEN-THEN scenarios under a `Feature:` heading.

The mapping between the two is not symbol-for-symbol.
OpenSpec's WHEN bundles the precondition and the trigger together, so translating into Gherkin splits it: the precondition becomes GIVEN, the trigger becomes WHEN, and THEN maps directly to THEN.
The correspondence is non-total and non-one-to-one.
It is non-total because only behavioral requirements are witnessed by feature files, and it is non-one-to-one because one OpenSpec capability fans out to many feature files and one requirement fans out to one or more scenarios.

## Modality routing through Gate 1

Not every OpenSpec requirement is behavior-driven, so this skill routes each requirement's scenarios through the existing Gate 1 before any of them becomes a committed `.feature` scenario.
Gate 1 is the modality decision table in the atdd-outer-loop skill at ../../../../testing-and-quality/.apm/skills/atdd-outer-loop/references/is-bdd-the-right-tool.md; consult it for the row-by-row routing and do not restate its table here.

Only the behavioral rows produce committed feature scenarios: domain lifecycle behavior, invariant rejection, observable effect or coeffect, and observable runtime computation.
The remaining rows route elsewhere and never enter the feature files: an algebraic-law requirement becomes a property test, a proof obligation routes to refinement-driven-development, a static exhaustiveness requirement is discharged by the type checker, a symbolic-edge requirement routes to CrossHair, and a dependency or import requirement becomes a smoke test.
Record each requirement's Gate 1 verdict, naming the chosen modality and, where the modality is not BDD, why not, in the change's design.md.
Record these verdicts as a Gate 1 modality verdict table in design.md carrying one row per requirement with an explicit `modality` column; this column is the machine-checkable field that the pre-apply EST layout and the before-archive reconciliation both read to decide, per requirement, whether an EST witness is expected.
Because the before-archive reconciliation greps for exact tokens, an EST-routed row must carry the literal `modality` value `est-property`, `est-contract`, or `est-symbolic`, never the corresponding Gate 1 prose name such as `Property test`, which would silently defeat the machine check.
These tokens map one-to-one from the Gate 1 rows: a general, metamorphic, or model-based property requirement becomes `est-property`; a design-by-contract precondition, postcondition, or invariant becomes `est-contract`; and a symbolic-edge-exploration requirement becomes `est-symbolic`.
A change with no row in that EST-routed subset carries no EST obligation and behaves exactly as a change without the enrichment.
This mirrors the behavioral-surface boundary that the safeadt reference project keeps in its design D6 table.

## Pre-apply alignment

The pre-apply alignment step is what the carrier's pre-apply gate defers to.
Before apply-change runs, confirm that the change's delta specs are laid out and that, for the requirements Gate 1 admitted as behavioral, the corresponding `.feature` files are laid out and aligned with those specs.
The apply-phase test-driven development that follows then includes writing the step definitions that bind these scenarios in the target runner, so the pre-apply step establishes the acceptance surface that apply implements against.

Symmetric to how a behavioral requirement gets its witnessing `.feature` file laid out before apply, a requirement whose design.md `modality` is `est-property`, `est-contract`, or `est-symbolic` gets its EST test artifact laid out in the same pre-apply step: an inferred Hypothesis strategy for an `est-property` verdict, an icontract `@require`/`@ensure` predicate for an `est-contract` verdict, or a CrossHair check for an `est-symbolic` verdict, per the executable-specification-testing skill.
The step additionally emits a corresponding tasks.md entry for each such requirement so the modality-agnostic apply-change executor drives it RED-first during red-green exactly as it drives a bound scenario, without any EST-specific instruction reaching the read-only upstream cycle.
This is strictly additive: when no requirement's `modality` falls in the EST-routed subset, no EST artifact is laid out and no tasks.md entry is emitted, and the acceptance surface is byte-identical to a change without the enrichment.

## Traceability convention

The tag-and-guard convention is recommended rather than hard-mandated, and it generalizes the pattern safeadt proves in practice.
Tag each feature at the feature level with `@<capability>`, where the capability is the OpenSpec capability directory name, and tag each scenario with `@req-<slug>` naming its requirement.
Pair the tags with a traceability guard test that asserts every scenario is tagged, every tag is owned by a real requirement, and every in-scope behavioral requirement is witnessed by at least one scenario.
The safeadt project realizes this guard as src/safeadt/tests/test_traceability.py with an `IN_SCOPE_REQUIREMENTS` dictionary that enumerates the behavioral requirements the guard expects to find witnessed.
Because the guard checks in-scope behavioral requirements only, the per-requirement Gate 1 verdict recorded in design.md, together with safeadt's D6 behavioral-surface boundary, is the reference for which requirements the guard is entitled to expect.

## Per-runner conventions

There is no single canonical `.feature` path, so the layout is per-runner rather than fixed.
Under pytest-bdd the features live as importable package resources, for example src/<pkg>/tests/features/; under cucumber-rs they live under tests/features/; under cucumber-js they live under features/**.
Organize step definitions by domain concept rather than one module per feature.
Authoring the Gherkin itself is owned by the bdd-gherkin-formulation skill at ../../../../testing-and-quality/.apm/skills/bdd-gherkin-formulation, and binding the scenarios to native step definitions is owned by the bdd-step-definitions skill at ../../../../testing-and-quality/.apm/skills/bdd-step-definitions and its per-runner references.

## Maintained correspondence and before-archive reconciliation

The correspondence is maintained rather than established once.
The pre-apply step is the initial alignment, apply-phase re-sync keeps specs and features aligned as scenarios are refined mid-development, and a final reconciliation runs before archive.
The before-archive reconciliation is a soft, guidance-only layer, not a new blocking gate and not a competing mechanism.
At reconciliation time it overlays agent-driven guidance on top of the existing Scenario Coverage check inside openspec-verify-change — which already iterates every `#### Scenario:` marker, emits a non-blocking warning when a scenario appears uncovered, and does not block archive — without modifying that upstream skill's built-in check; the overlay is advisory, not an edit to openspec-verify-change.
For a behavioral scenario, the reconciliation confirms that a witnessing `.feature` scenario and a bound step definition exist and that the change's traceability guard test passes; for a scenario Gate 1 routed to a non-behavioral modality, no feature witness is expected, so its absence from the feature files is not a defect.
For a requirement whose design.md `modality` is EST-routed (`est-property`, `est-contract`, or `est-symbolic`), the same reconciliation additionally confirms — as a WARNING only, never blocking archive — that an EST witness exists for it: a committed property test, icontract contract, or CrossHair check corresponding to the artifact laid out pre-apply, mirroring the `.feature` witness check for behavioral scenarios.
When the design.md verdict table carries no EST-routed row this check is N/A and emits nothing, preserving the soft, guidance-only character of the surrounding layer.

## Cross-references

This skill points upward and sideways to the artifacts it coordinates and never installs a downward pointer from the BDD skills back to itself.
It defers to the carrier gate at ../agentic-planning-development-workflow/references/board-and-gates.md#spec-and-feature-alignment-pre-apply for board placement, to Gate 1 at ../../../../testing-and-quality/.apm/skills/atdd-outer-loop/references/is-bdd-the-right-tool.md for modality routing, to bdd-gherkin-formulation for authoring the Gherkin, and to bdd-step-definitions for binding scenarios to a runner.
