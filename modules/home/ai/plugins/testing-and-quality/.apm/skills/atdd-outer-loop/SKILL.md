---
name: atdd-outer-loop
description: Orchestrate the ATDD outer loop that wraps inner TDD. Load when starting acceptance-driven work, choosing ATDD versus plain TDD, routing a proposition to BDD versus a property/law test versus a regression/smoke test versus a formal proof, or enforcing RED-before-GREEN through a real runner. Defers formulation, step binding, discovery, inner TDD, and severity to their owners.
---

# ATDD outer loop

This skill orchestrates acceptance-test-driven development as an outer loop that wraps an inner test-driven-development loop.
It owns two things and delegates everything else: the loop's phase choreography, and the two routing gates that decide whether the outer loop should run at all and whether a given proposition belongs in a behavioral scenario.
Formulation of Gherkin and the observable-outcome craft belong to `bdd-gherkin-formulation`; native step binding belongs to `bdd-step-definitions`; discovery belongs to `preferences-collaborative-modeling`; the inner red-green-refactor belongs to `test-driven-development`; severity, evidence quality, and test adequacy belong to `preferences-validation-assurance`.

## What this skill orchestrates

The method reads on two axes at once.
The first axis is a maturity gradient that carries a decision from discovery through formulation to automation: a divergent conversation surfaces what must be true, a convergent encoding fixes each decision as a scenario in the ubiquitous language, and a runner binds each scenario to the running system.
The second axis is the loop nesting: the acceptance stream constrains what the system does as an external observable, while the inner unit stream constrains how it does it, and both must go green together before a unit of work is complete.

The automation leg here uses native `.feature` runners, not a portable intermediate representation.
A scenario is executed directly by the language's own Cucumber-family runner — pytest-bdd, cucumber-jvm, cucumber-rs, Cucumber.js — with step definitions that call into the system and are committed as first-class source.
This is a deliberate divergence from Disciplined Agentic Engineering, whose pipeline parses a `spec.md` into a JSON intermediate representation and regenerates gitignored test files from it through a project-specific generator.
The two-axis reading, the discovery-to-artifact gradient, the per-runner triad, and the outer-loop gates are shared; the intermediate-representation indirection is dropped in favor of runners that own their bindings.
See `references/outer-loop-workflow.md` for the phase-by-phase choreography.

## Gate 0 — outer loop or plain inner TDD?

Not every change earns the outer loop.
The gate asks whether the change has an external observable that a non-implementer stakeholder would recognize and care about.
When it does — a user-facing behavior, a domain rule, a service contract, an observable effect of an operation — run the full outer loop so the acceptance stream pins the behavior independently of its structure.
When it does not — an internal refactor that preserves behavior, a private helper, a data-structure choice with no observable shadow — skip the outer loop and drive the work with plain inner TDD through `test-driven-development`, because an acceptance scenario over a purely internal change can only restate the implementation and will couple to it.
The tell that the outer loop is being forced is a scenario whose steps name functions, tables, or endpoints; that is Gate 1's failure surfacing early, and the honest response is to drop to inner TDD rather than to launder structure through Gherkin.

## Gate 1 — is BDD the right tool for this proposition?

Even inside the outer loop, a single proposition may not belong in a behavioral scenario.
This gate routes each proposition to the modality that can actually witness it, along a behavioral-surface boundary.
A behavioral proposition — a lifecycle a user drives, an invariant the system enforces at its surface, an observable effect or coeffect of a concrete operation, an observable runtime computation — routes to a BDD scenario.
A universal or algebraic law — a monoid, semiring, or homomorphism law, a functor or monad law, anything quantified over all inputs — routes to a property or law test; see `preferences-algebraic-laws`.
A proof obligation or a static-exhaustiveness claim routes to a formal check: a Lean proof and its round trip through `refinement-driven-development`, or the type checker and build gate that already discharge it.
A dependency-compatibility or import-smoke proposition routes to a regression or smoke test, not to Gherkin, because dressing an import check as a scenario yields a vacuous `Given` and a `Then` that swallows the very error it should surface.

| Proposition | Modality | Owner |
|---|---|---|
| Domain lifecycle, invariant rejection, observable effect/coeffect, runtime computation | BDD scenario | this skill → `bdd-gherkin-formulation` |
| Universal / algebraic law (monoid, semiring, homomorphism, functor, monad) | Property / law test | `preferences-algebraic-laws` |
| Proof obligation, static exhaustiveness | Formal proof / type-and-build gate | `refinement-driven-development` |
| Symbolic edge exploration | Symbolic (CrossHair) or property test | `preferences-algebraic-laws` |
| Dependency compatibility, import smoke | Regression / smoke test | `references/fix-defect-loop.md` |

The `safeadt` behavioral-acceptance specification is the canonical exemplar of this boundary drawn cleanly.
Its behavioral-surface-boundary requirement scopes into BDD only the ledger Decider lifecycle and invariant rejections, the service and projection observable behavior, the observable effect and coeffect grading of a concrete operation, the geometry runtime behavior, and the shim-import acceptance criterion, and it scopes out static exhaustiveness, the Lean proofs, CrossHair symbolic checking, and the pure algebraic monoid, semiring, and homomorphism laws — each left on its existing gate of basedpyright strict, `lake build`, the CrossHair backend, or a Hypothesis property test respectively (behavioral-acceptance `spec.md`, the "Behavioral surface boundary" requirement and its "stay on their existing gates" scenario).
The spec also records the witnessing spectrum a scenario sits in: a Lean proof witnesses more than a Hypothesis property, which witnesses more than a Gherkin scenario, so a scenario is a high-legibility, low-rigor example certificate that complements but never substitutes for a property or proof.
The full boundary table with these citations is `references/is-bdd-the-right-tool.md`, the canonical home for the routing boundary.

## The outer loop — eight gated phases

Each phase defers its craft to an owner and then closes on a gate that the next phase's entry checks.
The phases are elaborated in `references/outer-loop-workflow.md`; in brief:

P1 discovers acceptance criteria as decisions in domain language, deferring facilitation to `preferences-collaborative-modeling`, and closes on the coverage gate that every criterion maps to at least one scenario.
P2 formalizes each criterion as a scenario in the ubiquitous language, deferring authoring to `bdd-gherkin-formulation`, and closes on the observable-outcome gate below.
P3 runs an independent spec-leakage audit — a fresh agent, never the author — and closes on a clean audit.
P4 binds the scenarios to the system through native step definitions, deferring to `bdd-step-definitions`, and closes on the RED gate: the acceptance suite runs and fails for the right reason, proving the behavior does not yet exist.
P5 implements against the specs with the inner two-stream TDD loop, deferring the red-green-refactor to `test-driven-development`.
P6 closes on the GREEN gate: a full acceptance run and the unit suite pass together, not an impact-selected subset.
P7 refines under the design constraints without changing observable behavior.
P8 verifies and optionally fires the mutation firewall, deferring severity and adequacy to `preferences-validation-assurance`.

## Phase 3 in depth — independent spec-leakage audit

Specs describe external observables in domain language; the audit removes anything that names the machine.
It runs as a fresh subagent whose identity differs from the author's, so the review is not the author re-reading their own intent.
The taxonomy has four buckets: code references (class, function, method, variable, module, file-path names), infrastructure references (tables, columns, queries, endpoints, HTTP verbs and status codes, queue and cache keys), framework references (controller, service, repository, middleware, reducer, resolver, hook, store), and technical-implementation references (data structures, algorithms, wire protocols, internal events).
The audit is read-only: it proposes domain-language rewrites and lets the human decide, and a term that genuinely is the domain — "balance" in a ledger, "table" in a database tool — is not leakage.

```gherkin
# leakage — names the store and the command handler
Given the LedgerService has an empty EventStore
When handle() is called with a Deposit command
Then store.streams[account] contains a Deposited row

# observable — the same behavior in the ubiquitous language
Given a new account with no history
When 50 is deposited
Then the balance is 50
```

The audit is a gate, not advice: the leakage taxonomy and the re-anchored ledger examples are in `references/spec-leakage-and-guardian.md`.

## Observable-outcome gate

A scenario's `Then` must assert an outcome, not the mechanism that produced it.
The gate is two lines.
First, would the wording of the `Then` change if the implementation changed but the observable behavior did not — if yes, the step is coupled to structure, not to outcome.
Second, assert the outcome against an independent literal oracle, never against a value recomputed by the same production path that produced it, since a `Then` that recomputes its own expectation is a tautology that passes vacuously.
The full corpus lives at its single canonical home and is not restated here: the positive and negative `safeadt` exemplars, the independent-literal-oracle rule, and the extension of that rule to Scenario Outline `Examples` columns (an expected column computed by the production path is the tautology trap at scale) are in `bdd-gherkin-formulation` at `references/observable-outcome-discipline.md`.

## Handoff-as-gate and verification independence

Phases coordinate through durable handoffs, not chat, so context survives a compaction or an agent swap.
Each handoff asserts its exit criteria with evidence, and the next phase's entry gate reads that handoff rather than trusting a claim of completion.
Verification independence is a hard constraint: the agent that verifies a unit of work must have an `agent_id` different from the agent that implemented it and from the agent that refined it, because an author cannot independently confirm their own output.
Fresh-per-phase agents also resist the role erosion that a long-lived agent suffers as its context compacts; dispatch of those fresh agents defers to `subagent-driven-development`.
See `references/handoff-as-gate.md`.

## The fix/defect loop

A defect is repaired regression-spec-first.
Before touching the fix, write the scenario or unit test that reproduces the defect and confirm it is RED on the current code — a test that passes before the fix witnesses nothing.
Then make it GREEN with the smallest change, and keep the reproduction as a permanent regression witness.
A dependency-compatibility regression routes to a regression or smoke test rather than a scenario, per Gate 1; severity and evidence quality defer to `preferences-validation-assurance`.
See `references/fix-defect-loop.md`.

## Anti-patterns

Writing the code before the acceptance scenario inverts the loop and lets the implementation dictate the specification.
Forcing a scenario over a purely internal change launders structure through Gherkin and is Gate 0 failing silently.
Asserting a `Then` against a value the production path recomputed is the tautology trap and is the observable-outcome gate failing silently.
Treating acceptance tests as sufficient leaves internal structure unchecked, and treating unit tests as sufficient misses integration — the two streams constrain differently and neither alone suffices.
Letting the author audit their own specs, or the implementer verify their own code, collapses verification independence.

## Provenance and cross-references

The outer-loop discipline, the two-test-stream constraint, the spec-leakage rule, the fresh-per-phase verification independence, and the mutation-firewall idea are original prose synthesized from the ideas of Disciplined Agentic Engineering (DAE), MIT (c) 2026 Miklos, and its Robert C. Martin acceptance-test lineage (the application of ATDD to agentic coding, itself descended from the XP/FIT/FitNesse tradition of Beck and Cunningham).
This skill diverges from DAE in one deliberate respect: DAE routes specs through a portable JSON intermediate representation and a project-specific generator that emits gitignored tests, whereas this group binds native `.feature` runners whose step definitions are committed source.
The two-axis split, the discovery-to-artifact gradient, the per-runner triad, the when-BDD gate, and the one-directional pointers up from the runner layer are re-authored in this group's own words from the bushido-collective han BDD skills, used for structure and ideas only.

- `bdd-gherkin-formulation` — Gherkin authoring and the canonical observable-outcome corpus.
- `bdd-step-definitions` — native step binding, the runner layer.
- `preferences-collaborative-modeling` — discovery and Example Mapping, the source of the acceptance criteria the loop formalizes.
- `test-driven-development` — the inner red-green-refactor loop P5 delegates to.
- `subagent-driven-development` — fresh-agent dispatch for the independent audit and verification.
- `preferences-validation-assurance` — severity, evidence quality, confidence, and test adequacy for the verify and mutation phases.
- `refinement-driven-development` — the formal-proof oracle Gate 1 routes proof obligations to.
- `preferences-algebraic-laws` — the property/law-test route for universal propositions.
- `preferences-domain-modeling` — the ubiquitous language and the algebraic-data-type literals the observable oracle asserts against.
