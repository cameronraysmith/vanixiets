# Vocabulary

This reference fixes the terms of refinement-driven development so the pipeline can be discussed without ambiguity.
The pipeline is a composition of three steps, and its hazard is that one English word — *extraction* — names two opposite legs at once, so this skill bans the bare word and substitutes disciplined replacements throughout.
The name of the methodology is anchored in *refinement calculus* (Back & von Wright; Morgan), the order-theoretic account of programs related by a refinement order ⊑.
The single-word recall alias is TD³ (type-driven development × domain-driven design), used at most once and never as the skill name.

## Contents

- The pipeline as a composition
- The three steps named precisely
- The extraction hazard
- Transpiler versus functional translation
- Compact term table
- Source anchors

## The pipeline as a composition

The whole loop is a composition over the objects in the chain (the Lean spec, Rust, LLBC, and the lifted Lean model), none of which may be elided because each is a real artifact the toolchain produces and consumes — the Rust is what actually compiles and ships in production, LLBC is the borrow-explicit IR Charon emits and Aeneas ingests, and the lifted Lean model is the pure proof artifact checked against the spec.

```text
Lean 4  --refine/lower-->  Rust  --Charon-->  LLBC  --Aeneas-->  Lean 4
```

The forward leg *refine/lower* carries the Lean 4 specification down to Rust.
The reverse leg *lift* is the composite Aeneas ∘ Charon, carrying Rust back up to a Lean 4 model, and it is always kept as two visibly distinct sub-steps because the borrow-explicit IR in the middle is real and consumed by tooling.
The final correspondence between the lifted model and the original spec is established by *check*.

Written as types, the lift is a composition lift :: Rust ⟶ Lean, factored as lift = Aeneas ∘ Charon, with Charon :: Rust ⟶ LLBC and Aeneas :: LLBC ⟶ Lean.
The forward direction refine/lower :: Lean ⟶ Rust is human authoring, not an automated generator; nothing in this ecosystem emits Rust from Lean.

## The three steps named precisely

*Refine/lower* is the forward step Lean 4 → Rust.
It is manual, LLM-assisted authoring: write the executable Lean spec, then hand-write Rust that stays inside the subset Charon and Aeneas can ingest.
This is the classic model-to-code sense that the verification literature has historically called program extraction, but this skill never uses that word for it (see the hazard below).

*Charon* is the step Rust → LLBC.
LLBC is the Low-Level Borrow Calculus, the borrow-explicit intermediate representation that Charon produces; the name is inherited from the Aeneas project, of which Charon was originally a part.
Charon is a `rustc` driver that emits a single serialized AST as JSON (a compact `postcard` binary form also exists), and `charon-ml` is the OCaml library that deserializes and prints that JSON.
For an Aeneas-compatible artifact the invocation carries the Aeneas preset, for example:

```bash
charon cargo --preset=aeneas --dest-file=my_crate.llbc
```

LLBC comes in two flavours: structured LLBC (the default, with reconstructed `if`/`match`/`loop`) and unstructured ULLBC (a control-flow graph, selected with `--ullbc`).
Aeneas consumes the structured form.

*Aeneas* is the step LLBC → Lean, a *functional translation by symbolic execution*: it symbolically executes the LLBC and translates the trace into a pure lambda calculus model in the target proof assistant.
Aeneas supports F\*, Coq/Rocq, HOL4, and Lean as backends; this skill uses the Lean backend, selected by passing the backend value as a separate token after the selector flag:

```bash
aeneas -backend lean my_crate.llbc -dest proofs -split-files
```

Mutable references (`&mut T`) are modeled by *backward functions* — a function returned alongside the borrowed value that propagates the update to the original owner — so the model needs no heap.
Aeneas is *not* a transpiler; its output is a pure model for proving, not deployable code.

*Check* is the final step: establish a refinement (the ⊑ order) or a functional/observational equivalence (≈, ≅) between the lifted model and the original spec.
The a-posteriori discipline of producing an artifact and then proving it matches the specification is *translation validation* (Pnueli, Siegel, and Singerman), and that is the recognized name used for the check leg throughout this skill.
There is no in-repo operator named ⊑; the order is imported order-theoretic framing, realized operationally as Hoare-triple-style spec theorems over the lifted model.

## The extraction hazard

The bare word *extraction* is banned in this skill because it points in both directions and collides with itself.

In one direction it is the verification community's name for proof-assistant-to-code generation (the classic F\*/Coq program-extraction sense), which is the refine/lower leg here, model → code.
In the other direction the tools in this very ecosystem burn the same word on code → IR and on backend emission: Eurydice's README describes itself as extracting Rust into KaRaMeL's internal AST, and Aeneas's own source directory for backend emission is literally named `src/extract/`.
So the word cannot disambiguate direction even within a single toolchain, and it additionally erases the distinction between producing runnable code and producing a proof model.
Wherever the temptation to write *extraction* arises, substitute the precise step name instead: refine/lower, Charon, Aeneas, lift, check, or translation validation.

## Transpiler versus functional translation

Two consumers sit behind Charon's shared LLBC front-end, and the contrast between them is the load-bearing reason the disciplined vocabulary matters.

Eurydice is a genuine *transpiler*: it consumes the same LLBC that Aeneas does and lowers it to C (C11, with C++ compatibility) via the KaRaMeL back end and a chain of nano-passes.
Its output is ordinary, compilable, runnable C — structs, pointers, loops, `static` helpers — and its informal guarantee is operational: if the Rust program terminates without panicking, the generated C computes the same result without undefined behavior.
Its purpose is backwards compatibility, shipping verified Rust crypto (libcrux, ML-KEM/Kyber) as C to toolchains that cannot depend on Rust.
A transpilation is operational source to operational source.

Aeneas is *not* a transpiler.
It is a semantics-preserving *functional translation*: it lowers the same LLBC to a pure lambda calculus model in a proof assistant, with borrows and mutation translated away via symbolic execution and backward functions.
Its output is a mathematical model fed to Lean for proving, not code to be compiled and run, and its guarantee is by-construction semantics preservation discharged as proof obligations rather than a runtime result claim.
A functional translation is operational source to a pure model.

Both tools live under the same organization, are written in OCaml, and ingest the identical Charon LLBC through the same JSON deserializer; they diverge completely only after that shared front-end.
Calling either step *extraction* would erase exactly this transpiler-versus-functional-translation distinction, which is why the term is forbidden and the two are always named by their tools.

## Compact term table

The table fixes each term, the direction of the transform, the tool that realizes it, and its meaning.
Read the direction column as the arrow within the pipeline composition above.

| Term | Direction | Tool | Meaning |
|---|---|---|---|
| refine/lower | Lean → Rust | human (LLM-assisted) | author the Rust realization of the spec within the Aeneas/Charon-safe subset; no automated generator exists |
| Charon | Rust → LLBC | `charon` (`rustc` driver) | translate Rust to the borrow-explicit LLBC IR, emitted as JSON; `charon-ml` reads it |
| LLBC | (the IR itself) | Charon output | Low-Level Borrow Calculus; structured by default, ULLBC (CFG) under `--ullbc` |
| Aeneas | LLBC → Lean | `aeneas -backend lean` | functional translation by symbolic execution to a pure model; `&mut` → backward functions; not a transpiler |
| lift | Rust → Lean | Aeneas ∘ Charon | the composite reverse leg, always shown as its two sub-steps |
| check | model vs spec | Lean proofs | establish refinement ⊑ or equivalence ≈/≅ between lifted model and original spec |
| translation validation | model vs spec | (the discipline) | the recognized name for check: produce an artifact, then prove it matches the spec |
| transpiler (Eurydice) | LLBC → C | `eurydice` | operational-to-operational lowering to runnable C; contrast object, not part of this skill's loop |
| functional translation (Aeneas) | LLBC → Lean | `aeneas` | operational-to-pure-model translation for verification |
| extraction | (banned) | — | ambiguous: names both model→code and code→IR; never use the bare word |

## Source anchors

Eurydice as a Rust-to-C transpiler and its shared Charon front-end are grounded in `~/projects/functional-programming-workspace/eurydice` (README and `bin/main.ml`).
Aeneas as a verification toolchain translating to a pure lambda calculus, its four backends, and the backward-function model are grounded in `~/projects/functional-programming-workspace/aeneas` (README, `src/Config.ml`, `src/Main.ml`, `backends/lean`).
Charon's LLBC/ULLBC distinction, the Aeneas preset, and the JSON surface are grounded in `~/projects/functional-programming-workspace/charon` (`docs/usage.md`, `src/options.rs`, `charon-ml`).
The disciplined-term contrast and the extraction hazard are developed in `references/lift-charon-aeneas.md` and `references/check-translation-validation.md`; the name anchor in refinement calculus is developed in `references/mathematics.md`.
For the spec-side authoring conventions this vocabulary serves, see `preferences-domain-modeling`.
