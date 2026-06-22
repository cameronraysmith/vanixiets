# Lift: Charon then Aeneas

The *lift* is the composite Rust ⟶ Lean direction of the pipeline, equal to Aeneas ∘ Charon.
Symbolically the whole loop is Lean 4 --refine/lower--> Rust --Charon--> LLBC --Aeneas--> Lean 4, and this document covers the two right-hand arrows.
Keeping the two sub-steps visibly distinct matters: Charon and Aeneas are separate tools with separate flake outputs, separate version pins, and separate intermediate objects, and conflating them hides where a failure actually lives.
Charon turns Rust into LLBC, the borrow-explicit intermediate representation; Aeneas turns that LLBC into a pure functional Lean model.
Aeneas is *not* a transpiler — it is a semantics-preserving functional translation by symbolic execution; the genuine transpiler sibling in this ecosystem is Eurydice (Rust ⟶ C), which also consumes Charon's LLBC.
See `references/vocabulary.md` for the full term mapping and the hazard around the bare word the two arrows would otherwise both claim.

## Contents

| Section | Topic |
|---|---|
| [Charon: Rust to LLBC](#charon-rust-to-llbc) | what LLBC and ULLBC are, the verified CLI, the JSON / charon-ml surface |
| [Aeneas: LLBC to Lean](#aeneas-llbc-to-lean) | the CLI, functional translation by symbolic execution, backward functions |
| [The Aeneas Lean support library](#the-aeneas-lean-support-library) | the `Aeneas` package, the `Result`/`Error` model, the tactics |
| [Alternative backends](#alternative-backends) | Coq, F*, HOL4 |
| [Nix-flake invocation](#nix-flake-invocation) | charon/aeneas flake outputs, the intended vanixiets import, pin parity |

## Charon: Rust to LLBC

Charon is a rustc driver: it runs the Rust compiler with itself installed as the codegen backend, reaches the parts of the crate and its dependencies it needs, and serializes a single AST file.
Its own framing, in the project's words, is that it "allows us to cross the river of compiler internals to go from the world of Rust programs to the world of code analysis and verification."
Because it links against rustc's internal MIR APIs it must build the crate with a pinned Rust *nightly* (see [Nix-flake invocation](#nix-flake-invocation)); this is structural, not incidental.
The checkout grounding this skill is Charon `0.1.216`, and Charon is explicitly alpha: it does not yet cover the whole Rust language, mistranslates some edge cases, and plans breaking API changes.

LLBC stands for Low-Level Borrow Calculus, "the name we give to the output of Charon," inherited from the Aeneas project that Charon was first built for.
The intermediate object the lift carries between its two tools is exactly an LLBC file.
Charon also has an unstructured variant, ULLBC (Unstructured LLBC), which is LLBC without control-flow reconstruction.
The distinction is solely how control flow is represented.
The MIR Charon receives from rustc is a control-flow graph where jumps are arbitrary gotos; ULLBC keeps that goto/basic-block shape while simplifying redundancies such as constant representation; LLBC restructures the CFG back into nested `match`, `if … then … else`, and `loop` constructs and merges MIR statements and terminators into a single statement type.
LLBC is the default and is what Aeneas consumes; ULLBC is selected with `--ullbc`.
The structural difference shows up cleanly in the OCaml AST: a ULLBC body is a vector of *blocks* (a CFG) while an LLBC body is a single structured *block*.

### The verified Charon CLI

Charon is a clap application with subcommands.
The two that matter for the lift are `charon cargo` (run on a cargo project, much as you would run `cargo build`) and `charon rustc` (run on a single Rust file, with trailing rustc options after `--`).
Run it from *within* the crate of interest.
Charon's own version is queried with the `version` subcommand (`charon version`), and `charon toolchain-version` prints the pinned rustc toolchain it embeds; the GNU-style `charon --version` is not accepted and errors.

The destination is controlled by `--dest-file <path>`, which overrides the default `<crate_name>.llbc` placement and ignores the deprecated `--dest` directory flag.
Do not write `-o my_output.llbc`; that form does not exist on this CLI.
The load-bearing flag for this pipeline is `--preset=aeneas`: it enables the option bundle Aeneas expects (associated-type lifting, treating `Box` as builtin, reconstructing fallible operations and asserts, hiding marker traits and the allocator, and related micro-passes), and Aeneas-compatible LLBC is not produced without it.
For the single-file `charon rustc` form a second flag is equally load-bearing: `--crate-type=rlib`.
A bare `.rs` file is a binary crate, so without it rustc aborts before Charon runs with E0601 ('no main'); the `charon cargo` form never needs it because the manifest supplies the crate type.

The canonical crate invocation, taken from the Aeneas test runner and the tutorial driver, is:

```bash
cd rust
charon cargo --preset=aeneas --dest-file my_crate.llbc
```

The single-file form, from the Aeneas test runner, threads the load-bearing `--crate-type=rlib` and the edition through trailing rustc arguments:

```bash
charon rustc --dest-file my_crate.llbc --preset=aeneas \
  -- my_file.rs --crate-name=my_crate --crate-type=rlib --edition=2021
```

The output extension follows the format and structure: LLBC JSON is `.llbc`, ULLBC JSON is `.ullbc`, and the compact postcard binary variants append `.postcard`.
For debugging without writing a file, `charon rustc --no-serialize --print-llbc -- foo.rs` pretty-prints the structured IR; this exact form is the flake's own end-to-end smoke check.
`charon pretty-print <file> --format json|postcard` re-renders an already-serialized LLBC file.

One determinism note matters when reproducing a committed golden: Charon records the source file's path and line numbers, and Aeneas threads them into the generated Lean `Source:` comment, so the relative cwd from which you invoke Charon controls part of the output byte-for-byte.
Run Charon from the crate or clone root with a cwd-relative source path when you intend to diff against a committed golden; an absolute or differently-rooted invocation perturbs only that `Source:` comment, which `references/toolchain-setup.md` treats as a benign diff in the tier-0 smoke test.

Internally `charon cargo` uses the rustc-wrapper trick: it sets `RUSTC_WRAPPER` to point at the separate `charon-driver` binary so cargo invokes the driver instead of plain rustc per crate, sets `RUSTC_WORKSPACE_WRAPPER` to a random fingerprint to defeat cargo's caching, and passes its own options through a `CHARON_ARGS` environment variable.
The user-facing binaries are therefore `charon` and `charon-driver`, both of which the nix builds install.

### The JSON and charon-ml surface

Charon's output is one JSON object.
The real top-level container is `CrateData`, shaped `{ "charon_version": "...", "translated": { ... }, "has_errors": bool }`; the README's flat `{ crate_name, type_decls, fun_decls, … }` is the conceptual content of the `translated` field, a `TranslatedCrate`.
`TranslatedCrate` carries the crate name, the flags Charon ran with, source files, item names, and five declaration maps — `type_decls`, `fun_decls`, `global_decls`, `trait_decls`, `trait_impls` — plus an optional SCC-reordered `ordered_decls` grouping that tells a consumer whether a declaration group is recursive.

The declaration maps are Rust `IndexMap`s but serialize as JSON *arrays*: array position is the integer id, and `null` marks a missing or invisible slot.
Consumers therefore index by integer id equal to array position.
Items reference one another only by these integer ids, never by inlined definition: a struct field of type `Foo<Bar>` is `TyKind::Adt(TypeDeclRef { id: TypeId::Adt(<id of Foo>), generics: … })`, and the single `TypeDecl` for `Foo` lives once in `type_decls`.
A type-graph node `TypeDecl` is a struct, enum, union, opaque, alias, or error — type aliases are inlined by rustc except at top level.
The relevance for the diagram emitters specified in `references/diagramming.md` is exactly this: the type graph's nodes are `type_decls` entries and its edges are the `TypeId`-tagged references reachable from each declaration's fields and variants.

Enums use serde's externally-tagged encoding: a unit-like variant is a bare string (`"Opaque"`, `"Tuple"`), a data-carrying variant is a single-key object (`{ "Adt": <id> }`, `{ "Struct": [ <field>, … ] }`).
By default Charon hash-conses repeated `Ty` and `TraitRef` values to shrink the file, so a JSON reader meets three forms per hash-consable value — an inline `Untagged` value, an inline-and-interned `HashConsedValue` pair, and a `Deduplicated` back-reference by id.
Passing `--no-dedup-serialized-ast` emits everything inline for human inspection.

charon-ml is the OCaml library that deserializes and prints this AST, living under `charon-ml/` in the Charon repo.
Its consumer-facing entry point is `OfJson.crate_of_json_file : string -> (crate, string) result`, which sniffs the format, version-checks, and returns a `crate` record whose five decl maps are id-keyed OCaml `Map.t` values.
The version check is an *equality* check: charon-ml carries a single `supported_charon_version` string and rejects any file whose version differs.
The same exact-string gate is not unique to charon-ml: Aeneas itself checks the `charon_version` recorded in the LLBC against the Charon it expects, and on pin skew aborts the lift with 'Incompatible version of charon' rather than producing Lean.
This is a likely first-encounter operational failure whenever Charon and Aeneas are pinned independently; the conservative default of depending only on Aeneas and relying on its transitively pinned, version-matched Charon avoids it.
A large part of charon-ml is auto-generated from the Rust AST by a `generate-ml` binary, and a flake check enforces that the committed generated OCaml matches what regeneration produces, so the OCaml deserializers are guaranteed faithful to the Rust types.
A typical consumer iterates `crate.type_decls`, matches each declaration's `kind`, and resolves an ADT reference by looking the target `type_decl_id` back up in the same map.

## Aeneas: LLBC to Lean

Aeneas reads the structured LLBC that Charon produced and emits a pure lambda-calculus model in the chosen backend.
It is a functional translation, not a transpiler: it exploits Rust's ownership discipline so that no heap model is needed, translates each function independently with no whole-program analysis, and is published with soundness results (the ICFP 2022 "Rust verification by functional translation" paper, and an ICFP 2024 follow-up proving the symbolic execution it performs is itself a sound borrow-checker).

### The Aeneas CLI

The binary is invoked as `aeneas -backend <backend> [OPTIONS] LLBC_FILE`.
Backend flags use a single leading dash, following the OCaml `Arg` convention, and the backend value is a separate token after `-backend` because it is parsed as a symbol from a fixed name list, not a free string.
The output destination is passed explicitly with `-dest <dir>` (and an optional `-subdir <dir>` beneath it); do not assume a default landing directory.

The minimal Lean run is:

```bash
aeneas -backend lean my_crate.llbc -dest proofs
```

The fuller recommended Lean invocation, from the getting-started documentation, splits files and namespaces the output:

```bash
aeneas -backend lean my_crate.llbc -dest proofs -subdir /MyCrate/Code -split-files -namespace MyCrate
```

With `-split-files` the generated tree is `Types.lean`, `Funs.lean`, and per-category `*External_Template.lean` files for declarations whose models must be supplied externally; the `*External_Template.lean` files are copied to `*External.lean` and hand-maintained, never overwritten.
Lean-only flags include `-lean-default-lakefile` to generate a default `lakefile.lean` and `-emit-json` to emit a `translation.json` alongside the Lean files.
The backend selector accepts `fstar`, `coq`, `rocq`, `lean`, and `hol4` (`coq` and `rocq` are aliases for the same backend); when no backend is given Aeneas defaults internally to Lean for its borrow-check-only mode.
One general flag is worth singling out operationally: `-checks` turns on Aeneas' internal consistency checks at roughly a 100x slowdown, so omit it unless you need exact parity with the upstream test runner — and if a lift is inexplicably slow, check whether `-checks` is set.

### Functional translation by symbolic execution

Aeneas works in two phases.
First it *symbolically executes* the LLBC; then it *translates the symbolic trace into pure code*.
At the start of execution each input argument is initialized as a fresh symbolic value of its type, and the function signature is instantiated with fresh region ids.
The interpreter tracks borrows, loans, and *abstractions* — the LLBC notion of the borrows owned by a region (a lifetime).
The ordinary forward evaluation runs to the `return` instruction; at that point a continuation synthesizes the *backward* direction by ending abstractions in dependency order.
This is the whole trick by which mutable state becomes pure: there is one backward function per region group, and the symbolic-to-pure pass turns the resulting trace into a pure function body, wrapping returns in the `Result` monad whenever the function can fail.

### Backward functions: how &mut T becomes pure

A Rust function that *takes* a `&mut T` but does not return a borrow lifts to a function that simply returns the updated value, merging the forward and backward directions.
The simplest cases make this concrete: `set_to_zero(x: &mut u32)` returning `()` lifts to `def set_to_zero (x : U32) : Result U32 := ok 0#u32`, `swap(&mut, &mut)` lifts to `def swap (x y : U32) : Result (U32 × U32) := ok (y, x)`, and `incr(x: &mut i32) -> i32` lifts to `def incr (x : I32) : Result I32 := x + 1#i32`.

A Rust function that *returns* a `&'a mut T` is where a distinct backward function appears.
It lifts to a forward function returning a pair (value, backward_function), where the backward function reconstructs the updated owner from the value finally written through the borrow.
This is precisely the lens pattern: the forward direction is the *get*, the backward direction is the *put*.
The generated Lean type is `Result (T × (T → CList T))` when the reconstruction cannot fail, or `Result (T × (T → Result OriginalType))` when it can.
With multiple `&mut` lifetimes there can be several backward functions, one per region group, matching the per-region-group synthesis described above.

The naming convention in generated code is fixed: the backward function returned by a recursive call is bound as `<fn>_back`, and the locally-built closure is named `back`.
The following is real generated output (the file header marks it as automatically generated by Aeneas), the canonical `list_nth_mut`:

```lean
def list_nth_mut
  {T : Type} (l : CList T) (i : Std.U32) : Result (T × (T → CList T)) := do
  match l with
  | CList.CCons x tl =>
    if i = 0#u32
    then let back := fun t => CList.CCons t tl
         ok (x, back)
    else
      let i1 ← i - 1#u32
      let (x1, list_nth_mut_back) ← list_nth_mut tl i1
      let back := fun t => let tl1 := list_nth_mut_back t
                           CList.CCons x tl1
      ok (x1, back)
  | CList.CNil => fail panic
partial_fixpoint
```

The recursive backward binding `list_nth_mut_back` and the locally-built `back` closure are the naming convention in the flesh; the `partial_fixpoint` keyword handles the potentially-diverging recursion (see the `Result.div` constructor below).
A caller consumes a backward function by destructuring the returned pair and then *applying* the backward function to the new value to push the update home:

```lean
def test_choose : Result Unit := do
  let (z, choose_back) ← choose true 0#i32 0#i32
  let z1 ← z + 1#i32
  let (x, y) := choose_back z1
  ok ()
```

## The Aeneas Lean support library

Generated Lean files open with `import Aeneas`, drawing on the `Aeneas` Lean package (with a companion `AeneasMeta` metaprogramming library) that ships in the Aeneas repo's `backends/lean` tree.
The package provides the runtime model under `Aeneas/Std/` (the `Result` monad, scalars, arrays, slices, vectors, the weakest-precondition notation), mathematical support under `Aeneas/Data/`, and the shipped tactics under `Aeneas/Tactic/`.

### The Result and Error model

The current error monad has *three* constructors:

```lean
inductive Result (α : Type u) where
  | ok (v: α): Result α
  | fail (e: Error): Result α
  | div
deriving Repr, BEq
```

`ok v` is success, `fail e` is a runtime failure (panic, overflow, out-of-bounds, division by zero, and so on), and `div` models divergence or non-termination — the flat-order CCPO that Lean's `partial_fixpoint` needs.
The `Error` enum has *seven* constructors: `assertionFailure`, `integerOverflow`, `divisionByZero`, `arrayOutOfBounds`, `maximumSizeExceeded`, `panic`, and `undef`.
Do not model this as `Except Error T` with a two-constructor `{panic, outOfFuel}` error or any fuel parameter; that is a stale form contradicted by the current source, where divergence is the `div` constructor plus `partial_fixpoint`, not a fuel mechanism.
Scalars lift to `I8`…`I128`, `U8`…`U128`, `Isize`, and `Usize`, with literals carrying a `#type` suffix (`1#i32`, `0#u64`) and checked arithmetic returning `Result` (overflow becomes `fail integerOverflow`); `[T; N]` becomes `Array T n`, `Vec<T>` becomes `Vec T`, and `Box<T>` collapses to `T` because the indirection is erased.

### The tactics

Correctness against a hand-authored spec is stated in a weakest-precondition / Hoare-triple style with the `⦃ ⦄` notation: for `f : Result T`, the goal `f ⦃ x => P x ⦄` asserts that `f` succeeds with some value `x` for which `P x` holds, and for a function returning a pair both the value and the backward function may be named, as in `f ⦃ x back => P x back ⦄`.

The workhorse tactic is `step` (with the `@[step]` attribute on spec theorems).
It finds the next monadic call in the goal, looks up an `@[step]`-tagged theorem whose conclusion matches, applies it, and leaves the preconditions and remaining goals; once a function's spec is proven and registered, every caller's `step` applies it automatically, which is what makes specs compositional.
The forms include `step`, `step as ⟨x, h1, h2⟩` to name the result and postcondition conjuncts, `step with my_theorem`, and `step*` to repeat.
`progress` and `@[pspec]` are *deprecated* aliases of `step` and `@[step]`; they emit a rename warning and should be mentioned only as deprecated.

Scalar arithmetic, bounds, and overflow goals are discharged with `scalar_tac`, which knows the machine-integer bounds (`U32.max` and the like) that plain `omega` does not.
This is why `omega` is forbidden *inside* Aeneas refinement proofs over the lifted model: `scalar_tac` is the bounds-aware entry point (it calls omega after machine-int preprocessing).
That prohibition is scoped to the lifted-model proofs; `omega` remains fine in spec-side hand-authored Lean that does not reason about lifted scalar types.
A `simp_scalar` variant runs simp with `scalar_tac` as its discharger, and further shipped tactics (`simp_lists`, `bvify`/`bv_tac`, `natify`, `agrind`) support list rewriting and BitVec/Nat/Int transfer.

The check itself — establishing refinement or functional equivalence between the lifted model and the original Lean spec — is the subject of `references/check-translation-validation.md`; this document covers only producing the lifted model and the tactics available for the check.

## Alternative backends

Aeneas supports F*, Coq (also spelled Rocq), HOL4, and Lean, with per-backend standard-library trees under `backends/{coq,fstar,hol4,lean}`.
Its most mature backends are Lean and HOL4, and the Lean backend is the most actively developed.
This skill uses the Lean backend throughout, but the same LLBC input and the same `aeneas -backend <backend>` invocation drive any of the four; only the emitted syntax and the support library differ.

## Nix-flake invocation

The clone-independent way to run either tool is the upstream flake's ready-to-run entry points: `nix run github:AeneasVerif/aeneas#charon -L` runs Charon, and `nix run github:AeneasVerif/aeneas -L -- -backend <backend> your.llbc` runs Aeneas over an existing LLBC file.
These need no local checkout and resolve a version-matched pair on the spot, which makes them the default for a quick lift; the devShell and import wiring below are the alternative when you want a pinned, version-matched local environment to develop against.
The check-tier setup that pairs with either path is in `references/toolchain-setup.md`.

Charon and Aeneas each expose a plain `flake-utils.lib.eachDefaultSystem` flake (neither is flake-parts).

Charon's `packages.<system>` set offers `charon` (the wrapped default, installing both `bin/charon` and `bin/charon-driver`), `charon-unwrapped`, `charon-portable`, the `charon-ml` OCaml library, and the pinned `rustToolchain` as a re-exported package.
There is no `apps` output; instead Charon exports a bare top-level function `extractCrateWithCharon { name; src; charonArgs ? ""; cargoArgs ? ""; … }` that runs `charon cargo … --dest-file $out` under crane and yields a `<name>.llbc` derivation — the pure-nix path to an LLBC artifact, noted here as an option rather than the selected wiring.

Aeneas's `packages.<system>` set offers `aeneas` (the default OCaml dune build), `aeneas-static`, `aeneas-release` / `aeneas-static-release` bundle trees, and re-exported `charon` and `charon-ml`.
A useful property: Aeneas's `postInstall` symlinks Charon into its own `bin/`, so `${aeneas}/bin/` carries *both* `aeneas` and `charon` — a single package drives both lift sub-steps.
Aeneas's devShell already provisions `elan`, the Lean toolchain manager, and elan is required rather than merely convenient: the Lean backend pins a release-candidate toolchain that whatever default Lean is on PATH will not satisfy, and elan reads the nearest `lean-toolchain` file to auto-install and select that exact toolchain per-directory, which is what drives `lake`/`lean` for the spec and check steps.
The full check-tier setup that pairs with the lift is in `references/toolchain-setup.md`.

The pin-parity discipline is load-bearing.
Aeneas pins an *exact* Charon commit in a `charon-pin` file and enforces, via a `check-charon-pin` flake check, that the lockfile's Charon revision equals it.
The Lean backend pins `leanprover/lean4:v4.30.0-rc2` with a matching mathlib.
The implication for any consumer that adds both Charon and Aeneas as separate inputs is that it must keep them at the matched revision (typically via `aeneas.inputs.charon.follows = "charon"`), or the parity invariant breaks.
When they drift, the `charon_version` equality gate described above fires and Aeneas aborts the lift with 'Incompatible version of charon'.
The conservative default is to add *only* Aeneas as an input and rely on its transitively pinned, version-matched Charon.

The intended vanixiets import follows the established repository pattern and is not yet wired; this is future work, documented as intent.
vanixiets is a flake-parts plus `import-tree ./modules` flake, so a tool flake is added to the top-level `inputs` block and its per-system package reaches a devShell through `inputs'.<flake>.packages.<name>` inside a `perSystem` module.
The conservative input edit adds Aeneas alone:

```nix
# intended/future — the inputs block of flake.nix (modules cannot edit inputs)
aeneas.url = "github:aeneasverif/aeneas";
aeneas.inputs.nixpkgs.follows = "nixpkgs";
```

A `perSystem` module under `modules/` (auto-discovered by import-tree) then exposes the binaries:

```nix
# intended/future — e.g. modules/devshells/aeneas.nix
{
  perSystem = { pkgs, inputs', ... }: {
    devShells.refinement = pkgs.mkShell {
      packages = [
        inputs'.aeneas.packages.aeneas
        pkgs.elan
      ];
    };
  };
}
```

Because `${aeneas}/bin/` carries both `aeneas` and `charon`, that single package supplies the Charon and Aeneas steps, while `pkgs.elan` supplies the `lake`/`lean` of the spec and check steps; the four pipeline commands then run inside `nix develop .#refinement`.
Two points are deliberately left as verification items rather than asserted: whether `aeneas.inputs.nixpkgs.follows = "nixpkgs"` is safe given that Charon and Aeneas build their own pinned Rust toolchain through their own `rust-overlay` and Aeneas applies a `pkgsStatic` overlay, and whether to add a dedicated devShell module or extend the existing default shell.
Both are flagged because confirming them requires a build, and this skill's v1 scope is methodology and specification, not a runnable harness.
