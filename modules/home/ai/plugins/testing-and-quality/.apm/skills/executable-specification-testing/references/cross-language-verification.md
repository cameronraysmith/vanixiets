# Cross-language verification matrix

This matrix places the three modalities this skill owns — property-based testing, design-by-contract or refinement, and SMT/concolic checking — across five languages.
Cells grounded in a local clone cite its source path.
Cells resting on model knowledge are marked *(model knowledge)* explicitly, and the one deliberate exclusion (Aeneas is not in the SMT column) is stated where it would otherwise be miscategorized.

Local clones read for this matrix live under `/Users/crs58/projects/rust-workspace/`, `/Users/crs58/projects/haskell-workspace/`, `/Users/crs58/projects/python-workspace/`, and `/Users/crs58/projects/functional-programming-workspace/`.

## The matrix

| Language | PBT | DbC / refinement | SMT / concolic |
|---|---|---|---|
| Python | Hypothesis (strategies; icontract-hypothesis infers a strategy from `@require` bounds) | icontract (`@require`/`@ensure`/`@invariant`, runtime); deal as a peer dialect | CrossHair (concolic, Z3-backed `StateSpace`) |
| Rust | proptest (`Strategy`/`ValueTree`, integrated shrinking); proptest-state-machine (stateful) | `contracts` crate (runtime `assert!`); nutype (refinement newtypes / smart constructors) | Kani (CBMC, SAT/SMT), Creusot (Why3→SMT), Prusti (Viper→Z3) — **not Aeneas** |
| Haskell | QuickCheck (manual/separate shrink); Hedgehog (integrated shrink) | LiquidHaskell (`{-@ ... @-}` refinement types) | SBV (symbolic values → SMT-LIB2, `prove`/`sat`) |
| Lean 4 | Plausible (`Testable`/`SampleableExt`/`Shrinkable`, the `plausible` tactic) | dependent/refinement types native to the type theory (subtypes `{x // p x}`) | SMT tactics via external solver *(model knowledge)* — the Charon/Aeneas path is **functional translation, not SMT** (a `refinement-driven-development` handoff) |
| TypeScript | fast-check *(model knowledge)* | runtime validators / smart constructors, e.g. zod, io-ts *(model knowledge)* | research gap: ExpoSE, SymJS *(model knowledge)* |

## Python

PBT is Hypothesis, and the single-contract thesis' strategy-inference bridge (icontract-hypothesis) is detailed in `single-contract-hub.md`.
DbC is icontract (the runtime `require`/`ensure`/`invariant` bearer), with deal as the documented peer dialect CrossHair also parses.
SMT/concolic is CrossHair, driving a Z3-backed symbolic execution per example.
All three are the safeadt worked example's Python pillars.

## Rust

PBT: proptest's `Strategy` trait with integrated shrinking through `ValueTree` (`proptest/proptest/src/strategy/traits.rs:37-60, 580-620`), and the stateful/model-based angle in proptest-state-machine (`ReferenceStateMachine` + `StateMachineTest`, `proptest/proptest-state-machine/src/strategy.rs:45-113`, `.../test_runner.rs:19-99`).

DbC/refinement: the x52dev `contracts` crate is the direct icontract analog — proc-macro `#[requires(...)]`/`#[ensures(...)]`/`#[invariant(...)]` lowering to runtime `assert!`, with `old()`, a synthesized `->` implication, and mode variants (`debug_*`, `test_*`) (`contracts/src/lib.rs:83-355`).
nutype supplies refinement newtypes / smart constructors: `#[nutype(...)]` with `sanitize`/`validate` generates a fallible `try_new(...) -> Result<Self, _>` that makes an invalid value uninstantiable, the "illegal states unrepresentable" idiom (`nutype/nutype/src/lib.rs:1-269`, `nutype/nutype_macros/src/string/generate/mod.rs:96-126`).

SMT/concolic: three solver-backed verifiers.
Kani is a bit-precise bounded model checker on CBMC (SAT/SMT); its `#[kani::proof]`/`requires`/`ensures`/`proof_for_contract`/`modifies` surface needs `-Zfunction-contracts` (`kani/library/kani_macros/src/lib.rs:361-458, 97-105`; README:5).
Creusot is a deductive verifier translating Rust to Coma to Why3, which dispatches verification conditions to SMT solvers (Z3, CVC4/5, Alt-Ergo); its spec macros encode Pearlite terms only under `cargo creusot` (`creusot/creusot-std-proc/src/lib.rs:42-87`, `.../creusot/specs.rs:23-100`, `creusot/README.md:27`).
Prusti builds on the Viper infrastructure (Silicon/Carbon → Z3), separation-logic-based (`prusti-dev/prusti-contracts/prusti-contracts/src/lib.rs:1-46`, `prusti-dev/README.md:9`).

The Aeneas exclusion: Aeneas is a verification toolchain that *translates* Rust's MIR to a pure lambda calculus for a proof assistant (Lean, Coq, HOL4, F\*) via the Charon frontend (`functional-programming-workspace/aeneas/README.md`), with no SMT solver in its core translation loop.
Kani, Creusot, and Prusti are solver-backed and belong in the SMT/concolic column; Aeneas is a functional-translation-and-proof path owned by `refinement-driven-development` and is deliberately not in this column.
The distinction is the discharge mechanism, not the attribute syntax (which looks similar across `contracts`, Creusot, Kani, and Prusti): runtime `assert!` for `contracts`/nutype versus compile-time solver proof for Creusot/Kani/Prusti versus functional translation for Aeneas.

## Haskell

PBT: the manual-versus-integrated shrinking contrast lives here.
QuickCheck's `Arbitrary` has separate `arbitrary`/`shrink` with `shrink _ = []` by default and a `Gen a` that carries no shrink information (`quickcheck/src/Test/QuickCheck/Arbitrary.hs:234, 251, 323-324`; `.../Gen.hs:66-67`).
Hedgehog's generator runs to a shrink tree (`GenT m a` → `TreeT (MaybeT m) a`), deriving shrinks automatically, with a `Range` origin (`hedgehog/hedgehog/src/Hedgehog/Internal/Gen.hs:257-266`, `.../Internal/Range.hs:80-105`).

DbC/refinement: LiquidHaskell attaches refinement types via `{-@ ... @-}` annotations; for a function the refinements "become pre and post conditions" (`liquidhaskell/docs/mkDocs/docs/specifications.md:44-48`).
Obligations discharge to an SMT solver with Z3 first in the auto-detect order `[Z3, Cvc5, Cvc4, Mathsat]` (`liquidhaskell/liquidhaskell-boot/src/Language/Haskell/Liquid/UX/CmdLine.hs:509-524`).
LiquidHaskell straddles the refinement and SMT columns — it is a refinement-type system whose checking is SMT-discharged; placed under DbC/refinement here because its *authoring surface* is refinement types, with the solver as the discharge mechanism.
(Its actual Z3 process invocation lives in the separate liquid-fixpoint dependency, not grounded in this clone; only solver *selection* is grounded here.)

SMT: SBV ("SMT Based Verification") — symbolic values `SBV a`/`SVal` compiled to an SMT-LIB2 script and dispatched by `prove :: ... -> IO ThmResult` / `sat :: ... -> IO SatResult`, with a `Solver` enum including Z3 and CVC5 and `defaultSMTCfg = z3` (`sbv/Data/SBV/Core/Data.hs:113`, `.../Client/BaseIO.hs:49-79`, `.../Core/Symbolic.hs:2303-2313`).

## Lean 4

PBT: Plausible is the Lean 4 property-testing framework, integrated into the tactic framework as `plausible`; a user type needs `Repr`, `Plausible.Shrinkable`, and `Plausible.SampleableExt` (or `Arbitrary`) instances, with `Testable` as the checkable-proposition class (`functional-programming-workspace/plausible/Plausible/{Shrinkable,Sampleable,Testable}.lean`; README).

DbC/refinement: refinement is native to the dependent type theory itself — a subtype `{x : α // p x}` carries its predicate in the type, so the "contract" is a type rather than a runtime assertion.
This is qualitatively different from the runtime-assert DbC of the other rows and is the value-level-shadow relationship the SKILL body's theory-mapping section names in reverse: Python's icontract predicate is the shadow of what Lean carries in the type.

SMT/concolic: Lean has SMT tactic frontends (e.g. `lean-smt`, and `omega` for linear integer/nat arithmetic) *(model knowledge — no local lean-smt clone was read)*.
The Charon/Aeneas path is *not* this cell: it is a functional translation of Rust into Lean for translation validation, owned by `refinement-driven-development`, and naming it under Lean's SMT column would be the same miscategorization the Rust row's Aeneas exclusion guards against.

## TypeScript

This entire row is *model knowledge* — no TypeScript verification clones were read for this matrix, and fast-check is known here only secondhand as the vehicle `preferences-algebraic-laws` names.
PBT: fast-check (arbitraries, integrated shrinking) *(model knowledge)*.
DbC/refinement: TypeScript has no widely-adopted native design-by-contract; the practical stand-in is runtime validators used as smart constructors (zod, io-ts) that make an invalid value uninstantiable at a boundary *(model knowledge)*.
SMT/concolic: an explicit research gap — symbolic execution for JavaScript exists in research tools (ExpoSE, SymJS) but there is no mainstream, maintained SMT/concolic checker for TypeScript comparable to CrossHair or Kani *(model knowledge)*.
Treat the TypeScript SMT cell as unfilled and flag it if a task depends on it.
