# Is BDD the right tool for this proposition?

This is the canonical home for the behavioral-surface boundary — the routing decision that sends each proposition to the modality that can actually witness it.
It is the deep reference behind Gate 1 in the SKILL body.
The boundary is single-owned here; every other skill in the group states the one-line litmus and points to this file rather than restating the table.

## The one-line litmus

A proposition belongs in a BDD scenario when it is a behavioral proposition: something the system does that is observable at its public surface and that a domain stakeholder would recognize and care about.
If the proposition is instead quantified over all inputs, discharged by a proof or a type check, or a compatibility fact about the environment, it belongs to another modality, and forcing it into Gherkin produces a scenario that either restates its own mechanism or witnesses nothing.

## The full boundary table

| Proposition class | What it asserts | Routes to | Owner |
|---|---|---|---|
| Domain lifecycle | A sequence a user drives (open, deposit, withdraw, close) reaching an observable state | BDD scenario | `bdd-gherkin-formulation` |
| Invariant rejection | The system refusing an illegal command at its surface, with the reason observable | BDD scenario | `bdd-gherkin-formulation` |
| Observable effect / coeffect | That a concrete operation incurs a specific observable effect grade or demands a specific input | BDD scenario | `bdd-gherkin-formulation` |
| Observable runtime computation | A computed observation (an area uses π; a runtime type is rejected at a boundary) | BDD scenario | `bdd-gherkin-formulation` |
| Universal / algebraic law | A monoid, semiring, or homomorphism law, a functor or monad law — anything ∀-quantified | Property / law test | `preferences-algebraic-laws` |
| General / metamorphic / model-based property | A ∀-quantified property, a metamorphic relation between two runs, or a stateful model-based invariant that is not a named algebraic law | Property test | `executable-specification-testing` |
| Design-by-contract precondition / postcondition / invariant | That a concrete operation's checked pre/post-condition or a class/type invariant holds at runtime | Contract check (runtime assertion) | `executable-specification-testing` |
| Symbolic edge exploration | Coverage of a symbolic input space beyond example rows | Symbolic (CrossHair/SMT) or property test | `executable-specification-testing` |
| Proof obligation | A theorem about the model that must hold by construction | Formal proof and round trip | `refinement-driven-development` |
| Static exhaustiveness | That a match or type is total, caught before runtime | Type checker / build gate | its existing gate |
| Dependency compatibility / import smoke | That a module imports or an upstream API still fits | Regression / smoke test | `references/fix-defect-loop.md` |

The boundary between the first four rows and the rest is the behavioral-surface boundary: a scenario is an example-based certificate of behavioral inhabitation at the public surface, and it is the wrong instrument for a proposition that is universal, proof-shaped, or environmental.

## The safeadt behavioral-acceptance specification as canonical exemplar

The `safeadt` behavioral-acceptance specification draws this boundary explicitly and is the reference exemplar.
Its "Behavioral surface boundary" requirement states that the layer covers only behavioral propositions and does not attempt to witness static, symbolic, proof, or universal-law properties.
It scopes into BDD exactly the ledger Decider lifecycle and its invariant rejections, the ledger service and projection observable behavior, the observable effect and coeffect grading of a concrete operation, the geometry runtime behavior, and the verification-stack shim-import acceptance criterion.
It scopes out, each left on its existing gate, static exhaustiveness, the Lean proofs, CrossHair symbolic checking, and the pure algebraic monoid, semiring, and homomorphism laws.
Its "static, symbolic, proof, and universal-law properties stay on their existing gates" scenario names those gates precisely: such a property must not be moved into the BDD suite and must remain discharged by basedpyright strict, `lake build`, the CrossHair backend, or a Hypothesis property test respectively (behavioral-acceptance `spec.md`, the "Behavioral surface boundary" requirement).

The same specification records where a scenario sits among witnesses: a Lean proof witnesses more than a Hypothesis property, which witnesses more than a Gherkin scenario, so a scenario is a high-legibility, low-rigor example certificate that complements but never substitutes for a property or a proof, and adding it does not reduce the rigor carried by the deeper witnesses (behavioral-acceptance `spec.md`, the witnessing-spectrum requirement).
The practical reading is that routing a proposition out of BDD is not a demotion; it is placing the proposition on the gate that actually witnesses it, while BDD carries the legible behavioral shadow.

## The routing example that most often trips the gate

The proposition most easily misrouted is one that looks like behavior but is really an unenforced universal law asserted on a single example.
A scenario that checks a concrete operation's effect grade against the exact grade the production path recorded — asserting the identical constructor a decorator stored, on a grade nothing at runtime enforces — is a tautology dressed as behavior, and it routes to a property or law test rather than to a scenario (the grade case at `test_grades_steps.py:39-40` in the `safeadt` source tree).
The behavioral shadow that does belong in BDD is the observable consequence of the grade — that handling a deposit incurs exactly the read-and-append effect and demands the balance coeffect as an observed fact of the operation — not the algebra of the grade itself, which stays on the property gate.
The full anti-pattern with its positive and negative exemplars is owned by `bdd-gherkin-formulation` at `references/observable-outcome-discipline.md`; this file owns only the routing decision that the unenforced-law shape leaves BDD.

## How this differs from the observable-outcome gate

Gate 1 and the observable-outcome gate are sequential, not redundant.
Gate 1 asks whether the proposition is a BDD proposition at all; if it is not, no amount of careful `Then` wording rescues it, and the proposition leaves for its proper modality.
The observable-outcome gate applies only after Gate 1 admits the proposition, and asks whether the admitted scenario's `Then` asserts an outcome against an independent oracle rather than recomputing its own expectation.
A proposition can pass Gate 1 (it genuinely is behavioral) and still fail the observable-outcome gate (its `Then` is a tautology), and the two gates are owned in different files precisely so each is stated once: the routing boundary here, the observable-outcome craft in `bdd-gherkin-formulation`.
