---
name: executable-specification-testing
description: Author one executable predicate and consume it three ways without redeclaration — runtime contract enforcement, property-test strategy inference, and SMT/concolic checking — and own the property-based-testing craft (generator and strategy design, shrinking mechanics, stateful and metamorphic testing) alongside design-by-contract as a named modality and the SMT/concolic rung. Load when wiring icontract, icontract-hypothesis, and CrossHair against a single contract; designing a generator, strategy, or shrinker; writing a stateful/model-based or metamorphic property test; placing a technique on the example-to-proof rigor ladder; or choosing between samplers and solvers. Routes the algebraic law catalogue and parametricity to preferences-algebraic-laws, the Lean-to-Rust round trip and Charon/Aeneas to refinement-driven-development, and severity, confidence, and the validation ladder to preferences-validation-assurance. Points up to atdd-outer-loop, whose Gate 1 loads this skill.
---

# Executable specification testing

This skill owns the family of techniques that turn a specification into something a machine runs against real or symbolic inputs: property-based testing as a craft, design-by-contract as a runtime verification modality, and SMT/concolic checking as the rung above them.
Its organizing payload is the single-contract thesis — one executable predicate authored once and consumed by three engines without redeclaration — and the craft absorbed underneath it: generator and strategy design, shrinking mechanics, stateful and metamorphic testing.
It routes the pieces it deliberately does not restate.
The algebraic law catalogue, the functor-applicative-monad hierarchy, and parametricity and free theorems belong to `preferences-algebraic-laws`; mechanical Lean-to-Rust proof, the Charon and Aeneas round trip, and translation validation belong to `refinement-driven-development`; severity, confidence, the validation ladder, and mutation analysis belong to `preferences-validation-assurance`; the closure-operator-and-regulators framing belongs to `preferences-compositional-continuous-verification`; the graded-dependent-type ideal and the capability-interface stance belong to `preferences-theoretical-foundations`; and the concrete monorepo instance belongs to `nucleus-platform`.
It points up to `atdd-outer-loop`, whose Gate 1 routes a universal, symbolic, or contract-shaped proposition here, and it is a peer of `bdd-gherkin-formulation`.

## The single-contract thesis

The thesis is that one executable predicate can be written once and read by three engines that verify it in three different ways, with no second declaration of the specification.
An icontract `@require`/`@ensure` predicate attached to a function is the single source of truth.
The runtime engine, icontract itself, checks the predicate on every concrete call and raises on violation.
The property engine, icontract-hypothesis, reads the very same `@require` bounds and *infers* a Hypothesis strategy from them, so a property test draws only inputs the precondition admits without a hand-written generator.
The symbolic engine, CrossHair, evaluates the same lambdas on Z3-backed symbolic inputs and searches for a concrete counterexample that satisfies the preconditions yet breaks a postcondition.

This is a *hub*, not a pipeline.
The three engines do not feed one another in sequence; they each read the same runtime contract metadata independently.
Nothing flows from icontract-hypothesis into CrossHair — they are distinct integration surfaces that happen to share one substrate, the four dunders (`__preconditions__`, `__postconditions__`, `__postcondition_snapshots__`, `__invariants__`) that icontract attaches to the checker.
Framing it as a pipeline invites the error of thinking the symbolic engine consumes the sampler's output; it does not.
The exact wiring — `infer_strategy` / `test_with_inferred_strategy`, the `AVAILABLE_PROVIDERS["crosshair"]` backend seam, and CrossHair's `IcontractParser` — is in `references/single-contract-hub.md`, which also records deal as a peer contract dialect.

## The rigor ladder as a routing re-reading

There is an intuitive ordering of these techniques by the strength of the guarantee they buy: a worked example is weaker than a property test over generated inputs, which is weaker than a runtime contract that holds on every actual call, which is weaker than a symbolic or concolic check that searches an input space, which is weaker than a machine-checked proof.
This skill does not render that ordering as a standalone table.
The freedom-ordered ladder of verification techniques is owned by `preferences-validation-assurance`, and this skill's rungs are a re-reading of that ladder through the severity criterion: each rung raises the Mayo-severity of the test — how hard the specification would find it to pass were the implementation wrong — and the choice of rung is a severity-and-confidence decision routed to that skill, not a fixed hierarchy asserted here.

One thing on that ladder is *this skill's own synthesis and must be flagged as such*.
That design-by-contract and SMT/concolic checking sit as a clean, monotone escalation strictly between property testing and proof is not asserted by any anchor.
`preferences-validation-assurance` omits SMT/concolic entirely and lists design-by-contract only as "contract tests" without placing it in a monotone order relative to properties or proof.
The monotonicity is a useful organizing conjecture, offered as a routing heuristic and discharged to the severity criterion, never presented as an established result.
Treat it as a claim to test against severity, not a law.

## The design-by-contract rung

Design by contract in Meyer's sense is a named verification modality: a routine carries a precondition (`require`) the caller must establish, a postcondition (`ensure`) the routine guarantees, and a class carries an invariant that holds before and after every method.
The distinguishing property is that these are *executable predicates checked at runtime on concrete calls* — assertions with a specification's intent, not a separate proof artifact.
icontract is the Python bearer (`@require`/`@ensure`/`@invariant`); the Rust `contracts` crate is the direct analog lowering to runtime `assert!`; both are cross-referenced in `references/cross-language-verification.md`.

The word "contract" is overloaded across the anchor skills, and this rung is none of the other five senses.
It is not the algebraic-law sense in which `preferences-algebraic-laws` says "laws are contracts that abstractions must satisfy" — those are ∀-quantified equational laws verified by property tests, not per-call runtime pre/post-conditions.
It is not the "contract tests" of `preferences-validation-assurance`, which are a place on the validation ladder concerned with consumer-provider compatibility.
It is not the "data contracts" of `preferences-bounded-context-design`, which govern the schema and semantics crossing a context boundary.
It is not the "capability interface" of `preferences-theoretical-foundations`, which is the effect-handler adjunction through which a side effect is discharged.
And it is not the "operating envelope" of `preferences-compositional-continuous-verification`, which is the precondition half of a regulator pair at the system level.
Design by contract here is specifically the Meyer runtime `require`/`ensure`/`invariant` on a routine, and holding those five senses apart is part of what this rung owns.

## The SMT/concolic rung

The rung above contracts is bounded model checking and concolic execution backed by an SMT solver: Z3 or CVC5 (and, through CBMC, a SAT layer) searching a symbolic input space for a concrete witness that satisfies the preconditions and breaks a postcondition.
CrossHair is the Python bearer — concolic execution driving a Z3-backed `StateSpace` per example, either as the standalone CLI checker or as a Hypothesis backend.
In Rust the rung is Kani (CBMC bit-precise bounded model checking, SAT/SMT-backed), Creusot (Rust to Coma to Why3 to SMT solvers, deductive), and Prusti (built on the Viper infrastructure to Z3).
In Haskell it is SBV (symbolic values compiled to SMT-LIB2 and dispatched by `prove`/`sat`, Z3 by default).

This rung is *solver-backed*, and that is the sharp line separating it from Aeneas.
Aeneas performs a functional translation of Rust's MIR into a pure lambda calculus for a proof assistant (Lean, Coq, HOL4, F\*) via the Charon frontend; there is no SMT solver in its core translation loop.
Kani, Creusot, and Prusti are the SMT/concolic rung; Aeneas is not.
Aeneas and the Charon round trip are owned by `refinement-driven-development` as the lift-back-to-Lean translation-validation path, and must not be filed under this rung.
The full cross-language placement, and the explicit Aeneas exclusion, are in `references/cross-language-verification.md`.

## The absorbed property-based-testing craft

`preferences-algebraic-laws` owns *which* laws to test and *why*: the monoid, functor, applicative, and monad laws, the least-power abstraction hierarchy, and parametricity and free theorems.
It treats property-based testing purely as the execution vehicle and does not teach the generative craft.
This skill owns that craft: how to *design* a generator or strategy so its distribution actually exercises the interesting region; how shrinking works and why integrated shrinking (Hedgehog's generator-produces-a-shrink-tree, proptest's `ValueTree` simplify/complicate) preserves invariants that manual or type-based shrinking (QuickCheck's separate `shrink`, default empty) cannot; how to model a system as a command sequence over a reference model for stateful/model-based testing (proptest-state-machine's `ReferenceStateMachine` + `StateMachineTest`, Hypothesis's `RuleBasedStateMachine`); and how to state a metamorphic relation when there is no independent oracle for a single output but a known relationship between two runs.

The boundary is surgical and one particular misclassification is forbidden.
The equation `map(f).filter(p) == filter(p ∘ f).map(f)` is a *free theorem* derived from the type by parametricity, owned by `preferences-algebraic-laws`; it is not a metamorphic relation and must not be reclassified as one here.
`references/pbt-craft.md` opens with the full boundary statement and treats the four craft topics cross-language.

## Samplers and solvers are complementary

The samplers-vs-solvers lesson is that the solver is *not strictly stronger* than the sampler: each finds bugs the other misses, so a mature setup runs both.
The concrete evidence is from safeadt.
When the width lower bound on `scaled_rectangle_area` is loosened from `1e-3 <= width` to `0 < width`, icontract-hypothesis finds a real counterexample in well under a second — tiny inputs underflow the product to `0.0`, violating the `result > 0.0` postcondition.
CrossHair's SMT engine did *not* flag the same underflow, because its float reasoning does not model IEEE-754 subnormals here.
The sampler caught a float bug the solver missed.
The lesson generalizes: solvers reason about an idealized model (here, floats without subnormals) and miss where the runtime diverges from that model, while samplers hit the runtime directly but only at the inputs they happen to draw.
Neither dominates; run both, and read a green from one as coverage of its own ground, not the other's.

## Worked example: safeadt (Python + Lean 4)

`safeadt` is the canonical Python worked example of the single-contract hub (its clone is Python and Lean 4 only — it has *no* Rust component, so it demonstrates the Python pillars and the Lean spec beside them, never the Rust pillars).
Its geometry layer declares one contract and consumes it three ways:

```python
@icontract.require(lambda width: 1e-3 <= width <= 1e6)
@icontract.require(lambda length: 1e-3 <= length <= 1e6)
@icontract.require(lambda factor: 1e-3 <= factor <= 1e3)
@icontract.ensure(lambda result: result > 0.0)
@beartype
def scaled_rectangle_area(width: float, length: float, factor: float) -> float:
    ...
```

icontract enforces the four predicates on every concrete call.
icontract-hypothesis reads the three `@require` bounds and infers a Hypothesis strategy, driven by `icontract_hypothesis.test_with_inferred_strategy(scaled_rectangle_area)` with no hand-written `@given`.
CrossHair checks the same lambdas symbolically, reached either through `@settings(backend="crosshair")` on a Hypothesis test or the `crosshair check ... --analysis_kind=icontract` CLI.
beartype answers "is it the right shape?" and icontract answers "does it satisfy φ(x)?" — types cannot express the predicate, so the two are complementary rather than redundant.

The suite reports 83 tests as of its current README (61 deep-verification, 19 acceptance scenarios, 3 trace guards); cite that headline figure rather than the archived 61-test count from an older revision.
The Lean 4 spec beside the Python proves the load-bearing laws — the projection homomorphism and the degree-2 area homogeneity — and each carries a `#print axioms` gate reported to show only `propext` with no `sorryAx`.
That Lean-green claim is asserted from the safeadt README and its `docs/correspondence.md`, not independently rebuilt in this authoring, and the correspondence between the Lean laws and the Python tests is evidenced prose-and-test, not mechanically verified — there is no Charon or Aeneas round trip in safeadt.
The tool-integration friction this example surfaced — the beartype claw hook crashing CrossHair's native importer, the `_hypothesis_compat` shim, and the two basedpyright strict relaxations — is documented in `references/tool-integration-sharp-edges.md`.

## Theory mapping (stated as routing)

The defensible altitude statement is that the property-testing, design-by-contract, and SMT/concolic triad is the *operational approximation, tractable today*, of the typed ideal that `preferences-theoretical-foundations` names — the graded, multimodal, adjoint, dependent type theory toward which the architecture converges.
Contracts are the value-level shadow of that ideal: an icontract `@require` predicate functions as a refinement type, the runtime-checked value-level residue of a dependent type that a richer type system would carry statically.
This is the only bridge to the graded-dependent-type ideal that this skill asserts.
Grades and coeffects themselves stay orthogonal and unconnected to the three tools; no anchor links grading to tests or contracts, so any "graded contract" or "coeffect-aware property" construction would be invention and is not claimed here.

The ladder raises Mayo-severity toward the machine-checked proof that `refinement-driven-development` names as the precise ideal, not a requirement — and that skill already sanctions property-based testing as an honest weaker stand-in in its three-tier degradation (mechanical proof, then differential/PBT, then LLM comparison), which is the standing sanction this skill relies on rather than re-teaching the round trip.
Each technique here is expressible as a first-class regulator in the sense of `preferences-compositional-continuous-verification`, composing with the others into a single closure operator over the codebase.
And each narrows the structural holonomy that `nucleus-platform` measures without paying for the full mechanical Lean-to-Rust round trip — a partial reduction bought cheaply.

## Cross-references

These pointers are one-directional: this skill points up to its orchestrator and across to the anchor owners, and does not restate what they own.

- `atdd-outer-loop` — the orchestrator whose Gate 1 routes a universal, symbolic, or contract-shaped proposition to this skill; this skill points up to it.
- `bdd-gherkin-formulation` — peer modality for behavioral propositions; the routing boundary between them is owned by atdd-outer-loop's Gate 1.
- `preferences-algebraic-laws` — the law catalogue, the abstraction hierarchy, and parametricity and free theorems that the property tests here verify; owns laws-as-properties, this skill owns the generative craft.
- `refinement-driven-development` — mechanical Lean-to-Rust proof, Charon and Aeneas, and translation validation; the proof the ladder points toward and the owner of the functional-translation path this skill's SMT rung is *not*.
- `preferences-validation-assurance` — severity, confidence, the freedom-ordered validation ladder, and mutation analysis; the ladder this skill re-reads and the home of the severity criterion.
- `preferences-compositional-continuous-verification` — the closure operator, regulator pairs, and the operating-envelope sense of "contract".
- `preferences-theoretical-foundations` — the graded-multimodal-adjoint-dependent-type ideal this triad approximates, and the capability-interface sense of "contract".
- `nucleus-platform` — the concrete monorepo instance (conformance checks, holonomy) this skill's techniques narrow.

Reference files:

- `references/single-contract-hub.md` — the icontract to icontract-hypothesis to CrossHair wiring with exact integration symbols, and deal as a peer dialect.
- `references/tool-integration-sharp-edges.md` — the beartype/CrossHair claw-hook conflict, the Hypothesis compatibility shim, and the basedpyright strict relaxations.
- `references/pbt-craft.md` — generator and strategy design, shrinking mechanics, stateful/model-based testing, and metamorphic relations, cross-language, with the algebraic-laws boundary stated first.
- `references/cross-language-verification.md` — the Python/Rust/Haskell/Lean/TypeScript matrix over the PBT, DbC/refinement, and SMT/concolic cells, with the Aeneas exclusion and the model-knowledge cells marked.
