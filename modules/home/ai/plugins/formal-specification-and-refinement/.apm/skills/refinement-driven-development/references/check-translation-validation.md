# The check leg: translation validation in three tiers

The check leg closes the loop.
After the lift has produced a Lean model from the Rust artifact (Charon compiles Rust to LLBC, then Aeneas translates LLBC to Lean; lift = Aeneas ∘ Charon), check establishes a correspondence between that lifted model and the original hand-authored Lean spec.
The recognized name for this discipline in the formal-methods literature is *translation validation*: rather than verifying a translator once and for all, you validate the output it produced on this particular run.
The originating reference is Pnueli, Siegel, and Singerman, "Translation Validation," TACAS 1998 (LNCS 1384).
This conceptual name is imported framing — it is not a term the Aeneas or hax tooling uses internally, and it is distinct from Aeneas' own one-time translator-soundness theorem (the symbolic-execution borrow-checking result, ICFP 2024, https://dl.acm.org/doi/10.1145/3674640).
That theorem makes the lift itself trustworthy; the per-program correspondence between *this* lifted model and *this* spec is a separate obligation, and discharging it per program is exactly what translation validation names.

## Contents

| Section | Topic |
|---|---|
| [The governing principle](#the-governing-principle-mechanization-when-available-never-required) | Mechanization is opportunistic, not mandatory |
| [Three notions of agreement](#three-notions-of-agreement) | Definitional equality, equivalence, refinement (⊑) |
| [Tier 1 — mechanical](#tier-1--mechanical-kernel-checked-refinement-proof) | Kernel-checked proof of refinement or equivalence |
| [Tier 2 — differential testing](#tier-2--differential-testing-with-plausible) | Property-based testing spec against lifted model |
| [Tier 3 — LLM comparison](#tier-3--llm-comparison-and-triage) | Diff-and-triage as preliminary pass and fallback |
| [Choosing a tier](#choosing-a-tier) | Finickiness and compute cost as the judgment criteria |

## The governing principle: mechanization when available, never required

State this first because it governs everything below.
The check leg takes advantage of mechanization whenever it is available and tractable, but it never *requires* mechanization.
The three tiers form a fallback ladder, not a checklist every artifact must pass.

Mechanical on-the-nose proof — a machine-checked proof, re-validated by the Lean kernel, that the lifted model refines or is equivalent to the spec — is the precise *ideal*.
It is not a requirement, and its absence is not a failure of the loop.
An undischarged correspondence is an open obligation, not a defect: it is precisely the thing the next refine iteration can target, or that a lower tier can cover with empirical evidence in the meantime.

The reference corpus treats unproven obligations exactly this way.
Tutorial theorems ship as `axiom` declarations — honest, non-failing placeholders that Lean accepts while verifying nothing — with a documented roadmap to discharge them later with real Aeneas tactics (`~/projects/functional-programming-workspace/rust-lean-aeneas`, `GAP_ANALYSIS.md`, `STATUS.md`).
The trusted-kernel completion criterion is stated alongside this openly: if `lake build` succeeds on a real proof, the Lean kernel has verified it; if a theorem is still an `axiom`, that is simply recorded as an open item rather than masked.

The kernel-recheck guarantee is what makes the whole ladder safe, and especially what makes AI-assisted proof safe.
An ordinary Lean proof term is re-checked by the small trusted kernel regardless of how it was produced.
A human-written proof, an Aeneas-tactic-generated proof, and an LLM-generated proof are all just proof terms, and the kernel re-checks every one of them.
Provenance is therefore irrelevant to soundness: a mis-generated proof simply fails to typecheck.
The sharp in-corpus contrast is between `decide` and `native_decide`: `decide` (and any normal tactic-produced proof) yields a kernel-checked term that adds no axiom, whereas `native_decide` is documented as adding the entire Lean compiler to the trusted base and surfacing a new axiom in `#print axioms` for anything that transitively depends on it (`~/projects/functional-programming-workspace/lean4`, `src/Init/Tactics.lean`).
The corollary is that you may let automation, including an LLM, propose proofs aggressively at tier 1, because nothing it proposes can corrupt soundness — at worst it fails to compile.

## Three notions of agreement

These three notions are distinct and the skill must not conflate them.
Each tier targets one or more of them, and naming which one you are after disambiguates what a passing check actually establishes.

*Definitional (judgmental) equality* holds when two expressions reduce to the same normal form purely by computation.
The kernel checks it automatically with no reasoning step: `example : 2 + 3 = 5 := rfl` succeeds because both sides compute to 5.
Definitional equality is strong but brittle.
For a variable `n`, the equation `n + 0 = n` is *not* definitional, because `Nat.add` recurses on its second argument so `n + 0` does not reduce, and proving it needs `induction` (`~/projects/functional-programming-workspace/rust-lean-aeneas`, `LEAN.md`).
Definitional equality is the rare, lucky case where the lifted model and the spec are literally the same function up to computation; do not expect it across a refine/lower boundary.

*Functional / observational equivalence* holds when two differently-implemented functions compute the same input-to-output relation — the same mathematical function — even with different internal strategies.
This is a *propositional* equality, proved by induction or case analysis rather than by reduction.
The canonical worked instance in the corpus is the infix-versus-RPN evaluator equivalence: tree recursion and a stack machine are completely different evaluation strategies that nonetheless compute the same function, and the bridging theorem states exactly that (`~/projects/functional-programming-workspace/rust-lean-aeneas`, `tutorials/03-infix-calculator/.../Equivalence.lean`).
A roundtrip/inverse property such as decrypt(encrypt(p, key), key) = p is another observational identity.
Across a refine/lower boundary, equivalence is the usual aspiration: the Rust you wrote should compute the same function as the Lean spec it was lowered from.

*Refinement* (the ⊑ order) is weaker and one-directional: the model refines the spec when every behaviour the model exhibits is permitted by the spec.
The model may be more deterministic or more defined than the spec, but it never violates a behaviour the spec forbids.
In the Aeneas / Hoare-style setting this surfaces operationally: under its precondition, the monadic function *succeeds* — yields `ok _`, with no `fail` and no `div` — and its result satisfies the postcondition.
Refinement is a containment, not a two-way identity, which is why it is the right notion when the spec is intentionally looser than the implementation.

A precision note that the skill must hold to: there is no in-repo ⊑ operator.
A search for the literal `⊑` symbol and the word "refinement" returns no hits in the Aeneas or rust-lean-aeneas Lean sources.
Present ⊑ as imported order-theoretic framing — the refinement order from the refinement calculus — and realize it operationally as the Hoare-triple-style spec-theorem shape that Aeneas' tooling actually consumes.
Do not assert that a Lean ⊑ operator exists in these repositories.

The spec-theorem shape that encodes a refinement obligation, and that the `step` tactic is built to consume, is a monadic function constrained by a precondition and a success-plus-postcondition spec:

```lean
theorem mul2_add1_spec (x : U32)
    (h : 2 * x.val + 1 ≤ U32.max) :          -- precondition: no overflow
    mul2_add1 x ⦃ y => ↑ y = 2 * ↑x + (1 : Nat) ⦄   -- success ∧ postcondition
```

The `⦃ y => P y ⦄` notation is Aeneas' postcondition / success-monad-spec syntax, written in the Hoare-logic style the tutorial advises — preconditions as hypotheses, postcondition inside the brace (`~/projects/functional-programming-workspace/aeneas`, `tests/lean/BaseTutorial.lean`).
Read against the three notions: the theorem asserts the lifted `mul2_add1` *refines* a spec that says "given no overflow, return twice the input plus one", and because the postcondition pins the result exactly, this particular instance also witnesses functional equivalence on the precondition's domain.

## Tier 1 — mechanical: kernel-checked refinement proof

Tier 1 is the ideal: produce a machine-checked proof, re-validated by the Lean kernel, that the lifted model refines the spec or is functionally equivalent to it.
The kernel re-checks every proof term, so tier 1's engineering task is *producing* that term with as much automation as possible, layering generic Lean automation under Aeneas' domain-specific tactics.

The generic Lean automation available in the kernel-checked layer includes `simp` and `simp_all` (rewriting by `@[simp]` lemmas, the refinement-proof workhorse called out in the gap analysis), `decide` (synthesizes and reduces a `Decidable` instance, producing a kernel-checked term for finite case analysis), `omega` (a decision procedure for linear arithmetic over `Nat` and `Int`), and `grind` (lean4's newer SMT-inspired automation, combining congruence closure, E-matching over `@[grind =]` patterns, and an integrated linear-integer-arithmetic procedure).
The structural tactics `cases`, `induction`, `split`, `rcases`, and `subst` carry the equivalence and invariant proofs.
Hammer-class automation — `aesop`, `duper`, LeanHammer — sits at the *external* end of this ladder: it is community tooling layered on top via Mathlib, not part of lean4 core or the Aeneas backend, and should be cited as the premise-selection-plus-external-ATP extreme rather than as shipped automation.

Aeneas' own tactics are the engine for discharging refinement obligations over the lifted model.
The principal tactic is `step`, with spec theorems registered via the `@[step]` attribute.
`step` looks for a suitable theorem — supplied by the user or found in the `@[step]` database — describing the behaviour of a monadic function, applies it to the current goal, introduces the existentially quantified result variables, splits the postcondition conjunctions, and tries to discharge the preconditions automatically, leaving any it cannot prove as subgoals (`~/projects/functional-programming-workspace/aeneas`, `backends/lean/Aeneas/Tactic/Step/Step.lean`, `tests/lean/BaseTutorial.lean`).
Precondition discharge internally threads a `grind` state across successive `step` calls, so `step` is itself a composite that delegates to lean4's `grind`.
The names `progress` and the `@[pspec]` / `@[progress]` attributes are deprecated aliases retained only for backward compatibility — they emit a deprecation warning and delegate to `step` / `@[step]` (`~/projects/functional-programming-workspace/aeneas`, `backends/lean/Aeneas/Tactic/Step/Deprecated.lean`).
Use `step` and `@[step]` in all new proofs; mention `progress` and `@[pspec]` only to note that they are deprecated.

Arithmetic obligations inside a refinement proof are discharged with `scalar_tac`, not bare `omega`.
`scalar_tac` is Aeneas' arithmetic solver, aware of machine-integer bounds (`U32`, `Usize`, and so on); it heavily preprocesses the goal and then calls `omega` under the hood, and with `scalar_tac +nonLin` it reaches some non-linear goals as well (`~/projects/functional-programming-workspace/aeneas`, `backends/lean/Aeneas/Tactic/Solver/ScalarTac/ScalarTac.lean`).
This is the load-bearing scope rule for the check leg: `omega` is forbidden *inside* Aeneas refinement proofs over the lifted model, because those goals manipulate machine-integer scalars whose bounds bare `omega` does not know; `scalar_tac` supplies the bounds preprocessing before delegating to `omega`.
Hand-authored, spec-side Lean over plain `Nat` or `Int` may use `omega` directly — that restriction applies only within the Aeneas-lifted refinement proofs.
Keep this distinction explicit wherever `omega` appears.

The canonical tier-1 idiom unfolds the lifted function, takes one `step` per monadic operation, and finishes the arithmetic with `grind` or `scalar_tac`:

```lean
theorem mul2_add1_spec (x : U32) (h : 2 * x.val + 1 ≤ U32.max) :
    mul2_add1 x ⦃ y => ↑ y = 2 * ↑x + (1 : Nat) ⦄ := by
  unfold mul2_add1
  step with U32.add_spec as ⟨ x1 ⟩
  step with U32.add_spec as ⟨ x2 ⟩
  grind
```

The gap analysis prescribes a one-liner of the same shape for a clamp function — unfold by `rw`, case-split by `split`, simplify by `simp_all`, discharge the arithmetic by `scalar_tac`:

```lean
@[step]
theorem clamp_in_bounds (x lo hi : Std.I32) (h : lo ≤ hi) :
    ∃ r, clamp x lo hi = ok r ∧ lo ≤ r ∧ r ≤ hi := by
  rw [clamp]
  split <;> split <;> simp_all <;> constructor <;> scalar_tac
```

Both of these are genuine kernel-checked proofs, not `axiom` placeholders, and the corpus also carries real ones — for example an invariant-preservation theorem and a reachability induction over an Aeneas-lifted traffic-light state machine, finished with `simp`, `cases`, `simp_all`, and `induction` (`~/projects/functional-programming-workspace/rust-lean-aeneas`, `tutorials/04-state-machines/.../TrafficLightProofs.lean`).

Aeneas' `Result` model is what these proofs reason over.
The current `Result` type has three constructors — `ok`, `fail`, and `div` — paired with a seven-constructor `Error`.
There is no `Except Error T` with `{panic, outOfFuel}`, and there is no fuel mechanism; do not write proofs against that stale model.
A refinement obligation in this setting says: under the precondition, the function returns `ok r` (excluding `fail` and `div`) with `r` satisfying the postcondition — which is exactly the "succeeds and satisfies" reading of ⊑ above.

## Tier 2 — differential testing with Plausible

When a tier-1 proof is not yet available, or as a fast preliminary sanity check before investing in one, tier 2 gathers empirical evidence for functional equivalence by property-based testing.
The hand-authored Lean spec is ordinary executable Lean, and the Aeneas-lifted model is also executable Lean over the `Result` monad, so the two can be tested against each other directly: generate many random inputs and check that the spec's output agrees with the lifted model's output (the ≈ relation), collecting statistical evidence for the ≈-identity short of a proof.

The framework is Plausible, Lean's QuickCheck-style property-based testing library (upstream `leanprover-community/plausible`).
Plausible is a standalone package, not part of lean4 core; Mathlib re-exports it and adds instances under (`~/projects/functional-programming-workspace/mathlib4`, `Mathlib/Testing/Plausible/`).
Its confirmed API surface is the `Plausible.Testable` type class (a testable proposition, run under a `Configuration`), `Plausible.SampleableExt` (random sample generation for a type so it can appear in a tested ∀-quantifier), `Plausible.Shrinkable` (counterexample shrinking), `Plausible.Gen` (the random-generation monad), and `Plausible.TestResult` / `Plausible.PrintableProp` (counterexample reporting).
State the agreement between the two executable Lean artifacts as a universally-quantified decidable proposition, then exercise it through one of two front-ends that both call the same runner.
The `#test <prop>` command tests the property at elaboration time; it is a macro that desugars to `#eval Plausible.Testable.check <prop>` (`~/projects/functional-programming-workspace/plausible`, `Plausible/Testable.lean:625`).
The `plausible` tactic (the confirmed successor to Mathlib's older `slim_check`) attacks a goal of that same shape (`~/projects/functional-programming-workspace/plausible`, `Plausible/Tactic.lean:158`).
Both route to `Plausible.Testable.check`, which runs `numInst` (default 100) randomized trials and reports a shrunk counterexample as `TestResult.failure` (`~/projects/functional-programming-workspace/plausible`, `Plausible/Testable.lean:80-102`), or reports success when no counterexample is found.
`Testable.run` is *not* a runner entry point: it is the `Testable` class method returning `Gen (TestResult p)` (`~/projects/functional-programming-workspace/plausible`, `Plausible/Testable.lean:174-176`); the runners proper are `Testable.check` (`Plausible/Testable.lean:603`) and `Testable.checkIO` (`Plausible/Testable.lean:549`).

Tier 2 establishes only empirical, approximate identity — not a proof — and that is its honest role: it is evidence that the spec and lifted model agree on the sampled inputs, strong enough to catch a divergence early and cheap enough to run constantly, but it never closes a refinement obligation on its own.
The load-bearing reason is mechanical, not merely a matter of statistical coverage: the `plausible` tactic is a test aid, not a proof tactic, and when it finds no counterexample it *admits* the goal via `admitGoal` (`~/projects/functional-programming-workspace/plausible`, `Plausible/Tactic.lean:206`) rather than discharging the theorem.
A passing `plausible` or `#test` run therefore raises confidence that Φ(S) ≈ S but does not establish it — producing a machine-checked refinement or equivalence is exactly tier 1's job, and that is precisely why tier 2 yields ≈-evidence while tier 1 yields a kernel-checked ⊑ or equivalence.
A passing tier-2 campaign over a function is a good reason to attempt tier 1 on it; a failing one is a counterexample that bounces straight back into the next refine iteration.
Note that this Lean-side spec-versus-lifted-model testing is the *prescribed* design for the loop, not something already wired in the corpus — the existing tutorials run Rust-side `proptest` / `quickcheck` on the Rust core as a tier-2 analog rather than testing the two Lean artifacts against each other.

## Tier 3 — LLM comparison and triage

Tier 3 is the cheapest and most approximate: an LLM reads the hand-authored executable spec and the Aeneas-lifted model side by side and triages each function and property as likely-equal or likely-diverged, producing a prioritized worklist.
It serves two roles in the ladder.
As a *preliminary pass* it runs before tiers 1 and 2 to tell them where to spend effort — which obligations look worth a mechanical proof attempt, and which look divergent and should bounce back to a refine iteration before any proof is attempted.
As a *fallback* it covers obligations for which neither a tier-1 proof nor a tier-2 campaign is currently practical, recording a human-reviewable judgment that feeds the next refinement iteration rather than leaving the obligation entirely unaddressed.

The artifacts tier 3 consumes already exist in the corpus structure: hand-authored proofs and specs live in files marked as hand-written (for example a `Proofs.lean`), while the lifted model lives in a sibling `generated/` tree, and the gap analysis describes exactly this split between hand-written approximations and real Aeneas output.
The diff target is the gap between a spec theorem's *statement* and the lifted function's *behaviour* — precisely the obligation that `step` would discharge if proved, or that a Plausible property would empirically probe.

Tier 3 is soundness-neutral, and the kernel-recheck principle is why it is safe to use aggressively.
A triage judgment is only a prioritization hint, never a trusted claim; and if the LLM proposes an actual proof rather than a judgment, that proof is just a proof term the kernel re-checks, adding no axiom for ordinary tactics.
So nothing tier 3 emits — judgment or proof — can corrupt the soundness established at tier 1.

## Choosing a tier

The tiers are a fallback ladder ordered by the strength of the guarantee they yield: tier 1 gives a kernel-checked proof, tier 2 gives statistical evidence, tier 3 gives a triage judgment.
Always prefer the strongest tier that is *tractable* for the obligation at hand.
The judgment criteria are finickiness and compute cost, not a wall-clock threshold.

Reach for tier 1 when the mechanical proof is tractable and not excessively finicky or compute-intensive — when the canonical `unfold`/`step`/`scalar_tac` idiom, or a short `split`/`simp_all`/`scalar_tac` combination, plausibly closes the goal.
Drop to tier 2 when a proof is achievable in principle but the proof engineering is currently too finicky to be worth it, or when you want fast empirical confidence before committing proof effort; differential testing buys evidence cheaply and surfaces counterexamples that redirect the refine iteration.
Fall to tier 3 when even framing the obligation for mechanization is premature — when you first need to know *whether* the spec and lifted model plausibly agree before deciding where proof or testing effort should go.

Deliberately, there is no hard wall-clock cutoff for this decision.
A proof that is tractable but slow is still tier 1; a proof that is fast to attempt but reliably finicky may be better served by tier 2 evidence plus an open obligation.
The criterion is the engineering judgment of finickiness and compute cost against the value of the guarantee, and the governing principle stands above all three tiers: the mechanical on-the-nose proof is the precise ideal, its absence is not a failure, and any obligation left below tier 1 is an honest open item that the next refine iteration — or a later, less finicky proof attempt — can pick up.
