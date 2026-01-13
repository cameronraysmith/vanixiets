# Functional reactive programming

## Purpose and scope

This document establishes Functional Reactive Programming as the foundational paradigm from which event sourcing, CQRS, the Decider pattern, signals, and reactive streams are derived consequences rather than independent inventions.
The shared insight across all these patterns is a fundamental inversion: privileging change over state, storing velocities rather than positions, and deriving current state through integration (folding) over the differential history.

This document addresses the "why" that unifies patterns documented elsewhere.
It provides the conceptual framework showing that these patterns are not design choices but mathematical necessities once you commit to modeling interactive systems that unfold over time.

For the detailed categorical structures (F-algebras, coalgebras, comonads, profunctors) and their formal definitions, see `theoretical-foundations.md`.
For practical event sourcing implementation, see `event-sourcing.md`.
For the Decider pattern and aggregate design, see `domain-modeling.md`.
For SSE-based reactive hypermedia, see `hypermedia-development/07-event-architecture.md`.
For distributed reactive streams and backpressure, see `distributed-systems.md`.

The relationship between this document and `theoretical-foundations.md` is that of perspective to mechanism: this document explains why certain structures are forced by the problem domain of interactive systems, while `theoretical-foundations.md` details what those structures are and how they compose.

## The fundamental problem

### Batch versus interactive computation

Computation as traditionally understood is the transformation of input to output: given `f : A → B`, apply `f` to some `a` and obtain `b`.
The function executes and terminates; the computation is done.
This model suffices for batch processing where all inputs are available upfront and the output is produced once.

Interactive systems differ structurally.
The user controls time.
Input arrives incrementally, unpredictably, across the lifetime of the system.
The system must be perpetually ready to receive input, produce output, and maintain consistency between what it knows and what it shows.
There is no termination in the batch sense; there is only ongoing participation in a temporal process.

This distinction is not merely about "handling events" as an engineering concern.
It represents a fundamental shift in the mathematical object being modeled.
Batch computation models functions.
Interactive computation models *processes*—ongoing entities that maintain state, respond to stimuli, and produce outputs incrementally over time.

### The poverty of imperative event handling

The naive approach to interactivity is imperative event handling: register callbacks, mutate state, trigger effects.
This approach collapses under its own complexity because callbacks compose poorly.
Each callback may read and write shared mutable state.
The order of callback invocation matters but is often implicit.
Reasoning about the system requires tracing through all possible interleaving of callbacks—a combinatorial explosion.

Imperative event handling also conflates concerns that should be separate: what happened (the event), what it means for state (the interpretation), and what visible effects result (the reaction).
Callbacks typically perform all three simultaneously, making testing difficult and composition impossible.

The problem is not "how to handle events" but "what is the correct mathematical model for systems whose behavior unfolds over time?"
Functional Reactive Programming provides that model.

### Time as first-class citizen

The key insight of FRP is that time-varying values should be first-class.
Rather than modeling a temperature as a single value that gets updated, model it as a function from time to temperature: `Temperature : Time → Float`.
This function, called a *behavior* or *signal*, represents the complete temporal evolution of the value.

With behaviors as the primitive, operations become natural: sample a behavior at a time, combine two behaviors pointwise, integrate a rate behavior to get a quantity behavior.
The temporal dimension is explicit in the types, not hidden in mutable state and callback scheduling.

Events, in contrast to behaviors, are discrete occurrences at specific times: `Events a = [(Time, a)]`.
An event stream is a list of time-stamped values.
Where behaviors are continuous (defined at every time), events are punctual (occur at isolated moments).

The duality between behaviors (continuous, sampled) and events (discrete, occurred) corresponds to the duality between integration and differentiation, between position and velocity, between state and change.
This duality is not metaphorical; it is mathematically precise and has deep consequences for system architecture.

## The categorical foundations

The patterns that emerge from FRP have precise categorical formulations.
These structures are not arbitrary abstractions but forced choices: once you commit to typed, compositional, functional programming for time-varying interactive systems, these structures become inevitable.

### The morphisms-over-objects principle

Category theory's foundational move is to privilege *morphisms* (arrows, transformations) over *objects* (things, states).
Objects matter only insofar as they serve as domains and codomains for morphisms; the morphisms carry the structure.
Two categories are equivalent not when they have the same objects but when they have the same pattern of morphisms.

This is precisely the shift reactive programming makes: events (transformations, changes) are primary; state (objects, values) is derived.
The event log is a sequence of morphisms; current state is their composition.
Querying "what is the state?" means "what is the composite effect of all transformations?"

The alignment is not coincidental.
Category theory provides the natural vocabulary for reactive systems because both share the same foundational inversion.
Understanding this principle clarifies why categorical structures appear throughout FRP: they are not imposed but discovered, forced by the decision to treat change as primary.

### Structures and their roles

| Structure | Role in FRP | Intuition |
|-----------|-------------|-----------|
| F-Coalgebras | Event-producing systems | Observation: unfold structure by inspecting state |
| F-Algebras | Event-consuming projections | Construction: fold structure by applying events |
| Comonads | Signals and behaviors | Values-in-context with extraction and extension |
| Arrows | Signal functions | Composable computations with exposed static structure |
| Presheaves | Time-varying values | Contravariant functors from time to values |
| Optics/Lenses | Bidirectional access | CQRS read/write separation at the type level |

These structures are not optional additions but core vocabulary.
A system that produces events based on state is a coalgebra.
A system that consumes events to build state is an algebra.
A reactive signal that provides a current value while supporting derived computations is a comonad.
Each structure captures a specific pattern of information flow.

### Coalgebras: observation and event production

An F-coalgebra for a functor `F` is a pair `(S, γ)` where `S` is a type (the state space) and `γ : S → F(S)` is a morphism (the observation function).

```haskell
type Coalgebra f s = s -> f s
```

The functor `F` determines what kind of observations are possible.
For Moore machines (output depends only on state), `F(S) = Output × S`, meaning observation produces an output and a next state.
For Mealy machines (output depends on state and input), `F(S) = Input → (Output × S)`, meaning observation produces a function from input to output-state pairs.

The coalgebraic perspective emphasizes *observation*: you cannot access the internal state directly, only observe it through the structure `γ` provides.
Event-producing systems are coalgebras because they take internal state and produce observable outputs (events) while transitioning to new states.

```haskell
-- An aggregate as coalgebra
decide :: Command -> State -> [Event]
-- Observation: given current state and command, produce observable events
```

The `decide` function in the Decider pattern is precisely the coalgebraic component: it observes state in the context of a command and produces events as observable output.

### Algebras: construction and event consumption

An F-algebra for a functor `F` is a pair `(A, α)` where `A` is a carrier type and `α : F(A) → A` is a morphism (the structure map).

```haskell
type Algebra f a = f a -> a
```

Where coalgebras unfold (produce structure from state), algebras fold (consume structure to build values).
The canonical example is list folding: `ListF a r = Nil | Cons a r` gives rise to algebras that consume lists by providing a base case and a combining function.

Event consumption follows this pattern exactly.
The event stream is the initial algebra (the free structure), and each fold over it is a catamorphism (the unique homomorphism from initial algebra to any other algebra).

```haskell
-- State reconstruction as catamorphism
evolve :: State -> Event -> State
reconstruct = foldl evolve initialState
```

The `evolve` function is the algebraic component of the Decider: it consumes events to construct state.
State reconstruction is the catamorphism from the free monoid of events to the state monoid.

### The coalgebra-algebra duality

The Decider pattern exhibits both structures simultaneously:

```haskell
data Decider c s e = Decider
  { decide  :: c -> s -> [e]  -- Coalgebraic: produce events by observation
  , evolve  :: s -> e -> s    -- Algebraic: consume events to build state
  , initial :: s              -- Initial state
  }
```

The `decide` function is a coalgebra: observation produces events.
The `evolve` function is an algebra: event consumption produces state.
The Decider is the coherent pairing of these dual perspectives, connected by the requirement that `evolve` applied to events from `decide` must produce consistent state transitions.

This duality is not a design choice but a forced structure.
Any system that must both react to inputs (producing events) and maintain consistent state (consuming events) must exhibit exactly this form.

### Comonads: values in temporal context

A comonad `W` is the categorical dual of a monad, equipped with:

```haskell
class Functor w => Comonad w where
  extract  :: w a -> a                    -- Get current value
  extend   :: (w a -> b) -> w a -> w b    -- Create derived values
  duplicate :: w a -> w (w a)             -- Nest the context
```

Where monads model effect production (building up context through sequenced computations), comonads model context consumption (extracting values from surrounding context).
Signals and behaviors are naturally comonadic: a signal has a current value (`extract`) and supports creating derived signals that compute from the signal's context (`extend`).

The comonad laws ensure that derivations compose correctly:

```haskell
-- Extracting then extending is identity
extend extract = id

-- Extending then extracting gives the function result
extract . extend f = f

-- Extension composes
extend f . extend g = extend (f . extend g)
```

These laws mean that if you derive signal B from signal A, and derive signal C from signal B, the result is equivalent to deriving C directly from A with the composed derivation.
This is why signal dependency graphs can be built incrementally without worrying about evaluation order—the comonad laws guarantee compositional correctness.

```haskell
-- Signal as comonad (simplified)
data Signal a = Signal
  { current :: a
  , update  :: a -> Signal a
  }

instance Comonad Signal where
  extract sig = current sig
  extend f sig = Signal (f sig) (\a -> extend f (update sig a))
```

Reactive signals in frameworks like SolidJS, Leptos, and Datastar implement (approximate) comonadic semantics.
The `extract` operation is reading `.value`; the `extend` operation is creating computed signals or effects.

### The monad-comonad duality in reactive systems

The server-client split in reactive hypermedia systems exhibits monad-comonad duality:

The server side is *monadic*: events are produced through effectful computations, command handlers may fail, persistence operations sequence through bind.
The effect production aspect of server-side processing fits the monadic model.

The client side is *comonadic*: signals hold current values, derived computations consume signal context, no effects are produced (only values extracted and transformed).
The context consumption aspect of client-side reactivity fits the comonadic model.

SSE bridges these worlds: the monadic effect production on the server generates events that flow to the client, where comonadic context consumption derives UI state.
This is not an architectural accident but a necessary consequence of the duality.

## Arrows: the original FRP computational model

### Signal functions as arrows

The original formulation of FRP by Conal Elliott and Paul Hudak used arrows rather than monads for signal processing.
An arrow is a generalization of functions that exposes more static structure, enabling optimizations and analyses that would be impossible with monads.

```haskell
class Category a => Arrow a where
  arr   :: (b -> c) -> a b c              -- Lift pure function
  first :: a b c -> a (b, d) (c, d)       -- Apply to first component
  (***)  :: a b c -> a b' c' -> a (b, b') (c, c')  -- Parallel composition
  (&&&) :: a b c -> a b c' -> a b (c, c')  -- Fan-out
```

A signal function `SF a b` represents a continuous transformation from input signal of type `a` to output signal of type `b`.
Unlike a pure function `a -> b` which operates on instantaneous values, a signal function operates on the entire temporal evolution.

The arrow abstraction exposes the static structure of signal networks.
Given a composition of signal functions, the arrow laws guarantee that the composition can be optimized, parallelized, and analyzed without evaluating it.

### Arrow laws

Arrow laws ensure that the abstraction behaves consistently:

```haskell
-- Identity
arr id = id

-- Composition
arr (g . f) = arr f >>> arr g

-- First preserves identity
first (arr id) = arr id

-- First preserves composition
first (arr (g . f)) = first (arr f) >>> first (arr g)

-- Association
first (first f) >>> arr assoc = arr assoc >>> first f
  where assoc ((a, b), c) = (a, (b, c))
```

These laws enable equational reasoning about signal networks.
If two arrow expressions satisfy the same equations, they are behaviorally equivalent and can be interchanged.

### ArrowLoop for feedback

Reactive systems often involve feedback: a signal that depends on its own past values.
The `ArrowLoop` class provides this capability:

```haskell
class Arrow a => ArrowLoop a where
  loop :: a (b, d) (c, d) -> a b c
```

The `loop` combinator takes an arrow with an extra output `d` that feeds back as an extra input `d`.
This is the arrow analogue of recursive function definitions.

Signal functions use `loop` to implement integrators, accumulators, and any stateful transformation:

```haskell
-- Accumulator: sum all input values
accumulator :: (Num n) => SF n n
accumulator = loop (arr (\(input, acc) -> let acc' = acc + input in (acc', acc')))
```

The feedback flows through the extra `d` channel, creating a signal that depends on its own history.
This is how continuous behaviors emerge from discrete event processing.

### Why arrows for FRP

Monads provide sequencing through bind: `m a -> (a -> m b) -> m b`.
The function `(a -> m b)` is constructed at runtime, so the structure of the computation is dynamic.
This dynamism makes certain optimizations impossible.

Arrows expose static structure through `first` and `(***)`.
Given `first f`, you know that `f` operates only on the first component; the second component passes through unchanged.
This static information enables:

- Dead code elimination (unused signal paths can be removed)
- Constant folding (constant signals can be evaluated once)
- Parallelization (independent signal computations can run concurrently)
- Optimization (signal networks can be algebraically simplified)

Modern FRP frameworks often use arrows internally while presenting a simpler API externally.
The arrow structure enables the implementation to optimize signal graphs aggressively.

## Presheaves and time-varying values

### Behaviors as presheaves

A presheaf on a category C is a functor `C^op → Set` (contravariant functor to sets).
A behavior assigning a value to each moment of time is a presheaf on the time category.

Consider time as a category with moments as objects and the temporal ordering as morphisms (t₁ → t₂ if t₁ ≤ t₂).
A behavior `B : Time^op → Set` assigns:
- To each moment `t`, a set `B(t)` of possible values at that time
- To each time progression `t₁ ≤ t₂`, a function `B(t₂) → B(t₁)` that restricts knowledge from later to earlier

The contravariance captures a fundamental asymmetry: you can always restrict knowledge to earlier times (by forgetting the future), but you cannot extend knowledge to later times without additional information.

### Denotational semantics for continuous behaviors

The presheaf perspective provides denotational semantics for continuous behaviors.
A behavior is not a sequence of sampled values but a complete mathematical function from time to values.
Sampling is a projection; the underlying behavior exists independently of when (or whether) you sample it.

```haskell
-- Behavior as function from time
type Behavior a = Time -> a

-- Sampling a behavior
at :: Behavior a -> Time -> a
at behavior time = behavior time

-- Combining behaviors pointwise
liftB2 :: (a -> b -> c) -> Behavior a -> Behavior b -> Behavior c
liftB2 f ba bb = \t -> f (ba t) (bb t)
```

The presheaf semantics justifies operations on behaviors that would be undefined for sampled sequences.
Integration, differentiation, and continuous transformation make sense for presheaves even when their discrete approximations are problematic.

### Discretization as approximation

Practical implementations cannot represent continuous behaviors exactly.
Signals in reactive frameworks are discrete approximations: they hold a current value and update at discrete moments.

The presheaf semantics provides a target for these approximations.
A good discretization should preserve the compositional properties of the underlying continuous behaviors.
When two behaviors are combined pointwise, their discretizations should combine in the same way (within the limits of the approximation).

This perspective clarifies what signals are: not the fundamental reality, but approximations to an underlying continuous semantics.
The approximation is necessary for implementation but should be invisible in the programming model.

### True FRP versus practical approximations

Conal Elliott, who originated FRP with Paul Hudak, has argued that many systems marketed as "FRP" (notably RxJS, ReactiveX, and most "reactive" JavaScript libraries) are more accurately described as asynchronous dataflow.
They lack the continuous-time denotational semantics that define FRP proper.

True FRP in Elliott's sense requires:
- Behaviors as functions `Time → a`, not sampled sequences or streams of discrete updates
- Denotational semantics independent of evaluation strategy—the meaning of a behavior is the mathematical function, not how it happens to be computed
- Continuous time as the semantic domain, with discretization as an implementation detail

Most practical frameworks sacrifice continuous-time semantics for implementation tractability.
Signals hold discrete values and update at discrete moments; there is no underlying continuous function being approximated.
This is a meaningful trade-off, not merely an implementation detail.

Understanding what is sacrificed clarifies what properties may be lost.
True FRP guarantees that behaviors compose mathematically; discrete approximations may exhibit artifacts (aliasing, timing dependencies, evaluation-order sensitivity) that the continuous semantics would forbid.
When debugging unexpected behavior in reactive systems, asking "would this occur in true FRP?" can identify whether the issue is fundamental or an artifact of the approximation.

The patterns in this document apply to both true FRP and its practical approximations, but the categorical semantics are cleanest in the continuous case.
Practical frameworks implement the structures with varying degrees of fidelity.

### Self-adjusting computation and incremental updates

The practical question for any reactive system is: given `y = f(x)`, how do we efficiently compute `y' = f(x')` when `x` changes?
Recomputing `f` from scratch is correct but potentially expensive.
Self-adjusting computation (Acar et al.) provides the theoretical foundation for efficient incremental updates.

The key insight is that a computation can be instrumented to track dependencies, then replayed with minimal recomputation when inputs change.
Only the parts of the computation that actually depend on changed inputs need to re-execute.
This is precisely what signal frameworks implement: dependency graphs that propagate changes incrementally.

Categorically, incremental computation involves computing *Kan extensions*—the "best approximation" of one functor along another.
When an input functor changes, the Kan extension describes how to adjust the output with minimal work.
This connects to derivatives of functors: just as calculus derivatives describe how functions change, functor derivatives describe how type constructors change.

```haskell
-- Derivative of a functor (conceptual)
-- ∂F describes "F with one hole"
type family Deriv (f :: * -> *) :: * -> *

-- For concrete types:
-- ∂(Const a) = Const Void        -- constants have zero derivative
-- ∂Identity = Const ()            -- identity has unit derivative
-- ∂(F × G) = (∂F × G) + (F × ∂G)  -- product rule
-- ∂(F + G) = ∂F + ∂G              -- sum rule
```

Signal frameworks implement approximate self-adjusting computation.
Dependency tracking ensures only affected signals recompute; memoization caches intermediate results; topological ordering guarantees correct propagation.
The theoretical foundation justifies why these optimizations preserve semantics: they are approximations to Kan extensions that respect the underlying categorical structure.

Understanding this connection clarifies what signal frameworks are doing and why certain optimizations are sound.
It also suggests directions for improvement: better approximations to the theoretical ideal yield more efficient reactive systems.

## The core insight: privileging change over state

### Positions versus velocities

All reactive patterns share a fundamental inversion in how they represent information:

Traditional systems store *positions*—the current accumulated state.
The state is the primary artifact; how you arrived there is secondary or lost entirely.
Querying state reads positions; updating state writes positions.

Reactive systems store *velocities*—the deltas, changes, events.
The change stream is the primary artifact; current state is derived by integration.
Querying state requires folding over history; recording change appends to the log.

This inversion has profound consequences.
Storing velocities preserves complete information: you can derive any position by integration, but you cannot recover velocities from positions.
Storing positions is lossy: you know where you are but not how you got there.

```haskell
-- Position storage (traditional)
type PositionDB = Map EntityId State

updatePosition :: EntityId -> State -> PositionDB -> PositionDB
updatePosition eid state db = Map.insert eid state db

-- Velocity storage (event sourcing)
type VelocityLog = [Event]

appendVelocity :: Event -> VelocityLog -> VelocityLog
appendVelocity event log = log ++ [event]

derivePosition :: VelocityLog -> State
derivePosition = foldl evolve initialState
```

### The connection to dynamical systems

The velocity/position duality is not merely a helpful metaphor—it is the same mathematics that underlies dynamical systems theory and numerical analysis.
Recognizing this connection transfers centuries of insight from those fields to reactive system design.

In dynamical systems, a differential equation `dy/dt = f(y, t)` specifies the velocity (rate of change) as a function of position and time.
Solving the equation means integrating velocities to recover positions: `y(t) = y₀ + ∫f(y, τ) dτ`.
This is precisely what event sourcing does: `state = foldl evolve initial events` is the discrete analogue of integration.

The correspondences are structural:

- *Event streams* are discrete approximations to continuous flows. Each event is a delta; the stream is a sampled derivative.
- *Folding events into state* is numerical integration. The `evolve` function is the integrator; the fold accumulates the integral.
- *Snapshotting* corresponds to adaptive step-size control. Just as numerical integrators take larger steps when the solution is smooth, event-sourced systems snapshot when the event rate is manageable.
- *Signal dependencies* form computational stencils. A signal that depends on neighbors in a grid is computing a discrete differential operator.
- *The comonadic `extend` operation* generalizes convolution. Applying a kernel to a signal's neighborhood is exactly what `extend` does: compute a derived value from the local context.

This connection has practical implications.
Numerical analysts have studied stability, convergence, and error accumulation for centuries; their insights apply directly to reactive systems.
Projection lag in CQRS is analogous to phase error in integration schemes.
CRDTs resemble symplectic integrators that preserve algebraic structure under composition, which is why they converge despite processing events in different orders.
Eventual consistency has the character of convergence analysis: does the discrete approximation approach the continuous limit?

For developers with backgrounds in numerical computing, physics simulation, or signal processing, this bridge provides immediate traction.
The abstractions are familiar; only the application domain is new.
For those without such backgrounds, the bridge remains available as a source of intuition when reactive systems exhibit unexpected behavior—asking "what would this mean in a dynamical systems context?" can suggest diagnostic approaches.

### The derivation generates all patterns

This single insight—privileging change over state—generates the entire constellation of reactive patterns:

*Event sourcing* stores the velocity stream (event log) and derives positions (current state) via fold (catamorphism).
The event log is the free monoid of changes; state reconstruction is the unique homomorphism to any target monoid.

*CQRS* separates the coalgebraic write path (commands produce events) from the algebraic read path (events produce views).
The separation arises because writing is about producing change (velocity) while reading is about observing state (position).

*The Decider pattern* is the pure functional encoding of this duality at the aggregate level.
`decide` produces velocities; `evolve` integrates them to positions.
The Decider is the minimal structure that captures both directions.

*Signals* are discretized comonadic behaviors with dependency tracking.
They hold current positions but update via velocity-like change propagation.
The signal graph is a network of integration points.

*Reactive streams* are coalgebraic event production with backpressure.
The stream is a source of velocities; consumers integrate those velocities into whatever positions they need.
Backpressure ensures that velocity production does not overwhelm position integration.

Each pattern is a realization of the velocity/position duality in a specific architectural context.
Understanding this shared foundation reveals why the patterns arise and when to apply them.

## The derivation hierarchy

The patterns form a hierarchy from abstract foundations to concrete implementations:

```
Category Theory Foundations
  (coalgebras, algebras, comonads, arrows, presheaves)
    ↓
Computational Models
  (Dataflow, FRP semantics, self-adjusting computation)
    ↓
Architectural Paradigms
  (Event Sourcing, CQRS, MVU, Reactive Streams)
    ↓
Implementation Patterns
  (Signals, Observables, Virtual DOM, CRDTs)
    ↓
Transport Mechanisms
  (SSE, WebSockets, HTTP Streaming)
    ↓
Concrete Frameworks
  (SolidJS, Leptos, React, Phoenix LiveView, Datastar)
```

Each level is a realization or approximation of the level above.

*Categorical foundations* provide the abstract structures: what kinds of compositions are possible, what laws must hold, what properties are preserved.
These foundations are language-agnostic and implementation-agnostic.

*Computational models* instantiate the categories in specific computational settings.
Dataflow graphs are concrete categories; FRP semantics are specific presheaves; self-adjusting computation provides memoization-compatible signal semantics.

*Architectural paradigms* are the high-level patterns that structure systems.
Event sourcing realizes the free monoid / catamorphism duality.
CQRS realizes the profunctor structure of read/write separation.
MVU (Model-View-Update) realizes the Decider loop in UI contexts.

*Implementation patterns* are the building blocks within paradigms.
Signals implement approximate comonads.
Observables implement approximate coalgebras.
Virtual DOM implements efficient diffing for state-to-view projection.
CRDTs implement commutative state merging for distributed signals.

*Transport mechanisms* handle the physical delivery of change information.
SSE, WebSockets, and HTTP streaming are ways to transmit events from server to client.
The mechanism is separate from the semantics; any mechanism that preserves ordering can carry event streams.

*Concrete frameworks* assemble these pieces into usable libraries.
SolidJS provides fine-grained signals.
Leptos combines signals with server functions.
React approximates MVU with hooks.
Datastar provides hypermedia-native signals with SSE transport.

Understanding the hierarchy clarifies framework choices.
Different frameworks make different trade-offs at each level, but they all approximate the same underlying structures.

## The Decider as forced structure

### Mathematical inevitability

The Decider pattern is not arbitrary design but mathematical necessity.
Given the constraints of typed, compositional, functional programming for stateful interactive systems, the Decider structure is forced.

Consider what is required:

1. Commands must be validated against current state (type safety)
2. Valid commands must produce observable effects (events)
3. Events must be applicable to reconstruct state (deterministic replay)
4. All operations must be pure (testability, composability)
5. The structure must compose (aggregate coordination)

These requirements uniquely determine the Decider:

```haskell
data Decider c s e = Decider
  { decide  :: c -> s -> [e]   -- (1, 2): validate and produce events
  , evolve  :: s -> e -> s     -- (3): apply events to state
  , initial :: s               -- (4): deterministic initial state
  }
```

There is no other structure that satisfies all five requirements.
The coalgebra `decide` handles (1) and (2); the algebra `evolve` handles (3); purity handles (4); the clean separation enables (5).

### Coalgebra-algebra coherence

The Decider's two functions must cohere: applying `evolve` to events produced by `decide` must yield valid state transitions.
This is not a design guideline but a structural requirement—the coalgebra and algebra must form an adjoint pair.

```haskell
-- Coherence requirement
forall cmd state:
  let events = decide cmd state
      state' = foldl evolve state events
  in valid(state')

-- Equivalently: decide and evolve form a coherent pair
```

The coherence ensures that the write path (decide) and read path (evolve) agree on what events mean.
Without coherence, the system would produce events that cannot be sensibly applied, or apply events in ways inconsistent with their production.

### State reconstruction as unique catamorphism

Given an event log and the algebra `(State, evolve)`, state reconstruction is the unique catamorphism from the initial algebra (event list) to the target algebra (state):

```haskell
reconstruct :: [Event] -> State
reconstruct = foldl' evolve initialState
```

Uniqueness is crucial: there is exactly one correct way to fold events into state.
This guarantees deterministic replay.
The same events always produce the same state, regardless of when or where the fold occurs.

The catamorphism perspective also explains snapshots: a snapshot is a memoization point in the fold.
Because the fold is unique, resuming from a snapshot produces the same result as folding from the beginning.

### Monoidal composition

Deciders compose monoidally: given two Deciders, their product is a Decider over product states and sum commands/events.

```haskell
combine :: Decider c1 s1 e1 -> Decider c2 s2 e2
        -> Decider (Either c1 c2) (s1, s2) (Either e1 e2)
combine d1 d2 = Decider
  { decide = \cmd (s1, s2) -> case cmd of
      Left c1  -> map Left (decide d1 c1 s1)
      Right c2 -> map Right (decide d2 c2 s2)
  , evolve = \(s1, s2) event -> case event of
      Left e1  -> (evolve d1 s1 e1, s2)
      Right e2 -> (s1, evolve d2 s2 e2)
  , initial = (initial d1, initial d2)
  }
```

This composition is associative with a unit (the trivial Decider with unit state and empty command/event types).
Deciders form a monoidal category, enabling algebraic reasoning about aggregate composition.

The monoidal structure means complex aggregates can be built from simpler Deciders without losing the fundamental properties.
Each component remains independently testable; the composition inherits correctness from the components.

## Why this matters

### Patterns as consequences, not choices

Without understanding FRP foundations, reactive patterns appear as disconnected "best practices."
Event sourcing seems like an audit-focused database technique.
CQRS seems like a performance optimization.
Signals seem like a state management convenience.
The Decider seems like one aggregate pattern among many.

With foundational understanding, these patterns become inevitable consequences.
They are not choices but discoveries—structures forced by the problem domain of interactive systems that unfold over time.
Choosing not to use them means either accepting less principled alternatives or reinventing the same structures under different names.

### Recognizing applicability

A developer who understands FRP foundations can recognize when patterns apply.
Any system with external asynchronous input—user interaction, network messages, sensor data, external API calls—is an interactive system.
Interactive systems benefit from reactive patterns because those patterns are designed precisely for systems whose behavior unfolds over time.

The question is not "should we use event sourcing?" but "are we modeling a system with temporal evolution?"
If yes, the FRP structures apply.
The choice is which level of the derivation hierarchy to instantiate, not whether the foundational structures are relevant.

### Deriving new patterns

Understanding foundations enables deriving new patterns for novel situations.
When you encounter a problem that existing patterns do not quite fit, foundational understanding lets you trace back to first principles and derive an appropriate variant.

The Decider pattern, for example, is an instantiation of coalgebra-algebra duality for event sourcing.
A different instantiation might be appropriate for streaming signal processing or real-time collaboration.
The foundations provide the vocabulary and laws; the specific patterns are instantiations for specific contexts.

### Seeing connections across domains

The same structures appear across domains that seem unrelated on the surface.
Databases, distributed systems, UI frameworks, and collaborative editing all share the same foundational structures because they all model interactive systems with temporal evolution.

Event sourcing in databases uses the same catamorphism structure as state reconstruction in Deciders, which uses the same fold semantics as signal derivation in UI frameworks.
CRDTs for distributed systems and signals for UI reactivity both approximate comonadic semantics.
The connections are not analogies but identities: the same mathematical structures instantiated in different contexts.

Understanding foundations reveals these connections, enabling knowledge transfer across domains.
Expertise in event-sourced databases translates to understanding reactive UI patterns.
Experience with distributed CRDTs informs signal-based state management.
The foundations unify what appears fragmented.

## Cross-references

This document provides the paradigmatic foundation connecting patterns detailed elsewhere.
For specific topics, consult:

*Categorical structures and formal definitions*:
See `theoretical-foundations.md` for detailed treatment of F-algebras, coalgebras, comonads, profunctors, and their laws.
The present document establishes why these structures matter for reactive systems; that document details what they are.

*Event sourcing implementation*:
See `event-sourcing.md` for the Decider pattern in full operational detail, including process managers, projections, CQRS, and schema evolution.
That document covers the practical aspects of building event-sourced systems.

*Aggregate and domain modeling*:
See `domain-modeling.md` for aggregate design patterns, smart constructors, state machines, and the Decider as aggregate implementation.
That document covers how these patterns manifest in domain modeling practice.

*SSE-based hypermedia*:
See `hypermedia-development/07-event-architecture.md` for how event sourcing and reactive signals combine in SSE-driven hypermedia applications.
That document covers the specific architecture of server-driven reactive UI.

*Reactive streams and distributed systems*:
See `distributed-systems.md` for reactive stream patterns, backpressure, CRDTs, and the authority question in distributed event-sourced systems.
That document covers distributed aspects of reactive architecture.

*Signal implementations*:
See `hypermedia-development/03-datastar.md` for Datastar's signal system.
See language-specific documents for signal patterns in various frameworks.

The connections among these documents are not cross-references in the bibliographic sense but structural relationships.
The present document provides the unifying paradigm; the others instantiate that paradigm in specific contexts.
Together they form a coherent treatment of reactive systems from foundations to implementation.
