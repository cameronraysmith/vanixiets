---
title: The internal language of compositional software architecture
---

## Contents

- [The ideal this skill converges on](#the-ideal-this-skill-converges-on)
- [Naming the conjectural calculus](#naming-the-conjectural-calculus)
- [Initiality, not a limit point](#initiality-not-a-limit-point)
- [Universal properties: the initial/final duality](#universal-properties-the-initialfinal-duality)
- [The existential-grade frontier](#the-existential-grade-frontier)
- [What we can do today](#what-we-can-do-today)

## The ideal this skill converges on

Good architecture factors every concern through an adjunction.
The companion file on abstraction-as-adjunction (see abstraction-as-adjunction.md) carries that routing heuristic and its defining laws; this file names the ideal the whole apparatus converges toward.

That ideal is a single typed calculus.
It is *not* a monad-transformer stack: a transformer stack is merely one leaky interpreter of a capability interface (see effects-handlers.md for why the capability interface, not any carrier, is the stable primitive).
The convergent ideal is instead the conjectural internal language of compositional software architecture — a calculus in which the capabilities a program demands, the resources it consumes, the modalities it crosses, and the dependencies its types track all live in one judgement, so that a well-typed term is correct-by-construction along every one of those axes at once.

The word *conjectural* is load-bearing and is not softened anywhere below.
This calculus does not exist as a single built or proven object.
What exists is a set of research fragments, each of which captures one axis precisely, and a well-motivated conjecture that they can be amalgamated.
We approach the ideal asymptotically; we do not claim to have reached it.

## Naming the conjectural calculus

State the full descriptive name once and then unpack it.

The ideal is *a quantitative (graded) multimodal adjoint dependent type theory of higher-order algebraic effects and coeffects — the conjectural internal language of compositional software architecture*.

Each adjective is a recognizable fragment of the contemporary type-theory literature, and each maps to exactly one citable axis.

The *graded / quantitative* adjective is resource grading over a semiring, carried in the type so that a usage or effect grade is a static index rather than a runtime fact (Atkey 2018, on the polynomial semantics of quantitative type theory; Moon, Eades, and Orchard 2021, on graded modal types).
The *multimodal* adjective is a host mode theory that lets several modalities coexist in one calculus, parameterized by a 2-category of modes (Gratzer, Kavvos, Nuyts, and Birkedal 2021, multimodal dependent type theory, MTT).
The *adjoint* adjective is the value/computation split as an `F ⊣ U` adjunction between a category of values and a category of computations (Levy 2004, call-by-push-value, together with the broader tradition of adjoint logic).
The *higher-order algebraic effects* adjective is scoped and higher-order operations with their handlers, where an operation may take a computation as an argument rather than only first-order parameters (Wu, Schrijvers, and Hinze 2014, on scoped effect handlers; Bach Poulsen and van der Rest 2023, on hefty algebras for higher-order effects).
The *dependent* adjective is dependency itself, modeled as a fibration of typed contexts so that types may mention terms.

Each fragment is real and citably mapped to its one axis.
No fragment paper, however, supports the *union*.
Atkey grounds the grading axis; he does not ground the unified calculus.
Gratzer and coauthors supply the multimodal host framework; presenting effects-and-coeffects as one adjunction inside MTT is part of the synthesis, not a theorem MTT proves.
The discipline is therefore strict: cite a fragment paper only for its own axis, and never cite any single fragment paper as evidence that the amalgamated calculus exists or is consistent.

## Initiality, not a limit point

It is tempting to describe the unifying calculus as a *limit point* of the fragments, as though it were where they accumulate.
That is the wrong categorical vocabulary, and the error is worth stating precisely because it inverts the intended object.

The genuinely precise universal property on offer is *initiality*.
The syntactic, or classifying, category of a type theory is the initial object presenting its doctrine, and its initiality is exactly the internal-language property: a model in any suitable category is the same thing as a structure-preserving functor out of the syntax, uniquely (Lawvere 1963, on functorial semantics and algebraic theories as the source of this framing).

An initial object is an empty colimit.
A limit of the fragment theories, by contrast, would be their common sub-fragment — the weakest theory that all of them extend, the intersection of their expressive power.
That is the opposite of what we want.
The unifying calculus, if it is ever built, is a colimit-style amalgamation sitting *above* the fragments, presenting a doctrine that each fragment is a special case of; it is not the meet that sits below them.

State the property as conjectural and contingent.
The classifying-category / initiality property is the property the calculus *would* possess once a syntax for it is actually presented.
It is a conjectured universal property of a not-yet-built object, not an established theorem.
Lawvere 1963 grounds the initiality-of-syntax framing in general; it does not certify that this particular union has an initial presentation, and it must not be cited as if it did.

## Universal properties: the initial/final duality

The initiality lens is not only an aspiration for the unbuilt calculus; it is the everyday tool that makes today's algebraic data types correct-by-construction, and that continuity is why this file is the foundations keystone.

A recursive data type is the *initial algebra* for a functor.
For lists, the functor is `ListF a r = NilF | ConsF a r`, and `List a` together with its constructor map `in : ListF a (List a) → List a` is the initial `F`-algebra.
Initiality means there is a *unique* algebra homomorphism from this initial algebra to any other `F`-algebra, and that unique homomorphism is the catamorphism — the fold.

```haskell
data List a = Nil | Cons a (List a)

-- the shape functor
data ListF a r = NilF | ConsF a r

-- List a is the initial ListF a-algebra; cata is the unique homomorphism out of it
cata :: (ListF a b -> b) -> List a -> b
```

The practical consequence is that every recursive data type carries a canonical fold expressing all of its structural recursion, and that fold is unique because initiality guarantees uniqueness.
This is the universal-property reading; the *laws* a catamorphism obeys belong to preferences-algebraic-laws, and the cross-language mechanics of declaring the underlying sum and product types belong to preferences-algebraic-data-types.
The mechanics of an `F`-algebra and its catamorphism as they appear in event-sourcing state reconstruction — `evolve` as the algebra, the fold as replay — are developed in decide-evolve-lens.md.

Products and coproducts are the dual universal properties one altitude down.
A product type `A × B` is the categorical product: it has projections `fst` and `snd`, and for any `C` with `f : C → A` and `g : C → B` there is a unique `h : C → A × B` factoring both.
A sum type `A + B` is the categorical coproduct, the exact dual: it has injections `inl` and `inr`, and for any `C` with `f : A → C` and `g : B → C` there is a unique `h : A + B → C`.
Because these are universal, products and coproducts are unique up to isomorphism, associative, commutative, and unital, and they satisfy distributivity `A × (B + C) ≅ (A × B) + (A × C)` — the algebra of types that mirrors the algebra of polynomials.

The same initial/final duality organizes how a program itself is encoded, and that is where this file hands off to its siblings.
A program built as a free / coproduct-of-functors term is the *initial* presentation: the program is inspectable data, an initial algebra you can fold over.
A program built tagless-final is the *final* presentation: the program is an opaque, directly-interpretable term, a Church-style encoding.
Neither presentation dominates; they are dual, and the trade between introspectability and interpretation efficiency is decided per use site.
That duality, with its handler/interpreter consequences, is owned by effects-handlers.md (initial = free versus final = tagless).

## The existential-grade frontier

The frontier is the open edge of the convergence, and it is *not* a fifth gap to be closed by ordinary expressivity — it is where a single calculus is presently unable to stay precise.

Where control flow is statically bounded, the grade pins in the type.
A single proposal step has a known, finite resource cost, so its type can name it exactly: in the worked example, `propose` has type `Prog draws ⟨2,0⟩ Command`, the `⟨2,0⟩` being the static grade.

Under unbounded, data-dependent recursion the grade stops pinning.
A full simulation runs an unbounded, data-dependent number of steps, so the strongest type any system can give it is an *existential* grade — the grade is real but unknown until runtime, so it is hidden behind a Σ.
The worked example records exactly this symptom at references/worked-example/Limit.lean line 261:

```lean
abbrev Trajectory := Σ g : Grade, Prog draws g (List Event)
```

This Σ is where static grading stops.
Graded modalities pin the grade only where control flow is statically bounded; unbounded recursion hands back an existential `∃ g`, unclosed by any type system available today.

Closing that existential in a single calculus is precisely the conjectural synthesis named above, viewed from its hardest instance.
The four research lines — quantitative / graded type theory, multimodal type theory, higher-order (scoped / hefty) algebraic effects, and call-by-push-value / adjoint logic — are each a recognizable fragment of the calculus that would subsume them, but their integration has not been built or proven.
The pieces are in hand; the unification is anticipated, not done.
This frontier framing, and not a grading citation, is what the existential `Trajectory` justifies, so reserve the grading citations for the statically-pinned grade and for the frontier statement itself rather than spreading them across the ordinary expressivity a total dependent type theory already provides.

## What we can do today

The ideal is conjectural, but the discipline it implies is available now, even when the implementation runs in an untyped or dynamically-typed runtime.

We partially realize the internal language by keeping a type-checkable Lean specification beside the implementation.
The specification carries, statically, as many of the axes as the present fragments allow — graded resources where control flow is bounded, dependent event families, total exhaustive evolution — and the existential grade marks honestly where a single calculus cannot yet keep its promise.
The Lean-beside-implementation round trip itself — lowering a specification to an implementation and lifting the implementation back to check the correspondence — is the subject of refinement-driven-development, which owns the entire verification process; this file owns only the claim that such a specification is the partial, present-day realization of a calculus that does not yet exist as one object.
