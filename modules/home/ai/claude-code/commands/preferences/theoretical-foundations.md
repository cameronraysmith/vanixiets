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
-- Catamorphism is the unique fold:
cata :: (ListF a b -> b) -> List a -> b
```

**Practical consequence**: Every recursive data type has a canonical "fold" operation that expresses all structural recursion.

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

-- Identity law: return >=> f ≅ f ≅ f >=> return
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
data FileHandle :: FileState -> * where
  -- File starts Closed, becomes Opened, ends Closed

openFile :: FilePath -> FileHandle Closed Opened Handle
readFile :: FileHandle Opened Opened String
closeFile :: FileHandle Opened Closed ()

-- Type system prevents:
readFile ∘ closeFile  -- Can't read closed file
closeFile ∘ closeFile -- Can't close twice
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
- Effects commute (order doesn't matter)
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

For state machines: F S = Output × S (produces output and next state)

```haskell
coalgebra :: State -> (Output, State)
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

Lens composition is function composition (contravariant).

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

## Event sourcing as algebraic duality

Event sourcing occupies a privileged position in the taxonomy of architectural patterns: it explicitly represents both construction (F-algebras, lines 123-143) and observation (coalgebras, lines 397-432) perspectives.
The event log is a free monoid over event types, a universal construction that preserves complete history while enabling arbitrary interpretations via monoid homomorphisms.
State reconstruction proceeds via catamorphism, the unique fold guaranteed by initiality.
This duality manifests concretely in CQRS: the command side (contravariant in commands) and query side (covariant in views) both factor through the event log as pivot point, forming a profunctor structure that preserves information while enabling independent scaling.

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
Back-reference to F-algebras (lines 123-143): just as recursive data types are initial algebras, the event log as list of events is the initial algebra for the list functor.

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
A natural transformation η : F ⇒ G between projections is a consistency check: for all event streams e, ηₑ (F e) = G e.

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
```

**Category-theoretic interpretation**:

Bitemporal events form an indexed monad (lines 250-395) tracking temporal state transitions.
The indices i, j represent positions in bitemporal space: i is input temporal context, j is output temporal context.
Connection to indexed monads: just as file handles track resource state (lines 281-292), bitemporal types track temporal state.

**Practical consequence**:

Time travel queries: query state as of event time (what we knew when event occurred) vs processing time (what we know now).
Late-arriving events: event time in past, processing time is now, indexed type makes this explicit.
Audit compliance: both indices preserved, enables reconstructing "what did we know at time T" for regulatory requirements.

### See also

**See also**:
- distributed-systems.md for practical event sourcing patterns
- rust-development/12-distributed-systems.md for Rust implementation of event-sourced systems
- domain-modeling.md#pattern-3-state-machines for state machines as event handlers
- railway-oriented-programming.md for Result composition in command handlers

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
