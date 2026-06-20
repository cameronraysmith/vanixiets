# The refine → lift → check loop

This reference is the operational spine of refinement-driven development.
It describes the three-step loop that turns a Lean 4 specification into running Rust and then back into a Lean 4 model that can be checked against the original spec.
The loop is a function composition over the pipeline objects, and the discipline of this skill is to never elide the intermediate objects, because they are exactly what compiles, links, and runs in production.

## Contents

- [The pipeline as a composition](#the-pipeline-as-a-composition)
- [Step 1: refine/lower (Lean → Rust), human authoring](#step-1-refinelower-lean--rust-human-authoring)
- [Step 2: Charon (Rust → LLBC), one CLI call](#step-2-charon-rust--llbc-one-cli-call)
- [Step 3: Aeneas (LLBC → Lean), one CLI call](#step-3-aeneas-llbc--lean-one-cli-call)
- [Step 4: check (translation validation), one CLI call](#step-4-check-translation-validation-one-cli-call)
- [The iteration cycle](#the-iteration-cycle)
- [Which reference for which sub-task](#which-reference-for-which-sub-task)

## The pipeline as a composition

The objects and arrows are fixed:

    Lean 4  --refine/lower-->  Rust  --Charon-->  LLBC  --Aeneas-->  Lean 4

The forward arrow `refine/lower :: Lean 4 → Rust` is human authoring, optionally LLM-assisted.
The return path is the composite `lift = Aeneas ∘ Charon :: Rust → Lean 4`, and this skill always keeps its two sub-steps visibly distinct.
`Charon :: Rust → LLBC` produces the borrow-explicit Low-Level Borrow Calculus intermediate representation as a single serialized LLBC file, by default a JSON object (Postcard is the alternative via `--format`).
`Aeneas :: LLBC → Lean 4` is a semantics-preserving functional translation by symbolic execution that yields a pure functional model in Lean, with backward functions modeling `&mut`.
The final arrow `check` establishes refinement (the ⊑ order) or functional equivalence between the lifted model and the original Lean 4 spec.

The single deliverable of one full pass is the pair (running Rust, lifted Lean model) together with the check artifact that ties the lifted model to the spec.
Rust and LLBC are not scaffolding to be discarded.
The Rust is what ships; the LLBC is the borrow-explicit witness that makes the lift well-defined.

A note on the three CLI tools and where each runs.
Charon is invoked from inside the Rust crate, the way `cargo build` is.
Aeneas consumes the `.llbc` file Charon produced.
The check is a Lean build that elaborates the spec, the lifted model, and the bridging theorems.
Each of Steps 2, 3, and 4 is exactly one command.
Step 1 has no command that generates Rust from Lean; it is authored by a person.

## Step 1: refine/lower (Lean → Rust), human authoring

There is no Lean-to-Rust generator in this pipeline.
The forward direction is a human writing Rust that realizes a Lean 4 specification, staying inside the subset of Rust that Charon and Aeneas can handle.
The realized commands at this step are entirely Lean-side: write the spec, then build it.

```bash
cd lean-spec && lake build
```

`lake build` elaborates and type-checks the hand-authored Lean specification; for a `lean_lib` default target this replays any proofs the spec already asserts.
Optionally a Lean metaprogram can emit an artifact at this step via `lake exe <name>`, but no such metaprogram generates Rust.

The intent of the loop is one CLI call per step, and that framing applies to Steps 2, 3, and 4.
Step 1 is the deliberate exception: it is authoring, not generation.
Do not imply that an automatic refine/lower tool exists.
The discipline that makes the subsequent steps succeed is keeping the hand-written Rust inside the Charon/Aeneas-safe subset and annotating ownership intent so the lift is faithful; see `references/refine-and-lower.md` for the safe subset and the annotation conventions.

## Step 2: Charon (Rust → LLBC), one CLI call

Charon is a `rustc` driver that translates a Rust crate into a single serialized LLBC file, by default a JSON object.
The Aeneas preset is the load-bearing flag: it turns on the micro-pass and serialization bundle Aeneas expects, so the produced `.llbc` is consumable by Step 3.

For a cargo crate, run inside the crate directory:

```bash
charon cargo --preset=aeneas --dest-file my_crate.llbc
```

For a single Rust file without cargo:

```bash
charon rustc --preset=aeneas --dest-file my_crate.llbc -- my_crate.rs --crate-name=my_crate
```

With no `--dest-file`, the default destination is `<crate_name>.llbc` in the current directory; the LLBC extension is `.llbc` for structured LLBC and `.ullbc` for the unstructured variant selected by `--ullbc`.
The default output is structured LLBC, which is what Aeneas wants.
The flag form here reflects the actual Charon checkout: `--dest-file <path>`, not a bare `-o <file>`.
The Aeneas-specific structure of the `.llbc` and the charon-ml OCaml surface over its JSON are detailed in `references/lift-charon-aeneas.md`.

## Step 3: Aeneas (LLBC → Lean), one CLI call

Aeneas reads the structured LLBC and produces a pure functional model in Lean 4 by symbolic execution.
The backend selector names the next token after `-backend`; `lean` selects the Lean 4 backend.
Aeneas also supports F*, Coq (also spelled `rocq`), and HOL4 as alternative backends; this skill uses Lean.

Minimal Lean run:

```bash
aeneas -backend lean my_crate.llbc -dest proofs
```

The fuller form used by worked drivers names a subdirectory, splits one file per declaration group, and sets a namespace:

```bash
aeneas -backend lean my_crate.llbc -dest proofs -subdir /MyCrate/Code -split-files -namespace MyCrate
```

The output directory selector is passed explicitly with `-dest` (then `-subdir`).
The flags use a single leading dash, following the OCaml argument convention.
With `-split-files`, generated files land as `Types.lean`, `Funs.lean`, and the `*External_Template.lean` companions under the destination tree; the `*External.lean` files are user-maintained and never overwritten.
The Aeneas binary as packaged also carries Charon, so a single package can drive Steps 2 and 3.
The symbolic-execution mechanics, the backward-function model for `&mut`, the three-constructor `Result` type and seven-constructor `Error`, and the Nix-flake invocation are all covered in `references/lift-charon-aeneas.md`.

## Step 4: check (translation validation), one CLI call

The check step establishes that the Aeneas-lifted model matches the hand-authored Lean spec.
Operationally it is a Lean build of the project that imports the Aeneas backend library, the lifted model, and the bridging theorems.

```bash
cd lean-proj && lake build
```

Building the `lean_lib` default targets elaborates and type-checks every theorem, which replays all the proofs.
The lifted model is established as a refinement of the spec, or as functionally equivalent to it, by Lean theorems written in the weakest-precondition / Hoare-triple style and discharged with the tactics Aeneas ships.

Two scope rules for this step are non-negotiable.
First, `omega` is forbidden *inside* refinement proofs over the lifted model; use `scalar_tac`, which preprocesses machine-integer bounds before calling omega under the hood.
Plain `omega` remains fine in spec-side hand-authored Lean that does not reason about the lifted model's scalar types.
Second, the refinement order ⊑ is imported order-theoretic framing, not an operator that exists in the tooling; it is realized operationally as Hoare-triple-style spec theorems.
The three check tiers (mechanical kernel proof, property-based differential testing, and LLM triage), the distinction between refinement and equivalence, and the principle that a mechanical on-the-nose proof is the ideal rather than a hard requirement are developed in `references/check-translation-validation.md`.

## The iteration cycle

The loop is run, not run once.
Each pass produces a lifted model and a check result, and the divergences surfaced by the check feed the next refinement.

The cycle has four moves.
First, model: state or revise the executable Lean 4 specification (Step 1, Lean-side authoring and `lake build`).
Second, refine/lower: write or revise the Rust realization under the safe subset (Step 1, human authoring).
Third, lift: run Charon then Aeneas to obtain the pure Lean model from the Rust (Steps 2 and 3, one CLI call each).
Fourth, check: build the Lean project to replay the bridging theorems and surface where the lifted model and the spec disagree (Step 4, one CLI call).

The feedback is the point.
A failed or absent check theorem is not a failure of the loop; it is an open obligation that names a precise place where spec and lifted model diverge.
That obligation is the input to the next iteration: either the Rust is adjusted so the lift matches the spec, or the spec is corrected because the Rust encodes the truer intent, or the bridging theorem is strengthened until it discharges.
Successive iterations pull the spec and the lifted model toward ≈-identity, in the sense that the set of unproven or divergent obligations shrinks toward empty.
The order-theoretic and adjunction framing of why this convergence is the right target, and the three honesty notes that keep it from being overstated, are in `references/mathematics.md`; this reference deliberately keeps the mathematics out and stays operational.

A practical convention for artifacts.
Charon's `.llbc` output and the Aeneas-generated Lean files are derived products of a given Rust revision.
Emit them into a gitignored output subdirectory so the hand-authored spec, the `*External.lean` files, and the bridging theorems remain the only tracked Lean sources.
This skill specifies that discipline conceptually; building the harness that enforces it is out of scope for v1.

## Which reference for which sub-task

When the sub-task is writing or revising the Lean 4 specification, including dependently-typed domain modeling, the executable and decidable fragment, and property-based testing setup, read `references/lean-spec-patterns.md`.

When the sub-task is the forward refine/lower from Lean to Rust, including the Charon/Aeneas-safe Rust subset and the ownership-intent annotations, read `references/refine-and-lower.md`.

When the sub-task is the lift itself, the Charon invocation and its LLBC/charon-ml surface, or the Aeneas symbolic execution, backward functions, `Result`/`Error` model, tactics, and Nix-flake invocation, read `references/lift-charon-aeneas.md`.

When the sub-task is the check, the three tiers, the refinement-versus-equivalence distinction, and the ideal-not-requirement principle, read `references/check-translation-validation.md`.

When the sub-task is visualizing the type graph or the pipeline, read `references/diagramming.md`, which specifies the `type-graph.json` schema and the emitters as a specification rather than built tooling.

When the sub-task needs the order-theoretic justification (the Galois/adjunction framing α ⊣ γ, Φ = α∘γ ≈ id, and the honesty notes), read `references/mathematics.md`.
