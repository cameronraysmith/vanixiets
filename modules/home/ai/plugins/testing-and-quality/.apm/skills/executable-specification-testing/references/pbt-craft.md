# Property-based-testing craft

## The boundary to preferences-algebraic-laws (read first)

`preferences-algebraic-laws` owns laws-as-properties and the reasoning that produces them: the monoid, semigroup, functor, applicative, and monad laws each stated then expressed as property tests, the functor-applicative-monad abstraction hierarchy with least-power selection, and parametricity and free theorems in the Wadler "Theorems for Free!" sense.
It treats property-based testing purely as the execution vehicle for those laws.
It deliberately does *not* own the generative craft: generator and strategy design appears there only as incidental scaffolding to make a law test runnable, shrinking is mentioned only in passing as a framework feature, and stateful/model-based and metamorphic testing are absent entirely.

This file owns exactly that unclaimed craft — how to design a generator, how shrinking works, how to model a stateful system, and how to state a metamorphic relation — and it does so cross-language, not Python-only.

One reclassification is forbidden.
The equation `map(f).filter(p) == filter(p ∘ f).map(f)` is a *free theorem* derived from a polymorphic type by parametricity; `preferences-algebraic-laws` owns it as such.
It is not a metamorphic relation and must not be re-presented as one in the metamorphic section below.
The distinction is real: a free theorem is entailed by the type and needs no test to be true (a test only guards against an implementation that breaks parametricity, e.g. via reflection), whereas a metamorphic relation is a chosen, domain-specific relationship between two runs of a function whose single output has no independent oracle.
The event-sourcing fold and reconstruction laws are likewise pure catamorphism properties owned by `preferences-algebraic-laws`; a stateful/model-based test over the same event-sourced domain is a different construction (a command sequence against a reference model), and the overlap is of subject, not of ownership.

## Generator and strategy design

A property test is only as good as the distribution its generator draws from: a generator that never produces the awkward input cannot witness the bug that lives there.
Designing a generator is choosing a distribution that concentrates probability on the boundary and adversarial region, not merely a type-correct sampler.

The generator abstraction differs across frameworks but the design task is the same.
In Rust proptest, `Strategy` is the generator trait, carrying an associated `type Tree: ValueTree` and `fn new_tree(&self, runner) -> NewTree<Self>` (`proptest/proptest/src/strategy/traits.rs:37-60`); strategies compose through combinators (`prop_map`, `prop_filter`, `prop_flat_map`, `prop_oneof`) so a composite generator's distribution is built from primitives.
In Haskell QuickCheck, `Gen a` is `newtype Gen a = MkGen { unGen :: QCGen -> Int -> a }` — a seed-and-size to value function (`quickcheck/src/Test/QuickCheck/Gen.hs:66-67`); the size parameter is the designer's main lever over distribution.
In Haskell Hedgehog the generator is `GenT m a` running to a shrink tree (see shrinking below), and a `Range` carries the size-dependent bounds (`hedgehog/hedgehog/src/Hedgehog/Internal/Range.hs:80-105`), with `constant`/`linear`/`exponential` range constructors choosing how the bound scales with size.
In Python Hypothesis, strategies are the `hypothesis.strategies` combinators, and — the point the single-contract thesis turns on — a strategy can be *inferred* from an icontract precondition rather than written, via icontract-hypothesis (see `single-contract-hub.md`).

The design discipline in all four: prefer composing primitive generators over hand-rolling; bias the distribution toward boundaries (empty, singleton, maximum, off-by-one, and, for floats, zero/subnormal/NaN/inf) rather than trusting a uniform draw to reach them; and restrict to valid inputs with a *filter of last resort only*, because a filter that rejects most draws (proptest `prop_filter`, QuickCheck `==>`, Hypothesis `.filter`) degrades into slow generation or a health-check failure — prefer constructing valid inputs directly (a bounded `integers(min,max)` over a filtered unbounded draw).

## Shrinking: integrated versus manual and type-based

When a property fails, shrinking reduces the failing input to a minimal counterexample.
The load-bearing distinction is *where the shrink information lives*.

In the manual/separate model (classic QuickCheck), generation and shrinking are two independent methods on `Arbitrary`: `arbitrary :: Gen a` and `shrink :: a -> [a]`, with the default `shrink _ = []` — no shrinking at all unless the user writes it or derives `genericShrink` (`quickcheck/src/Test/QuickCheck/Arbitrary.hs:234, 251, 323-324`).
Because `Gen a` produces only a value and carries no shrink information, the shrinker is supplied separately at test time (`propertyForAllShrinkShow arbitrary shrink ...`, `quickcheck/src/Test/QuickCheck/Property.hs:174`).
The cost of the separate model is that a hand-written `shrink` can produce shrinks that violate the invariant the generator carefully maintained, since it has no memory of how the value was built.

In the integrated model (Hedgehog), the generator *runs to a shrink tree*: `GenT m a` returns `TreeT (MaybeT m) a` where the tree is a rose tree whose children are the shrinks (`hedgehog/hedgehog/src/Hedgehog/Internal/Gen.hs:257-259`, runGenT comment at 262-266; `.../Internal/Tree.hs:104-137` for `TreeT`/`NodeT`).
Shrinks are derived automatically from the monadic structure that produced the value, so they respect the `bind`s that built it and cannot escape the invariant — the `integral` combinator binary-searches toward the `Range` origin with no user-written shrink, and the non-shrinking `integral_` is documented as the deliberate opt-out (`Gen.hs:818-851`).

proptest is integrated by a different mechanism: each `Strategy` carries its own shrinker in its `ValueTree`, which exposes `current`, `simplify` (move toward a low/high halfway point, rounding toward low), and `complicate` (partially undo the last simplification) — a binary search toward a minimal failing case, with no default no-op impl so that every strategy defines its own shrinking (`proptest/proptest/src/strategy/traits.rs:580-620`).

Type-based (or type-directed) shrinking is a third point on the spectrum: the shrinker is derived from the type's structure (QuickCheck's `genericShrink`, Hypothesis's structural shrinking of its internal buffer).
The practical guidance: prefer integrated shrinking when available (Hedgehog, proptest, Hypothesis all shrink well by construction), and when using separate-model QuickCheck, treat a hand-written `shrink` as a place invariants can leak and test the shrinker's outputs against the same precondition the generator honored.

## Stateful and model-based testing

When the unit under test is a stateful system rather than a pure function, the property is not an equation over one input but a claim about *every sequence of operations*: the system agrees with a simpler reference model after any legal command sequence.
The construction is a state machine — an abstract reference model, a set of transitions/commands, and a check run after each command against the real system under test.

Rust proptest-state-machine makes both halves explicit.
`ReferenceStateMachine` is the abstract model: `type State`, `type Transition`, `init_state`, `transitions(state) -> BoxedStrategy<Transition>`, `apply(state, transition) -> State`, and an overridable `preconditions(state, transition) -> bool` filtering which transitions are legal from a state (`proptest/proptest-state-machine/src/strategy.rs:45-113`).
`StateMachineTest` binds the concrete side: a `SystemUnderTest`, an `init_test`, an `apply` that drives the real system and checks post-conditions, and an overridable `check_invariants` run after every transition; `test_sequential` drives generated sequences and the `prop_state_machine!` macro is the declaration entry point (`proptest/proptest-state-machine/src/test_runner.rs:19-99, 177`).
This is the reference-model-versus-implementation differential pattern.

The shrinking of a *sequence* is its own mechanism, distinct from shrinking a single value: transition sequences shrink by three moves — `Shrink::InitialState`, `Shrink::DeleteTransition`, and `Shrink::Transition` — deleting unseen transitions from the back of the list (a delete is not undone on `complicate`, to keep reproducibility) then shrinking the remaining transitions and the initial state (`proptest/proptest-state-machine/src/strategy.rs:121-132`).

Python Hypothesis provides the same shape through `RuleBasedStateMachine`: `@rule`-decorated methods are the commands, `Bundle`s thread values produced by one rule into another's arguments, and `@invariant` methods are checked between rules; `run_state_machine_as_test` (or a `TestCase` subclass) drives and shrinks the command sequence.
The design task in both is choosing the reference model at the right abstraction — simple enough to be obviously correct, rich enough to distinguish the behaviors that matter.

## Metamorphic relations

A metamorphic relation is the tool for a function whose single output has no independent oracle — you cannot say what `f(x)` should be, but you know a relationship between `f(x)` and `f(t(x))` for some transformation `t`.
The property asserts that relation rather than an exact value.
Canonical relations: an idempotent operation, `f(f(x)) == f(x)`; a permutation-invariant one, `f(shuffle(xs)) == f(xs)`; a scale relation, `f(k·x) == g(k)·f(x)` (the safeadt geometry `area(scale(k, s)) == k*k * area(s)` degree-2 homogeneity is exactly this shape, and it is proved in the Lean spec as `area_scale_homogeneous`); an additive one for a homomorphism, `f(xs ++ ys) == f(xs) <> f(ys)`; or a round-trip, `decode(encode(x)) == x`.

The relation is *chosen and domain-specific*, which is what separates it from a free theorem.
A free theorem such as the map/filter commutation is entailed by a polymorphic type and holds for every well-typed inhabitant; a metamorphic relation is a fact about *this* function's semantics that the type does not force, so it earns a test.
When an exact oracle does exist, prefer asserting against it (that is an ordinary property with an independent literal oracle, per the observable-outcome discipline `bdd-gherkin-formulation` owns); reach for a metamorphic relation when the oracle is exactly what you lack.
