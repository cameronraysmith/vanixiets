---
name: refinement-driven-development
description: >
  Approximately-verifiable, refinement-driven development for type-driven domain-driven design. Use when modeling a domain as a dependently-typed Lean 4 specification, refining/lowering it to a Rust implementation, lifting the implementation back via Charon and Aeneas to check spec<->implementation correspondence (translation validation) — mechanically when tractable, otherwise via differential testing or LLM comparison — or when generating and diffing type-system diagrams of the model and implementation to track their evolution. Mechanical on-the-nose proof is the precise ideal, not a requirement; its absence is not a failure of the method.
---

# Refinement-driven development

Refinement-driven development is a methodology for building a domain implementation by writing its specification first as a dependently-typed Lean 4 model, refining and lowering that model into Rust, and then lifting the Rust back into Lean to check that the implementation still corresponds to the spec.
The portmanteau TD³ — type-driven development plus domain-driven design — is a convenient recall aid for the stance, and the name itself is anchored in the refinement calculus of Back and von Wright and of Morgan, where an implementation refines a specification under the ⊑ order.
In one breath: specify in Lean, refine and lower to Rust, lift the Rust back through Charon and Aeneas, then check the lifted model against the original spec, and iterate.

## The loop

The pipeline is a function composition whose intermediate objects are real artifacts that compile and run in production, not transient scaffolding:

    Lean 4  --refine/lower-->  Rust  --Charon-->  LLBC  --Aeneas-->  Lean 4

The first leg, *refine/lower*, takes the Lean 4 specification forward into a Rust implementation.
This is human authoring assisted by an LLM, never an automatic generator: you write the spec, run `lake build`, then hand-write Rust constrained to a subset Charon and Aeneas can consume.
Open `references/refine-and-lower.md` for the safe subset and the ownership-intent annotations.

The second leg, *lift*, is the composite Rust → Lean, equal to Aeneas ∘ Charon, and its two sub-steps stay visibly distinct.
Charon translates Rust into LLBC, the borrow-explicit Low-Level Borrow Calculus IR emitted as JSON (the `charon-ml` OCaml library reads that JSON).
Aeneas then translates LLBC into a pure functional Lean model by symbolic execution, with backward functions modeling `&mut`; Aeneas also targets Coq, F*, and HOL4, but this skill uses the Lean backend.
Open `references/lift-charon-aeneas.md` for the symbolic-execution account and the Nix-flake invocations.

The third leg, *check*, establishes refinement (the ⊑ order) or functional / observational equivalence between the lifted model and the original spec.
The discipline of producing an artifact and then proving it matches the spec a posteriori is translation validation, after Pnueli, Siegel, and Singerman.
Open `references/check-translation-validation.md` for the three check tiers and `references/methodology.md` for the full iteration cycle.

## Vocabulary in one breath

The fixed terms are *refine/lower* (Lean → Rust), *lift* (Rust → Lean, equal to Aeneas after Charon), and *check* (translation validation).
Never write the bare word "extraction": it points in both directions here — model to code and code to IR — and collides with itself.
Aeneas is a semantics-preserving functional translation, not a transpiler; Eurydice (Rust → C) is the genuine transpiler sibling in this ecosystem, and both consume Charon's LLBC.
See `references/vocabulary.md` for the full term mapping and the hazard in detail.

## When to use, when not

Reach for this methodology when you are modeling a domain as a dependently-typed Lean 4 specification and want the type system to make illegal states unrepresentable before any code exists.
Reach for it when refining and lowering such a spec to a Rust implementation while keeping the implementation honest to the model.
Reach for it when lifting a Rust implementation back to Lean to check spec-to-implementation correspondence, whether mechanically when a proof is tractable, via differential testing when it is not, or via LLM comparison as the loosest tier.
Reach for it, too, when you want to generate and diff type-system diagrams of the model and the implementation to track how they drift apart and back together over the loop's iterations.

Do not reach for it when the domain need not be lifted or verified at all, where the ceremony of the round trip buys nothing.
Do not reach for it when the goal is simply to transpile Rust to C: that is Eurydice's job, not this skill's, and the lift-and-check round trip would be wasted effort.
Do not reach for it for the schema-factored subset of a Lean spec, the product-oriented columnar, table, and record data-schema types that lower through LinkML multi-target codegen rather than the Charon/Aeneas round trip.
This is the lowering-path bifurcation defined in full by preferences-data-modeling: this skill owns only the domain-direct algebra round trip, while the schema-factored leg belongs to that hub, with the spec-anchored Lean → LinkML → bindings instance being nucleus-platform.

Before the first refine → lift → check cycle on a new machine, confirm each tool is present and version-matched and stand up the Lean backend the check leg needs; `references/toolchain-setup.md` covers that one-time setup and a tier-0 smoke test.

## Mechanical proof is the ideal, not a requirement

The precise ideal is an on-the-nose mechanical proof that the lifted model refines or equals the spec, but its absence is not a failure of the method.
When a mechanical proof is intractable, differential testing or LLM comparison still discharges the check at a weaker but honest tier, and the methodology remains sound.
This honesty principle is developed in `references/mathematics.md` (the adjunction framing and its three honesty notes) and operationalized in `references/check-translation-validation.md` (the three tiers and the ideal-not-requirement stance).

## References

| Reference | Open it for |
|---|---|
| [`references/methodology.md`](references/methodology.md) | The refine → lift → check loop, the one-CLI-call-per-step intent, and the iteration cycle |
| [`references/mathematics.md`](references/mathematics.md) | The Galois/adjunction framing (α ⊣ γ; Φ = α∘γ ≈ id) and the three honesty notes |
| [`references/vocabulary.md`](references/vocabulary.md) | The term mapping, the "extraction" hazard, and transpiler vs functional translation |
| [`references/lean-spec-patterns.md`](references/lean-spec-patterns.md) | Dependently-typed domain modeling in Lean 4, the executable/decidable fragment, and Plausible |
| [`references/refine-and-lower.md`](references/refine-and-lower.md) | Forward Lean → Rust, the Aeneas/Charon-safe Rust subset, and ownership-intent annotations |
| [`references/lift-charon-aeneas.md`](references/lift-charon-aeneas.md) | Charon then Aeneas, symbolic execution, backward functions, and Nix-flake invocation |
| [`references/toolchain-setup.md`](references/toolchain-setup.md) | Confirming the toolchain works before starting, the tier-0 translation-validation smoke test, and the Lean backend (lake/elan/cache) setup |
| [`references/check-translation-validation.md`](references/check-translation-validation.md) | The three check tiers, refinement vs equivalence, and the ideal-not-requirement stance |
| [`references/diagramming.md`](references/diagramming.md) | The type-graph.json schema spec, the three emitters as specification, Mermaid v1, SVG fallback, and future work |
| [`references/prior-art-idris2.md`](references/prior-art-idris2.md) | Lessons mined from ironstar and the later Idris2 → Lean 4 test exercise |

## See also

- `preferences-domain-modeling` — DDD aggregate design, smart constructors, and making illegal states unrepresentable, the source discipline for the Lean spec leg.
- `preferences-theoretical-foundations` — category and type theory and the home of the adjunction framing this skill leans on; it owns the general "keep a type-checkable Lean spec beside the implementation" stance, including the Lean-spec-beside-a-non-Rust-implementation (for example Python) case, while this skill owns the verified Lean-to-Rust round trip the two share.
- `preferences-algebraic-laws` — functor/monad laws and property-based testing, the backbone of the differential-testing check tier.
- `preferences-validation-assurance` — severity, evidence quality, and the confidence promotion chain that calibrates which check tier suffices.
- `preferences-architecture-diagramming` — format selection and diagram compendium conventions that the type-system diagramming leg specializes.
- `preferences-rust-development` — the Rust conventions the refine/lower leg must respect within the Aeneas/Charon-safe subset.
- `preferences-data-modeling` — the hub that defines the lowering-path bifurcation in full; it owns the schema-factored leg, where product-oriented table schemas lower via LinkML multi-target codegen, complementing this skill's domain-direct algebra round trip.
