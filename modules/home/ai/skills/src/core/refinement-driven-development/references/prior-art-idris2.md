# Prior art: ironstar's Idris2 spec and Rust crates

The ironstar template is the closest existing prior art for this skill's loop, and it is the substrate for the later full-loop test exercise.
It already practices the spec-leads-implementation half of refinement-driven development by hand: a dependently-typed Idris2 specification at `~/projects/rust-workspace/ironstar/spec` defines the domain model, algebraic laws, and proof terms, and a Rust workspace at `~/projects/rust-workspace/ironstar/crates` realizes those specifications as concrete types and trait implementations.
What ironstar does *not* yet have is the mechanized lift: no Charon, Aeneas, LLBC, or Lean material exists in the repository today, so its spec-to-code relationship is maintained entirely by hand and by tests.
That missing half is exactly what the later exercise targets, and this reference mines ironstar read-only to prepare for it; the actual Idris2 to Lean 4 re-modeling is the user's test of the finished skill, not work performed now.

## Contents

- [How the spec and crates mirror each other](#how-the-spec-and-crates-mirror-each-other)
- [Where dependent types actually appear](#where-dependent-types-actually-appear)
- [Correspondence patterns: clean versus awkward](#correspondence-patterns-clean-versus-awkward)
- [An Idris2 to Lean 4 pattern-mapping table](#an-idris2-to-lean-4-pattern-mapping-table)
- [What the later full-loop test exercise involves](#what-the-later-full-loop-test-exercise-involves)
- [Uncertainties to confirm against source](#uncertainties-to-confirm-against-source)

## How the spec and crates mirror each other

The Idris2 spec is organized as five `Core.*` abstraction modules (Decider, View, Saga, Effect, Event), a `SharedKernel.UserId` module, and four bounded contexts (Analytics as the core domain, Session and Workspace as supporting, Todo as a generic example), with `%default total` set in every module.
The whole pattern family descends from Jérémie Chassaing's Decider, realized in Rust via the `fmodel-rust` dependency (a local clone lives at `~/projects/rust-workspace/fmodel-rust`).
The central abstraction is a record of three function fields: `decide :: c -> s -> Either err (List e)` (the coalgebra unfolding commands into events), `evolve :: s -> e -> s` (the algebra folding events into state, deliberately total), and `initialState :: s`.
The totality of `evolve` is itself the encoding of the domain fact that events are historical and cannot fail.

The Rust workspace mirrors this as eleven crates in four layers: a foundation (`ironstar-core`, `ironstar-shared-kernel`), the domain crates (`ironstar-todo`, `ironstar-session`, `ironstar-analytics`, `ironstar-workspace`), infrastructure, and the `ironstar` binary as composition root.
The spec deliberately stops at the domain boundary: the binary and the two infrastructure-only crates carry no spec counterpart.
Each domain crate decomposes one Idris module into many files (`commands.rs`, `events.rs`, `state.rs`, `errors.rs`, `values.rs`, `decider.rs`, `view.rs`), and the Rust runs roughly two-to-three times the line count of the spec it realizes.
`ironstar-core` re-exports `fmodel-rust` under ironstar names so domain crates depend only on `ironstar-core`, and the Rust `Decider` is the `fmodel-rust` struct of boxed closures, `Decider { decide: Box::new(...), evolve: Box::new(...), initial_state: Box::new(|| None) }` — exactly the `Box<dyn Fn>` plus lifetime form the Idris spec documents as eliminated.

The single most important design premise, stated in `spec/README.md`, is that where Idris2 can express properties as compile-time proof terms — deterministic replay, monoid laws, purity — the Rust side maintains those invariants by convention and by testing.
The spec layer carries proofs the implementation language cannot, and the implementation re-asserts them operationally.
This is the human-driven analogue of the loop this skill mechanizes, and it is the central prior-art lesson.

## Where dependent types actually appear

A survey over `spec/**/*.idr` shows the genuinely dependent, proof-carrying machinery is concentrated in `Core/Event.idr` and `Core/Decider.idr`; the domain modules use only plain sum types and records.
`Core/Event.idr` carries `EventIdLT`, a value-level proof of strict ordering with an erased Bool-equality witness `(0 prf : x < y = True)`, and `MonotonicIds`, a proof that an event-ID list is monotonically increasing.
The module header is honest that `MonotonicSequence` and `SessionIsolation` are sketched but not fully proven, and `FailureEventPreservesState` leaves its proof obligation in comments rather than in code.

Erased zero-quantity proof terms — runtime-irrelevant lemmas — live across the Core modules.
`Decider.idr` carries `decideIsPure` (an explicit postulate, since user `decide` purity cannot be proven), `evolveIsDeterministic`, `replayDeterministic` (all `= Refl`), and `foldlAssociative` (the snapshot-correctness lemma, proved by structural induction).
`Event.idr` carries the free-monoid laws `appendLeftIdentity`, `appendRightIdentity`, `appendAssociative`.
`View.idr` carries `projectDeterministic` (`Refl`) and `projectIncremental`, the one outright-postulated nontrivial law, currently `believe_me ()` with the inductive proof sketched in comments.
`Saga.idr` carries `reactIsPure`, `identityLaw`, `emptyLaw`.
The full proof-term inventory is the exact checklist the later check step must re-establish on the lifted model.

The dominant illegal-states-unrepresentable technique is plain sum types as state machines, not `Dec`, dependent pairs, `Subset`, or refinement.
`TodoState` is a four-case sum (`NonExistent`, `Active`, `CompletedTodo`, `DeletedTodo`) whose invalid transitions are ruled out by pattern matching in `decide` rather than by the type of `decide` itself; idempotency is encoded as returning `Right []` rather than an error.
Two caveats matter for the port.
First, the Session `decide` is not total: it uses Idris holes for boundary-supplied effects (`?newSid`, `?now`, `?expires`, `?metadata`), so the spec is a typed skeleton rather than a runnable total program.
Second, refinement-style smart constructors are largely deferred in Idris and pushed to Rust — `validateChartData` is a runtime check, not a type-level constraint — and the cross-layer report flags this as a gap (GridSize allows zero, string-length bounds undocumented).

## Correspondence patterns: clean versus awkward

The records of function fields port cleanly: the Idris `record Decider`, `record View`, and `record Saga` each match the corresponding `fmodel-rust` struct structurally, with the awkwardness being incidental Rust complexity (boxing, lifetimes, `Send + Sync`) that the pure Idris model elides.
The `Sum`/`combine` composition (coproduct on commands and events, product on state) also maps cleanly, though Rust uses trait dispatch where Idris uses a record.
The n-ary `SumN`/`combineN` ladder is hand-rolled per arity (2, 3, 5) with no generic heterogeneous-list composition — a candidate awkwardness worth revisiting in Lean 4.

Two correspondences genuinely do not map to types.
The dependent ordering proofs `EventIdLT` and `MonotonicIds` have no Rust equivalent and survive only as convention plus runtime check.
The zero-quantity proof terms map not to types but to tests: `fmodel-rust`'s `DeciderTestSpecification` Given/When/Then builder re-asserts each law by example across the domain crates.

The headline awkwardness is the sum-type state collapsing into a flat struct.
The Idris `TodoState` is a four-case sum making each state's payload exact; the Rust `TodoState` is a single struct with every field `Option`-wrapped and a separate `TodoStatus` enum (`NotCreated`, `Active`, `Completed`, `Deleted`).
The state-machine encoding then splits across two type layers: `NonExistent` is pushed out to `Option<TodoState>` at the decider type (`None` versus `Some`), while the other three cases live in `TodoStatus`.
The flat encoding forces a defensive exhaustiveness fallback in `decide` — a `Some(_)` delete arm commented "this should never happen in normal operation but provides exhaustiveness" — for a case the Idris sum type renders genuinely unreachable.
This is concrete evidence that the Rust encoding re-admits states the Idris type excludes, and it is exactly where the lift and check must reconcile.

The refinement direction runs the unusual way here: Rust is richer than the spec.
`BoundedString<const MIN, const MAX>` is a const-generic parse-don't-validate refinement (used to build `DashboardTitle = BoundedString<1,200>` and the like), validated inside `decide` via `TodoText::new(...)`, while the Idris spec carries no such bounds.
A Lean 4 spec is the natural place to pull ahead, promoting those bounds into subtype refinements so the lifted Rust validation has a spec-level property to be checked against.

One live divergence is worth flagging because the lift would surface it.
The Idris spec models `UserId` as the composite `(provider, externalId)`, while the Rust uses a canonical `UserId(Uuid)` with the composite handled by a separate lookup table.
A January-dated cross-layer consistency report records UserId as "resolved to composite key," but both the Rust source and the spec README are newer and record the UUID-surrogate design as superseding it; treat the report as stale on that point and the composite-spec versus UUID-impl mismatch as a real correspondence divergence.

## An Idris2 to Lean 4 pattern-mapping table

The mapping below distills the constructs the later re-modeling will encounter.
It is the concrete payload of this reference: a faithful Idris-construct to Lean-construct correspondence, with the awkward cases flagged.

| Idris2 construct | Lean 4 target | Notes |
|---|---|---|
| `record Decider (c s e err) where constructor MkDecider; decide; evolve; initialState` | `structure Decider (c s e err : Type) where decide; evolve; initialState` | Anonymous `⟨_, _, _⟩` or named `{ decide := … }` covers `MkDecider`; `d.decide` projection matches 1:1 |
| `data Sum a b = First a \| Second b` | `inductive Sum (a b : Type) \| first : a → Sum a b \| second : b → Sum a b`, or built-in `a ⊕ b` | The `Sum3`/`Sum5` flatteners port as plain inductives; check whether nested `⊕` or `Sigma` retires the hand-rolled arity ladder |
| `Functor`/`Bifunctor` instances | `instance : Functor (Sum a) where map := …` | Lean `map` is `f <$> x`; law classes (`LawfulFunctor`) are separate from the operation class |
| zero-quantity lemma `0 foldlAssociative : …` | `theorem foldlAssociative …` in `Prop` | Lean has no quantity annotation, but `Prop` is proof-irrelevant and erased; `= Refl` becomes `rfl`, `cong (x ::)` becomes `congrArg (x :: ·)`, structural induction becomes `induction`/`simp` |
| `believe_me ()` (postulated `projectIncremental`) | `sorry`, or a real proof via `List.foldl_append` | This is the lemma to genuinely close in Lean rather than postulate |
| equality-witness GADT `EventIdLT` with `(0 prf : x < y = True)` | a `def`/`abbrev` returning `Prop`: `a.unEventId < b.unEventId` | Drop the Bool-to-`True` coercion; use the `Prop`-valued `<` directly |
| `MonotonicIds` bespoke inductive | `List.Chain'` / `List.Sorted` from core/Mathlib | The Idris version is an admitted sketch; reuse the library predicate |
| `{x, y : Integer}`, `{auto 0 prf : NonEmpty eids}` | `{x y : Int}` implicit; `[inst : …]` or `(prf : … := by …)` autoparam | No `auto` keyword in Lean; instance-implicit or autoparam serves |
| free lowercase autoimplicit type vars | explicit binders or `variable` declarations | Lean has no top-level autoimplicit inference; every variable must be bound |
| typed holes `?newSid`, `?now` | actual parameters (as Rust lifted them to command fields), not `sorry` | A compiling spec resolves the holes rather than deferring them |
| `%default total` | total by default | All Lean `def`s must terminate; the Idris non-covering `decide` will not compile until holes are resolved |
| `interface EventRepository … : IO (…)` | `class EventRepository (e err) where append : … -> IO (…)` | Ports cleanly; default methods (`publishAll`) become fields with `:= …` or a sibling `def` |
| `Either String` errors (Session) versus closed `TodoError` ADT | prefer the closed-ADT error everywhere | Bare `String` loses information the check needs to pattern-match expected failures |
| `BoundedString<MIN,MAX>` bound (Rust-only today) | a Lean refinement `{ s : String // 1 ≤ s.length ∧ s.length ≤ 200 }` | Promote into the spec to give the lifted Rust validation something to check against; closes the GridSize/string-bound gaps |
| `import public` re-export | `export` / `open … in`, or a hub module that `import`s and re-`export`s | Lean module path equals file path, so the directory layout ports directly |

For the dependently-typed modeling fragment this table feeds, see `references/lean-spec-patterns.md`; for the subtype-and-refinement promotion in the last two rows, see also `preferences-domain-modeling`.

## What the later full-loop test exercise involves

The user's test of the finished skill is to run ironstar through the entire loop: re-model the Idris2 spec as a Lean 4 spec, refine/lower it to or reconcile it with the existing Rust crates, lift the Rust back via Charon plus Aeneas into Lean 4, and check the lifted model against the Lean 4 spec.

The re-model step ports `Core.Decider`/`View`/`Saga`/`Effect`/`Event`, the `SumN`/`combineN` ladder, the bounded-context state machines, and the erased proof terms into Lean using the mapping table above; `references/lean-spec-patterns.md` carries the executable and decidable fragment guidance, and Plausible for the property restatements.
The refine-and-lower step must be written so the known spec-to-code divergences reconcile: the Lean state ADT should map onto the Rust `Option<struct>` plus status encoding, and the const-generic `BoundedString` bounds should be promoted into Lean refinement types so the check has something to validate against.
The Aeneas/Charon-safe Rust subset and ownership-intent annotations for this step are in `references/refine-and-lower.md`.
The lift step is brand-new for ironstar — there are no existing Charon or Aeneas artifacts — and the realistic translatability risks to scope are the `fmodel-rust` boxed closures, trait-object dispatch, the `chrono`/`uuid`/`serde` dependencies, and `tracing::instrument` attributes, since Aeneas produces a semantics-preserving functional translation rather than a transpiler output; `references/lift-charon-aeneas.md` covers the Charon-then-Aeneas invocation, symbolic execution, and backward functions.
The check step establishes correspondence between the hand-written Lean spec and the Aeneas-lifted Lean functional model — does the lifted `decide`/`evolve` satisfy the spec's purity, total-evolve, replay-determinism, free-monoid append, and incremental-projection laws — using the proof-term inventory as the checklist; `references/check-translation-validation.md` describes the three check tiers and the refinement-versus-equivalence framing.

Two ironstar methodology documents are themselves prior art for the check, since they record the human-driven reconciliation ironstar actually performed: a D2-to-Idris cross-reference that classifies every command, event, and read-model as aligned, semantic-match, missing, intentional, or extra, and a cross-layer consistency report giving a severity-graded discrepancy matrix.
These are the manual translation-validation that the mechanized check is meant to replace.

## Uncertainties to confirm against source

A few claims here are sketched in ironstar itself and should be confirmed against source before the exercise leans on them.
It is not settled whether real property tests (`proptest!` macro bodies) exist versus only example-based `DeciderTestSpecification` Given/When/Then; the Todo decider tests inspected were example-based, and the `proptest` mentions matched mostly README and re-export lines, so treat the laws as verified by example primarily.
The exact `fmodel-rust` 0.9 surface for `View`/`Saga`/`Aggregate` was read through ironstar's re-exports and usage rather than upstream source; consult `~/projects/rust-workspace/fmodel-rust` directly for the `Decider`/`Sum` definitions when assessing lift translatability.
The `MonotonicIds` `MonoCons` constructor as written appears to be a sketch that does not thread the ordering proof, so treat `MonotonicIds` as aspirational, not load-bearing, when porting (the `List.Chain'`/`List.Sorted` substitution in the table is the cleaner target anyway).
Finally, the Analytics and Workspace per-aggregate modules were not exhaustively line-cited; they follow the same Decider-plus-sum-state-plus-`Either`-error shape, but specific command and event names should be read from source per aggregate when porting them.
