---
name: preferences-theoretical-foundations
description: >
  Category-theory and type-theory foundations for compositional, correct-by-construction software architecture. Load when designing, refactoring, reviewing, or maintaining an architecture; when reasoning about abstractions, functors, optics, or type-level constructs; when choosing or justifying an effect system, or weighing a monad-transformer stack against a capability interface discharged by handlers; when drawing event-sourcing or CQRS boundaries, or making a read model a verifiable projection; when modeling a domain's effects and coeffects; when making a component's decide/evolve (Decider) structure explicit; and when retaining a type-checkable Lean architecture spec beside a non-Rust (for example Python) implementation. Pairs with refinement-driven-development, which owns the verified Lean-to-Rust round trip.
---

# Theoretical foundations

Good architecture factors every concern through an adjunction, and the ideal it converges on is a single typed calculus — the conjectural internal language of compositional software architecture — which we approach asymptotically and partially realize today by keeping a type-checkable Lean specification beside the implementation.

In one breath: treat the capability interface as the stable primitive and any carrier as one interpreter, model state as a Decider whose `evolve` leg is an F-algebra, make each read model a monoid-homomorphism projection, track effect and coeffect grades separately, and discharge all of this as type-checked obligations in a Lean spec the implementation mirrors.

## The thesis

The organizing claim of this skill is that good architecture *factors every concern through an adjunction* `F ⊣ U`.
That is a routing heuristic, not a theorem: when a best abstraction exists it is the left adjoint of a Galois connection, but not every useful abstraction is a full Galois connection, so the slogan earns its keep only when you exhibit the specific defining law per concern (see abstraction-as-adjunction.md).

The ideal that stance converges on is a single typed calculus: the *internal language* of compositional software architecture, whose syntactic category would be the initial object presenting its doctrine.
This is *initiality*, an empty colimit, not a "limit point" — an actual limit of the fragment theories would be their common sub-fragment, the opposite of the intended object.
That unifying calculus — a quantitative, multimodal, adjoint dependent type theory of higher-order algebraic effects and coeffects — does not yet exist as one built or proven calculus; it is a conjectural synthesis of fragments that are each real and individually citable (see internal-language.md).

Critically, the ideal is *not* an indexed monad transformer stack.
A transformer stack is merely one leaky interpreter of a capability interface, never the interface itself and never the theoretical ideal.
The primary framing throughout this skill is a *capability interface discharged by handlers*; the stack appears only as one non-canonical interpreter among others (a handler-record carrier, an algebraic-effect runner), and its well-known defects are engineering experience about that one carrier family, not a theorem (see effects-handlers.md).

We approach the ideal asymptotically and partially realize it today, even when the runtime is untyped, by keeping a type-checkable Lean specification beside the implementation.
The Lean file is where illegal states are made unrepresentable, where the projection homomorphism is proved rather than merely tested, and where resource grades are pinned or shown existential; the implementation is then a mirror of that spec, and verification closes the gap between them.

## When to use, when not

Reach for this skill when you are designing, refactoring, reviewing, or maintaining an architecture and want the design decisions grounded in the structure that makes them compose rather than in taste alone.
Reach for it when reasoning about abstractions, functors, optics, or type-level constructs, and when you need the universal property a pattern is an instance of.
Reach for it when choosing or justifying an effect system, when weighing a transformer stack against a capability interface, when drawing event-sourcing or CQRS boundaries, when making a read model a verifiable projection, when modeling a domain's effects and coeffects, when making a component's decide/evolve structure explicit, or when deciding to keep a Lean spec beside a non-Rust implementation.

Do not reach for it for the operational mechanics a sibling owns: aggregate boundary sizing and smart constructors belong to preferences-domain-modeling, the laws-as-property-tests machinery to preferences-algebraic-laws, the snapshot/replay/upcasting details to preferences-event-sourcing, and the Lean-to-Rust verification round trip to refinement-driven-development.
Do not reach for it to settle a question that is purely about style, tooling, or a single language's idioms; the language-specific preference skills own those.

## Practitioner rules

These are the checkable design rules that fall out of the foundations, in compact form; each is developed in full, with its check and its grounding, in practitioner-rules.md, and tagged below with the reference file that justifies it.

Rule 1 — model state as a Decider (`decide`, `evolve`) and make illegal states unrepresentable in the spec first; reconstructing state must be nothing but folding `evolve` over the event history (decide-evolve-lens.md; aggregate design in preferences-domain-modeling, type construction in preferences-algebraic-data-types).

Rule 2 — prefer a capability interface discharged by handlers over a transformer tower; keep interface and handler separable, and if a stack is unavoidable, document the effect-ordering commitment it bakes in (effects-handlers.md; the laws a lawful handler preserves in preferences-algebraic-laws).

Rule 3 — treat the committed event log as the source of truth and assert the projection homomorphism law `project (xs ++ ys) == project xs <> project ys` as a test; the CQRS split is exactly this homomorphism promoted to an architectural boundary (observability-as-theorem.md; operational mechanics in preferences-event-sourcing, the read-side stream in preferences-functional-reactive-programming).

Rule 4 — aggregate only over an exact monoid; IEEE-754 float addition is not associative, so float-summing read models are not true homomorphisms and resharded rollups can disagree (observability-as-theorem.md).

Rule 5 — track two distinct grades and never call them adjoint: an ordered-monoid effect grade and an ordered-semiring coeffect grade, each composing along its own algebra and coordinated by a distributive-law-style rule (graded-effects-coeffects.md).

Rule 6 — grade in the type when control flow is statically bounded; hand back an existential grade, deliberately, when it is not, because static pinning under unbounded data-dependent recursion is a conjectural synthesis, not a theorem (internal-language.md).

Rule 7 — keep a type-checkable Lean architecture spec the implementation mirrors, regardless of runtime language; this is how the typed ideal is partially realized today (practitioner-rules.md; defer the Rust round trip to refinement-driven-development and the check-tier calibration for non-Rust implementations to preferences-validation-assurance).

## References

The references split into two spines that meet at the worked example.
The *foundations spine* states the categorical and type-theoretic facts precisely; the *practitioner spine* is loadable standalone and gives the checkable rules.
The worked example is the Lean-to-Python proof that the theory pays rent.

| Reference | Spine | Open it for |
|---|---|---|
| [`references/abstraction-as-adjunction.md`](references/abstraction-as-adjunction.md) | foundations | Galois connection as adjunction, the free-forgetful generalization, and the "factor through an adjunction" routing heuristic kept at its honest altitude |
| [`references/effects-handlers.md`](references/effects-handlers.md) | foundations | Capability interfaces as the same pattern as finally-tagless, the transformer stack as one interpreter, the initial/final duality, and why the defect list is engineering experience |
| [`references/graded-effects-coeffects.md`](references/graded-effects-coeffects.md) | foundations | The effect grade (ordered monoid, graded monad), the coeffect grade (ordered semiring, graded comonad), and the distributive law that coordinates them without an adjunction |
| [`references/internal-language.md`](references/internal-language.md) | foundations | The conjectural unifying calculus, initiality (not a limit point), the initial/final universal-property duality, and the existential-grade frontier |
| [`references/decide-evolve-lens.md`](references/decide-evolve-lens.md) | practitioner | The Decider, `evolve` as F-algebra, state reconstruction as catamorphism, and the Moore-machine/lens reading kept as a labelled gloss |
| [`references/observability-as-theorem.md`](references/observability-as-theorem.md) | practitioner | The read-model projection as a strict monoid homomorphism, the CQRS algebra/coalgebra split, and the exact-monoid (no IEEE float) caveat |
| [`references/practitioner-rules.md`](references/practitioner-rules.md) | practitioner | The seven design rules in full, each with its concrete check, its grounding reference, and how the rules compose |
| [`references/reading-map.md`](references/reading-map.md) | both | The tiered bibliography and the load-bearing scope notes recording exactly what each citation does and does not ground |
| [`references/worked-example/`](references/worked-example/) | both | The Lean-and-Python proof the theory pays rent: `Limit.lean` discharges in the type what `limit.py` can only assert at runtime; see `correspondence.md` for the gap-by-gap mapping |

## See also

Reach for refinement-driven-development for the verified Lean-to-Rust round trip — the refine/lower, lift via Charon and Aeneas, and check by translation validation — that turns the worked example's proofs into a development process; this skill is the foundations it leans on.
Reach for preferences-domain-modeling for DDD aggregate design, smart constructors, and making illegal states unrepresentable, the source discipline for the Decider's spec.
Reach for preferences-algebraic-data-types for the sum and product patterns that make the command, event, and state types exclude the bad cases by construction.
Reach for preferences-algebraic-laws for the functor, monad, and monoid laws, and the property-based testing strategies, that turn these structures into checkable obligations.
Reach for preferences-event-sourcing for the operational event-sourcing patterns the Decider and the projection homomorphism illustrate.
Reach for preferences-functional-reactive-programming for the reactive-stream and FRP foundations on the read side.
Reach for preferences-validation-assurance for the check-tier and confidence-promotion calibration that governs how strongly any of these claims may be asserted, and how much assurance a non-mechanical correspondence warrants.
Reach for preferences-architecture-diagramming for diagram format selection when these structures need to be drawn.

## How the foundations map to practical patterns

This skill grounds patterns that live in the sibling skills; the pointers below say which structure underwrites which pattern, so the foundation and the practice stay connected.
They are prose pointers, not links, naming each sibling by its real directory name.

For domain modeling, see preferences-domain-modeling: types as domain vocabulary are algebraic data types as initial algebras, smart constructors are refinement types, state machines are coalgebras for endofunctors, workflows as pipelines are Kleisli composition, aggregates are the Decider plus optics, and domain errors are a coproduct of error types.

For algebraic data types, see preferences-algebraic-data-types: product types are categorical products, sum types are coproducts, the newtype pattern is a refinement type, and pattern matching is a catamorphism (structural recursion).

For error handling, see preferences-railway-oriented-programming: the Result type is the Kleisli category of the error monad, bind is Kleisli composition, map is functor mapping, and applicative validation is applicative composition in parallel.

For architectural patterns, see preferences-architectural-patterns: effect signatures are the capability interface (Rule 2, effects-handlers.md), dependency injection is the Reader capability, and a transformer stack is one interpreter of that interface — never the interface itself.

For distributed systems, see preferences-distributed-systems: the event log as authority is the free monoid of events, deterministic replay is state reconstruction as a catamorphism (Rule 1), the CQRS split is the projection homomorphism promoted to a boundary (Rule 3), and idempotency rests on the monoid identity law.

For reactive and hypermedia read-side delivery, see preferences-functional-reactive-programming and preferences-hypermedia-development: an SSE projection channel is a functor from the event log to a stream, temporal consistency is an ordered monoid preserving causality, a signal system is comonadic context consumption, and a thin web-component wrapper is a coalgebra or Moore machine.

For data modeling, see preferences-data-modeling: read models as derived views stand in a Galois connection with the event log, query caching is memoization with naturality-based invalidation, temporal versioning (DuckLake time travel) is indexing by version, and views as quotients are equivalent event sequences under projection.

## Further reading

For category theory, see Milewski, *Category Theory for Programmers*, and Pierce, *Basic Category Theory for Computer Scientists*.
For type theory, see Pierce, *Types and Programming Languages*, and Pierce (ed.), *Advanced Topics in Types and Programming Languages*.
For functional-programming theory, see Okasaki, *Purely Functional Data Structures*, and Chiusano and Bjarnason, *Functional Programming in Scala* (the Red Book).
For effect systems, see the algebraic-effects-and-handlers literature (Plotkin and Pretnar; Wu, Schrijvers, and Hinze; Bach Poulsen and van der Rest) and the call-by-push-value treatment (Levy).
For applied category theory, see Fong and Spivak, *Seven Sketches in Compositionality*, and Riehl, *Category Theory in Context*.
The reading-map.md reference is the tiered bibliography with the per-citation scope notes; consult it before attaching any of these to a load-bearing claim.
