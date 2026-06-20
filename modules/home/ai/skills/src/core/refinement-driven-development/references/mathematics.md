# The adjunction framing

The whole method is organized around one idealization: the round trip from a specification down to an implementation and back up to a model should land you, up to equivalence, on the specification you started with.
Written as a composite, the lift of the lowering of a spec S should satisfy Φ(S) ≈ S, where Φ is the round-trip endomorphism on the world of specifications.
This is an approximate identity map from spec back to spec, and it is the guiding star of refinement-driven development rather than a theorem you get for free.
The portmanteau TD³ (type-driven development fused with domain-driven design) is the working alias for this discipline; the academic anchor is refinement calculus (Back & von Wright; Morgan), and the categorical reading below makes the "approximate identity" precise.

This page sets up the categories, the two functors realizing lowering and lifting, the adjunction between them, the round-trip composite, and the dual closure on the implementation side.
It closes with three honesty notes that keep the framing load-bearing rather than decorative.

## The two categories

Let Spec be the order-enriched category of Lean pure models: objects are dependently-typed Lean specifications and their pure functional denotations, and the order on each hom-set records refinement and equivalence between models.
Let Impl be the category of operational artifacts: Rust programs first, then their borrow-explicit LLBC intermediate form, carrying the operational semantics that actually executes.
The two live at different levels of abstraction in the sense of abstract interpretation (Cousot): Spec is the abstract domain where you reason and prove, Impl is the concrete domain where computation happens and where nondeterminism gets resolved.

Order-enrichment matters: the hom-sets are not bare sets but carry the ⊑ refinement order, so "equal up to equivalence" and "refines" are first-class.
In this thin / order-enriched setting an isomorphism is a mutual refinement, which is exactly the notion of "the same" that the method can actually establish.

## Concretization γ : Spec → Impl

Lowering is concretization, the functor γ : Spec → Impl.
It is the refine/lower step: take a Lean model and realize it as a Rust artifact within the Aeneas/Charon-safe subset.
γ is manual, LLM-assisted authoring rather than a canonical construction; there is no automatic generator producing the Rust from the Lean.
γ chooses one operational realization among many that a single specification admits, which is why the dual composite below is only a closure and not an identity.

## Abstraction α : Impl → Spec, the composite that stays explicit

Lifting is abstraction, the functor α : Impl → Spec, and it is a composite that must never be collapsed into a single opaque arrow, because its two stages are the objects that compile and run in production.

    Spec  --γ (refine/lower)-->  Rust  --Charon-->  LLBC  --Aeneas-->  Spec

The first stage, Charon, takes Rust to LLBC, the Low-Level Borrow Calculus where borrows and mutable references are made explicit.
The second stage, Aeneas, takes LLBC to a pure functional Lean model by functional translation through symbolic execution, with backward functions modeling &mut.
As functors this is the composite

    α = Aeneas ∘ Charon

so α factors through the intermediate object LLBC, which is itself an object of Impl.
The two stages stay visibly distinct throughout this skill: Charon is the borrow-explicit IR producer, Aeneas is the semantics-preserving functional translation, and neither is a transpiler in the Eurydice (Rust → C) sense.

## The adjunction α ⊣ γ

The lowering and lifting functors sit as an adjunction, with abstraction left adjoint to concretization:

    α ⊣ γ

This is the categorical form of the abstract-interpretation Galois connection between the concrete domain Impl and the abstract domain Spec.
Reading the connection in the standard Cousot direction, α as left adjoint is the best abstraction: it sends each implementation to the most precise specification that still soundly over-approximates it, and γ as right adjoint sends each spec to the largest set of implementations the spec admits.
With α ⊣ γ the adjunction supplies a counit  ε : α∘γ ⟹ id_Spec  on the spec side and a unit  η : id_Impl ⟹ γ∘α  on the implementation side, and the round-trip behavior of the method is read off from these two natural transformations.
The unit η is the reflection map: at an implementation it compares id to the closure γ∘α, witnessing γ∘α ⊑ id and so generally not an isomorphism, since it is the unit of the idempotent closure rather than an inverse.
The counit ε is the insertion witness on the spec side: at a spec S it compares (α∘γ)(S) to S, so checking Φ ≈ id amounts to showing that this counit component is an equivalence and not merely a one-way refinement; the dual implementation-side relation γ∘α versus id is the closure discussed below.

## The round-trip Φ = α ∘ γ and the goal Φ ≈ id

The endomorphism of interest is the round trip on the spec side,

    Φ = α ∘ γ : Spec → Spec ,

which lowers a spec to an implementation and lifts it back to a model.
The goal of the method is

    Φ ≈ id_Spec ,

that the lifted model of a faithfully lowered spec is equivalent to the original spec.
In abstract-interpretation terms Φ ≈ id is the Galois insertion condition: when α∘γ is the identity on the abstract side rather than only comparable to it, the Galois connection is a Galois insertion, equivalently a reflection of Spec inside Impl.

Categorified, this says Spec is reflective in Impl with reflector α: the unit η : id_Impl ⟹ γ∘α is the reflection map on Impl, and the insertion condition is that the counit ε : α∘γ ⟹ id_Spec is a pointwise equivalence.
So Φ = α∘γ ≈ id_Spec means the counit ε is an equivalence at each object, and "approximate identity" at a given object means exactly that the counit at that object is an equivalence rather than only a one-way refinement step.
Establishing Φ(S) ≈ S object by object is therefore the categorical content of checking the lift against the original spec.

## The dual closure γ ∘ α ⊑ id

The dual composite on the implementation side,

    γ ∘ α : Impl → Impl ,

is not the identity and is not expected to be.
It is a closure operator, an idempotent comparable to the identity but distinct from it, and the right relation here is

    γ ∘ α ⊑ id_Impl .

The asymmetry is exactly right for the situation: many implementations share one specification, so lowering after lifting cannot recover the specific artifact you started from, only some canonical representative of its equivalence class under the spec.
This is the formal content of the everyday statement that the implementation refines the spec and may resolve nondeterminism that the spec deliberately left open.
A Galois connection that is an insertion on the abstract side (Φ ≈ id on Spec) is in general only a closure on the concrete side (γ∘α ⊑ id on Impl), and that one-sidedness is precisely the "one spec, many implementations" shape of the engineering problem.

## Three honesty notes

These notes keep the framing operative rather than ornamental.

It is the guiding idealization, not a free theorem.
Because γ is manual and LLM-assisted refinement, it is not a canonical construction, so the adjunction α ⊣ γ does not hold automatically and Φ ≈ id is not handed to you.
Instead you witness Φ(S) ≈ S for each object S individually, and that per-instance witness is exactly translation validation in the Pnueli–Siegel–Singerman sense: produce the artifact, then prove this particular round trip matches this particular spec.

"≈" is deliberately weaker than "=".
What you typically establish is functional equivalence or mutual refinement, which is isomorphism in the thin / order-enriched setting, not on-the-nose definitional equality between the lifted model and the spec.
That gap is the precise meaning of "approximate" in "approximate identity map".
Fully mechanical, definitional discharge of every proof obligation is the ideal you describe precisely so that you can measure distance from it; its absence in any given case is not a failure of the approach but the expected, named state of affairs.

The intermediates are essential.
Φ factors through Impl, and the intermediate objects, Rust and LLBC, carry the operational semantics, so the factorization is not an accounting convenience.
You execute the factorization and you verify the composite: the diagram you check lives over Spec, and the artifact you ship is the midpoint of the path, the Rust program whose borrow structure Charon made explicit and whose behavior Aeneas reflected back into Lean.
Eliding the intermediates would discard both the thing that runs and the borrow-level evidence that the lift is faithful.
