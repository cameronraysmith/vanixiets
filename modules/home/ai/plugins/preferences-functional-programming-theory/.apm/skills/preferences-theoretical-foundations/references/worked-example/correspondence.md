---
title: Correspondence between Limit.lean and limit.py
---

## What the example computes

The example recovers the posterior over the immigration rate lambda of a stochastic immigration-death process by Approximate Bayesian Computation over an exactly-simulated (Gillespie/SSA) likelihood.
The process is the pair of reactions immigration (rate lambda) and death (rate mu times the current count), and with mu fixed to one it is Poisson-stationary with mean lambda, so the recovered posterior must concentrate near the truth.
That stationary identity is the whole reason the program can check that it did inference rather than theatre: the printed `recovered : YES` line asserts the truth `TRUE_LAM = 4.0` lies inside the 90% credible interval, and because the seed is fixed (`random.Random(20260620)`) the result is deterministic.

The two files are the same construction expressed at two altitudes.
`limit.py` is the runnable artifact; `Limit.lean` is the idealized type system underneath it.
The example exists to make one thing concrete: the static gap between what Lean checks in the type and what Python can only assert at runtime.
Every place where Python leaves a `# STATIC-GAP:` comment is a place where Lean has discharged the obligation in the type, machine-checked, before the program ever runs.

`Limit.lean` type-checks under `leanprover/lean4:v4.30.0-rc2` with Lean 4 core only, no Mathlib, and `lake build` is clean.
`limit.py` runs as a uv script (`uv run limit.py`), stdlib-only, with the import-time `_check_laws()` property checks passing.

## The four static gaps, gap by gap

The line references below are to the final files in this directory.

### Gap 1 — graded modality: the grade lives in the type

In Lean the grade is a type-level index, not a runtime value.
`Prog S g α` is a program over signature `S` of grade `g` returning `α`, declared as the graded free monad at `Limit.lean:72-75`, where the `op` constructor forces the resulting grade to be `S.cost o + g` by construction.
The consequence is visible at `Limit.lean:102-104`: `draw` has type `Prog draws ⟨1, 0⟩ Float`, so its grade is forced by the type rather than asserted, and at `Limit.lean:154-157` `propose` is typed `Prog draws ⟨2, 0⟩ Command`, its two-draw cost fixed statically.
The `#check` lines at `Limit.lean:268-269` confirm the elaborator agrees: it prints `draws := 1` and `draws := 2` for the two programs.

In Python the same grade is a runtime dataclass.
The `# STATIC-GAP:` marker at `limit.py:48-50` states it directly: the `Grade` class at `limit.py:53-58` tracks the effect as a value the handler accumulates, so the bound is observed at run time, not proven before it.
The handler's `grade` field is updated by each interpreter (for example at `limit.py:88-90` and `limit.py:96-98`), which is exactly the accumulation that Lean erases because the index already carries it.

### Gap 2 — dependent decide: the event type depends on the command

In Lean the move event is indexed by the reaction it came from.
`Moved : Reaction → Type` at `Limit.lean:113-115` has constructors `born : Moved .birth` and `died : Moved .death`, so a `Moved .birth` value can only be `born`.
The dependent decision function `moveOf : (r : Reaction) → Moved r` at `Limit.lean:120-122` therefore cannot map `.birth` to `.died`; the commented line at `Limit.lean:124-125` records that `example : Moved .birth := .died` is rejected by typing.
`decideBD` consumes this at `Limit.lean:172`, emitting `Event.moved (moveOf c.rxn)`, so the produced event cannot contradict the command that produced it.

In Python the obligation is left as a comment.
The `# STATIC-GAP:` marker at `limit.py:135-136` sits inside `decide` (`limit.py:134`) and says that in `Limit.lean` a dependent type makes the return type depend on the command, so a birth-command cannot yield a `Died`, whereas Python erases that obligation.
The Python `decide` at `limit.py:138` selects `Born()` or `Died()` by an ordinary string test on `c.reaction`, with nothing stopping a mismatched pairing other than the programmer's care.

### Gap 3 — exhaustiveness: evolve is total and the impossible case is unwritable

In Lean the fold is total over a closed event type.
`evolveBD` at `Limit.lean:178-183` matches `dwelt`, `moved .born`, `moved .died`, and `halted` with no catch-all and no unreachable branch, because the `moved` constructor only admits `born` and `died`.
There is no line to write for a non-exhaustive case; the totality checker accepts the definition precisely because every case is covered.

In Python the missing case is a runtime guard.
The `# STATIC-GAP:` marker at `limit.py:146` is the `raise AssertionError("non-exhaustive")` at the end of `evolve` (`limit.py:141`), reachable only if some future edit introduces an event variant the `isinstance` ladder does not handle.
That `AssertionError` is the line `Limit.lean` is, by construction, not permitted to write.

### Gap 4 — static effect row: programs are indexed by the signature

In Lean the effect row is a first-class signature carried in the program's type.
`Sig` at `Limit.lean:53-56` bundles the operation type, each operation's return type, and each operation's grade, and `Sig.sum` at `Limit.lean:60-63` composes rows as the coproduct of theories.
`Prog` is indexed by `S : Sig` at `Limit.lean:72`, so the row a program may use is fixed in its type, and the concrete one-effect row `draws` is defined at `Limit.lean:97-100`.
A program over `draws` cannot silently reach for a capability outside that signature.

In Python the effect row is documented but untyped.
The effect-signature section at `limit.py:60-75` describes the capability interface, but `Eff = Iterator` at `limit.py:71` makes an effectful program merely an iterator, and the `Handler` protocol at `limit.py:73-75` accepts any `Effect` without a type-level row.
Which capabilities a generator actually demands is observable only by running it and seeing what it yields, not stated in its type.

## The open frontier: the trajectory's grade is existential

This is the open frontier, presented as a conjectural synthesis, and it is not a fifth gap.
A single step has static grade `⟨2, 0⟩` (`propose`), but the full simulation runs an unbounded, data-dependent number of steps, so the strongest type any system can give the whole run is an existential grade.
`Limit.lean:261` records this as `abbrev Trajectory := Σ g : Grade, Prog draws g (List Event)`: the `Σ` is where static grading stops, because graded modalities pin the grade only where control flow is statically bounded and unbounded recursion hands back an existential.
The surrounding prose at `Limit.lean:246-259` states the position: closing this in a single calculus is not a known result but a conjectural synthesis of four research lines that remain unintegrated — quantitative/graded type theory, multimodal type theory, higher-order (scoped/hefty) algebraic effects, and call-by-push-value / adjoint logic.
The fragments are in hand; the unifying calculus is anticipated but unbuilt.
The same field-level claim appears in the Python header at `limit.py:25-31`, kept deliberately distinct from the four local gaps.

## Driving toward the limit even in Python

The reading the example invites is that Python drives toward the same limit object, tracking at runtime what Lean checks statically.
The grade that Lean carries as a type-level index, Python accumulates as the `Grade` value the handler updates, and the final `effect grade` line of the output reports it.
The dependent pairing that Lean makes unrepresentable, Python preserves by discipline in `decide` and would only break with an `AssertionError`.
The exhaustiveness Lean proves, Python approximates with the runtime guard at `limit.py:146`.
The effect row Lean indexes by `Sig`, Python keeps as a yielded-request convention.
Observability is the one place where Python reaches the same standard as Lean: the projection law `project(xs ++ ys) == project(xs) + project(ys)` is asserted as a property check at `limit.py:217-219` and is proved as the monoid-homomorphism theorem `project_hom` at `Limit.lean:242-244`, itself a corollary of `fmap_hom` at `Limit.lean:217-221`.
In both files this is observability recovered as a theorem rather than a logging convention; in Lean it is machine-checked, and it depends on no `sorry` and no added axiom.

## Upgrade path: a verified Lean-to-Rust round trip

When the implementation is Rust rather than Python, the same `Limit.lean` specification feeds the `refinement-driven-development` skill for a verified Lean-to-Rust round trip.
The pipeline lowers the spec to a Rust implementation and lifts the implementation back as Rust to Charon to LLBC to Aeneas to Lean, so that spec and implementation can be checked for correspondence by translation validation, mechanically when tractable and otherwise by differential testing or comparison.
At that point the file would add the Aeneas Lean library dependency pinned to rev `fa699427cdfa8f604b891fb0223ef42883dd7dc4`, matching the `flake.lock` aeneas pin, under toolchain `v4.30.0-rc2`, which is the reason the toolchain here is pinned to the Aeneas backend's own version even though the file imports nothing from Aeneas today.
Python, by contrast, gets the human and differential verification tier rather than the mechanical one.
This Rust tier is intentionally left to a separate session and is not implemented here.
