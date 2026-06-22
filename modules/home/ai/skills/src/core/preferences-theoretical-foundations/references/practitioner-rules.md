---
title: Practitioner rules
---

# Practitioner rules

This is the practical spine of the skill, loadable standalone.
It collects eight checkable design rules that fall out of the foundations, each stated in its corrected form and tagged with the sibling reference file that justifies it and the grounding that anchors it.
The rules share one stance.
The routing heuristic is to factor every concern through an adjunction: a slogan, not a theorem, since when a best abstraction exists it is the left adjoint, but not every useful abstraction is a full Galois connection.
The ideal that stance converges on is a single typed calculus — the conjectural internal language of compositional software architecture, which does not yet exist as one calculus.
We approach that ideal asymptotically and partially realize it today, even in an untyped runtime, by keeping a type-checkable Lean specification beside the implementation.
A capability interface discharged by handlers, not a particular monad-transformer stack, is the stable thing we are converging on; a stack is merely one leaky interpreter.

## Contents

- [Rule 1 — model state as decide/evolve, illegal states unrepresentable in the spec first](#rule-1--model-state-as-decideevolve-illegal-states-unrepresentable-in-the-spec-first)
- [Rule 2 — prefer a capability interface over a transformer tower](#rule-2--prefer-a-capability-interface-over-a-transformer-tower)
- [Rule 3 — event log is the source of truth; assert the projection homomorphism law](#rule-3--event-log-is-the-source-of-truth-assert-the-projection-homomorphism-law)
- [Rule 4 — aggregate only over an exact monoid](#rule-4--aggregate-only-over-an-exact-monoid)
- [Rule 5 — track two distinct grades; never call them adjoint](#rule-5--track-two-distinct-grades-never-call-them-adjoint)
- [Rule 6 — grade in the type when control flow is bounded; existential grade when it is not](#rule-6--grade-in-the-type-when-control-flow-is-bounded-existential-grade-when-it-is-not)
- [Rule 7 — keep a type-checkable Lean spec the implementation mirrors](#rule-7--keep-a-type-checkable-lean-spec-the-implementation-mirrors)
- [How the rules compose](#how-the-rules-compose)

## Rule 1 — model state as decide/evolve, illegal states unrepresentable in the spec first

Model every stateful component as a Decider: the pair `decide : Command → State → [Event]` and `evolve : State → Event → State`, plus an initial state.
Write the Lean specification first and make illegal states unrepresentable there before any implementation, so the spec rejects the bad transition rather than the runtime catching it.
The check is concrete.
The component is pure, so testing requires no mocking or infrastructure: given a command and a state, verify the events `decide` produces; given events and an initial state, verify the final state `evolve` folds to.
If reconstructing state needs anything other than folding `evolve` over the event history, the rule is being violated.

The grounding lives in `evolve`, not `decide`.
With an initial state, `evolve` makes `State` an F-algebra for the list functor, so state reconstruction is the catamorphism — the unique fold over the event history — which is exactly what makes the component replayable and testable.
Be precise about what the pair *is*: `decide` is the output/readout leg and `evolve` is the update leg, so the whole Decider is Moore-machine-shaped, and Moore machines are lens-structured.
That last identification is a labelled gloss pending source verification; do not write in code or docs that a Decider literally is a lens, an optic, or a Para morphism, and do not call decide/evolve an adjoint pair.

For the full algebra-of-evolve treatment see decide-evolve-lens.md.
Aggregate mechanics — boundary sizing, invariant placement, the DDD framing of what a Decider models — belong to a sibling: see preferences-domain-modeling for aggregate design and smart constructors, and see preferences-algebraic-data-types for making the command, event, and state types sums and products that exclude the bad cases by construction.

## Rule 2 — prefer a capability interface over a transformer tower

Treat the capability interface — the effect signature, the set of operations a component is allowed to perform — as the stable primitive, and treat any concrete carrier that discharges it as one non-canonical interpreter.
An mtl-style capability constraint is the same design pattern as a finally-tagless encoding: operations are overloaded over an abstract carrier and meaning is supplied by handler selection, so a monad-transformer stack is just one interpreter of the interface, with a handler-record carrier or an algebraic-effect runner as equally valid alternatives.
Prefer the capability interface discharged by handlers over a transformer tower.

The check has two parts.
First, the interface and the handler are separable: you should be able to swap the interpreter (a real handler, a test handler, an alternative carrier) without touching the program written against the interface.
Second, if a transformer stack is genuinely unavoidable, document the effect-ordering commitment it bakes in, because the order in the tower is a semantic choice — `StateT` over `ExceptT` does not commute with `ExceptT` over `StateT`, and the difference is whether state survives an error.
The defect list around transformer stacks (leaky abstraction, ordering commitment, absence of fusion, quadratic lift-chaining) is engineering experience about one carrier family, not a theorem and not a universal property of capability interpreters; some entries are fixed by particular libraries.

See effects-handlers.md for the capability-interface-and-handler treatment and the initial-vs-final duality between an inspectable free encoding and an opaque tagless-final term.
For the functor and monad laws a lawful handler must preserve, see preferences-algebraic-laws.

## Rule 3 — event log is the source of truth; assert the projection homomorphism law

Treat the committed event log as the single source of truth.
Derive the write model by folding `evolve` over the log, and derive every read model as a projection: a per-event observation folded into a target monoid.
Each such projection is a monoid homomorphism from the free monoid of events into the target, and you should assert the law as a test:

```
project (xs ++ ys) == project xs <> project ys
```

This is the foldMap universal property of the free monoid, so observability for the read-model fold is recovered as a theorem rather than an instrumentation convention.
The check is the property test above plus its unit case (`project [] == mempty`); a projection that fails it is not a homomorphism, and any incremental or sharded rollup built on it can silently disagree with a full recompute.

The proof needs only associativity and an identity — the target must be a monoid, nothing more; commutativity is a strictly separate requirement (Rule 4) that buys shard-order invariance, not the homomorphism itself.
The CQRS split — write model on the algebra side, read models on the coalgebra side — is exactly this homomorphism promoted to an architectural boundary.
Keep any richer categorical phrasing (the read model as a "lax-monoidal projection 2-cell") as a suggestive slogan only; the structure actually proven is a strict monoid homomorphism, and the worked example constructs no 2-cell.

See observability-as-theorem.md for the homomorphism proof and the CQRS algebra/coalgebra split.
For operational event-sourcing mechanics — snapshots, replay, upcasting — see preferences-event-sourcing; for how the read-side stream reaches a client, see preferences-functional-reactive-programming.

## Rule 4 — aggregate only over an exact monoid

For any metric that will be sharded, rolled up, or recomputed incrementally, choose an exact aggregation monoid up front, and never aggregate over a non-associative operation silently.
The load-bearing case is numeric: IEEE-754 floating-point addition is not associative, so a read model that sums floats is not a true monoid homomorphism, and reordered or resharded rollups can disagree.
Aggregate over integers, exact rationals, fixed-point decimals, or a canonical-order construction instead, and if you must aggregate floats, treat the result as order-dependent and document that the rollup is approximate.

The check rides on Rule 3: the same `project (xs ++ ys) == project xs <> project ys` property test, run over realistic shard splits and reorderings, fails for a non-associative aggregation and passes for an exact one.
Commutativity is the additional property to test when shard arrival order is not fixed; it is separate from associativity and is what makes order-independent rollups sound.

See observability-as-theorem.md for the associativity requirement and the float caveat.

## Rule 5 — track two distinct grades; never call them adjoint

When a component's resource discipline matters, track two distinct grades and keep them distinct.
The effect grade is drawn from an ordered monoid and records what a computation does to the world; the usage (coeffect) grade is drawn from an ordered semiring and records what a computation demands of its context.
Compose each along its own algebra — effects along the monoid, usage along the semiring's two operations — and wire their interaction through an explicit distributive-law-style rule.
Never call the two faces adjoint, and never collapse demand into the dual of effect: in the literature they are two distinct functors over two distinct grading algebras coordinated by a distributive law, which is precisely the data for composing a comonad with a monad when no adjunction is assumed.

The check is structural: there should be two indices in your types or contracts, not one, and they should compose by different rules.
A single index doing double duty, or a claim that one is the adjoint or dual of the other, is the violation.
The word *grade* is reserved for this resource-semiring index; use *effect* and *coeffect* for its two faces.

See graded-effects-coeffects.md for the graded-monad effect side, the graded-comonad coeffect side, and the distributive law between them.

## Rule 6 — grade in the type when control flow is bounded; existential grade when it is not

Track the grade in the type wherever control flow is statically bounded, and hand back an existential grade — knowingly — where it is not.
When a program performs a fixed, statically known amount of work, pin its grade in the type so the cost is checked at compile time.
When work depends on data the type system cannot bound (unbounded, data-dependent recursion), the strongest honest type is an existential grade: a `Σ g, Prog g a` that says "some grade exists" without naming it.
Choose the existential deliberately and document that the bound is dynamic, rather than faking a static grade you cannot defend.

The check is a judgment call made explicit: for each graded operation, state whether its grade is pinned or existential, and justify an existential one by pointing at the unbounded loop or data-dependent branch that forces it.
Pinning the grade statically under unbounded recursion is, today, a conjectural synthesis of several unintegrated research lines, not a theorem — so an existential grade there is the correct, not the lazy, answer.

See internal-language.md for the existential-grade frontier and why static pinning under unbounded recursion remains open.

## Rule 7 — keep a type-checkable Lean spec the implementation mirrors

Keep a type-checkable Lean architecture file for any component worth getting right, regardless of the implementation language, and let it be the spec the implementation mirrors.
This is how we partially realize the typed ideal today even when the runtime is untyped: the Lean file is where illegal states are made unrepresentable (Rule 1), where the projection homomorphism is proved rather than merely tested (Rule 3), and where grades are pinned or shown existential (Rule 6).
The implementation in the runtime language is then a mirror of that spec, and the gap between them is the thing verification closes.

The check depends on the implementation language.
When the implementation is Rust, hand the verified round trip to a sibling: refinement-driven-development owns the Lean-to-Rust lowering, the lift back via translation validation, and how much mechanical correspondence is achievable; defer all verification process there.
When the implementation is in a language without that round trip (for example Python), the correspondence is established by human review and differential testing rather than mechanically — so calibrate how much assurance that warrants per preferences-validation-assurance, which owns the check-tier and confidence-promotion model.
Either way the Lean spec is the artifact of record; a component "worth getting right" with no type-checkable spec beside it is the violation this rule names.

## How the rules compose

The rules are not independent checklist items; they layer.
Rule 1 fixes the shape of a stateful component, Rule 3 fixes how its history becomes read models, and Rule 4 constrains what those read models may aggregate over.
Rule 2 fixes how the component talks to the world, and Rules 5 and 6 refine that with resource discipline.
Rule 7 is the spine that holds the rest: it is where Rules 1, 3, and 6 are discharged as type-checked obligations rather than runtime hopes, and it is the partial, present-day realization of the single typed calculus the whole skill converges on.
For the foundations behind any individual rule, follow its named reference file; for the conjectural calculus that unifies them, see internal-language.md.
