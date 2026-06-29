---
title: Graded effects and coeffects
---

## What a grade is

A *grade* is a static index drawn from an ordered algebraic structure that travels with a computation and records something the bare type cannot.
The word "grade" names the index; the two faces it indexes are *effects* (what a computation does to the world) and *coeffects* (what a computation demands of its context), and these two faces are graded by different algebras.
This file is on the foundations spine: it states the structure precisely, names the citable poles, and gives the one design rule that follows.

A graded *effect* is a refinement of an ordinary effect.
An untyped `IO` says only that something may happen; an effect grade says *which* effects, bounded above by an element of an ordered monoid, so that the type carries the upper bound and the type checker can reject a computation that exceeds it.
A *coeffect* is the dual concern of *context demand*: how much of, or in what mode, a computation reads the environment it runs in — how many times a variable is used, what capabilities it requires, what stability or liveness it assumes of its inputs.
The coeffect grade lives on the context side of the judgement rather than on the result, which is why it is graded by a richer algebra than the effect grade.

## The two algebras are different, and that asymmetry is load-bearing

A (pre)ordered monoid grades a monad to model effects.
Precisely, a graded monad is a lax monoidal functor from the grading monoidal preorder `(E, ≤, ·, 1)` into the endofunctor category `([C, C], ∘, Id)` (Katsumata 2014, parametric effect monads): each grade `e` names an endofunctor `T_e`, the unit `1` names the trivial effect, and the monoid multiplication `·` composes effects when computations sequence.
The preorder `≤` lets a computation be weakened to a larger effect bound, which is exactly the subeffecting that makes the system usable in practice.

An ordered *semiring* grades a comonad to model coeffects and context demand.
The two semiring operations carry distinct meanings: the multiplication composes usage through a binder (running a function `n` times that itself uses its argument `m` times demands `n · m` uses), and the addition contracts — merges — two usages of the same variable that arise on different branches or in different subterms (Petricek/Orchard/Mycroft 2014 in the bounded-reuse fragment; made precise as resource and usage grading in McBride 2016 and in Atkey 2018's quantitative type theory).
The semiring is the coeffect side specifically: do not write "a semiring grades a (co)monad" symmetrically, because the effect side needs only an ordered monoid — one operation, not two.
The second operation, addition, exists because contexts can be split and merged, and a result cannot be split and merged the same way; this asymmetry between the demand side and the production side is the reason the two algebras are not the same and the reason their graded structures are a monad and a comonad rather than two instances of one shape.

## Effects and coeffects are not adjoint, and not faces of one self-dual modality

A single type system can carry both grades at once: the world-facing effect grade on the result captured by a graded monad, and the context-facing demand grade on the judgement's context captured by a graded comonad.
The temptation is to call these two faces of one self-dual graded modality, or to call them adjoint to each other.
Both framings are wrong, and the correction is the spine of this file.

In the grounding literature effects and coeffects are two distinct functors over two distinct grading algebras, coordinated when they coexist by a graded *distributive law* between the effect graded monad and the coeffect graded comonad (Gaboardi/Katsumata/Orchard/Breuvart/Uustalu 2016, combining effects and coeffects via grading).
A distributive law is precisely the data for composing a comonad with a monad when *no adjunction is assumed*: it is a natural transformation discharging the coherence needed to push one structure through the other, and it exists exactly because there is no adjunction doing the job for free.
A distributive law is not an adjunction, and an adjunction is not a distributive law; saying so explicitly is the point.
The honest dualities in the neighbourhood are two and only two: the standard categorical monad/comonad duality (which relates the *shapes* of the two structures, not the structures of a given language to each other), and an informal produce-versus-consume contrast.
Neither licenses calling a language's effects and its coeffects adjoint, and neither makes them faces of a single self-dual modality.

For the order-theoretic adjunctions that genuinely do appear in this skill — Galois connections and free-forgetful pairs as the shape of abstraction — see preferences-theoretical-foundations' abstraction-as-adjunction reference; do not let that adjunction framing leak onto the effect/coeffect axis, which is governed by a distributive law instead.

## The design rule

Track two distinct grades on a computation, each composed along its own algebra, and wire their interaction through an explicit distributive-law-style rule rather than collapsing one into the other.

The effect grade is an ordered-monoid element on the result: compose it by the monoid multiplication when computations sequence, weaken it up the preorder when a caller needs a looser bound, and let the unit mark the pure computation.
The usage grade is a per-context-entry ordered-semiring element on each free variable: compose it by semiring multiplication through binders, contract it by semiring addition when a variable is used in more than one place, and read off resource facts (linearity, affinity, irrelevance, unrestricted use) as the specific semiring you chose — the booleans, the naturals, `{0, 1, ω}`, an interval lattice — makes the type checker enforce.
When both grades are present in one judgement, their interaction is the explicit rule, not an identity: do not collapse demand into the dual or the adjoint of effect, and do not assume one grade determines the other.

Concretely, in a host language this means two annotations that do not share an algebra: an effect row or effect bound on a function's return, and a usage annotation on each of its parameters or captured context entries.
The effect annotation answers "what may this do"; the usage annotation answers "what does this require, and how much."
Composing a pipeline composes the effect bounds by the monoid and the usage bounds by the semiring, independently, with the cross-term governed by the distributive-law rule.

## Where this sits relative to siblings

The grade index is an algebraic structure, and the laws that the chosen monoid, semiring, monad, and comonad must satisfy — together with how to property-test them at the value level — belong to preferences-algebraic-laws; this file states which structures grade which face, not how to test the laws.
The underlying monad and comonad shapes, and the monad/comonad duality this file invokes, are treated for the reactive case in preferences-functional-reactive-programming.
The effect grade is the type-system face of effect handling; the capability interface that effects discharge against, and the finally-tagless versus free-coproduct presentations of that interface, are covered in this skill's effects-handlers reference.
The frontier question — whether a single calculus could carry the effect grade, the coeffect grade, dependency, and modality all at once, and why that calculus does not yet exist as one typed language — is the internal-language reference's concern; the effect/coeffect distributive law is part of that conjectural synthesis, not a theorem of any one fragment.

## Residual uncertainty

The citation-to-claim mapping above rests on the established literature rather than on in-session page-level verification of the five papers.
Two points are structurally sound but unchecked at the page level: the exact direction and coherence conditions of the Gaboardi et al. 2016 graded distributive law, and whether Petricek/Orchard/Mycroft 2014 state the general coeffect indexing as a full ordered semiring grading a comonad in the body or only as semiring-structured indexing with the comonadic semantics deferred.
Neither affects the structure asserted here.
None of the five cited papers may be used to support an adjoint single-modality framing, a lax-monoidal-2-cell framing, or a combined-calculus initiality claim; they ground only the corrected statements above.
