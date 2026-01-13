# Theoretical foundations

## Purpose

This document maps practical domain modeling patterns to their foundations in category theory, type theory, and abstract algebra.

Consult this document for:
- Deeper understanding of why patterns work
- Formal semantics and correctness proofs
- Connections between seemingly different concepts
- Theoretical context for practical techniques

For practical application, see:
- domain-modeling.md for patterns
- algebraic-data-types.md for implementation techniques
- railway-oriented-programming.md for error handling composition
- functional-reactive-programming.md for the foundational paradigm connecting category theory to interactive system design

## Contents

- [Algebraic data types as initial algebras](#algebraic-data-types-as-initial-algebras)
  - [Product types as categorical products](#product-types-as-categorical-products)
  - [Sum types as coproducts](#sum-types-as-coproducts)
  - [Algebraic laws](#algebraic-laws)
  - [F-algebras and catamorphisms](#f-algebras-and-catamorphisms)
- [Workflows as morphisms in Kleisli categories](#workflows-as-morphisms-in-kleisli-categories)
  - [Functions as morphisms](#functions-as-morphisms)
  - [Kleisli category for a monad](#kleisli-category-for-a-monad)
  - [Monad laws as category laws](#monad-laws-as-category-laws)
  - [Functor, Applicative, Monad hierarchy](#functor-applicative-monad-hierarchy)
- [Effect systems as indexed monads](#effect-systems-as-indexed-monads)
  - [Simple monads for effects](#simple-monads-for-effects)
  - [Indexed monads for effect tracking](#indexed-monads-for-effect-tracking)
  - [Monad transformers](#monad-transformers)
  - [Algebraic effects and handlers](#algebraic-effects-and-handlers)
- [State machines as coalgebras](#state-machines-as-coalgebras)
  - [Coalgebras for endofunctors](#coalgebras-for-endofunctors)
- [Aggregates and optics](#aggregates-and-optics)
  - [Lenses for nested data access](#lenses-for-nested-data-access)
  - [Prisms for sum type navigation](#prisms-for-sum-type-navigation)
  - [Optics hierarchy](#optics-hierarchy)
- [The category of effects](#the-category-of-effects)
  - [Effects as monoidal category](#effects-as-monoidal-category)
  - [Effect handlers as algebra homomorphisms](#effect-handlers-as-algebra-homomorphisms)
- [Indexed monad transformer stacks in practice](#indexed-monad-transformer-stacks-in-practice)
  - [Theoretical ideal](#theoretical-ideal)
  - [Practical challenges](#practical-challenges)
  - [Pragmatic approach](#pragmatic-approach)
  - [Best practices for effect composition](#best-practices-for-effect-composition)
- [The Decider pattern: minimal algebraic interface](#the-decider-pattern-minimal-algebraic-interface)
  - [Formal definition](#formal-definition)
  - [Coalgebra-algebra adjoint pair](#coalgebra-algebra-adjoint-pair)
  - [Signature-Algebra-Interpreter correspondence](#signature-algebra-interpreter-correspondence)
  - [State reconstruction as catamorphism](#state-reconstruction-as-catamorphism-decider)
  - [Monoidal composition of Deciders](#monoidal-composition-of-deciders)
  - [Product monoid for aggregate state](#product-monoid-for-aggregate-state)
- [Event sourcing as algebraic duality](#event-sourcing-as-algebraic-duality)
  - [Events as free monoid](#events-as-free-monoid)
  - [State reconstruction as catamorphism](#state-reconstruction-as-catamorphism)
  - [CQRS as profunctor structure](#cqrs-as-profunctor-structure)
  - [Projections as functors](#projections-as-functors)
  - [Temporal semantics](#temporal-semantics)
- [Reactive systems and comonads](#reactive-systems-and-comonads)
  - [Signals as comonads](#signals-as-comonads)
  - [Signal graphs as free categories](#signal-graphs-as-free-categories)
  - [Web components as coalgebras](#web-components-as-coalgebras)
  - [Composing reactive systems](#composing-reactive-systems)
  - [Backpressure as algebraic constraint](#backpressure-as-algebraic-constraint)
- [Materialized views as Galois connections](#materialized-views-as-galois-connections)
  - [The abstraction-concretion pair](#the-abstraction-concretion-pair)
  - [Views as quotients of the event monoid](#views-as-quotients-of-the-event-monoid)
  - [Query caching as memoization](#query-caching-as-memoization)
  - [Temporal versioning as indexed types](#temporal-versioning-as-indexed-types)
- [The ladder of pattern quality](#the-ladder-of-pattern-quality)
- [Cross-references to practical documents](#cross-references-to-practical-documents)
- [Further reading](#further-reading)

## Algebraic data types as initial algebras

### Product types as categorical products

**Practical pattern**: Record types combine data with AND

```haskell
data Measurement = Measurement
  { value :: Float
  , uncertainty :: Float
  , qualityScore :: Float
  }
```

**Category-theoretic interpretation**:

A product type is a categorical product in the category of types and functions.

For types A, B, the product A × B is characterized by:
- Projections: fst :: A × B → A, snd :: A × B → B
- Universal property: for any type C with functions f :: C → A and g :: C → B, there exists unique h :: C → A × B such that fst ∘ h = f and snd ∘ h = g

```
        h
    C -----> A × B
     \      /  |
    f \    /fst|snd
       \  /    |
        vv     v
        A      B
```

This universal property makes products the "most general" way to combine types.

**Consequences**:

1. Products are unique up to isomorphism
2. Products compose: (A × B) × C ≅ A × (B × C)
3. Unit type (()) is identity: A × () ≅ A
4. Products commute: A × B ≅ B × A

**Connection to algebra**: Product types correspond to multiplication in algebraic notation.

### Sum types as coproducts

**Practical pattern**: Discriminated unions represent choice with OR

```haskell
data Result a e
  = Ok a
  | Error e
```

**Category-theoretic interpretation**:

A sum type is a categorical coproduct (dual of product).

For types A, B, the coproduct A + B is characterized by:
- Injections: inl :: A → A + B, inr :: B → A + B
- Universal property: for any type C with functions f :: A → C and g :: B → C, there exists unique h :: A + B → C such that h ∘ inl = f and h ∘ inr = g

```
    A      B
     \    /
   inl\  /inr
       \/
      A + B
        |
        | h
        v
        C
```

**Consequences**:

1. Coproducts are unique up to isomorphism
2. Coproducts compose: (A + B) + C ≅ A + (B + C)
3. Void type (⊥) is identity: A + ⊥ ≅ A
4. Coproducts commute: A + B ≅ B + A

**Connection to algebra**: Sum types correspond to addition in algebraic notation.

### Algebraic laws

Product and sum types satisfy algebraic laws:

```
Distributivity:
  A × (B + C) ≅ (A × B) + (A × C)

Identity:
  A × 1 ≅ A
  A + 0 ≅ A

Associativity:
  (A × B) × C ≅ A × (B × C)
  (A + B) + C ≅ A + (B + C)

Commutativity:
  A × B ≅ B × A
  A + B ≅ B + A
```

These laws enable algebraic manipulation of types, analogous to manipulating polynomial expressions.

### F-algebras and catamorphisms

**Pattern**: Structural recursion over recursive data types

A recursive data structure can be modeled as the initial algebra for a functor.

For lists:
```haskell
data List a = Nil | Cons a (List a)

-- Corresponds to functor:
data ListF a r = NilF | ConsF a r

-- List a is the initial algebra for ListF a
-- The initial algebra is (List a, in :: ListF a (List a) -> List a)
-- where in NilF = Nil, in (ConsF x xs) = Cons x xs
-- Catamorphism is the unique algebra morphism to any other algebra:
cata :: (ListF a b -> b) -> List a -> b
```

**Practical consequence**: Every recursive data type has a canonical "fold" operation that expresses all structural recursion.
Initiality guarantees that cata is the unique homomorphism from the initial algebra to any other algebra structure.

**See also**: domain-modeling.md pattern matching, algebraic-data-types.md for concrete examples

## Workflows as morphisms in Kleisli categories

### Functions as morphisms

**Basic category of types**:
- Objects: Types (A, B, C, ...)
- Morphisms: Functions (f :: A → B)
- Composition: g ∘ f for f :: A → B, g :: B → C
- Identity: id :: A → A

Functions compose associatively and have identity.

### Kleisli category for a monad

**Practical pattern**: Composing functions that return Result, Option, Async

```haskell
validateOrder :: UnvalidatedOrder -> Result ValidatedOrder ValidationError
priceOrder :: ValidatedOrder -> Result PricedOrder PricingError
```

These don't compose with regular function composition because output type (Result B) doesn't match input type (B).

**Category-theoretic solution**: Kleisli category

For a monad M, the Kleisli category has:
- Objects: Same types as base category
- Morphisms: Functions A → M B (Kleisli arrows)
- Composition: >=> (Kleisli composition, implemented via bind)
- Identity: return :: A → M A

```haskell
-- Kleisli composition
(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> (a -> m c)
f >=> g = \x -> f x >>= g

-- Identity law: return >=> f ≡ f ≡ f >=> return
-- Associativity: (f >=> g) >=> h ≅ f >=> (g >=> h)
```

**Practical consequence**: bind (>>=) enables composition of effectful computations while maintaining category laws.

**Connection to practice**: railway-oriented-programming.md uses bind to compose Result-returning functions.

### Monad laws as category laws

Monads must satisfy laws that ensure Kleisli composition forms a valid category:

```haskell
-- Left identity: return >=> f ≡ f
bind (return x) f ≡ f x

-- Right identity: f >=> return ≡ f
bind m return ≡ m

-- Associativity: (f >=> g) >=> h ≡ f >=> (g >=> h)
bind (bind m f) g ≡ bind m (\x -> bind (f x) g)
```

These laws ensure:
1. return doesn't alter computation
2. Nested binds can be flattened
3. Order of composition doesn't matter (associativity)

**Practical consequence**: If monad laws hold, we can refactor and compose Kleisli arrows freely without changing semantics.

### Functor, Applicative, Monad hierarchy

```haskell
class Functor f where
  fmap :: (a -> b) -> f a -> f b

class Functor f => Applicative f where
  pure :: a -> f a
  (<*>) :: f (a -> b) -> f a -> f b

class Applicative m => Monad m where
  return :: a -> m a  -- same as pure
  (>>=) :: m a -> (a -> m b) -> m b
```

**Relationships**:
- Functor: Can map functions over wrapped values
- Applicative: Can combine multiple wrapped values in parallel
- Monad: Can chain operations where each depends on previous result

**Laws**:
```haskell
-- Functor laws:
fmap id ≡ id
fmap (g . f) ≡ fmap g . fmap f

-- Applicative laws (homomorphism):
pure f <*> pure x ≡ pure (f x)

-- Monad laws (as above)
```

**Practical use**:
- Functor (map): Transform successful results without changing error channel
- Applicative: Validate multiple fields in parallel, collecting all errors
- Monad (bind): Chain dependent computations, short-circuit on first error

**See also**: railway-oriented-programming.md#composing-in-parallel-with-applicatives

## Effect systems as indexed monads

### Simple monads for effects

**Practical pattern**: Result, Option, Async for error and IO effects

```haskell
Result a e    -- may fail with error e
Option a      -- may return nothing
Async a       -- asynchronous computation
```

Problem: Effects not tracked at type level. Result Int String could have many different semantic meanings.

### Indexed monads for effect tracking

**Theoretical solution**: Index monad by input/output effects

```haskell
class IxMonad m where
  ireturn :: a -> m i i a
  ibind :: m i j a -> (a -> m j k b) -> m i k b
```

Type parameters i, j, k track effect state:
- i: Effects at input
- j: Effects at intermediate step
- k: Effects at output

**Example: File handle tracking**

```haskell
data FileState = Closed | Opened
data FileHandle :: FileState -> FileState -> * -> * where
  -- Indexed monad tracking file state transitions

openFile :: FilePath -> FileHandle Closed Opened Handle
readFile :: FileHandle Opened Opened String
closeFile :: Handle -> FileHandle Opened Closed ()

-- Indexed bind enables safe composition:
-- ibind :: FileHandle i j a -> (a -> FileHandle j k b) -> FileHandle i k b

-- Type system prevents:
readFile `ibind` (\_ -> closeFile) `ibind` (\_ -> readFile)  -- Can't read after close
```

**Practical limitations**:

Most languages lack indexed monad support:
- Type inference becomes intractable
- Ergonomics suffer (heavy type annotations)
- Library support minimal

**Pragmatic approach**:

1. Use simple effect types (Result, Async) for common cases
2. Document effects in signatures: AsyncResult<A, E>
3. Use effect systems (Effect-TS, Polysemy) where available
4. Reserve indexed monads for critical safety properties

**See also**: architectural-patterns.md#effect-signatures, domain-modeling.md#workflows-as-type-safe-pipelines

### Monad transformers

**Pattern**: Layer multiple effects (Result + Async)

```haskell
type AsyncResult a e = Async (Result a e)
```

**Theoretical structure**:

Monad transformers add one effect to existing monad:

```haskell
newtype ResultT e m a = ResultT (m (Result a e))

instance Monad m => Monad (ResultT e m) where
  return x = ResultT (return (Ok x))
  m >>= f = ResultT $ do
    result <- m  -- unwrap outer monad
    case result of
      Ok x -> f x    -- apply function
      Error e -> return (Error e)
```

**Stack composition**:

```haskell
type App a = ReaderT Config (StateT AppState (ExceptT Error IO)) a

-- Equivalently: layers of effects
-- IO (may perform I/O)
-- ExceptT Error (may fail with Error)
-- StateT AppState (has mutable state)
-- ReaderT Config (has read-only config)
```

**Practical challenges**:

1. Stack ordering matters (not always commutative)
2. Lift functions needed to access lower layers: lift, liftIO
3. Type inference struggles with deep stacks
4. Performance overhead from multiple wrapping

**Pragmatic approach**:

1. Keep stacks shallow (2-3 effects max)
2. Use type aliases: type AppM a = ReaderT Config IO a
3. Prefer specialized types (AsyncResult) over general transformers
4. Consider effect systems (algebraic effects) as alternative

**See also**: railway-oriented-programming.md#adding-the-async-effect

### Algebraic effects and handlers

**Alternative to monad transformers**: Algebraic effects

```haskell
-- Define effect operations
data FileSystem :: Effect where
  ReadFile :: FilePath -> FileSystem String
  WriteFile :: FilePath -> String -> FileSystem ()

-- Program using effects (no monad transformers)
processFile :: FilePath -> Eff '[FileSystem, Error] Result
processFile path = do
  contents <- readFile path  -- FileSystem effect
  validate contents          -- may throw Error effect
  writeFile outputPath result
  return result

-- Handle effects at edges
runFileSystem :: Eff '[FileSystem, Error] a -> IO (Either Error a)
```

**Advantages**:
- Effects can be reordered more flexibly (handlers interpret effect sets, order matters less than with transformers)
- No lift boilerplate
- More modular effect handlers
- Better type inference

**Status**:
- Research-stage in most languages
- Production-ready in OCaml (effect handlers)
- Libraries: Polysemy (Haskell), ZIO (Scala), Effect-TS (TypeScript)

**See also**: architectural-patterns.md for effect composition in practice

## State machines as coalgebras

### Coalgebras for endofunctors

Dual to F-algebras (which model data construction), coalgebras model state-based computations.

**Practical pattern**: State machines with transitions

```haskell
data State = StateA | StateB | StateC

transition :: State -> (Output, State)
```

**Category-theoretic interpretation**:

A coalgebra for functor F is:
```haskell
c :: S -> F S
```

For Moore machines: F S = Output × S (output depends only on state).
Note that Mealy machines use F S = Input → (Output × S) where output depends on both state and input.

```haskell
-- Moore machine coalgebra
mooreCoalg :: State -> (Output, State)

-- Mealy machine coalgebra
mealyCoalg :: State -> Input -> (Output, State)
```

**Final coalgebra**:

Just as initial algebras correspond to finite data, final coalgebras correspond to potentially infinite processes.

**Behavioral equivalence**: Two states are behaviorally equivalent if they produce same observations (bisimulation).

**Practical consequence**: State machines can be reasoned about via their observable behavior, not internal representation.

**See also**: domain-modeling.md#state-machines-for-entity-lifecycles

## Aggregates and optics

### Lenses for nested data access

**Practical pattern**: Access/update fields in nested records

```haskell
data Address = Address { street :: String, city :: String }
data Person = Person { name :: String, address :: Address }

-- Without lens: deep update is verbose
updateCity :: String -> Person -> Person
updateCity newCity person =
  person { address = (address person) { city = newCity } }

-- With lens: compositional update
cityL :: Lens' Person String
cityL = addressL . cityFieldL

set cityL "New York" person
```

**Category-theoretic interpretation**:

A lens is a pair of functions:
```haskell
data Lens s a = Lens
  { view :: s -> a           -- getter
  , update :: (a, s) -> s    -- setter
  }

-- Laws:
-- GetPut: update (view s, s) = s
-- PutGet: view (update (a, s)) = a
-- PutPut: update (a', update (a, s)) = update (a', s)
```

Lenses are morphisms in category of types with product × and function →.

Lens composition is covariant in the focus direction: composing `addressL :: Lens' Person Address` with `cityFieldL :: Lens' Address String` gives `cityL :: Lens' Person String`, moving deeper into the structure following the flow of data access.

**Profunctor representation**:

```haskell
type Lens s t a b = forall f. Functor f => (a -> f b) -> s -> f t
```

This representation enables lens composition via regular function composition.

**Practical use**: Accessing aggregate internals while maintaining encapsulation

**See also**: domain-modeling.md#aggregates-as-consistency-boundaries

### Prisms for sum type navigation

**Practical pattern**: Access cases in discriminated unions

```haskell
data Result a e = Ok a | Error e

okPrism :: Prism' (Result a e) a
-- Allows: preview okPrism result :: Maybe a
```

**Category-theoretic interpretation**:

A prism is dual to a lens (for sum types vs product types):

```haskell
data Prism s a = Prism
  { match :: s -> Either a s  -- extract if matches
  , build :: a -> s            -- inject
  }

-- Note: Using Either a s (match on Right) instead of conventional Either s a
-- to emphasize successful extraction as the primary case

-- Laws (dual to lens laws)
-- MatchBuild: match (build a) = Right a
-- BuildMatch: either build id (match s) = s
```

**Practical use**: Pattern matching on state machine variants, extracting errors from Result types.

### Optics hierarchy

```
           Iso
          /   \
       Lens   Prism
          \   /
         Traversal
            |
          Fold
```

- **Iso**: Bidirectional conversion (isomorphism)
- **Lens**: Access product type fields
- **Prism**: Access sum type cases
- **Traversal**: Access multiple elements
- **Fold**: Read-only access

**Practical consequence**: Uniform interface for nested data access across different type structures.

**See also**: Optics libraries (lens, optics, monocle)

## The category of effects

### Effects as monoidal category

Effects can be modeled as morphisms in a monoidal category:

```
Category: Types and functions
Objects: Types
Morphisms: A → M B (effectful functions)
Tensor: ⊗ (effect composition)
Unit: Id (no effect)
```

**Example effects**:
```haskell
Error e:  Functions that may fail
State s:  Functions that access state
Reader r: Functions that require environment
Writer w: Functions that produce logs
IO:       Functions that perform I/O
```

**Monoidal structure**: Effects compose

```haskell
-- Note: ⊗ denotes abstract effect composition; concrete realization
-- depends on transformer stack ordering (ExceptT e (StateT s m) ≠ StateT s (ExceptT e m))

-- Compose effects (monad transformers)
Error e ⊗ State s ≅ StateT s (Either e)

-- Associativity
(Error e ⊗ State s) ⊗ Reader r ≅ Error e ⊗ (State s ⊗ Reader r)

-- Identity
Error e ⊗ Id ≅ Error e
```

**Practical consequence**: Effects can be combined in predictable ways following monoidal laws.

### Effect handlers as algebra homomorphisms

**Pattern**: Interpreting effects

```haskell
-- Effect operations
data FileOp a where
  Read :: FilePath -> FileOp String
  Write :: FilePath -> String -> FileOp ()

-- Handler interprets to IO
handleIO :: FileOp a -> IO a
handleIO (Read path) = readFile path
handleIO (Write path contents) = writeFile path contents

-- Handler interprets to pure (for testing)
handlePure :: FileOp a -> State FileSystem a
handlePure (Read path) = gets (lookup path)
handlePure (Write path contents) = modify (insert path contents)
```

**Category-theoretic interpretation**:

Handlers are algebra homomorphisms preserving structure:

```haskell
handle :: Effect a -> Target a

-- Preserves composition
handle (e1 >> e2) = handle e1 >> handle e2

-- Preserves identity
handle (return x) = return x
```

**Practical consequence**: Multiple interpretations of same effectful program (production vs test, pure vs IO).

## Indexed monad transformer stacks in practice

### Theoretical ideal

All effects tracked at type level, composed as indexed monad transformers:

```haskell
type Workflow i j a = IxMonadT (ReaderT Config (StateT AppState (ExceptT Error IO))) i j a

-- i: Effects at input (what we require)
-- j: Effects at output (what we produce)
-- a: Return value
```

Type signatures document complete effect behavior:

```haskell
processData
  :: Workflow
      '[Reader Config, Error DatabaseError]  -- input effects
      '[State Results, Error ProcessingError, IO] -- output effects
      ProcessedData
```

### Practical challenges

1. **Type inference**: Compiler cannot infer complex indexed types
2. **Ergonomics**: Heavy type annotations required everywhere
3. **Library support**: Most libraries don't support indexed effects
4. **Compilation time**: Complex type-level computation is slow
5. **Error messages**: Type errors become incomprehensible

### Pragmatic approach

**Level 1: Simple effect types** (most code)

```haskell
type AsyncResult a e = Async (Result a e)

-- Document effects in signature but don't index
processData :: Config -> Data -> AsyncResult ProcessedData Error
```

**Level 2: Effect systems** (where available)

```haskell
-- Effect-TS (TypeScript)
Effect<A, E, R>
  A: success type
  E: error type
  R: required environment

// ZIO (Scala)
ZIO[R, E, A]
  R: required environment
  E: error type
  A: success type
```

**Level 3: Shallow monad transformers** (2-3 effects max)

```haskell
type AppM a = ReaderT Config (ExceptT Error IO) a

-- Keep stack shallow, use type aliases
```

**Level 4: Indexed monads** (critical safety properties only)

```haskell
-- File handle tracking
data FileHandle :: FileState -> * where
  openFile :: FilePath -> FileHandle Closed Opened Handle
  closeFile :: FileHandle Opened Closed ()

-- Type system prevents invalid operations
```

### Best practices for effect composition

1. **Document effects explicitly**: Always include effects in type signatures
2. **Prefer specialized types**: AsyncResult over generic transformers
3. **Keep stacks shallow**: 2-3 effects maximum
4. **Use type aliases**: Hide transformer stack complexity
5. **Consider effect systems**: Use Effect-TS, ZIO, Polysemy where available
6. **Test effect handlers**: Write handlers for production and testing

**See also**:
- architectural-patterns.md for effect composition patterns
- railway-oriented-programming.md for Result composition
- domain-modeling.md#workflows-as-type-safe-pipelines

## The Decider pattern: minimal algebraic interface

The Decider pattern, formalized by Jérémie Chassaing, provides the minimal algebraic interface for event-sourced aggregates.
It unifies command handling and state reconstruction into a single coherent structure that is both coalgebra (commands unfold into events) and algebra (events fold into state).
This pattern is the concrete realization of Ghosh's Signature → Algebra → Interpreter framework applied to event sourcing.

### Formal definition

A Decider is a triple of operations with an initial state:

```haskell
data Decider cmd state event = Decider
  { decide       :: cmd -> state -> [event]
  , evolve       :: state -> event -> state
  , initialState :: state
  , isTerminal   :: state -> Bool  -- optional: detect terminal states
  }
```

**Type signatures**:
- `decide: Command → State → List<Event>` produces events based on current state and command
- `evolve: State → Event → State` applies a single event to state
- `initialState: State` provides the starting state
- `isTerminal: State → Bool` (optional) determines if aggregate reached terminal state

**Minimal complete definition**: decide, evolve, initialState form the essential triple.

The decider is pure: both decide and evolve are referentially transparent functions with no side effects.
Effects (persistence, event publishing, external queries) are handled by the interpreter layer, not the decider itself.

**Code example: Bank account decider**

```haskell
data AccountCommand
  = OpenAccount CustomerId InitialBalance
  | Deposit Amount
  | Withdraw Amount
  | CloseAccount

data AccountEvent
  = AccountOpened CustomerId InitialBalance
  | Deposited Amount
  | Withdrawn Amount
  | AccountClosed
  | WithdrawalRejected Reason

data AccountState
  = NotOpened
  | Active { balance :: Amount }
  | Closed

accountDecider :: Decider AccountCommand AccountState AccountEvent
accountDecider = Decider
  { decide = \cmd state -> case (cmd, state) of
      (OpenAccount cid bal, NotOpened) -> [AccountOpened cid bal]
      (Deposit amt, Active bal) -> [Deposited amt]
      (Withdraw amt, Active bal)
        | amt <= bal -> [Withdrawn amt]
        | otherwise -> [WithdrawalRejected InsufficientFunds]
      (CloseAccount, Active _) -> [AccountClosed]
      _ -> []  -- invalid command for current state

  , evolve = \state event -> case (state, event) of
      (NotOpened, AccountOpened _ bal) -> Active bal
      (Active bal, Deposited amt) -> Active (bal + amt)
      (Active bal, Withdrawn amt) -> Active (bal - amt)
      (Active _, AccountClosed) -> Closed
      _ -> state  -- failure events or invalid transitions preserve state

  , initialState = NotOpened

  , isTerminal = \state -> case state of
      Closed -> True
      _ -> False
  }
```

**Practical consequence**:
The entire aggregate logic is captured in one pure value.
Testing requires no mocking or infrastructure: given command and state, verify events.
Given events and initial state, verify final state.

### Coalgebra-algebra adjoint pair

The Decider exhibits coalgebra-algebra duality through its two core operations.

**decide as coalgebra** (command unfolding):

```haskell
decide :: cmd -> state -> [event]
-- equivalently: decide :: (cmd, state) -> F event
-- where F event = [event] is the list functor
```

This is a coalgebra for the functor F X = Command × State → List X:
- Given current aggregate state and a command
- Unfold structure into a list of events
- Events represent the "transition trace" from current state

The coalgebra perspective emphasizes observation: decide observes the command-state pair and produces events as observable outputs.

**evolve as algebra** (event folding):

```haskell
evolve :: state -> event -> state
-- equivalently: evolve :: (state, event) -> state
```

This is an algebra for the list functor List Event → State:
- Given a sequence of events (the free monoid over events)
- Fold them into a single state value
- State is the "collapsed history" of all events

The algebra perspective emphasizes construction: evolve constructs state from event sequences.

**ASCII diagram: The adjoint pair**

```
         decide (coalgebra)
Command ──────────────────────▶ List<Event>
   │                                 │
   │ (contravariant)         (covariant)
   │                                 │
   └──────── State ◀─────────────────┘
                 evolve (algebra)
```

**Category-theoretic interpretation**:

The pair (decide, evolve) forms an adjunction between the command category (contravariant in commands) and the event category (covariant in events), with state as the pivot.

- Left adjoint (decide): Free construction from commands to events via state
- Right adjoint (evolve): Forgetful functor from event sequences to state

The adjunction satisfies the unit-counit equations:
- Unit: evolve ∘ decide gives a state transition endomorphism
- Counit: decide ∘ evolve gives an event sequence endomorphism (modulo state projection)

This duality is analogous to CQRS profunctor structure (see [CQRS as profunctor structure](#cqrs-as-profunctor-structure)), but at the aggregate level rather than system level.

**Practical consequence**:
The coalgebra-algebra duality ensures consistency between command handling (decide) and state reconstruction (evolve).
If decide produces events e1, e2, e3, then folding those events via evolve must yield a state consistent with the command's intent.
This bidirectional coherence is guaranteed by the adjunction, not by programmer discipline.

### Signature-Algebra-Interpreter correspondence

The Decider pattern instantiates Ghosh's three-level architecture (from "Functional and Reactive Domain Modeling"):

**Level 1: Signature** (types and operation names)

```haskell
-- Signature defines the interface
signature EventSourcingSignature = {
  types: Command, Event, State
  operations:
    decide: Command → State → List<Event>
    evolve: State → Event → State
    initial: State
}
```

The signature specifies what operations exist, but not their implementation.
This is the "module signature" in ML terminology.

**Level 2: Algebra** (implementation of signature)

```haskell
-- Algebra provides concrete implementation
algebra AccountAlgebra : EventSourcingSignature = {
  Command = AccountCommand
  Event = AccountEvent
  State = AccountState

  decide = \cmd state -> ... -- business logic here
  evolve = \state event -> ... -- state transition here
  initial = NotOpened
}
```

The Decider IS the algebra: it provides concrete implementations of decide, evolve, and initialState for specific types.

Multiple algebras can exist for the same signature (different aggregates: Account, Order, Inventory).

**Level 3: Interpreter** (effects and persistence)

```haskell
-- Interpreter runs the pure algebra against effectful infrastructure
data EventSourcingInterpreter m = Interpreter
  { loadEvents :: AggregateId -> m [Event]
  , saveEvents :: AggregateId -> [Event] -> m ()
  , snapshot   :: AggregateId -> State -> m ()  -- optional optimization
  }

runDecider
  :: Monad m
  => EventSourcingInterpreter m
  -> Decider cmd state event
  -> AggregateId
  -> cmd
  -> m [event]
runDecider interp decider aggId cmd = do
  events <- loadEvents interp aggId
  let currentState = foldl' (evolve decider) (initialState decider) events
  let newEvents = decide decider cmd currentState
  saveEvents interp aggId newEvents
  return newEvents
```

The interpreter handles all effects:
- Loading events from event store (IO, database queries)
- Saving new events (IO, transactions)
- Snapshot management (performance optimization)
- Concurrency control (optimistic locking)

**Separation of concerns**:

```
Signature (interface)
    ↓
Algebra (pure logic) ← Decider lives here
    ↓
Interpreter (effects) ← fmodel, infrastructure code lives here
```

**Practical consequence**:
The three-level separation enables:
- Testing the algebra (Decider) in isolation without effects
- Multiple interpreters: production (Postgres), test (in-memory), simulation
- Swapping persistence mechanisms without changing business logic
- Formal verification of the algebra (pure functions are amenable to proof)

**Connection to fmodel-rust**:

The fmodel library implements exactly this pattern:
- Decider is the algebra (pure)
- EventSourcingAggregate is the interpreter (effectful)
- User code implements decide and evolve
- Library handles persistence, optimization, error recovery

### State reconstruction as catamorphism {#state-reconstruction-as-catamorphism-decider}

State reconstruction via evolve is precisely a catamorphism (fold) over the event list.

**Formal statement**:

Given an event log `events = [e₁, e₂, ..., eₙ]` and the algebra `(State, evolve)`, the current state is:

```haskell
currentState = foldl' evolve initialState events
```

This is the unique catamorphism from the initial algebra (event list, cons) to the algebra (State, evolve).

**Category-theoretic interpretation**:

Event lists form the initial algebra for the list functor F X = 1 + (Event × X):
- Constructors: Nil :: 1 → List Event, Cons :: Event × List Event → List Event
- Initial algebra: (List Event, [Nil, Cons])

The evolve function defines an algebra structure on State:
- Algebra carrier: State
- Algebra morphism: evolve :: State → Event → State

Initiality guarantees there exists a unique homomorphism from (List Event, constructors) to (State, evolve).
That unique homomorphism is `fold evolve initialState`.

**ASCII diagram: Catamorphic reconstruction**

```
EventLog (initial algebra)
    │
    │ unique catamorphism (fold)
    │
    ▼
  State (target algebra)
```

**Practical consequence**:

Uniqueness means: given the algebra (evolve, initialState), there is exactly one way to interpret the event sequence.
This guarantees deterministic replay: same events always produce same state, regardless of when or where events are replayed.

**Connection to snapshots**:

Snapshots are partial evaluations of the catamorphism:
- Snapshot at event N: `snapshotₙ = foldl' evolve initialState (take N events)`
- Resume from snapshot: `currentState = foldl' evolve snapshotₙ (drop N events)`

Memoization is valid because fold is deterministic and associative (assuming evolve is total and deterministic).

**Law: evolve must be total and deterministic**:

```haskell
-- Totality: evolve must handle all event cases
evolve state event  -- always terminates, no exceptions

-- Determinism: same state + event always gives same next state
evolve s e == evolve s e  -- referential transparency

-- Associativity (for folding): grouping doesn't matter
foldl' evolve s [e1, e2, e3] == foldl' evolve (foldl' evolve s [e1, e2]) [e3]
```

If evolve violates these laws, state reconstruction becomes non-deterministic, breaking the catamorphism property.

**See also**:
- [F-algebras and catamorphisms](#f-algebras-and-catamorphisms) for general catamorphism theory
- [Events as free monoid](#events-as-free-monoid) for the monoid structure of event logs
- [State reconstruction as catamorphism](#state-reconstruction-as-catamorphism) in the event sourcing section for broader context

### Monoidal composition of Deciders

Deciders compose monoidally: two deciders can be combined into a single decider with product state and sum command/event types.

**Formal construction**:

Given:
- `Decider<C₁, S₁, E₁>` (first decider)
- `Decider<C₂, S₂, E₂>` (second decider)

Construct:
- `Decider<C₁ + C₂, S₁ × S₂, E₁ + E₂>` (combined decider)

```haskell
-- Sum type for commands
data SumCmd c1 c2 = Left1 c1 | Right1 c2

-- Sum type for events
data SumEvent e1 e2 = Left2 e1 | Right2 e2

-- Product type for state
type ProductState s1 s2 = (s1, s2)

-- Monoidal composition operator
combine
  :: Decider c1 s1 e1
  -> Decider c2 s2 e2
  -> Decider (SumCmd c1 c2) (ProductState s1 s2) (SumEvent e1 e2)
combine d1 d2 = Decider
  { decide = \cmd (s1, s2) -> case cmd of
      Left1 c1 -> map Left2 (decide d1 c1 s1)
      Right1 c2 -> map Right2 (decide d2 c2 s2)

  , evolve = \(s1, s2) event -> case event of
      Left2 e1 -> (evolve d1 s1 e1, s2)
      Right2 e2 -> (s1, evolve d2 s2 e2)

  , initialState = (initialState d1, initialState d2)

  , isTerminal = \(s1, s2) -> isTerminal d1 s1 && isTerminal d2 s2
  }
```

**Monoidal laws**:

This composition satisfies monoidal axioms:

```haskell
-- Associativity (up to isomorphism)
combine (combine d1 d2) d3 ≅ combine d1 (combine d2 d3)

-- Identity (unit decider)
data Unit = Unit
unitDecider = Decider
  { decide = \_ _ -> []
  , evolve = \_ _ -> ()
  , initialState = ()
  , isTerminal = \_ -> False
  }

combine d unitDecider ≅ d
combine unitDecider d ≅ d
```

**Category-theoretic interpretation**:

Deciders form a monoidal category:
- Objects: Type triples (Command, State, Event)
- Morphisms: Decider implementations
- Monoidal product: ⊗ defined by combine
- Unit object: (Unit, (), Void) with trivial decider

The monoidal product distributes command sums over state products:
```
(C₁ + C₂) × (S₁ × S₂) → List(E₁ + E₂)
```

**Practical use case: Aggregate composition**

```haskell
-- Account aggregate
accountDecider :: Decider AccountCmd AccountState AccountEvent

-- Audit log aggregate
auditDecider :: Decider AuditCmd AuditState AuditEvent

-- Combined aggregate: account with audit trail
type CombinedCmd = SumCmd AccountCmd AuditCmd
type CombinedState = (AccountState, AuditState)
type CombinedEvent = SumEvent AccountEvent AuditEvent

combinedDecider :: Decider CombinedCmd CombinedState CombinedEvent
combinedDecider = combine accountDecider auditDecider
```

**Practical consequence**:

Monoidal composition enables:
- Building complex aggregates from simpler deciders (composition)
- Testing each sub-decider independently (modularity)
- Reusing deciders across different aggregate contexts (e.g., audit decider used with account, order, inventory)
- Incremental aggregate design (start with one decider, compose in additional concerns)

**Connection to fmodel**:

The fmodel library provides `combine()` method implementing exactly this monoidal composition.
Users can compose multiple deciders without writing boilerplate sum/product types.

### Product monoid for aggregate state

When aggregate state is a product of monoidal fields, the state itself forms a monoid, simplifying evolve implementation.

**Practical pattern**: Aggregates with independent fields

```haskell
-- Aggregate state as product of monoidal components
data OrderState = OrderState
  { items :: Map ProductId Quantity  -- monoidal: Map with (Max Quantity) values
  , totalPrice :: Sum Money          -- monoidal: Sum monoid
  , status :: Last OrderStatus       -- monoidal: Last (most recent wins)
  , appliedDiscounts :: Set DiscountCode  -- monoidal: Set union
  }
```

**Monoidal structure**:

Each field is a monoid:
- `Map k v` is monoid when `v` is monoid (pointwise merge)
- `Sum a` is monoid with addition
- `Last a` is monoid taking the most recent value
- `Set a` is monoid with union

**Product monoid law**:

If S₁, S₂, ..., Sₙ are monoids, their product S₁ × S₂ × ... × Sₙ is a monoid with:
- Identity: (mempty₁, mempty₂, ..., memptyₙ)
- Operation: (s₁, s₂, ..., sₙ) <> (s₁', s₂', ..., sₙ') = (s₁ <> s₁', s₂ <> s₂', ..., sₙ <> sₙ')

**Code example: Monoidal evolve**

```haskell
instance Monoid OrderState where
  mempty = OrderState
    { items = mempty            -- empty map
    , totalPrice = Sum 0        -- zero
    , status = Last Nothing     -- no status yet
    , appliedDiscounts = mempty -- empty set
    }

  mappend s1 s2 = OrderState
    { items = items s1 <> items s2
    , totalPrice = totalPrice s1 <> totalPrice s2
    , status = status s1 <> status s2  -- Last monoid: s2 wins
    , appliedDiscounts = appliedDiscounts s1 <> appliedDiscounts s2
    }

-- evolve becomes simple monoid append
evolve :: OrderState -> OrderEvent -> OrderState
evolve state event = state <> eventToState event
  where
    eventToState :: OrderEvent -> OrderState
    eventToState (ItemAdded prodId qty price) = mempty
      { items = Map.singleton prodId qty
      , totalPrice = Sum price
      }
    eventToState (StatusChanged status) = mempty
      { status = Last (Just status)
      }
    eventToState (DiscountApplied code discount) = mempty
      { appliedDiscounts = Set.singleton code
      , totalPrice = Sum (negate discount)
      }
```

**Practical consequence**:

Monoidal state simplifies evolve to: "convert event to partial state, then monoidally append."
This pattern eliminates complex case analysis in evolve, reducing bugs and cognitive load.

**When monoidal state works**:
- Fields are independent (no cross-field constraints)
- Append semantics match domain (e.g., items accumulate, status updates)
- Conflicts resolve monoidally (Last, Max, Set union)

**When monoidal state doesn't work**:
- Complex invariants across fields (e.g., "total price must equal sum of item prices")
- Non-commutative updates (order matters beyond what monoid captures)
- State transitions require examining multiple fields (decision tree logic)

**Connection to CRDTs**:

Monoidal aggregate state is structurally similar to CRDTs (Conflict-Free Replicated Data Types).
If all fields are commutative monoids, the aggregate state is a CRDT, enabling eventual consistency in distributed scenarios.

**See also**:
- algebraic-laws.md#monoid-laws for monoid axioms and testing
- domain-modeling.md#pattern-5-deciders-for-event-sourced-aggregates for practical implementation guidance
- event-sourcing.md for operational event sourcing patterns

### See also

**Practical implementation**:
- domain-modeling.md#pattern-5-deciders-for-event-sourced-aggregates for implementation guidance and examples
- event-sourcing.md for comprehensive operational patterns (aggregate design, snapshots, process managers)
- rust-development/12-distributed-systems.md for Rust-specific decider implementation with fmodel

**Theoretical foundations**:
- [F-algebras and catamorphisms](#f-algebras-and-catamorphisms) for catamorphism theory underlying state reconstruction
- [Coalgebras for endofunctors](#coalgebras-for-endofunctors) for coalgebra theory underlying command handling
- [Event sourcing as algebraic duality](#event-sourcing-as-algebraic-duality) (next section) for system-level algebraic structure

**Algebraic laws**:
- algebraic-laws.md#monoid-laws for testing monoidal state composition
- algebraic-laws.md#functor-laws for ensuring evolve preserves structure

## Event sourcing as algebraic duality

Event sourcing occupies a privileged position in the taxonomy of architectural patterns: it explicitly represents both construction (see [F-algebras and catamorphisms](#f-algebras-and-catamorphisms)) and observation (see [Coalgebras for endofunctors](#coalgebras-for-endofunctors)) perspectives.
The event log is a free monoid over event types, a universal construction that preserves complete history while enabling arbitrary interpretations via monoid homomorphisms.
State reconstruction proceeds via catamorphism, the unique fold guaranteed by initiality.
This duality manifests concretely in CQRS: the command side (contravariant in commands) and query side (covariant in views) both factor through the event log as pivot point, forming a profunctor structure that preserves information while enabling independent scaling.

The [Decider pattern](#the-decider-pattern-minimal-algebraic-interface) (previous section) provides the minimal algebraic interface that makes this duality concrete at the aggregate level, unifying command handling (coalgebra) and state reconstruction (algebra) into a single coherent structure.
This section examines the broader system-level algebraic properties that emerge when event sourcing is applied across multiple aggregates and projections.

**ASCII diagram: The duality triangle**

```
       Commands
          │
          │ contravariant
          ↓
      EventLog ─────────→ State/Queries
       (pivot)   covariant
    Free monoid    Functoriality
```

### Events as free monoid

Event logs form a free monoid over event types, explaining why event sourcing preserves complete history while enabling arbitrary interpretations.

**Code example: Free monoid structure**

```haskell
-- Event types are generators of the free monoid
data Event
  = UserRegistered UserId Email
  | EmailVerified UserId
  | OrderPlaced OrderId UserId
  | OrderShipped OrderId

-- Event log is free monoid over Event
newtype EventLog = EventLog [Event]

instance Monoid EventLog where
  mempty = EventLog []
  mappend (EventLog xs) (EventLog ys) = EventLog (xs ++ ys)
```

**Category-theoretic interpretation**:

The free monoid Free(S) over set S is the initial object in the comma category (S ↓ U) where U is the forgetful functor from monoids to sets.
This is precisely the initial algebra construction: the free monoid is the initial algebra for the list functor ListF X = 1 + (S × X).
Just as recursive data types are initial algebras (see [F-algebras and catamorphisms](#f-algebras-and-catamorphisms)), the event log as list of events is the initial algebra for the list functor.

**Universal property**:

```haskell
-- For any monoid homomorphism, there's a unique fold
foldEvents :: Monoid m => (Event -> m) -> EventLog -> m
foldEvents f (EventLog events) = foldMap f events
```

**Practical consequence**:

Initiality guarantees arbitrarily many projections, each a monoid homomorphism from EventLog to some target monoid.
The append-only structure is enforced by monoid axioms: associativity ensures event order is preserved, identity (empty log) provides a starting point.
Log compaction (removing obsolete events) must be a monoid homomorphism to preserve semantics.

### State reconstruction as catamorphism

Reconstructing state from event log is precisely a catamorphism (fold), initiality guarantees uniqueness.

**Code example: Catamorphic reconstruction**

```haskell
data State = State
  { users :: Map UserId UserInfo
  , orders :: Map OrderId OrderInfo
  , emailVerified :: Set UserId
  }

initialState :: State
initialState = State mempty mempty mempty

-- Algebra structure: how to apply one event
apply :: State -> Event -> State
apply state (UserRegistered uid email) =
  state { users = Map.insert uid (UserInfo email False) (users state) }
apply state (EmailVerified uid) =
  state { emailVerified = Set.insert uid (emailVerified state) }
apply state event = -- ... other cases

-- Catamorphism: unique fold from initial algebra
reconstruct :: EventLog -> State
reconstruct (EventLog events) = foldl' apply initialState events
-- Note: Using foldl' (strict left fold) instead of canonical foldr for:
-- - Stack-safety with long event sequences
-- - Strictness in state accumulation (avoids space leaks)
-- - Natural left-to-right event processing order
-- Valid because the algebra (State, apply) is associative
```

**Category-theoretic interpretation**:

The function apply :: State → Event → State defines an algebra structure (State, apply) for the list functor.
The catamorphism reconstruct is the unique morphism from the initial algebra (EventLog, constructors) to this algebra.
Initiality ensures there is exactly one way to interpret the event sequence as state transitions.

**Practical consequence**:

Uniqueness: given the algebra (apply), there is exactly one correct way to fold events into state.
Deterministic replay: same event sequence always produces same state, crucial for debugging and audit.
Snapshots are partial evaluations (memoization): snapshot at event N is reconstruct (take N events), then continue folding from that point.

### CQRS as profunctor structure

CQRS exhibits profunctor structure: command side contravariant in commands, query side covariant in views, event log as pivot.

**Code example: Profunctor instance**

```haskell
-- Profunctor class
class Profunctor p where
  dimap :: (a' -> a) -> (b -> b') -> p a b -> p a' b'

-- CQRS as profunctor
data CQRS cmd view = CQRS
  { handleCommand :: cmd -> EventLog         -- contravariant
  , deriveView :: EventLog -> view           -- covariant
  }

instance Profunctor CQRS where
  dimap f g (CQRS handle derive) = CQRS
    (handle . f)    -- contravariant: precompose
    (g . derive)    -- covariant: postcompose
```

**Category-theoretic interpretation**:

A profunctor P : C^op × D → Set is contravariant in first argument, covariant in second.
CQRS cmd view is a profunctor from commands to views, with event log as the "hom-set" mediating the relationship.
Connection to Kleisli: command handlers are Kleisli arrows cmd → M EventLog where M captures effects (IO, validation errors).

**Code example: Multiple views**

```haskell
-- Different views from same event stream (covariance)
data UserView = UserView { userCount :: Int }
data OrderView = OrderView { orderStats :: Stats }

userProjection :: EventLog -> UserView
orderProjection :: EventLog -> OrderView

-- Both derive from same event log
cqrsUser :: CQRS Command UserView
cqrsOrder :: CQRS Command OrderView
```

**Practical consequence**:

Independent scaling: profunctor factors through event log, allowing command processing and view derivation to scale independently.
Multiple read models: covariance in views means we can derive arbitrarily many projections from same event stream without affecting command handling.
Command versioning: contravariance in commands means we can adapt new command formats to old handlers via dimap.

### Projections as functors

Each projection is a functor from event streams to read models, natural transformations capture consistency.

**Code example: Functor projections**

```haskell
-- Event stream is time-indexed
newtype EventStream a = EventStream { events :: [(Timestamp, a)] }

instance Functor EventStream where
  fmap f (EventStream evs) = EventStream [(t, f e) | (t, e) <- evs]

-- Projection is functor from EventStream to read model
newtype Projection model = Projection
  { runProjection :: EventStream Event -> model }

-- Example projections
userCountProjection :: Projection Int
userCountProjection = Projection $ \stream ->
  length . filter isUserEvent . map snd . events $ stream

activeOrdersProjection :: Projection (Set OrderId)
activeOrdersProjection = Projection $ \stream ->
  foldl' updateOrders mempty (events stream)
```

**Category-theoretic interpretation**:

Each projection is a functor F : EventStream → ReadModel preserving structure.
Multiple projections form a diagram in the functor category [EventStream, ReadModel].
A natural transformation η : F ⇒ G between projections is a family of morphisms indexed by event streams: for all event streams e, ηₑ :: F e → G e, such that consistency is maintained across stream transformations (naturality square commutes).

**Code example: Natural transformation as consistency**

```haskell
-- Natural transformation checks projection consistency
type ConsistencyCheck m n = forall e. EventStream e -> m -> n -> Bool

-- Example: user count should match cardinality of user set
userCountConsistent :: ConsistencyCheck Int (Set UserId)
userCountConsistent stream count userSet =
  count == Set.size userSet
```

**Practical consequence**:

Multiple projections = multiple functors from same source, enabling polyglot persistence.
Projection independence: functors compose, so we can build complex views from simpler projections.
Eventual consistency = failure of naturality: projection update lags behind event stream, natural transformation doesn't hold at all times.

### Temporal semantics

Event time vs processing time creates bitemporal structure modeled as indexed type.

**Code example: Bitemporal indexing**

```haskell
-- Event time: when event occurred in domain
newtype EventTime = EventTime UTCTime

-- Processing time: when event was recorded in log
newtype ProcessingTime = ProcessingTime UTCTime

-- Bitemporal event indexed by both times
data BitemporalEvent i j a where
  BitemporalEvent
    :: EventTime
    -> ProcessingTime
    -> a
    -> BitemporalEvent EventTime ProcessingTime a

-- Indexed monad bind tracks temporal provenance
ibind
  :: BitemporalEvent i j a
  -> (a -> BitemporalEvent j k b)
  -> BitemporalEvent i k b

-- Note: This GADT always produces the same index types (EventTime, ProcessingTime)
-- making this phantom typing rather than true indexed monad effect tracking.
-- A proper indexed bitemporal monad would track temporal state transitions through i, j, k.
```

**Category-theoretic interpretation**:

Bitemporal events form an indexed monad (see [Indexed monads for effect tracking](#indexed-monads-for-effect-tracking)) tracking temporal state transitions.
The indices i, j represent positions in bitemporal space: i is input temporal context, j is output temporal context.
Just as indexed monads can track file handle resource state transitions, bitemporal types track temporal state.

**Practical consequence**:

Time travel queries: query state as of event time (what we knew when event occurred) vs processing time (what we know now).
Late-arriving events: event time in past, processing time is now, indexed type makes this explicit.
Audit compliance: both indices preserved, enables reconstructing "what did we know at time T" for regulatory requirements.

### Hoffman's laws as algebraic constraints

Kevin Hoffman's "10 Laws of Event Sourcing" (from "Real World Event Sourcing") can be understood as constraints that preserve the algebraic structure described above.

*Law 1: Events are immutable* corresponds to the monoid axiom that elements, once introduced, cannot be modified.
The free monoid is append-only by construction.

*Law 2: Event schemas are immutable* preserves the *closed universe* assumption required for exhaustive pattern matching in the algebra structure.
A change to an event schema creates a new type, hence a new generator for the free monoid.

*Law 3: All data for a projection must be on the events* ensures the catamorphism (fold) is *self-contained*.
If projections could access external state, the homomorphism property would fail.

*Law 4: All projections must stem from events* ensures projections are *derived artifacts* (catamorphism results), not independent sources of truth.
This preserves the initiality of the event log.

*Law 5: Different projectors cannot share projections* ensures projections form independent homomorphisms from the free monoid.
Shared state would create implicit coupling that breaks composition.

*Law 6: Applying a failure event returns previous state* corresponds to a *partial identity* in the algebra: failure events act as identity morphisms on state.
This maintains the state machine interpretation where rejected commands produce no state transition.

*Law 9: Process managers consume events and emit commands* establishes the coalgebra-algebra duality: aggregates are coalgebras (state observation yields events), process managers are algebras (event consumption yields commands).

These laws are not arbitrary conventions but algebraic necessities.
Violating them breaks the structural guarantees that make event sourcing mathematically tractable.

### See also

**See also**:
- `event-sourcing.md` for comprehensive event sourcing patterns synthesizing FDM and Hoffman's approach
- `distributed-systems.md` for practical event sourcing patterns
- `rust-development/12-distributed-systems.md` for Rust implementation of event-sourced systems
- `domain-modeling.md#pattern-3-state-machines` for state machines as event handlers
- `railway-oriented-programming.md` for Result composition in command handlers

## Reactive systems and comonads

This section applies concepts from functional reactive programming to practical signal systems.
See `functional-reactive-programming.md` for the foundational treatment of why signals are comonadic, why event sourcing is monadic, and how the Decider pattern emerges from this duality.

Reactive signal systems exhibit comonadic structure, the categorical dual of monads.
While monads model effect production (building up context through sequenced computations), comonads model context consumption (extracting and transforming values from surrounding context).
This duality is essential for understanding how dataflow reactive systems work and how they compose with the monadic event sourcing patterns described above.

### Signals as comonads

**Practical pattern**: Reactive signals that hold current values and support derived computations

```haskell
-- A signal is a container with a current value
-- and the ability to create derived signals
data Signal a = Signal
  { current :: a
  , neighbors :: [Signal a]  -- conceptual: related signal values
  }
```

**Category-theoretic interpretation**:

A comonad W is a functor with two natural transformations:

```haskell
class Functor w => Comonad w where
  extract :: w a -> a                     -- get current value
  extend :: (w a -> b) -> w a -> w b      -- create derived signal
  -- or equivalently:
  duplicate :: w a -> w (w a)             -- nest the context
```

For signals:
- `extract` retrieves the current value from a signal
- `extend f signal` creates a derived signal where each point computes `f` over the signal's context
- `duplicate` creates a signal of signals (each point sees its neighborhood)

**Comonad laws** (dual to monad laws):

```haskell
-- Left identity: extracting then extending is identity
extend extract = id

-- Right identity: extending then extracting gives the function result
extract . extend f = f

-- Associativity: extension composes
extend f . extend g = extend (f . extend g)
```

**Practical consequence**:

Derived signals compose correctly.
If you derive signal B from signal A, and derive signal C from signal B, the result is equivalent to deriving C directly from A with the composed derivation function.
This is why signal graphs can be built incrementally without worrying about evaluation order.

**Code example: Signal derivation**

```typescript
// Datastar signal system (conceptual model)
const price = signal(100);
const quantity = signal(5);

// Derived signal: extend over price and quantity context
const total = computed(() => price.value * quantity.value);
// extend: (context -> result) -> signal -> derived signal

// Extracting from derived signal
const currentTotal = total.value;  // extract: signal -> value
```

**Monad/comonad duality**:

```
Monad (effects):                    Comonad (context):
  return :: a -> m a                  extract :: w a -> a
  bind :: m a -> (a -> m b) -> m b    extend :: (w a -> b) -> w a -> w b

  Effects flow inward (produced)      Values flow outward (consumed)
  Kleisli composition: a -> m b       CoKleisli composition: w a -> b
```

In SSE-based hypermedia:
- Server events arrive via monadic effect channel (SSE stream produces values)
- Client signals consume those values via comonadic extraction (signals hold and derive)

This explains the architectural split: server-side event sourcing is monadic (effect production), client-side reactivity is comonadic (context consumption).

### Signal graphs as free categories

**Practical pattern**: Directed acyclic graph of signal dependencies

```typescript
// Signal dependency graph
const a = signal(1);
const b = computed(() => a.value * 2);      // b depends on a
const c = computed(() => a.value + 10);     // c depends on a
const d = computed(() => b.value + c.value); // d depends on b and c
```

**Category-theoretic interpretation**:

The dependency DAG generates a free category (the DAG's vertices and edges freely generate objects and morphisms, with paths as compositions).
Signals form a diagram (functor) from this free category to the category of types and derivation functions:
- Objects: Signals (typed by their value type)
- Morphisms: Derivation functions between signal types
- Composition: Function composition of derivations
- Identity: The identity derivation (signal depends on itself trivially)

The DAG constraint (no cycles) ensures the category is well-founded, meaning every signal can be evaluated in topological order.

**Code example: Category structure**

```haskell
-- Morphisms in the signal category
type Derivation a b = Signal a -> b

-- Identity morphism
idDeriv :: Derivation a a
idDeriv = extract

-- Composition
composeDeriv :: Derivation b c -> Derivation a b -> Derivation a c
composeDeriv f g = f . extend g
```

**Practical consequence**:

Signal frameworks can topologically sort the dependency graph and update signals in dependency order.
The free category structure ensures this ordering exists and that incremental updates propagate correctly.
Memoization at each signal node is sound because the category laws guarantee consistent evaluation.

### Web components as coalgebras

**Practical pattern**: Web components with state, rendering, and event handling

```javascript
class ChartWrapper extends HTMLElement {
  // State
  data = [];

  // Output: render state to DOM
  render() { /* state -> HTML */ }

  // Transition: handle events/attributes to update state
  attributeChangedCallback(name, old, new) { /* (state, input) -> state */ }
}
```

**Category-theoretic interpretation**:

A web component is a Moore machine (a type of coalgebra where output depends only on state, not on current input).

For functor F S = Output × (Input → S):

```haskell
-- Moore machine coalgebra
coalgebra :: S -> (Output, Input -> S)
coalgebra state = (render state, \input -> transition state input)
```

Where:
- S is the component's state type (reactive properties, internal state)
- Output is the rendered DOM
- Input is the union of events and attribute changes
- `render` produces output from current state
- `transition` computes next state from current state and input

**Bisimulation as behavioral equivalence**:

Two component states are behaviorally equivalent (bisimilar) if they:
1. Produce the same rendered output
2. Transition to bisimilar states on all inputs

This is crucial for morphing algorithms: if two DOM states are bisimilar with respect to user interaction, morphing can safely replace one with the other without observable behavior change.

**Code example: Coalgebra structure**

```haskell
-- Component as coalgebra
data Component s = Component
  { state :: s
  , render :: s -> HTML
  , transition :: s -> Event -> s
  }

-- Coalgebra morphism (natural transformation)
observe :: Component s -> (HTML, Event -> Component s)
observe (Component s r t) = (r s, \e -> Component (t s e) r t)
```

**Connection to hypermedia**:

The thin wrapper pattern (05-web-components.md line 24) describes components as "morphisms between the hypermedia signal world and imperative library APIs."
This is precisely the coalgebra structure: components observe signal state and produce library state as output.

```
Signals ──extract──▶ Component State ──render──▶ Library DOM
                           │
                           ◀──transition──
                           │
                      Event Input
```

### Composing reactive systems

**Full reactive pipeline**:

```
Server Events ──(monad)──▶ Signal Updates ──(comonad)──▶ Component State ──(coalgebra)──▶ DOM
      │                          │                              │
      │                          │                              │
      └──────────── Profunctor structure ───────────────────────┘
```

The complete system is a profunctor:
- Contravariant in inputs (server events flow to signals)
- Covariant in outputs (component state renders to DOM)

**Code example: Pipeline composition**

```haskell
-- Server → Signal (monadic effect reception)
receiveEvent :: SSE Event -> IO (Signal State)

-- Signal → Component (comonadic extraction)
bindComponent :: Signal State -> Component State
bindComponent = extend (\sig -> ComponentState { ... })

-- Component → DOM (coalgebraic observation)
renderComponent :: Component State -> HTML
renderComponent = fst . observe
```

**Practical consequence**:

This decomposition clarifies responsibility boundaries:
1. SSE layer handles effect reception (monadic)
2. Signal layer handles state derivation (comonadic)
3. Component layer handles DOM observation (coalgebraic)

Each layer has its own laws and can be tested independently.
The composition laws ensure end-to-end correctness.

**See also**:
- hypermedia-development/03-datastar.md for signal system patterns
- hypermedia-development/05-web-components.md for component integration
- hypermedia-development/07-event-architecture.md for SSE as projection channel

### Backpressure as algebraic constraint

In reactive stream systems, backpressure represents a bidirectional flow constraint.
Data flows from producer to consumer; demand signals flow in the opposite direction.

This bidirectional flow can be modeled as a profunctor or as adjoint functors between producer and consumer categories.
The backpressure mechanism ensures that the compositional properties of streams (ordering, exactly-once) are preserved under varying load.

See distributed-systems.md#reactive-streams-for-distributed-messaging for practical reactive stream patterns.

## Materialized views as Galois connections

Read models and materialized views in CQRS/event sourcing architectures form a Galois connection with the event log.
This algebraic structure explains why projections are lossy, how query caching works, and how temporal versioning enables time travel.

### The abstraction-concretion pair

**Practical pattern**: Projecting event logs to queryable views

```haskell
-- Abstraction: project events to view (loses information)
project :: EventLog -> ReadModel

-- Concretion: what events could produce this view (gains uncertainty)
reconstruct :: ReadModel -> Set EventLog
```

**Category-theoretic interpretation**:

A Galois connection is a pair of functions between ordered sets:

```haskell
abstract :: EventLog -> ReadModel
concrete :: ReadModel -> EventLog

-- Poset structures:
-- EventLog ordered by prefix: e1 ⊑_E e2 iff e1 is prefix of e2
-- ReadModel ordered by refinement: m1 ⊑_M m2 iff m1 refines/extends m2

-- Galois condition: for all e, m
abstract(e) ⊑_M m  ⟺  e ⊑_E concrete(m)
```

The abstraction-concretion pair preserves and reflects the ordering structure between event sequences and their derived views.

For event sourcing:
- `abstract` (projection): collapses event sequences into aggregated views
- `concrete` (reconstruction): maps views back to minimal event sequences that produce them

**Properties**:

```haskell
-- Projection is surjective onto its image
abstract . concrete . abstract = abstract

-- Reconstruction is injective on views
concrete . abstract . concrete = concrete

-- Projection loses information monotonically
abstract(e1 ++ e2) ⊑ abstract(e1) <> abstract(e2)
```

**Practical consequence**:

Multiple event sequences can produce the same view (abstract is many-to-one).
Views can be rebuilt from events, but events cannot be recovered from views.
This is why event logs are the source of truth—views are derived, disposable, and rebuildable.

### Views as quotients of the event monoid

**Practical pattern**: Equivalent event sequences producing the same view

The event log is a free monoid (see "Event sourcing as algebraic duality" above).
A materialized view is a quotient monoid—the free monoid modulo an equivalence relation that identifies event sequences producing the same view.

**Code example: Quotient structure**

```haskell
-- Events that commute produce equivalent sequences
-- [DepositA, DepositB] ≡ [DepositB, DepositA]  (same final balance)

-- Events that are idempotent collapse
-- [SetStatus "active", SetStatus "active"] ≡ [SetStatus "active"]

-- The projection is a monoid homomorphism
project :: [Event] -> View
project [] = initialView                      -- preserves identity
project (e1 ++ e2) = project e1 <> project e2 -- preserves composition
```

**Category-theoretic interpretation**:

The quotient is the coequalizer of all equivalent event sequences:

```
EventLog ──π──▶ EventLog/≡ ≅ View
```

Where π is the projection to equivalence classes.

**Practical consequence**:

Different event sequences may be equivalent for querying purposes.
This enables:
- Log compaction (remove redundant events)
- Snapshot optimization (store view state instead of replaying)
- Parallel projection (events that commute can be processed concurrently)

**When events commute**:

Events commute when their order doesn't affect the final view:

```haskell
commute :: Event -> Event -> Bool
commute (Deposit a1) (Deposit a2) = True   -- deposits commute
commute (Deposit _) (Withdraw _) = False   -- these don't commute
commute (SetField f1 _) (SetField f2 _) = f1 /= f2  -- different fields commute
```

Commutativity analysis enables parallel projection and relaxed consistency models.

### Query caching as memoization

**Practical pattern**: Caching query results for repeated access

```haskell
-- Uncached query
query :: ReadModel -> QueryParams -> Result
query model params = expensiveComputation model params

-- Cached query
cachedQuery :: Cache -> ReadModel -> QueryParams -> Result
cachedQuery cache model params =
  case lookup params cache of
    Just result -> result
    Nothing -> let result = query model params
               in insert params result cache; result
```

**Category-theoretic interpretation**:

Memoization is a form of profunctor memoization where:
- Queries form a category (by refinement/composition)
- Results form another category
- The query function is a profunctor Q : Params^op × Model → Result
- Caching adds morphism memoization to the profunctor

**Cache invalidation as naturality**:

A cached result is valid when the naturality square commutes:

```
Model_old ───query(p)───▶ Result_old
    │                          │
 update                     same?
    │                          │
    v                          v
Model_new ───query(p)───▶ Result_new
```

If `update` changes data relevant to query `p`, the cache entry is invalid.
This is why cache invalidation is "hard"—determining affected queries requires understanding the naturality conditions.

**Practical strategies**:

```haskell
-- Time-based invalidation (eventual consistency)
cachedWithTTL :: Duration -> Cache -> Query -> Result

-- Event-based invalidation (strong consistency)
invalidateOn :: [EventType] -> Cache -> Query -> Result

-- Dependency tracking (precise invalidation)
cachedWithDeps :: DependencyGraph -> Cache -> Query -> Result
```

**DuckDB connection**:

DuckDB's query optimizer can be understood through this lens:
- Predicate pushdown: restructuring the query profunctor
- Partition pruning: memoization over partition boundaries
- Statistics-based optimization: using cached metadata for query planning

### Temporal versioning as indexed types

**Practical pattern**: Time-travel queries in lakehouse architectures

```sql
-- DuckLake/Iceberg time travel
SELECT * FROM orders VERSION AS OF '2025-01-01';
SELECT * FROM orders VERSION AS OF 12345;  -- snapshot ID
```

**Type-level interpretation**:

Tables are indexed by version/time:

```haskell
-- Table parameterized by version
data Table (v :: Version) a

-- Query parameterized by table version
query :: Table v a -> Query -> Result

-- Time travel: change version index
asOf :: Table v a -> Version -> Table v' a
```

**Connection to indexed monads** (see [Indexed monads for effect tracking](#indexed-monads-for-effect-tracking)):

Just as indexed monads track effect state through computation, versioned tables track temporal state through queries.

```haskell
-- Indexed query composition
data VersionedQuery v1 v2 a where
  Query :: Table v1 a -> Query -> VersionedQuery v1 v1 Result
  TimeTravel :: Version -> VersionedQuery v1 v2 a -> VersionedQuery v1 v2 a

-- Bind tracks version changes
ibind :: VersionedQuery v1 v2 a -> (a -> VersionedQuery v2 v3 b) -> VersionedQuery v1 v3 b
```

**Bitemporal connection** (see "Temporal semantics" in Event sourcing section):

DuckLake versioning implements the processing-time axis of bitemporality:
- Event time: when the business event occurred
- Processing time (DuckLake version): when the data was recorded in the lake

```haskell
-- Full bitemporal query
queryBitemporal :: Table ProcessingTime a -> EventTime -> ProcessingTime -> Query -> Result
queryBitemporal table eventT procT q =
  let snapshot = asOf table procT
  in query (filterByEventTime eventT snapshot) q
```

**Practical consequence**:

Temporal versioning enables:
- Audit queries ("what did we know at time T?")
- Debugging ("why did this query return X last week?")
- Reproducibility ("run the same analysis on historical snapshot")
- Schema evolution (new schema on new versions, old queries use old schema)

**See also**:
- data-modeling.md for DuckDB patterns
- distributed-systems.md "Position 1: Event log as authority" for read model derivation
- hypermedia-development/07-event-architecture.md for bitemporal event handling

## The ladder of pattern quality

Ghosh describes a hierarchy of pattern quality based on algebraic properties:

1. **Pure functions**: Foundation enabling fearless composition and equational reasoning

2. **Algebraic abstractions with static types**: Patterns with well-defined laws (monoids, functors, monads) that can be verified

3. **Free theorems from parametricity**: Polymorphic functions where behavior is constrained by type signature alone

Each level builds on the previous.
Pure functions enable algebraic abstractions.
Algebraic abstractions with parametric polymorphism yield free theorems.

This hierarchy guides pattern selection: prefer patterns higher on the ladder when possible, as they provide stronger guarantees with less explicit verification.

See algebraic-laws.md for laws that algebraic patterns must satisfy.
See algebraic-laws.md#parametricity-and-free-theorems for how parametricity reduces testing burden.

## Cross-references to practical documents

This theoretical foundation supports patterns described in:

### domain-modeling.md
- **Types as domain vocabulary** → Algebraic data types as initial algebras
- **Smart constructors** → Dependent types and refinement types (simplified)
- **State machines** → Coalgebras for endofunctors
- **Workflows as pipelines** → Kleisli categories and monad composition
- **Aggregates** → Optics (lenses and prisms)
- **Domain errors** → Coproduct of error types

### algebraic-data-types.md
- **Product types** → Categorical products
- **Sum types** → Categorical coproducts
- **Newtype pattern** → Refinement types
- **Pattern matching** → Catamorphisms (structural recursion)

### railway-oriented-programming.md
- **Result type** → Kleisli category for error monad
- **bind composition** → Kleisli composition (>=>)
- **map transformation** → Functor mapping
- **Applicative validation** → Applicative composition in parallel

### architectural-patterns.md
- **Effect signatures** → Indexed monads (simplified)
- **Dependency injection** → Reader monad / ReaderT transformer
- **Monad transformer stacks** → Composition of effect transformers

### distributed-systems.md
- **Event log as authority** → Free monoid of events (event-sourcing-as-algebraic-duality)
- **Deterministic replay** → State reconstruction as catamorphism
- **CQRS pattern** → Profunctor structure separating read/write
- **Idempotency** → Monoid identity laws for event application

### hypermedia-development/07-event-architecture.md
- **SSE as projection channel** → Functors from event log to stream
- **Temporal consistency** → Ordered monoid preserving causality

### hypermedia-development/03-datastar.md
- **Signal system** → Comonadic context consumption (reactive-systems-and-comonads)
- **Computed signals** → CoKleisli composition for derived values
- **PatchSignals** → Monadic effect delivery from server to client

### hypermedia-development/05-web-components.md
- **Thin wrapper pattern** → Web components as coalgebras/Moore machines
- **Morphing boundaries** → Bisimulation for behavioral equivalence
- **Signal-to-library bridge** → Comonad extraction feeding coalgebra observation

### data-modeling.md
- **Read models as derived views** → Galois connection with event log
- **Query caching** → Memoization with naturality-based invalidation
- **DuckLake time travel** → Temporal versioning as indexed types
- **Views as quotients** → Equivalent event sequences under projection

## Further reading

### Category theory
- "Category Theory for Programmers" by Bartosz Milewski
- "Basic Category Theory for Computer Scientists" by Benjamin Pierce

### Type theory
- "Types and Programming Languages" by Benjamin Pierce
- "Advanced Topics in Types and Programming Languages" by Benjamin Pierce (ed.)

### Functional programming theory
- "Purely Functional Data Structures" by Chris Okasaki
- "Functional Programming in Scala" by Chiusano and Bjarnason (Red Book)

### Effect systems
- "Algebraic Effects for Functional Programming" (research papers)
- "Effekt: Capability-Passing Style for Type- and Effect-Safe Programming"

### Applied category theory
- "Seven Sketches in Compositionality" by Fong and Spivak
- "Category Theory in Context" by Emily Riehl
