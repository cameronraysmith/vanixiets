---
title: Algebraic laws
---

# Algebraic laws

Algebraic laws are equations that domain operations must satisfy to ensure correctness and composability.
These laws are not mathematical curiosities but executable specifications that verify your abstractions behave correctly.
When types satisfy algebraic laws, you gain theorems for free: properties guaranteed by parametricity that reduce the testing burden and enable safe refactoring through equational reasoning.

This document bridges the categorical foundations in theoretical-foundations.md to testable specifications using property-based testing frameworks.
Laws become test properties that validate domain abstractions across thousands of generated examples.

## Why algebraic laws matter

Laws serve three purposes in domain modeling.

First, laws are contracts that abstractions must satisfy.
When you claim a type forms a monoid or a function is a functor, the laws specify exactly what that means.
Satisfying these contracts enables using the abstraction safely in contexts that rely on those properties.

Second, parametricity reduces the test burden.
Generic functions constrained by laws have far fewer possible implementations than unconstrained functions.
A function with signature `f[A]: List[A] => List[A]` that obeys functor laws has only a handful of valid implementations, drastically limiting what tests must verify.

Third, compiler-verified properties enable fearless refactoring.
When the type system enforces laws, illegal states become unrepresentable and illegal operations fail to compile.
Refactoring becomes mechanical: if it type-checks and passes law tests, it preserves semantics.

## Relationship to other documents

- See theoretical-foundations.md for categorical foundations of these laws
- See domain-modeling.md for applying law-governed abstractions to domain design
- See railway-oriented-programming.md for Result and Either laws in error handling contexts
- See rust-development/05-testing.md, python-development.md, typescript-nodejs-development.md for language-specific property testing examples

## Monoid and semigroup laws

### The laws

A semigroup is a type with an associative binary operation:

```haskell
-- Associativity
op(op(x, y), z) == op(x, op(y, z))
```

A monoid extends semigroup with an identity element:

```haskell
-- Associativity (from semigroup)
op(op(x, y), z) == op(x, op(y, z))

-- Left identity
op(zero, x) == x

-- Right identity
op(x, zero) == x
```

The identity element `zero` is named for numeric addition but represents the "do nothing" element for any operation.
For multiplication it's 1, for list concatenation it's the empty list, for boolean AND it's true.

### Domain examples

Monoids appear throughout domain modeling whenever you need to aggregate or combine values.

Money aggregation forms a monoid when currencies match.
The operation is addition, the identity is zero dollars.
Associativity means you can sum transactions in any grouping order: `(a + b) + c == a + (b + c)`.
This enables parallel aggregation where different workers sum subsets then combine results.

Account balance computation uses the monoid of transactions.
Each transaction is a state update function `Balance -> Balance`.
Function composition is associative, the identity is the no-op function.
You can apply transactions in any parenthesization, enabling incremental updates and replay from checkpoints.

Event log concatenation forms a list monoid.
The operation is list append, the identity is the empty list.
Associativity ensures you can merge logs from different sources in any order without affecting the final sequence.

Configuration merging often uses monoid structure.
The operation might be "override" or "merge deeply", the identity is empty configuration.
Laws ensure that the order of merging groups of configs doesn't affect the final result.

### Property-based tests for monoid laws

Use property-based testing to verify monoid laws across thousands of generated examples.

Rust with proptest:

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn money_associativity(a: Money, b: Money, c: Money) {
        let left = a.combine(&b).combine(&c);
        let right = a.combine(&b.combine(&c));
        prop_assert_eq!(left, right);
    }

    #[test]
    fn money_left_identity(m: Money) {
        let zero = Money::zero();
        prop_assert_eq!(zero.combine(&m), m);
    }

    #[test]
    fn money_right_identity(m: Money) {
        let zero = Money::zero();
        prop_assert_eq!(m.combine(&zero), m);
    }
}
```

Haskell with QuickCheck:

```haskell
instance Arbitrary Money where
  arbitrary = Money <$> arbitrary <*> arbitrary

prop_monoid_assoc :: Money -> Money -> Money -> Bool
prop_monoid_assoc x y z = (x <> y) <> z == x <> (y <> z)

prop_monoid_left_id :: Money -> Bool
prop_monoid_left_id x = mempty <> x == x

prop_monoid_right_id :: Money -> Bool
prop_monoid_right_id x = x <> mempty == x
```

Python with Hypothesis:

```python
from hypothesis import given, strategies as st

@given(st.builds(Money), st.builds(Money), st.builds(Money))
def test_money_associativity(a: Money, b: Money, c: Money):
    left = a.combine(b).combine(c)
    right = a.combine(b.combine(c))
    assert left == right

@given(st.builds(Money))
def test_money_left_identity(m: Money):
    assert Money.zero().combine(m) == m

@given(st.builds(Money))
def test_money_right_identity(m: Money):
    assert m.combine(Money.zero()) == m
```

TypeScript with fast-check:

```typescript
import * as fc from 'fast-check';

fc.assert(
  fc.property(moneyArb, moneyArb, moneyArb, (a, b, c) => {
    const left = a.combine(b).combine(c);
    const right = a.combine(b.combine(c));
    return left.equals(right);
  })
);

fc.assert(
  fc.property(moneyArb, (m) => {
    return Money.zero().combine(m).equals(m);
  })
);
```

### Fold and reconstruction laws for event sourcing

Event-sourced systems reconstruct state by folding the `evolve` function over event sequences.
This fold operation must satisfy algebraic laws ensuring deterministic reconstruction.

The fold laws for state reconstruction:

```haskell
-- Identity: folding over empty events yields initial state
fold(evolve, s₀, []) ≡ s₀

-- Single element: folding over one event is equivalent to applying evolve once
fold(evolve, s₀, [e]) ≡ evolve(s₀, e)

-- Associativity: folding over concatenated event lists can be done in stages
fold(evolve, s₀, es₁ ++ es₂) ≡ fold(evolve, fold(evolve, s₀, es₁), es₂)
```

The associativity law is critical for distributed systems: it enables incremental state reconstruction and checkpointing.
You can fold events up to time T, snapshot the state, then fold remaining events from that snapshot rather than replaying from the beginning.

When `State` itself has monoidal structure (e.g., balance as Sum monoid, analytics as product of counters), the fold inherits that structure:

```haskell
-- If State is a monoid and evolve preserves monoidal structure:
fold(evolve, mempty, events) <> fold(evolve, mempty, moreEvents)
  ≡ fold(evolve, mempty, events ++ moreEvents)
```

Property-based tests for fold laws ensure state reconstruction is deterministic:

```rust
proptest! {
    #[test]
    fn fold_identity(initial: AccountState) {
        let events: Vec<AccountEvent> = vec![];
        let result = events.iter().fold(initial.clone(), Account::evolve);
        prop_assert_eq!(result, initial);
    }

    #[test]
    fn fold_single_element(initial: AccountState, event: AccountEvent) {
        let result1 = vec![event.clone()].iter().fold(initial.clone(), Account::evolve);
        let result2 = Account::evolve(initial, &event);
        prop_assert_eq!(result1, result2);
    }

    #[test]
    fn fold_associativity(
        initial: AccountState,
        events1: Vec<AccountEvent>,
        events2: Vec<AccountEvent>
    ) {
        let intermediate = events1.iter().fold(initial.clone(), Account::evolve);
        let left = events2.iter().fold(intermediate, Account::evolve);

        let all_events: Vec<_> = events1.iter().chain(events2.iter()).collect();
        let right = all_events.iter().fold(initial, Account::evolve);

        prop_assert_eq!(left, right);
    }
}
```

These laws connect to the monoidal structure of events (see monoid laws above) and enable correctness guarantees for event-sourced state machines.
See event-sourcing.md#state-reconstruction for domain context and patterns, and theoretical-foundations.md#the-decider-pattern for the categorical interpretation of `evolve` as an F-algebra and state reconstruction as catamorphism.

## Functor laws

### The laws

A functor is a type constructor `F[A]` with a `map` operation satisfying:

```haskell
-- Identity
map(fa)(identity) == fa

-- Composition
map(map(fa)(f))(g) == map(fa)(f andThen g)
```

The identity law states that mapping the identity function does nothing.
The composition law states that mapping two functions sequentially is equivalent to mapping their composition.

### Why functor laws matter

Functor laws ensure that mapping preserves structure.
If you map a function over a data structure, you get back the same shape with transformed values.
No elements appear or disappear, no duplicates are introduced, the container structure is untouched.

This structural preservation enables equational reasoning.
When refactoring code that uses functors, you can freely rewrite `map(map(xs)(f))(g)` as `map(xs)(f andThen g)` without changing behavior.
The compiler and laws guarantee equivalence.

Functors compose: if `F` and `G` are functors, then `F[G[A]]` is also a functor.
The composition law ensures this works correctly without special handling.

### Domain examples

Result types are functors where `map` transforms the success value while preserving errors.
This enables building pipelines that automatically short-circuit on failure while transforming successful results.

Optional types are functors where `map` applies the function only when a value is present.
The laws ensure that None propagates through chains of maps without requiring special cases.

List types are functors where `map` applies the function to each element.
The composition law means you can fuse multiple transformations into a single pass for efficiency.

### Property-based tests for functor laws

Rust:

```rust
proptest! {
    #[test]
    fn result_functor_identity(r: Result<i32, String>) {
        let mapped = r.map(|x| x);
        prop_assert_eq!(mapped, r);
    }

    #[test]
    fn result_functor_composition(r: Result<i32, String>) {
        let f = |x: i32| x + 1;
        let g = |x: i32| x * 2;
        let left = r.map(f).map(g);
        let right = r.map(|x| g(f(x)));
        prop_assert_eq!(left, right);
    }
}
```

Haskell:

```haskell
prop_functor_identity :: Result Int String -> Bool
prop_functor_identity fa = fmap id fa == fa

prop_functor_composition :: Result Int String -> Fun Int Int -> Fun Int Int -> Bool
prop_functor_composition fa (Fun _ f) (Fun _ g) =
  fmap g (fmap f fa) == fmap (g . f) fa
```

Python with Expression library:

```python
from hypothesis import given
from expression import Result

@given(result_strategy)
def test_result_functor_identity(r: Result[int, str]):
    assert r.map(lambda x: x) == r

@given(result_strategy)
def test_result_functor_composition(r: Result[int, str]):
    f = lambda x: x + 1
    g = lambda x: x * 2
    left = r.map(f).map(g)
    right = r.map(lambda x: g(f(x)))
    assert left == right
```

TypeScript with Effect-TS:

```typescript
fc.assert(
  fc.property(resultArb, (r) => {
    const mapped = pipe(r, E.map(identity));
    return E.equals(mapped, r);
  })
);

fc.assert(
  fc.property(resultArb, fc.func(fc.integer()), fc.func(fc.integer()), (r, f, g) => {
    const left = pipe(r, E.map(f), E.map(g));
    const right = pipe(r, E.map(flow(f, g)));
    return E.equals(left, right);
  })
);
```

## Applicative laws

### The laws

An applicative functor extends functor with the ability to apply functions wrapped in the same structure:

```haskell
-- Identity
ap(pure(id))(v) == v

-- Composition
ap(ap(ap(pure(compose))(u))(v))(w) == ap(u)(ap(v)(w))

-- Homomorphism
ap(pure(f))(pure(x)) == pure(f(x))

-- Interchange
ap(u)(pure(y)) == ap(pure(f => f(y)))(u)
```

The `pure` function wraps a value in the minimal structure.
The `ap` function applies a wrapped function to a wrapped value.

### Domain applications

Applicative functors shine when combining independent effects in parallel.

Validation is the canonical example.
When validating a domain object with multiple fields, you want to collect all errors rather than failing at the first one.
Applicative validation accumulates errors using a semigroup:

```haskell
data Validated e a
  = Valid a
  | Invalid (NonEmptyList e)

-- Validate multiple fields, accumulating all errors
validateOrder :: UnvalidatedOrder -> Validated ValidationError ValidatedOrder
validateOrder unvalidated =
  ValidatedOrder
    <$> validateQuantity unvalidated.quantity
    <*> validateProduct unvalidated.productCode
    <*> validateCustomer unvalidated.customerId
```

If any validation fails, you get all failures in a list.
This provides better user experience than failing at the first error.

Configuration composition uses applicative structure when you need to combine settings from multiple sources where each source might be missing or invalid.
Applicatives let you collect all configuration issues rather than failing on the first.

Parallel computation uses applicative when you have independent computations that can run concurrently.
The applicative structure makes the independence explicit in types, enabling automatic parallelization.

### When to use applicative vs monad

Use applicative functors when effects are independent and don't need to inspect prior results.
This is weaker than monadic composition but the constraint enables optimizations.

Use monadic composition when later steps depend on earlier results.
If you need to choose what to do next based on a previous value, you need the full power of monads.

The guideline: use the least powerful abstraction that works.
Applicative is less powerful than monad, so prefer applicative when possible.
This keeps options open and makes parallelization opportunities explicit.

### Property-based tests for applicative laws

Testing applicative laws requires generating wrapped functions, which is more complex than testing functor laws.

Rust (conceptual, as Rust doesn't have native applicative trait):

```rust
// Identity law
proptest! {
    #[test]
    fn validated_identity(v: Validated<String, i32>) {
        let id_fn = Validated::Valid(|x: i32| x);
        prop_assert_eq!(v.ap(id_fn), v);
    }
}

// Composition law tests require more setup
```

Haskell:

```haskell
prop_applicative_identity :: Validated String Int -> Bool
prop_applicative_identity v = (pure id <*> v) == v

prop_applicative_composition
  :: Validated String (Fun Int Int)
  -> Validated String (Fun Int Int)
  -> Validated String Int
  -> Bool
prop_applicative_composition u v w =
  (pure (.) <*> u <*> v <*> w) == (u <*> (v <*> w))

prop_applicative_homomorphism :: Fun Int Int -> Int -> Bool
prop_applicative_homomorphism (Fun _ f) x =
  (pure f <*> pure x) == (pure (f x) :: Validated String Int)
```

TypeScript with Effect-TS:

```typescript
import { Either as E, Apply } from 'effect';

fc.assert(
  fc.property(eitherArb, (v) => {
    const applied = Apply.ap(E.right(identity), v);
    return E.equals(applied, v);
  })
);
```

## Monad laws

### The laws

A monad is a type constructor `M[A]` with `pure` (also called `unit` or `return`) and `flatMap` (also called `bind` or `>>=`) satisfying:

```haskell
-- Left identity
flatMap(pure(a))(f) == f(a)

-- Right identity
flatMap(m)(pure) == m

-- Associativity
flatMap(flatMap(m)(f))(g) == flatMap(m)(a => flatMap(f(a))(g))
```

The `pure` function wraps a value in the minimal monadic structure.
The `flatMap` function sequences computations where later steps depend on earlier results.

### Domain applications

Monads enable sequential composition of operations that produce effects or may fail.

Fail-fast error handling uses the Result or Either monad.
When a pipeline step fails, subsequent steps don't execute.
This avoids checking each step manually and makes the happy path code linear:

```haskell
processOrder :: UnvalidatedOrder -> Result OrderPlaced OrderError
processOrder unvalidated = do
  validated <- validateOrder unvalidated
  priced <- priceOrder validated
  confirmed <- confirmOrder priced
  pure $ OrderPlaced confirmed
```

The monad laws ensure this behaves correctly.
If any step returns an error, the entire computation returns that error without executing subsequent steps.

Workflow composition builds complex domain processes from smaller steps.
Each step produces the input for the next step, with effects tracked in the monad type:

```haskell
-- Each step depends on the previous result
processObservations :: RawData -> AsyncResult ProcessedData Error
processObservations raw = do
  calibrated <- calibrate raw
  threshold <- determineThreshold calibrated  -- depends on calibrated data
  filtered <- filterOutliers threshold calibrated  -- depends on both
  pure filtered
```

State threading uses the State monad to pass state through a sequence of computations without manual plumbing.
This is common in simulations and stateful algorithms.

### Kleisli composition

Monadic functions `A -> M[B]` form a category under Kleisli composition.
The composition operator `>=>` (sometimes called "fish") composes two monadic functions:

```haskell
(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> (a -> m c)
(f >=> g) x = flatMap(f(x))(g)
```

This enables building pipelines from smaller transformations:

```haskell
validateOrder :: UnvalidatedOrder -> Result ValidatedOrder Error
priceOrder :: ValidatedOrder -> Result PricedOrder Error
confirmOrder :: PricedOrder -> Result OrderConfirmed Error

processOrder :: UnvalidatedOrder -> Result OrderConfirmed Error
processOrder = validateOrder >=> priceOrder >=> confirmOrder
```

The monad laws ensure Kleisli composition is associative with `pure` as identity, making it a proper category.

### Property-based tests for monad laws

Rust:

```rust
proptest! {
    #[test]
    fn result_left_identity(a: i32) {
        let f = |x: i32| if x > 0 { Ok(x * 2) } else { Err("negative") };
        let left = Ok(a).and_then(f);
        let right = f(a);
        prop_assert_eq!(left, right);
    }

    #[test]
    fn result_right_identity(r: Result<i32, String>) {
        let with_pure = r.and_then(Ok);
        prop_assert_eq!(with_pure, r);
    }

    #[test]
    fn result_associativity(r: Result<i32, String>) {
        let f = |x: i32| if x > 0 { Ok(x + 1) } else { Err("negative".to_string()) };
        let g = |x: i32| if x < 100 { Ok(x * 2) } else { Err("too large".to_string()) };
        let left = r.and_then(f).and_then(g);
        let right = r.and_then(|a| f(a).and_then(g));
        prop_assert_eq!(left, right);
    }
}
```

Haskell:

```haskell
prop_monad_left_identity :: Int -> Fun Int (Result Int String) -> Bool
prop_monad_left_identity a (Fun _ f) =
  (return a >>= f) == f a

prop_monad_right_identity :: Result Int String -> Bool
prop_monad_right_identity m =
  (m >>= return) == m

prop_monad_associativity
  :: Result Int String
  -> Fun Int (Result Int String)
  -> Fun Int (Result Int String)
  -> Bool
prop_monad_associativity m (Fun _ f) (Fun _ g) =
  ((m >>= f) >>= g) == (m >>= (\x -> f x >>= g))
```

Python with Expression:

```python
from expression import Result

@given(st.integers())
def test_result_left_identity(a: int):
    f = lambda x: Result.Ok(x * 2) if x > 0 else Result.Error("negative")
    left = Result.Ok(a).bind(f)
    right = f(a)
    assert left == right

@given(result_strategy)
def test_result_right_identity(r: Result[int, str]):
    assert r.bind(Result.Ok) == r

@given(result_strategy)
def test_result_associativity(r: Result[int, str]):
    f = lambda x: Result.Ok(x + 1) if x > 0 else Result.Error("negative")
    g = lambda x: Result.Ok(x * 2) if x < 100 else Result.Error("too large")
    left = r.bind(f).bind(g)
    right = r.bind(lambda a: f(a).bind(g))
    assert left == right
```

## The abstraction hierarchy

The abstractions form a hierarchy where each level adds power and constraints.

### Functor → Applicative → Monad

Functor provides pure function lifting via `map`.
You can transform values inside a context without affecting the context structure.
This is the weakest abstraction, imposing minimal constraints.

Applicative extends functor with independent effect composition via `ap` and `pure`.
You can apply wrapped functions to wrapped values and combine multiple independent effects.
Effects must be independent: you cannot choose the next effect based on a previous result.

Monad extends applicative with dependent effect composition via `flatMap`.
You can sequence effects where later steps depend on earlier results.
This is the most powerful abstraction, imposing the strongest constraints.

### Selection guidance

Use the least powerful abstraction that solves your problem.
More powerful abstractions are more specialized, making code less reusable.

The power hierarchy trades flexibility for capability:
- Functor is most flexible, least capable
- Applicative is moderately flexible, moderately capable
- Monad is least flexible, most capable

A function requiring monad can only work with monads.
A function requiring only functor works with functors, applicatives, and monads.

| Need | Use | Example |
|------|-----|---------|
| Transform value in context | Functor | `result.map(transform)` |
| Combine independent validations | Applicative | `validate(a, b, c).mapN(construct)` |
| Chain dependent operations | Monad | `result.flatMap(x => computeNext(x))` |
| Parallel independent effects | Applicative | `traverse(items, fetchInParallel)` |
| Sequential dependent effects | Monad | `user.flatMap(loadPreferences).flatMap(applyTheme)` |

In domain modeling:
- Use functor when transforming domain values without affecting workflows
- Use applicative when validating multiple fields independently
- Use monad when later workflow steps depend on earlier results

## Parametricity and free theorems

### What parametricity provides

Parametric polymorphism constrains function implementations by preventing inspection of type parameters.
A function with signature `f[A]: List[A] => List[A]` cannot examine what type `A` actually is, only manipulate the list structure.

This uniformity across types dramatically reduces possible implementations.
Without parametricity, `f` could do anything based on runtime type checks.
With parametricity, `f` can only rearrange, duplicate, or drop elements, not transform them.

The possible implementations for `f[A]: List[A] => List[A]` include: identity, reverse, take n elements, drop n elements, duplicate elements, or combinations.
Notably absent: sorting (requires Ord), filtering by value (requires predicate), transforming elements (requires knowing the type).

### Free theorems from types

Philip Wadler's "Theorems for Free" shows that polymorphic type signatures imply equations the function must satisfy.

For `map[A, B]: (A => B) => List[A] => List[B]`, parametricity gives:

```haskell
map(g) . map(f) == map(g . f)
```

This is the functor composition law, derived purely from the type signature.
You don't need to test it, the type guarantees it.

For `filter[A]: (A => Bool) => List[A] => List[A]`, parametricity gives:

```haskell
map(f) . filter(p) == filter(p . f) . map(f)
```

The function commutes with map in a specific way.
This follows from the type, not implementation details.

### Testing implications

Parametricity reduces testing burden for generic functions.

When testing a polymorphic function, you can use simple types like Int or String.
The parametricity theorem guarantees behavior is uniform across all types.
If tests pass for Int, the function behaves identically for any other type.

For `reverse[A]: List[A] => List[A]`, testing with `List[Int]` proves correctness for all types.
The implementation cannot vary by type because it cannot inspect the type parameter.

This dramatically reduces test cases.
Instead of testing every type, test one representative type.
The type system guarantees uniform behavior.

Generic functions need fewer tests than specialized functions.
A function `sumInts: List[Int] => Int` has many possible implementations, most wrong.
A function `fold[A, B]: (B => A => B) => B => List[A] => B` has very few implementations, and parametricity eliminates most bugs.

### Laws and parametricity together

Combining parametricity with laws creates strong correctness guarantees.

For monoids, parametricity plus laws mean:
```haskell
mconcat[A]: Monoid A => List[A] => A
```

This function has essentially one implementation: fold with mappend and mempty.
Parametricity prevents examining the type, laws constrain how to combine elements.

For functors, parametricity plus functor laws mean:
```haskell
fmap[A, B]: (A => B) => F[A] => F[B]
```

The implementation must preserve structure and apply the function uniformly.
Any other behavior violates parametricity or the laws.

Testing becomes validation that the implementation actually satisfies the laws, not discovering what the function does.
The type signature already tells you what it must do.

## Cross-language patterns

### Rust

Rust uses the proptest crate for property-based testing, providing generators for arbitrary values and automatic shrinking of failures.

The Arbitrary trait defines how to generate random instances:

```rust
use proptest::prelude::*;

#[derive(Debug, Clone, PartialEq)]
struct Money {
    amount: i64,
    currency: String,
}

impl Arbitrary for Money {
    type Parameters = ();
    type Strategy = BoxedStrategy<Self>;

    fn arbitrary_with(_args: Self::Parameters) -> Self::Strategy {
        (any::<i64>(), "[A-Z]{3}")
            .prop_map(|(amount, currency)| Money { amount, currency })
            .boxed()
    }
}
```

Testing laws:

```rust
proptest! {
    #[test]
    fn monoid_associativity(a: Money, b: Money, c: Money) {
        prop_assume!(a.currency == b.currency && b.currency == c.currency);
        let left = a.combine(&b).combine(&c);
        let right = a.combine(&b.combine(&c));
        prop_assert_eq!(left, right);
    }
}
```

The `prop_assume!` macro filters generated inputs, ensuring tests only run on valid inputs like same-currency money.

### Haskell

Haskell uses QuickCheck, the original property-based testing library that inspired all others.

The Arbitrary type class generates random values:

```haskell
instance Arbitrary Money where
  arbitrary = Money <$> arbitrary <*> elements ["USD", "EUR", "GBP"]

instance Arbitrary a => Arbitrary (Result a String) where
  arbitrary = oneof [Ok <$> arbitrary, Error <$> arbitrary]
```

Testing laws:

```haskell
import Test.QuickCheck

prop_monoid_assoc :: Money -> Money -> Money -> Property
prop_monoid_assoc x y z =
  currency x == currency y && currency y == currency z ==>
    (x <> y) <> z == x <> (y <> z)

main :: IO ()
main = quickCheck prop_monoid_assoc
```

The `==>` operator filters inputs to only test valid cases.

QuickCheck automatically shrinks failing cases to minimal examples, making debugging easier.

### TypeScript

TypeScript uses the fast-check library for property-based testing with excellent type inference.

Defining arbitrary generators:

```typescript
import * as fc from 'fast-check';

const moneyArb = fc.record({
  amount: fc.integer(),
  currency: fc.constantFrom('USD', 'EUR', 'GBP'),
});

const resultArb = <T, E>(
  valueArb: fc.Arbitrary<T>,
  errorArb: fc.Arbitrary<E>
): fc.Arbitrary<Result<T, E>> =>
  fc.oneof(
    valueArb.map(Ok),
    errorArb.map(Error)
  );
```

Testing laws:

```typescript
import { pipe } from 'effect';
import * as E from 'effect/Either';

describe('Result functor laws', () => {
  it('satisfies identity law', () => {
    fc.assert(
      fc.property(resultArb(fc.integer(), fc.string()), (r) => {
        const mapped = pipe(r, E.map((x) => x));
        return E.equals(mapped, r);
      })
    );
  });

  it('satisfies composition law', () => {
    fc.assert(
      fc.property(
        resultArb(fc.integer(), fc.string()),
        fc.func(fc.integer()),
        fc.func(fc.integer()),
        (r, f, g) => {
          const left = pipe(r, E.map(f), E.map(g));
          const right = pipe(r, E.map((x) => g(f(x))));
          return E.equals(left, right);
        }
      )
    );
  });
});
```

Effect-TS provides lawful implementations of functor, applicative, and monad for various types.

### Python

Python uses Hypothesis for property-based testing with excellent integration for standard library types.

Defining strategies:

```python
from hypothesis import given, strategies as st
from dataclasses import dataclass

@dataclass(frozen=True)
class Money:
    amount: int
    currency: str

money_strategy = st.builds(
    Money,
    amount=st.integers(),
    currency=st.sampled_from(['USD', 'EUR', 'GBP'])
)

def result_strategy(value_strategy, error_strategy):
    return st.one_of(
        value_strategy.map(lambda v: Result.Ok(v)),
        error_strategy.map(lambda e: Result.Error(e))
    )
```

Testing laws with Expression library:

```python
from expression import Result
from hypothesis import given, strategies as st

@given(
    result_strategy(st.integers(), st.text()),
    st.functions(like=lambda x: x, returns=st.integers()),
    st.functions(like=lambda x: x, returns=st.integers())
)
def test_functor_composition(r: Result[int, str], f, g):
    left = r.map(f).map(g)
    right = r.map(lambda x: g(f(x)))
    assert left == right
```

Hypothesis automatically generates function implementations for `st.functions`, enabling testing higher-order properties.

For domain types, implement `__eq__` and `__hash__` properly to enable shrinking and meaningful failure reports.

## References

- Scott Wlaschin, "Domain Modeling Made Functional" (2018), Chapter 4 (monoids in domain modeling), Chapter 9 (property-based testing), Chapter 10 (composition)
- See theoretical-foundations.md for categorical foundations of these laws and their origins in category theory
- See domain-modeling.md for applying law-governed abstractions to domain design, especially Pattern 4 (workflows as pipelines)
- See railway-oriented-programming.md for Result and Either monad laws in error handling contexts
- Philip Wadler, "Theorems for Free!" (1989), functional programming conference
- Language-specific testing guides in rust-development/05-testing.md, python-development.md, typescript-nodejs-development.md
