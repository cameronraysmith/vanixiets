---
name: bdd-step-definitions
description: >
  Bind formulated Gherkin to native step definitions across pytest-bdd, cucumber-rs, and cucumber-js. Load when writing or reviewing step glue, choosing a matcher (Cucumber Expression vs regex vs typed parser), structuring a per-scenario World or context, wiring feature discovery and the run command, or diagnosing a tautologically-green or private-state-piercing Then. Runner layer of the BDD/ATDD group; points up to the concept layer, never down.
---

# BDD step definitions

This is the runner layer of the BDD/ATDD group.
It assumes a scenario has already been discovered, judged worth automating, and formulated as declarative Gherkin by the concept layer above it (`atdd-outer-loop` for the routing gate, `bdd-gherkin-formulation` for the observable-outcome craft).
Its one job is to bind that `.feature` to executable step definitions in a specific runner without letting the automation drift away from the observable outcome the scenario names.
Everything here is one-directional: this skill points up to the concept layer and the wider fleet, and nothing in the concept layer depends on it.

## When this applies, and when not

Reach for a step-definition runner only once the when-BDD gate has passed.
The gate's litmus in one line: automate as a scenario when it names an observable business outcome a non-author stakeholder would recognize and that outcome survives an implementation change; if the behavior is an internal invariant, an algebraic law, or a single-function contract, it belongs in a unit, property, or law test instead.
The full is-BDD-the-right-tool boundary — the routing table and the labeled anti-patterns it sorts away — lives canonically in `atdd-outer-loop` (Gate 1 and its `references/is-bdd-the-right-tool.md`); do not restate that boundary here, and do not write step definitions for a behavior the gate would have routed elsewhere.

## The universal shape

Every runner in scope decomposes into the same four parts, and porting between them is mostly re-spelling these.
A `.feature` file holds the formulated Gherkin (authored under `bdd-gherkin-formulation`).
Glue holds the step definitions that match each step line to code.
A per-scenario World or context carries state between the Given, When, and Then of one scenario.
A run entry point binds features to glue, filters by tag, and executes.

## The divergence that matters: per-scenario World or context

The runners agree on the shape and disagree on exactly one thing worth internalizing: how a scenario's state is isolated and threaded.
pytest-bdd has no World object at all; state flows through pytest fixtures, and a step publishes its result by returning it under `target_fixture="name"`, which downstream steps then request by parameter name, one fresh function-scoped graph per scenario with no globals.
cucumber-rs makes the World a `#[derive(cucumber::World)]` struct, default-constructed fresh for each scenario and threaded into every step as `&mut World`.
cucumber-js makes the World the `this` of each step, a fresh instance of the class registered through `setWorldConstructor`, discarded when the scenario concludes even on a retry run.
The shared invariant beneath all three is that no scenario may observe state left by another, so a global mutable shared across scenarios is the classic flake and must not appear.

## Matching a step line

Prefer a Cucumber Expression (`{int}`, `{string}`, `{word}`) for readable matches and drop to a regular expression only when the expression cannot capture the shape.
pytest-bdd spells the expression form as `parsers.parse("{amount:d}")` with typed converters and offers `parsers.re(...)` as the regex escape hatch, while a bare string is an exact match.
cucumber-rs spells it as `#[given(expr = "...")]` versus `#[when(regex = r"^...$")]`, and additionally supports typed capture through any `FromStr` argument or a custom `#[derive(Parameter)]` type.
cucumber-js spells it as a Cucumber Expression string versus a `RegExp`, with the same `{int}`/`{string}` typing role.
Across all three, the typed capture (`:d`, `{int}`, a `FromStr` target) is what lets a step body receive a domain value rather than a raw string.

## Organize by domain concept, not by feature file

Bind steps by the domain concept they exercise, not one step-definition module per feature file.
The safeadt suite is split by capability — decider steps, service steps, grade steps — so each module is reusable across whatever features touch that concept, mirroring the ubiquitous language (see `preferences-domain-modeling`).
One step-definition file per feature file is the documented feature-coupled-step-definitions anti-pattern: it duplicates glue and couples reuse to file layout.
Its line-level cousin is the conjunction step, a single step that folds two facts into one line and forces its body to do two things; that smell is owned upstream by `bdd-gherkin-formulation`, but it surfaces here as a step body that cannot stay single-purpose.

## Observable-outcome at the step body

Every Then binding reduces to a two-line rule.
First, bind the observed value from the public surface a real caller would use — the returned `Result`, the reconstructed state, `balance_of(store, _STREAM)` — never a private field.
Second, assert that value against an independent oracle, a literal you wrote by hand such as `== Active(60)` or `== Error(Overdraft())`, not a value the production path recomputes for you.

The one-line negative to recognize: the safeadt clock scenario reaches `store.streams[_STREAM]` behind the `EventStore` protocol (`test_ledger_service_steps.py:88-89`), a private-state-piercing Then that stays green even if the public read-through breaks; assert through the public surface instead.
This is the same trap that a Scenario Outline hits at scale when an Examples column holds a value the production path computes rather than an independent literal.
The full corpus — the decider's independent literal oracles, the grade tautology, the shim smoke test dressed as a scenario, the weak `is_error()` that hides the domain reason, and the Scenario-Outline extension of the independent-oracle rule — lives canonically in `bdd-gherkin-formulation/references/observable-outcome-discipline.md`.
Do not duplicate that corpus here; cite the litmus and point.

## Binding, discovery, and run per runner

The three reference files each carry a minimal `.feature`, a step-definition file, a run command, and the runner-unique idioms.

| Runner | Bind features to glue | Run | Reference |
|---|---|---|---|
| pytest-bdd | `scenarios(files(...))` in the step module | `pytest` | [`references/pytest-bdd.md`](references/pytest-bdd.md) |
| cucumber-rs | `World::run("tests/features/...")` in a `harness = false` `[[test]]` | `cargo test --test <name>` | [`references/cucumber-rs.md`](references/cucumber-rs.md) |
| cucumber-js | `paths` + `import` globs in the config | `npx cucumber-js` | [`references/cucumber-js.md`](references/cucumber-js.md) |

The pytest-bdd reference is grounded near-verbatim in the safeadt suite and serves as the positive model; the other two re-anchor the same ledger narrative in their language's idiom.

## Traceability and CI wiring

Tag every scenario with one `@<spec>` capability tag and at least one `@req-<slug>` requirement tag, and let the runner surface them.
pytest-bdd applies each Gherkin tag as a pytest mark, so register the tags where the runner expects them — safeadt does this in the packaged `conftest.py` via `pytest_configure` calling `config.addinivalue_line("markers", ...)` so that `filterwarnings = ["error"]` does not turn an unregistered mark into a failure — and select with `pytest -m <tag>`.
cucumber-rs and cucumber-js expose the same tags as run-time filters (`--tags`).
A guard test then resolves the shipped `.feature` files and asserts the trace is intact — every scenario carries its tags and every in-scope requirement is witnessed by at least one scenario — exactly as safeadt's `test_traceability.py` does through `importlib.resources`.
The unbound-step half of that guard is the runner's own scaffolding path (`pytest --generate-missing` for pytest-bdd) or its strict undefined-step exit code.

## Cross-references

These pointers all run upward, out of the runner layer.

- `bdd-gherkin-formulation` authors the `.feature` files this skill binds and is the canonical home of the observable-outcome discipline and its safeadt corpus.
- `atdd-outer-loop` owns the when-BDD gate (Gate 1) and the ATDD orchestration this runner sits inside.
- `test-driven-development` and `subagent-driven-development` are the inner red-green-refactor loop each step body drives and the fresh-agent dispatch that runs it.
- `preferences-validation-assurance` calibrates severity and test adequacy — whether a scenario's oracle is severe enough to fail under a plausible wrong implementation.
- `preferences-domain-modeling` supplies the ubiquitous language and the algebraic-data-type literals the step bodies assert against.
- `refinement-driven-development` and `preferences-algebraic-laws` are where an internal invariant or a universal law belongs when the when-BDD gate routes it away from Gherkin.
- `preferences-collaborative-modeling` runs the Discovery and Example Mapping that produce the examples before any formulation.
