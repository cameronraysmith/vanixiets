# Lean 4 specification patterns

The first leg of the pipeline writes the specification in Lean 4, before any Rust exists.
This reference covers how to model a domain in Lean 4 so that illegal states cannot be constructed, so that the spec stays *runnable*, and so that it can be differentially tested against the lifted model later in the check leg.
The throughline is a single discipline: keep the spec inside the executable, decidable, computable fragment of Lean, because a spec you cannot `#eval` is a spec you cannot differentially test against the Aeneas-produced model.

## Contents

- [Making illegal states unrepresentable](#making-illegal-states-unrepresentable)
- [Smart constructors](#smart-constructors)
- [The decidability layer](#the-decidability-layer)
- [A domain DSL via notation and macros](#a-domain-dsl-via-notation-and-macros)
- [The executable, decidable, computable fragment](#the-executable-decidable-computable-fragment)
- [Property-based testing with Plausible](#property-based-testing-with-plausible)
- [omega scope](#omega-scope)

## Making illegal states unrepresentable

The principle is the same one `preferences-domain-modeling` states for ordinary algebraic types, sharpened by dependent typing: an inhabitant of the type carries a proof that its invariant holds, so the invalid value has no representation at all rather than merely being discouraged.
Lean 4 offers a small palette of constructs for this, ordered roughly by how much proof machinery they pull in.

A subtype `{ x : T // p x }` desugars to `Subtype (fun x => p x)`, a structure whose two fields are a carrier `val : T` and a proof `property : p val`.
The proof is a real field, so you cannot build a `{ n : Nat // n % 2 = 0 }` from an odd number, and `{ xs : Array String // xs.size = 5 }` is precisely the arrays of exactly five strings.
This is the canonical output type for a smart constructor: a function returning `{ x : T // p x }` cannot return an `x` that violates `p`, and downstream code reads the witness back off `.property`.

```lean
def Even := { n : Nat // n % 2 = 0 }

def double (n : Nat) : Even := ⟨2 * n, by omega⟩
```

`Fin n` is the same shape specialized to bounded naturals: a `Nat` `val` paired with a proof `isLt : val < n`.
A `Fin n` coerces to `Nat` (it carries `attribute [coe] Fin.val`), so it is usable wherever a `Nat` is expected while statically carrying its bound; use it for indices into fixed-size collections so out-of-bounds access is unrepresentable.
Equality on `Fin` is decided by the `val` component alone — the bound proof is irrelevant — which is what keeps `Fin` in the decidable fragment.

Length-indexed vectors lift the size into the type.
The core `Vector α n` (distinct from mathlib's older `List.Vector`) is a structure wrapping `Array α` together with a proof `size_toArray : toArray.size = n`.

```lean
structure Vector (α : Type u) (n : Nat) where
  toArray : Array α
  size_toArray : toArray.size = n
deriving Repr, DecidableEq
```

The `#v[...]` literal is a macro that supplies the length proof `rfl` automatically, and `deriving DecidableEq` keeps vectors in the executable fragment out of the box.
Reach for a length-indexed vector when the index must gate which operations type-check — zipping two vectors of equal length, indexing without a runtime bounds check.

Indexed inductive families are Lean's GADTs: an `inductive` whose result type varies per constructor over an index.
The archetype is propositional equality `Eq`, whose sole constructor `refl` forces its two indices to coincide.
There are two distinct uses, and choosing between them and a plain structure-with-invariant is the main modeling decision.
Use an indexed inductive *predicate* — a family landing in `Prop` — when the legal set is defined by a closed inductive grammar with no decision procedure baked in; the only inhabitants are the things buildable by the rules, so an ill-formed value simply has no proof term.
The RPN well-formedness predicate below is exactly this.
Use an indexed inductive *type* — a family landing in `Type` — when the index itself must drive which operations type-check, as with a length-indexed vector, a session-typed channel, or a tagged AST where `Expr Bool` versus `Expr Nat` rules out type errors.
Use a plain structure with a separate `Prop` invariant when the invariant is a side condition over an otherwise ordinary product and you want the data to stay first-class and projectable.
Indexed families cost more in dependent pattern-matching and recursion, so prefer the structure-plus-invariant form when the index is not needed to gate operations.

```lean
inductive Token where
  | Num : Int → Token
  | Plus | Minus | Mul | Div : Token
deriving Repr, DecidableEq

inductive WellFormedRPN : List Token → Prop where
  | num (n : Int) : WellFormedRPN [Token.Num n]
  | binop (e1 e2 : List Token) (op : Token)
      (h1 : WellFormedRPN e1) (h2 : WellFormedRPN e2) (hop : is_binop op) :
      WellFormedRPN (e1 ++ e2 ++ [op])
```

This block is the spec-side adaptation: it uses unbounded `Int` plus a constructive `DecidableEq`, in contrast to the lifted model's `I64` and `BEq`.

The structure-with-invariant pattern comes in two flavours.
The invariant can live *inside* the structure as a proof field, as in `Subtype`, `Fin`, and `Vector`, so it travels with every value.
Or the invariant can be a *separate* predicate over a plain structure, asserted at the boundaries that need it.
The separate-predicate flavour dominates the lifted-model side of the pipeline, because Aeneas emits plain structures (see `references/lift-charon-aeneas.md`) and the human writes the invariant alongside; the gap-buffer example below is the canonical case.

## Smart constructors

A smart constructor validates its input and returns a wrapped result rather than an unchecked value, the pattern `preferences-domain-modeling` and `preferences-railway-oriented-programming` both build on.
In plain Lean the two idioms are a function returning `Option T` for validate-or-nothing, and a function returning `Except E T` (`.ok` / `.error`) for validate-with-reason.

```lean
def mkPort (n : Nat) : Option { p : Nat // p ≤ 65535 } :=
  if h : n ≤ 65535 then some ⟨n, h⟩ else none
```

A dependent `if h : p then … else …` is the workhorse here: in the `then` branch you have `h : p` in scope, so you can produce the subtype witness or discharge a downstream index obligation.
This pattern is what later lets the lifted model's tag-dispatch decoders (a byte into a closed enum, failing on out-of-range) and length-checked deserializers stay total while still rejecting malformed input.
Keep these smart constructors total and decidable so the spec can run; the same sum-of-outcomes shape reappears on the lifted side as the Aeneas `Result` monad, covered in `references/lift-charon-aeneas.md`.

## The decidability layer

`Decidable p` is a class-inductive carrying *either* a proof of `p` *or* a proof of `¬p` — an algorithm that resolves the proposition with evidence.

```lean
class inductive Decidable (p : Prop) where
  | isFalse (h : Not p) : Decidable p
  | isTrue (h : p) : Decidable p
```

A `Decidable` instance does double duty: it powers `if`-expressions (the branch is selected at run time with codegen identical to a `Bool` conditional) and it powers the `decide` tactic (synthesize the instance, reduce it, and on `isTrue h` return the proof `h`).
The derived abbreviations `DecidablePred r`, `DecidableRel r`, and `DecidableEq α` are the pointwise, relational, and equality forms.
Bridge lemmas (`decide_eq_true`, `of_decide_eq_true`, and their false-side mirrors) move between the Boolean `decide p : Bool` world and the propositional `p : Prop` world; that bridge is exactly what makes a `decide`-backed spec both runnable and provable.

For closed enums and structures, `deriving DecidableEq` (and `deriving BEq` for a `Bool`-valued `==`, and `deriving Repr` for printing) generates the machinery, keeping the type in the decidable, executable fragment.

```lean
inductive DoorState where
  | Locked | Unlocked | Alarmed
  deriving DecidableEq, Repr
```

When a predicate is custom rather than auto-derived, you supply the decision procedure yourself.
The lightweight idiom builds the instance by tactic, letting `simp` plus instance inference do the work; the explicit idiom writes a recursive function returning `isTrue` / `isFalse` directly, which you then register as an instance.

```lean
instance (t : Token) : Decidable (is_binop t) := by
  cases t <;> simp [is_binop] <;> infer_instance

def no_div_tokens_dec : (ts : List Token) → Decidable (no_div_tokens ts)
  | [] => isTrue trivial
  | Token.Div :: _ => isFalse not_false
  | Token.Plus :: rest => no_div_tokens_dec rest
  | Token.Minus :: rest => no_div_tokens_dec rest
  | Token.Mul :: rest => no_div_tokens_dec rest
  | Token.Num _ :: rest => no_div_tokens_dec rest

instance (ts : List Token) : Decidable (no_div_tokens ts) := no_div_tokens_dec ts
```

There are two tactics that close a decidable goal, and the choice carries a trust cost.
`decide` reduces the `Decidable` instance *in the kernel* by definitional reduction: trustworthy, adds no axiom, but can be slow on large computations.
`native_decide` is a synonym for `decide +native`: it compiles the instance and runs it via `#eval`, which is fast on large computations but *adds the entire Lean compiler to the trusted computing base* and introduces an axiom visible in `#print axioms`.
Prefer plain `decide` for small obligations and reserve `native_decide` for genuinely large ones, accepting the trust cost knowingly.

The footgun that links decidability to computability: if a `Decidable` instance reduces to `Classical.choice` rather than to `isTrue`, `decide` fails with a diagnostic naming `Classical.choice`.
A classical decidability instance silently destroys the runnable fragment, which is why the next section forbids `Classical` in the executable path.

## A domain DSL via notation and macros

Lean's extensible-syntax stack lets the spec carry domain notation, which keeps the specification close to the language the domain experts use.
The layers, lowest to highest: `syntax` declares a new parser in a syntax category, and `macro_rules` (or a one-shot `macro`) gives the expansion.
The high-level mixfix commands `prefix`, `infix`, `infixl`, `infixr`, `postfix`, and `notation` are ergonomic front-ends over that mechanism; `infixl:prec "op" => f` desugars to a `notation` with the appropriate precedences.

```lean
infixl:65 " ⊕ " => myMerge

notation:50 lhs " ⊨ " rhs => satisfies lhs rhs
```

Drop down to `syntax` plus `macro_rules` when you need new bracket forms, binders, or to synthesize a proof as part of the expansion.
The core `#v[...]` vector literal is the worked example: its macro emits a `Vector.mk` call and supplies the length proof `rfl` itself.
The block below is an *illustrative paraphrase* of that notation, not the verbatim core declaration; the real core syntax is named `«term#v[_,]»` (lean4 `src/Init/Data/Vector/Basic.lean`) and its expansion threads through additional elaboration helpers.

```lean
syntax (name := termIllustrativeVec) "#v[" withoutPosition(term,*,?) "]" : term
macro_rules
  | `(#v[ $elems,* ]) => `(Vector.mk (n := $(quote elems.getElems.size)) #[$elems,*] rfl)
```

Use `notation` and the `infix` family for operators that just need a precedence; reserve the `syntax` + `macro_rules` route for forms that introduce binders or generate proofs.

## The executable, decidable, computable fragment

This is the load-bearing constraint of the whole specification leg: the spec must be runnable so that the check leg can differentially test it against the lifted model.
A spec that depends on classical reasoning or non-terminating recursion cannot be `#eval`'d, and a model that cannot be evaluated cannot be compared against the Rust-derived one on concrete inputs.

`#eval` runs a term through the compiler and prints it via its `Repr` instance, which is why every domain type carries `deriving Repr`.
It requires the term to be computable.
`native_decide` is itself `#eval`-backed, which is the other face of its trust cost.

Two things break computability and must be kept out of the executable path.
The first is `noncomputable` and `Classical`.
A `noncomputable def` cannot be compiled because it depends on `Classical.choice` or another non-constructive axiom, so it cannot be `#eval`'d; `Classical.choice`, `Classical.choose`, and `Classical.indefiniteDescription` are all `noncomputable`, and a classical `Decidable` instance such as `Classical.propDecidable` silently makes every predicate that uses it un-runnable while still type-checking.
The second is non-termination.
A normal `def` must be proved terminating (structural recursion or a well-founded measure), keeping it kernel-reducible; `partial def` opts out of the termination proof and is treated as *opaque to the kernel*, so it compiles and runs but does *not* definitionally reduce and cannot be unfolded in proofs.
A `partial` spec function therefore breaks `rfl`-based and `decide`-based translation validation even though it still executes.
Keep spec functions total.
On the lifted side, Rust loops do not arrive as naive `partial def`: the lift leg renders them as recursive functions declared via a fixpoint construction (`partial_fixpoint`, annotated `@[rust_loop]`), which preserves reasoning; that mechanism is described in `references/lift-charon-aeneas.md`.

The practical checklist for a runnable spec:

- domain types `deriving Repr, DecidableEq` (and `BEq` if you want `==`);
- all spec functions total `def`, never `partial`;
- every predicate carries a *constructive* `Decidable` or `DecidablePred` instance, derived or hand-written;
- no `noncomputable` and no `Classical.*` in the executable path;
- validate with `#eval` and `#guard` and `decide`, escalating to `native_decide` only for large computations and accepting the added trust.

## Property-based testing with Plausible

Plausible is the QuickCheck-style property-testing engine for Lean 4, the `leanprover-community/plausible` package and successor to mathlib3's `SlimCheck`.
It is neither in lean4 core nor in batteries; mathlib4 pins it as a top-level dependency, and nixpkgs packages it independently, so it is a separate `require` in the spec's lakefile.
Property testing is the fast-falsification half of the development loop: state the spec-versus-model correspondence as a `∀`-quantified decidable proposition, throw random inputs at it to find a counter-example quickly, then prove it (or `decide` / `native_decide` the finite instances) for the final check.

The package is the standalone Lake package `plausible`, imported with `import Plausible`; mathlib4 re-exposes it transitively through `Mathlib.Tactic.Common` (`~/projects/functional-programming-workspace/plausible`, `Mathlib/Tactic/Common.lean:12`).
There are three equivalent ways to run a property, all of which synthesize a `Testable` instance and call the same `Testable.check`: the `#test <prop>` command, a direct `#eval Testable.check <prop>`, or the `plausible` tactic applied to a goal of that shape (`~/projects/functional-programming-workspace/plausible`, `Plausible/Tactic.lean:158`).
The `#test` command is itself a macro that desugars to `#eval Plausible.Testable.check <prop>` (`~/projects/functional-programming-workspace/plausible`, `Plausible/Testable.lean:625`).

```lean
import Plausible
open Plausible

def myReverse : List Nat → List Nat
  | []      => []
  | x :: xs => myReverse xs ++ [x]

#test ∀ xs : List Nat, myReverse xs = xs.reverse
-- info: Unable to find a counter-example
```

The `plausible` tactic discharges a `∀` goal in place by random testing, reporting a shrunk counter-example on failure, and accepts the same configuration record.

```lean
example : ∀ x : Nat, 2 ∣ x → x < 100 := by
  plausible (config := { randomSeed := some 257, maxSize := 200 })
```

On failure it prints a counter-example block naming the bound variables, the failing `issue:`, and the number of shrinks performed, because the `Shrinkable` machinery minimizes the witness.
A bare `by plausible` uses the default config.
Property testing requires `SampleableExt` (built from `Arbitrary`, which supplies the `Gen α` generator, and `Shrinkable`) plus `Repr` instances for the quantified types; `SampleableExt` is usually inferable for closed types via `:= by infer_instance`, while `Arbitrary` and `Shrinkable` are hand-written for the non-derivable ones.
This dependency is the reason a *runnable, decidable* spec is the prerequisite for property-testing it: the same constructive instances that make the spec `#eval`-able are the ones the generators and the `Testable` mechanism consume.

The underlying class is `Testable`, declared `class Testable (p : Prop) where run (cfg : Configuration) (minimize : Bool) : Gen (TestResult p)` (`~/projects/functional-programming-workspace/plausible`, `Plausible/Testable.lean:174-176`).
`Testable.run` is the class *method* that produces a `Gen (TestResult p)`; it is not a run-and-get-result entry point, so reach for the runners instead — `Testable.check : CoreM PUnit` (`Plausible/Testable.lean:603`), which `#test` and the tactic call, and `Testable.checkIO : IO (TestResult p)` (`Plausible/Testable.lean:549`) for programmatic use.
A `TestResult` is one of `success`, `gaveUp`, or `failure`, the last carrying the shrunk counter-example (`Plausible/Testable.lean:80-102`).
The default trial count is `numInst = 100`, raised or lowered through the configuration record as `(config := { numInst := N })`.

Custom quantified types supply their own generation: derive or instance `Repr`, `Plausible.Shrinkable` (its `shrink : α → List α` drives counter-example minimization), and `Plausible.Arbitrary` (a `Gen α`), and `Plausible.SampleableExt` then follows automatically via the `selfContained` default instance (`~/projects/functional-programming-workspace/plausible`, `Plausible/Sampleable.lean:123-129`).
The older `SampleableExt.mkSelfContained` route is deprecated as of 2025-10-22 (`Plausible/Sampleable.lean:132`).
These signatures were read at toolchain v4.32.0-rc1; `Arbitrary` in particular has seen churn across versions, so confirm it against the toolchain the spec's lakefile actually pins.

## omega scope

`omega` is a complete decision procedure for linear integer and natural-number arithmetic, and it is welcome in spec-side hand-authored Lean — discharging a `Fin` bound, a length side condition in a smart constructor, or an index obligation in a dependent `if`.

```lean
def get0 (xs : List α) (h : xs.length ≠ 0) : α := xs.get ⟨0, by omega⟩
```

The restriction lands later, in the check leg, not here: `omega` is *forbidden inside Aeneas refinement proofs over the lifted model*, where the bounded-machine-integer reasoning needs `scalar_tac` instead (which itself calls omega after machine-integer-bounds preprocessing).
Keep that boundary explicit when you carry a lemma across the pipeline: a proof that closed with `omega` on the spec side may need `scalar_tac` once it is stated over the lifted model.
The full rule and its rationale live in `references/check-translation-validation.md`.
