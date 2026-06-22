---
title: Reading map
---

## Contents

- [How to read this map](#how-to-read-this-map)
- [Tier 1: spine](#tier-1-spine)
- [Tier 2: supporting](#tier-2-supporting)
- [Tier 3: practitioner anchor](#tier-3-practitioner-anchor)
- [Grounded notes that are not single-citable results](#grounded-notes-that-are-not-single-citable-results)
- [Scope notes: do not re-introduce these misattributions](#scope-notes-do-not-re-introduce-these-misattributions)

This file is the bibliography for the foundations spine.
It collects every source the rest of the skill leans on, sorts them into three tiers, and records exactly what each source does and does not ground.
The scope annotations are load-bearing: several of these citations were demoted from stronger claims during review, and the demotions must survive future edits.
Read the scope-notes section before attaching any citation here to a new normative assertion.

The three tiers reflect how directly a source carries the skill's argument.
Tier 1 sources state, as theorems or canonical definitions, the categorical and type-theoretic facts the spine rests on.
Tier 2 sources supply the surrounding machinery the spine generalizes from or coordinates, real results adjacent to the claims rather than the claims themselves.
Tier 3 is the practitioner anchor: textbooks and longer-form treatments for building the background a reader needs to follow the spine at all, not cited for any specific load-bearing step.

## How to read this map

Each entry gives a full reference and one line on what it actually contributes, followed where needed by an explicit scope bound.
A scope bound names the claim a source *does* ground and, when the source was found misattributed during review, the claim it must never again be cited for.
Where a connection the skill draws is folklore or the author's own synthesis rather than a published theorem, it appears under grounded notes rather than being pinned to a fabricated citation.

For the algebraic laws these sources underwrite as property tests, see preferences-algebraic-laws.
For the domain-modeling patterns (aggregates, smart constructors, illegal states unrepresentable) that these foundations justify, see preferences-domain-modeling.
For the Lean-to-Rust verification round trip that turns the worked example's proofs into a development process, see refinement-driven-development; this map is the bibliography, not the method.

## Tier 1: spine

Carette, Kiselyov, and Shan, *Finally Tagless, Partially Evaluated: Tagless Staged Interpreters for Simpler Typed Languages*, Journal of Functional Programming 19(5), 2009.
Grounds the finally-tagless pattern and the final pole of the initial-versus-final duality: operations overloaded over an abstract carrier, meaning supplied by instance selection.
Scope: this is the technique only.
It does *not* prove that mtl-style capability constraints *are* finally-tagless (state that correspondence as "an instance of / the same pattern as," never as a CKS09 theorem), and it does *not* ground the transformer-stack defect list (leaky abstraction, non-commuting `StateT`/`ExceptT`, absence of fusion, O(n^2) lifting); that list is engineering experience about one carrier family.

Swierstra, *Data Types à la Carte*, Journal of Functional Programming 18(4), 2008.
Grounds the initial pole dual to CKS09: the free coproduct-of-functors encoding that keeps a program as inspectable data, against which the tagless-final encoding keeps it as an opaque directly-interpretable term.

Katsumata, *Parametric Effect Monads and Semantics of Effect Systems*, POPL 2014.
Grounds the effect face of grading: a graded monad is a lax monoidal functor from the grading monoidal preorder into the endofunctor category.
Also the parametric-effect-monad reading of the worked example's graded free monad.

Petricek, Orchard, and Mycroft, *Coeffects: A Calculus of Context-Dependent Computation*, ICFP 2014.
Grounds the coeffect face of grading: an ordered semiring grades a comonad to track context demand, with multiplication composing usage through a binder and addition contracting two usages of one variable.

Gaboardi, Katsumata, Orchard, Breuvart, and Uustalu, *Combining Effects and Coeffects via Grading*, ICFP 2016.
Grounds the coordination of the two faces: a graded distributive law composes the effect graded monad with the coeffect graded comonad precisely when no adjunction is assumed.
Scope: the two faces are coordinated by a distributive law, *not* an adjunction and *not* a single self-dual modality.
This paper proves combined effects-and-coeffects in one judgement; do not credit it for a static effect-row mechanism the worked example does not exhibit, and do not stretch any of the five graded papers to an adjoint modality or a combined initiality.

Cousot and Cousot, *Abstract Interpretation: A Unified Lattice Model for Static Analysis of Programs by Construction or Approximation of Fixpoints*, POPL 1977.
Grounds the canonical instance of the Galois half: a monotone Galois connection α ⊣ γ as the order-theoretic form of abstraction, from which soundness follows.
Scope: this grounds the connection *when a best abstraction exists*, the left-adjoint case only.
It does *not* ground a necessity claim that every abstraction requires a Galois connection (the same authors' later concretization-only frameworks handle domains with no best α), and it does *not* ground the "factor every concern through an adjunction" slogan.

Lawvere, *Functorial Semantics of Algebraic Theories*, PhD thesis / PNAS, 1963.
Grounds the free-forgetful and initiality content: syntax is the initial (free) object, the model functor is forgetful, and the classifying category is the initial object presenting the doctrine.
Scope: this grounds free-forgetful and initiality only.
It does *not* ground the "a DSL is the free-forgetful adjunction" slogan as a theorem (DSLs with equations, binding, or effects need monads, PROPs, or sketches beyond plain F ⊣ U), it does *not* license an arbitrary-DSL identity, and it does *not* license a "limit point" decoding — an initial object is an empty colimit, not a limit.

## Tier 2: supporting

Plotkin and Pretnar, *Handlers of Algebraic Effects*, ESOP 2009.
Supports the capability-interface stance: an algebraic-effect runner built from delimited continuations is an alternative interpreter of an effect signature, so a transformer stack is one non-canonical interpreter rather than the interface.

Hyland, Plotkin, and Power, *Combining Effects: Sum and Tensor*, Theoretical Computer Science 357, 2006.
Supports the static effect row as a coproduct of theories: the row idea is algebraic-effects theory, the substrate for reading the worked example's `Sig.sum` as a coproduct.

Atkey, *Syntax and Semantics of Quantitative Type Theory*, LICS 2018.
Supports the quantitative/graded axis: resource grading over a semiring, and the grade-in-the-type reading of the worked example's graded free monad.
Scope: reserve for the grading axis (gap 1 and the existential-grade frontier); do not extend it to cover dependent-decide or exhaustiveness, which are ordinary dependent typing and generic totality checking.

McBride, *I Got Plenty o' Nuttin'*, in *A List of Successes That Can Change the World*, LNCS 9600, 2016.
Supports the resource-grading-of-a-comonad reading that makes coeffect usage precise.

Moon, Eades, and Orchard, *Graded Modal Dependent Type Theory*, ESOP 2021.
Supports the quantitative/graded axis as one fragment of the conjectural unifying calculus.
Scope: one axis only; never cite a single fragment paper as support for the unified calculus.

Gratzer, Kavvos, Nuyts, and Birkedal, *Multimodal Dependent Type Theory*, LICS 2020 / LMCS 2021.
Supports the multimodal-host axis: a mode theory parameterized by a 2-category of modes carrying modalities.
Scope: MTT supplies the host framework; presenting effects-and-coeffects as one adjunction inside it is synthesis, not an MTT theorem.

Levy, *Call-by-Push-Value: A Functional/Imperative Synthesis*, Springer, 2004.
Supports the F ⊣ U value/computation adjunction axis (call-by-push-value and adjoint logic) of the conjectural calculus.

Wu, Schrijvers, and Hinze, *Effect Handlers in Scope*, Haskell Symposium 2014.
Supports the higher-order/scoped algebraic-effects axis.

Bach Poulsen and van der Rest, *Hefty Algebras: Modular Elaboration of Higher-Order Algebraic Effects*, POPL 2023.
Supports the modern higher-order algebraic-effects axis alongside Wu/Schrijvers/Hinze.

Chassaing, *functional event sourcing / the Decider*, 2021 (Jérémie Chassaing, "Functional Event Sourcing Decider").
Supports the Decider origin: the `decide : Command → State → [Event]` and `evolve : State → Event → State` pair.
Scope: this is the naming and signature origin only.
The Decider's algebra structure (evolve as an F-algebra, state reconstruction as a catamorphism) is the citable identification; do not cite Chassaing for the cofree-comonad identification of the log.

Spivak, *Generalized Lens Categories via Functors C^op → Cat* / mode-dependent dynamical systems as lenses, and Myers, *Categorical Systems Theory* (draft).
Support the Moore-machine-as-lens bridge: a `(readout, update)` pair is lens-structured.
Scope: background pending source verification.
The skill states only "the Decider is fold/catamorphism on evolve and is Moore-machine-shaped"; do not assert a Decider literally is a lens, optic, or Para morphism.

Capucci, Gavranović, Hedges, and Rischel, *Towards Foundations of Categorical Cybernetics*, ACT 2021 / 2022.
Supports the Para/optics family resemblance as adjacent background.
Scope: it unifies parametrized maps and bidirectional processes but does not include the Decider, and a bare Para morphism is a single parametrized map, not a two-legged pair; this is a design heuristic, never a load-bearing identity.

Rutten, *Universal Coalgebra: A Theory of Systems*, Theoretical Computer Science 249, 2000.
Supports the final-coalgebra reading of the bare event stream as background.
Scope: background only for the Decider, and it does *not* support the cofree-comonad identification of the observation-annotated log; that enrichment is the author's synthesis (see grounded notes).

Pickering, Gibbons, and Wu, *Profunctor Optics: Modular Data Accessors*, Programming Journal 1(2), 2017.
Supports optics as modular accessors as background.
Scope: background only for the Decider; it does not ground a Decider-is-a-lens identity.

## Tier 3: practitioner anchor

These build the background needed to follow the spine; none is cited for a specific load-bearing step.

Milewski, *Category Theory for Programmers*, 2019 (online / Blurb).
Programmer-facing introduction to functors, monads, adjunctions, and the categorical vocabulary the spine uses.

Pierce, *Basic Category Theory for Computer Scientists*, MIT Press, 1991.
Compact category-theory primer aimed at the same audience.

Pierce, *Types and Programming Languages*, MIT Press, 2002, and Pierce (ed.), *Advanced Topics in Types and Programming Languages*, MIT Press, 2005.
The standard type-theory grounding for the calculus-facing arguments.

Okasaki, *Purely Functional Data Structures*, Cambridge University Press, 1998, and Chiusano and Bjarnason, *Functional Programming in Scala* (the "Red Book"), Manning, 2014.
Functional-programming background, including the monoid/foldMap material the observability-as-homomorphism argument depends on.

Fong and Spivak, *Seven Sketches in Compositionality: An Invitation to Applied Category Theory*, Cambridge University Press, 2019, and Riehl, *Category Theory in Context*, Dover, 2016.
Applied and rigorous category-theory treatments for readers who want the adjunction, (co)limit, and (co)algebra material in full.

## Grounded notes that are not single-citable results

Several connections the skill draws are folklore or the author's own synthesis riding on the citable substrates above, not published theorems.
Recording them as notes here keeps future authors from inventing attributions for them.

The internal-language correspondence — that the conjectural "quantitative multimodal adjoint dependent type theory of higher-order algebraic effects and coeffects" would be the initial object presenting its doctrine — is a conjectural synthesis.
No fragment paper grounds the union; only Lawvere 1963 carries the initiality/doctrine content, and even that describes the property the calculus *would* have once a syntax exists, not an established fact about a built calculus.

The mtl-equals-tagless correspondence is widely recognized folklore (Kiselyov's writings, the fused-effects and polysemy design discourse) with no single peer-reviewed paper stating it as a theorem; keep it at "an instance of / the same pattern as."

Observability as a monoid homomorphism is proven locally in the worked example (`fmap_hom` / `project_hom`) as a strict homomorphism `project (xs ++ ys) = project xs <> project ys`, the foldMap universal property; the "lax-monoidal projection 2-cell off the committed event coalgebra" phrasing is a decorative slogan the worked example itself cashes out as that homomorphism, with no 2-category or 2-cell constructed.

The cofree-of-the-log gloss — the observation-annotated stream carrying `Cofree F a = νX. a × F X` for the linear stream functor `F X = E × X`, with `extract` reading current state and `duplicate` yielding all replay points — is the author's novel synthesis on the final-coalgebra and algebra/coalgebra-split substrates, not existing event-sourcing doctrine; keep it as a labelled gloss naming the annotation step, and see preferences-event-sourcing for the operational patterns it illustrates.

The decide/evolve-as-Moore/lens reading is a precise-but-to-be-verified bridge: evolve-as-F-algebra and state-reconstruction-as-catamorphism are solid, while the Moore-machine-as-lens framing awaits Spivak/Myers source verification and stays a labelled gloss.

## Scope notes: do not re-introduce these misattributions

The following demotions were established during adversarial review and must persist.
A future author who wants to use one of these citations for the demoted claim must first re-open the verification, not silently re-attach it.

CKS09 (Carette/Kiselyov/Shan 2009) grounds the finally-tagless pattern and the final pole; it does *not* ground the mtl-equals-tagless identity (its subject is embedding typed object languages, not Haskell's mtl) nor the transformer-stack defect list.

Rutten 2000 and Pickering/Gibbons/Wu 2017 are background only for the Decider; neither grounds a Decider-is-a-lens-in-Para identity.

Rutten 2000 and Chassaing 2021 do not ground the cofree-comonad identification of the event log.

Lawvere 1963 grounds free-forgetful and initiality only; it does not ground the DSL slogan, an arbitrary-DSL identity, or a limit-point decoding (an initial object is an empty colimit, not a limit).

Cousot and Cousot 1977 grounds the Galois half when a best abstraction exists; it does not ground a necessity claim nor the "factor every concern through an adjunction" slogan.

The five graded papers (Gaboardi et al. 2016, Katsumata 2014, Petricek/Orchard/Mycroft 2014, Atkey 2018, McBride 2016) do not support an adjoint modality, a lax-monoidal 2-cell, or a combined initiality; each supports one axis only.

Gaboardi et al. 2016 does not ground static gaps 2–4 (dependent decide, exhaustiveness, the static effect row); those are ordinary indexed-family dependent typing, generic coverage/totality checking, and the Hyland-Plotkin-Power coproduct of theories respectively.
Atkey 2018 and Moon/Eades/Orchard 2021 likewise do not ground gaps 2–3; reserve the grading citations for gap 1 and the existential-grade frontier.

For where these claims live in prose, see the per-concern reference files this map indexes, and for the check-tier and confidence-promotion calibration that governs how strongly any of these may be asserted, see preferences-validation-assurance.
