---
name: bdd-gherkin-formulation
description: >
  Use when writing, refining, or reviewing Gherkin as living documentation. Applies BRIEF, groups scenarios under Rules-vs-Examples, keeps steps declarative over imperative via the implementation-change litmus, and enforces the observable-outcome discipline — assert observable behavior against an independent literal oracle, never re-derive the expected value through the production path, never inspect private state behind a protocol. This is the formulation craft only: not discovery (see preferences-collaborative-modeling), not binding steps to a runner (see bdd-step-definitions), not orchestration or the when-BDD gate (see atdd-outer-loop).
---

# BDD Gherkin formulation

## Overview

Formulation is the craft of writing Gherkin that reads as living documentation.
A good scenario is a concrete example of a business rule, expressed in the domain's ubiquitous language, not a script of the mechanics that happen to satisfy it today.
The scenario states what the system does; the binding underneath states how the check is wired.
When the two are kept apart, the feature file survives implementation churn and remains a document a domain expert can read.

This skill owns the authoring craft and the canonical statement of the observable-outcome discipline for the two-layer group.
The running example throughout is a small account ledger: an account can be opened, deposited into, withdrawn from, and closed; it exposes a balance; and it rejects an overdraft.
Every Gherkin fragment below is anchored on that one narrative so the reader learns the craft against a coherent story rather than a scatter of unrelated snippets.

## When to use

Reach for this skill when writing new scenarios, when refining a feature file that feels bloated or unclear, or when reviewing scenarios for whether each one proves a rule.
Reach for it when a scenario name restates its Rule instead of naming a specific instance, when a Then reads like it is inspecting the implementation rather than an outcome, or when steps have accreted conjunctions and UI mechanics.
Reach for it, too, whenever you are about to write a Then and need to decide what to assert and against what oracle.

Do not reach for it to discover the examples in the first place: that is Example Mapping and collaborative modeling, which precede formulation (see preferences-collaborative-modeling).
Do not reach for it to write the step bindings that make a scenario executable: that is the runner layer (see bdd-step-definitions).
Do not reach for it to decide whether the change wants BDD at all, or to sequence the outer acceptance loop against the inner TDD loop: that is the orchestration layer (see atdd-outer-loop).

## Where this sits

This skill is the formulation half of the concept layer in a two-layer group.
The concept layer pairs atdd-outer-loop (orchestration, routing gates, and the when-BDD boundary) with this skill (Gherkin authoring craft and the observable-outcome discipline).
The runner layer is bdd-step-definitions, which binds a formulated feature to a native test runner.

The pointers run one direction only.
This skill points up and across to atdd-outer-loop and the fleet skills it depends on, and the runner points up to this skill and to atdd-outer-loop.
Nothing points back down, so a change to a runner never forces a change to the craft, and the craft stays independent of any one language's binding mechanism.

## BRIEF

Seb Rose's BRIEF gives six properties every scenario should have.
Read the acronym as a review pass: take each scenario and ask the six questions in turn.

Business language asks whether a domain expert would recognize the wording; a scenario written in the vocabulary of the storage layer or the framework fails it.
Real data asks whether the values are vivid and concrete; "an open account with balance 100" carries a story, "user1 / thing-a" carries none.
Intention revealing asks whether the step says what happens, not the click-by-click how.
Essential asks whether every line serves the rule under test, with setup for unrelated concerns removed.
Focused asks whether the scenario proves exactly one rule, so it fails only when that rule breaks and not from some unrelated change.
Brief asks whether it fits in about five lines, because a stakeholder skips a scenario that sprawls.

The ledger feature reads well against all six: "Given an open account with balance 100 / When 150 is withdrawn / Then the command is rejected as an overdraft / And no events are emitted" is domain language, vivid data, intention-revealing, essential, focused on the overdraft rule, and brief.

## Rules versus Examples

Liz Keogh's distinction separates the acceptance criterion from its illustration.
A Rule is the abstract business rule; an Example (a Scenario) is one concrete instance that illustrates it.
Group the scenarios that demonstrate the same rule under a single `Rule:` keyword whose text states that rule crisply, not the mechanism that implements it.

```gherkin
Rule: A withdrawal that exceeds the balance is rejected as an overdraft

  Example: Withdrawing 150 against a balance of 100 overdraws
    Given an open account with balance 100
    When 150 is withdrawn
    Then the command is rejected as an overdraft
    And no events are emitted
```

The Rule names a business rule a stakeholder would recognize; a heading like "Rejecting the withdraw command in the decider" would name a mechanism and fail the test.
When a scenario discovers a rule the feature does not yet name, add or split out a new `Rule:` section rather than piling it under a loosely related one.
If the Example heading reads more like a rule than the Rule does, promote it, and prefer several small `Rule:` groups over one long pile of scenarios.
A feature with many scenarios and no `Rule:` sections is usually hiding its acceptance criteria; extract the rules and group the scenarios around them.

## Declarative over imperative

A scenario should describe intended behavior, not the implementation that currently delivers it.
The cucumber litmus is a single question asked of every step: will this wording need to change if the implementation changes?
If yes, the step has leaked a mechanism and should be reworked in terms of what the user or domain observes.

An imperative ledger scenario spells out keystrokes — navigate here, type there, press this — and breaks the moment any of those move.
A declarative one says "When 40 is withdrawn through the service / Then the balance read through the store is 60" and survives a change of transport, storage, or UI because the intent is unchanged.
The full litmus, the imperative-versus-declarative contrast on the ledger narrative, and the atomic-step rules live in [`references/declarative-vs-imperative.md`](references/declarative-vs-imperative.md).

## The observable-outcome discipline

This is the crux of formulation and the reason a BDD suite is worth more than a pile of asserts, so it is stated canonically here.
A Then earns its place only when it checks something that genuinely comes out of the system, compared against an expectation the production code did not compute.
Two litmus tests decide it.

The independent-oracle test asks: would this Then still fail if the production path were subtly wrong?
It fails when the expected value is re-derived by calling the very function under test, or reconstructed by the same closed-form the production path uses, because then the assertion can only confirm that the code equals itself.
It passes when the expected value is an independent literal — `Ok([Deposited(50)])`, `Error(Overdraft())`, `Active(60)`, the balance `60` — written down by the author and compared against what the system produced.

The public-surface test asks: does this Then read only what the system exposes through its public, observable surface?
It fails when the assertion reaches behind a protocol into private state — indexing a store's internal streams, reading an envelope's timestamp field — because that couples the document to an implementation detail a domain expert never sees.
It passes when the outcome is read through the public surface the feature is documenting, such as the balance obtained through the store's read-through rather than the store's internal dictionary.

Together the two tests give the observable-outcome rule in one breath: assert an observable outcome against an independent literal oracle, and never re-derive it through the production path or fish it out of private state.
The nine-scenario safeadt corpus that teaches this rule case by case — the positive exemplars, the labeled anti-patterns, the file-and-line citations, and the Scenario Outline caveat — lives in [`references/observable-outcome-discipline.md`](references/observable-outcome-discipline.md).
Consult it whenever you are unsure whether a Then is a genuine check or a tautology in Gherkin clothing.

## Is BDD the right tool?

Not every change wants a Gherkin scenario: a universal law wants a property test, a pure algebraic invariant wants preferences-algebraic-laws, and a smoke or regression check wants a plain unit test.
The one-line litmus is that Gherkin fits an observable, example-shaped business rule stated in the domain's language; anything better expressed as a universal quantifier or an import-time smoke test does not belong in a `.feature`.
The full boundary — the routing gate that decides BDD versus property versus unit before any scenario is written — is Gate 1 of atdd-outer-loop; do not restate it here, route to it.

## Formulation checklist

Run the seven-point checklist over each scenario before considering it done, and again when reviewing an existing feature.
It asks whether the Rule is a crisp business rule rather than a mechanism, whether the Example name adds information beyond the Rule, whether the data is real and carries the one ledger narrative, whether every line is essential, whether the scenario proves exactly one rule, whether cross-cutting assertions are inline as extra Then steps rather than split into their own rules, and whether an assertion on exact output uses a doc string with precise expected text.
The full checklist, the review loop for an existing feature file, and the common-mistakes table are in [`references/brief-checklist.md`](references/brief-checklist.md).

## Atomic steps

Keep each step to one thing.
A `Given` that contains "and" in the middle is usually two preconditions wearing one step, and it should split so each half can be reused; "Given an open account with balance 100" and "And a clock fixed at a known instant" are two steps, not one conjunction.
Conjunction steps make bindings over-specialized and hard to reuse, and feature-coupled step wording — naming a step after the feature file it happens to live in rather than the domain concept — drives an explosion of one-off bindings.
The cucumber treatment of conjunction steps, feature-coupled step definitions, and the one-thing-per-Given rule is paraphrased in [`references/declarative-vs-imperative.md`](references/declarative-vs-imperative.md).

## Review process

Reviewing an existing feature file is a fixed loop.
Read each Rule in turn and ask what business rule it states; apply BRIEF to each Example beneath it; look for duplicate examples across rules and for rules broad enough that they should split; confirm the ledger narrative runs consistently throughout; and check that setup is minimal, with incidental `Given` steps pushed into a `Background` only when they are truly incidental to every scenario.
The single question that drives the whole pass is: what rule does this scenario prove?
If the answer is unclear, reformulate the scenario or take it back to discovery.

## Common mistakes

The recurring formulation faults each have a fix, and the safeadt corpus supplies a labeled anti-pattern for the sharp ones.
A Rule that describes a mechanism is fixed by stating the business rule; test-label data ("thing-a") is fixed by a vivid consistent narrative; an Example name that restates its Rule is fixed by naming the specific instance; several rules crammed under one `Rule:` are fixed by splitting.

The dangerous mistakes are the ones that produce a green scenario proving nothing.
A grade assertion compared against the identical constructor the production code stored is a tautology and routes to a property or law test; a Then that indexes a store's private streams reaches behind the protocol and should assert through the public surface; a Then whose When swallowed the exception under test over a vacuous Given is an import smoke test in Gherkin clothing and belongs in a regression test; a weak `is_error()` that hides which domain reason fired should name the instance and assert the domain reason.
Each of these is documented with its exact assertion and file-and-line citation in [`references/observable-outcome-discipline.md`](references/observable-outcome-discipline.md); the table in [`references/brief-checklist.md`](references/brief-checklist.md) collects the craft-level faults.

## Cross-references

- `atdd-outer-loop` — the sibling concept skill; owns orchestration, the routing gates, and the canonical when-BDD boundary (Gate 1) this skill defers to.
- `bdd-step-definitions` — the runner-layer skill; binds a formulated feature to a native test runner and points up to this skill.
- `preferences-collaborative-modeling` — Example Mapping and EventStorming, the discovery that surfaces the examples before formulation begins.
- `preferences-domain-modeling` — ubiquitous language and algebraic-data-type literals; the source of the domain vocabulary a scenario must speak and of the literal values an independent oracle compares against.
- `preferences-algebraic-laws` — where a universal law belongs when the litmus routes a candidate scenario away from Gherkin toward a property or law test.
- `test-driven-development` — the inner unit loop that turns each formulated scenario green step by step; the acceptance scenario is its outer frame.
- `subagent-driven-development` — fresh-agent dispatch for implementing against a formulated feature without contaminating the authoring context.
- `preferences-validation-assurance` — severity and test adequacy; the calibration for how strong an outcome assertion must be, referenced rather than restated here.
- `refinement-driven-development` — the formal-oracle route when the expected outcome is a verified Lean specification rather than a hand-written literal.

## Sources and attribution

The BRIEF framework, the Rules-versus-Examples grouping, the formulation checklist, and the review process are adapted from yaks by Matt Wynne (MIT), de-branded and re-anchored on the ledger narrative; see [`NOTICE-yaks.md`](NOTICE-yaks.md) for the license and attribution, which credits yaks and the underlying work of Seb Rose ("Keep Your Scenarios BRIEF") and Liz Keogh ("Acceptance Criteria vs. Scenarios").
The declarative-over-imperative treatment, the implementation-change litmus, the conjunction-step and feature-coupled anti-patterns, the one-thing-per-Given rule, and the Gherkin constructs are cited and paraphrased from the cucumber documentation (bdd/better-gherkin, guides/anti-patterns, bdd/who-does-what, gherkin/reference).
The observable-outcome corpus embeds exemplars from the user's own safeadt project, cited to its source test tree.
