# Decide, evolve, and the algebra/coalgebra of components

This file is on the practitioner spine.
It is meant to be loadable on its own, without the rest of the theoretical-foundations files.
It glosses any categorical term it needs at the point of use and points to the foundations files only as optional depth.

The thesis is narrow and load-bearing.
A component written as a *Decider* — a pair of pure maps `decide` and `evolve` — is replayable and testable because *one* of those maps, `evolve`, makes the component's state an *F-algebra*, and reconstructing state is then the unique *fold* over the event history.
That single identification is solid and citable.
Everything else in this file — the Moore-machine shape, the lens structure, the parametrized-optics family resemblance — is presented as a labelled bridge or adjacent background, not as an equation, and the reasons for that caution are stated where each appears.

## Contents

- [F-algebras and catamorphisms, briefly](#f-algebras-and-catamorphisms-briefly)
- [State machines as coalgebras](#state-machines-as-coalgebras)
- [The Decider pattern](#the-decider-pattern)
- [State reconstruction as catamorphism](#state-reconstruction-as-catamorphism)
- [The algebra lives in evolve, not decide](#the-algebra-lives-in-evolve-not-decide)
- [Moore-machine shape and the lens bridge](#moore-machine-shape-and-the-lens-bridge)
- [Monoidal composition of Deciders](#monoidal-composition-of-deciders)
- [Product monoid for aggregate state](#product-monoid-for-aggregate-state)
- [Event sourcing as algebraic duality](#event-sourcing-as-algebraic-duality)
- [Aggregates and optics: foundations only](#aggregates-and-optics-foundations-only)
- [Reactive components and comonads](#reactive-components-and-comonads)
- [Where to go next](#where-to-go-next)

## F-algebras and catamorphisms, briefly

A recursive data structure can be modeled as the *initial algebra* for a functor.
An *F-algebra* for a functor `F` is just a carrier type `A` together with a structure map `F A -> A`; it says "given one layer of `F`-structure already evaluated, here is how to collapse it into an `A`."
An *initial algebra* is the F-algebra that maps uniquely into every other F-algebra, and that unique map is the *catamorphism*, the canonical *fold*.

For lists:

```haskell
data List a = Nil | Cons a (List a)

-- corresponding functor (one layer of list-shape, with the tail position abstracted):
data ListF a r = NilF | ConsF a r

-- List a is the initial algebra for ListF a
-- the initial structure map "in" rebuilds the list:
--   in NilF        = Nil
--   in (ConsF x xs) = Cons x xs
-- the catamorphism is the unique algebra morphism to any other algebra:
cata :: (ListF a b -> b) -> List a -> b
```

Every recursive data type therefore has a canonical fold that expresses all structural recursion, and initiality guarantees that fold is the *unique* homomorphism from the initial algebra to any other algebra structure.
This uniqueness is the entire reason the Decider is replayable: there is exactly one way to interpret an event sequence as state.

For functor/monoid *laws* and property-based testing of folds, see preferences-algebraic-laws.
For concrete sum/product type encodings across languages, see preferences-algebraic-data-types.

## State machines as coalgebras

A *coalgebra* for a functor `F` is the dual of an algebra: a carrier `S` together with a map `c : S -> F S`.
Where an algebra collapses structure into a value, a coalgebra observes a value and unfolds one layer of structure.
Coalgebras model state-based computations and their observable behavior.

```haskell
-- a coalgebra for functor F:
c :: S -> F S
```

For Moore machines, `F S = Output × S` — the output depends only on the state.
Mealy machines instead use `F S = Input -> (Output × S)`, where the output depends on both state and input.

```haskell
-- Moore machine coalgebra
mooreCoalg :: State -> (Output, State)

-- Mealy machine coalgebra
mealyCoalg :: State -> Input -> (Output, State)
```

Just as initial algebras correspond to finite data, *final coalgebras* correspond to potentially infinite processes.
Two states are *behaviorally equivalent* (bisimilar) when they produce the same observations under all inputs, which lets us reason about a state machine through its observable behavior rather than its internal representation.

For entity-lifecycle state machines as a domain-design pattern, see preferences-domain-modeling.

## The Decider pattern

The Decider pattern, formalized by Jérémie Chassaing in functional event sourcing, provides a minimal algebraic interface for an event-sourced component.
It packages a component as two pure maps over an initial state.

```haskell
data Decider cmd state event = Decider
  { decide       :: cmd -> state -> [event]
  , evolve       :: state -> event -> state
  , initialState :: state
  , isTerminal   :: state -> Bool  -- optional: detect terminal states
  }
```

The two essential maps have these signatures:

- `decide : Command -> State -> [Event]` produces events based on the current state and a command.
- `evolve : State -> Event -> State` applies a single event to the state.

The `decide`/`evolve` pair plus `initialState` is the minimal complete definition; `isTerminal` is an optional terminal-state detector.
The `(decide, evolve)` pair is what this skill means by "Decider" wherever the term appears.

The Decider is pure: both maps are referentially transparent functions with no side effects.
Effects — persistence, event publishing, external queries — live in an interpreter layer, not in the Decider itself.

A worked bank-account Decider:

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

The entire aggregate logic is captured in one pure value.
Testing requires no mocking or infrastructure: given a command and a state, verify the events; given events and an initial state, verify the final state.

The pure Decider is the *algebra* in the classical signature/algebra/interpreter split; an effectful *interpreter* runs it against infrastructure.
A representative interpreter loads the event history, folds it into the current state via `evolve`, calls `decide` to get new events, and persists them:

```haskell
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

The three-level separation — interface, pure algebra, effectful interpreter — lets you test the algebra in isolation, swap interpreters (production Postgres, in-memory test, simulation), and reason about the pure functions formally.
For the operational concerns of running event-sourced aggregates (snapshots, process managers, schema evolution), see preferences-event-sourcing.
For the smart-constructor and aggregate-design mechanics around the Decider, see preferences-domain-modeling.

## State reconstruction as catamorphism

State reconstruction via `evolve` is precisely a catamorphism (fold) over the event list.
Given an event log `events = [e₁, e₂, ..., eₙ]` and the algebra `(State, evolve)`, the current state is:

```haskell
currentState = foldl' evolve initialState events
```

This is the unique catamorphism from the initial algebra of event lists to the algebra `(State, evolve)`.

Event lists form the initial algebra for the list functor `F X = 1 + (Event × X)`:
the constructors are `Nil : 1 -> List Event` and `Cons : Event × List Event -> List Event`, and `(List Event, [Nil, Cons])` is the initial algebra.
The `evolve` function defines an algebra structure on `State` with carrier `State` and structure map `evolve : State -> Event -> State`.
Initiality guarantees a *unique* homomorphism from the event-list initial algebra to `(State, evolve)`, and that unique homomorphism is `fold evolve initialState`.

Uniqueness is the practical payoff: given the algebra `(evolve, initialState)`, there is exactly one way to interpret the event sequence, so replay is deterministic — the same events always produce the same state, regardless of when or where they are replayed.

Snapshots are partial evaluations of this catamorphism:

```haskell
-- snapshot at event N
snapshotₙ   = foldl' evolve initialState (take N events)
-- resume from snapshot
currentState = foldl' evolve snapshotₙ (drop N events)
```

Memoization here is valid because the fold is deterministic, which in turn requires `evolve` to be total and deterministic:

```haskell
-- totality: evolve handles all event cases, always terminates, no exceptions
evolve state event

-- determinism: same state + event always gives the same next state
evolve s e == evolve s e
```

If `evolve` violates these, state reconstruction becomes non-deterministic and the catamorphism property is lost.
Property-test these laws with the techniques in preferences-algebraic-laws.

## The algebra lives in evolve, not decide

The precise structural claim of this skill is deliberately one-sided, and getting the side right matters.

The F-algebra structure — the fold that makes replay deterministic — lives entirely in `evolve`.
`evolve` with the initial state *is* the F-algebra for `F X = 1 + Event × X`, and that is the whole content of the "Decider is replayable and testable" thesis.

`decide` is the *output / readout leg*.
It is not the F-algebra, and it is not, on its own, a coalgebra: it is the map that, given the current (already-folded) state and a command, reads out the events to emit.
Earlier informal presentations of this material called `(decide, evolve)` an *adjoint pair* — `decide` the left adjoint, `evolve` the right adjoint, with unit/counit equations.
That framing overstates the structure: no adjunction between a command category and an event category with state as pivot is established by any source consulted here, and the unit/counit story does not actually hold up.
Do not call `(decide, evolve)` an adjoint pair.

The honest joint statement is operational, not adjoint: the *whole* Decider — `decide` composed with the `evolve`-fold — behaves as a Mealy/Moore machine, with `evolve` the update leg and `decide` the readout leg.
That Mealy/Moore framing is the correct bridge to a lens structure, and it is the subject of the next section, where it is flagged as pending source verification.

## Moore-machine shape and the lens bridge

The genuinely precise but *to-be-verified* bridge is at the level of machines, not of the Decider as such.

`(decide, evolve)` has the `(readout, update)` signature of a *Moore machine*: `decide` reads an output off the state and `evolve` updates the state on each input event.
Moore machines are, in turn, lens-structured — they are coalgebras of `S ↦ B × S^A`, which is the carrier shape of a lens (Spivak's mode-dependent dynamical systems as lenses; Myers, *Categorical Systems Theory*).
Chaining these two facts gives "the Decider is Moore-shaped, hence lens-structured at the machine level."

Treat that chained statement as a *labelled gloss pending a source check*, not as settled fact.
Whether Spivak or Myers explicitly frame `decide`/`evolve` (or event-sourced Deciders specifically) in lens language is unverified, and no local copy of either source was available; the Moore-machine-as-lens fact is well known about Moore machines but should be confirmed against the actual text before it is cited for the Decider.
A lens itself is just a pair of functions over a product structure:

```haskell
data Lens s a = Lens
  { view   :: s -> a           -- getter / readout
  , update :: (a, s) -> s      -- setter / update
  }
```

What you must *not* do, in code or in docs, is assert that a Decider literally *is* a lens, an optic, or a Para morphism.
The verifiable statements are exactly two: the Decider is a fold/catamorphism on `evolve`, and the Decider is Moore-machine-shaped (and therefore lens-structured at that level, pending the source check above).

The broader "learned/parametrized maps form Para, bidirectional processes form optics, and these are one construction" line (Categorical Cybernetics — Capucci, Gavranović, Hedges, Rischel, 2022) is *adjacent background only*.
It is a fertile family resemblance, not a theorem about Deciders: that work unifies parametrized maps and bidirectional processes but does not include the Decider, and a bare Para morphism is a single parametrized map `P × A -> B`, not a two-legged pair.
The two-leggedness that the Decider shares with lenses lives in optics, not in Para itself, so describing the Decider as "a pair of legs over a shared object in Para" conflates parametrization with bidirectionality.
Rutten's work on coalgebras (2000) and the profunctor-optics line of Pickering, Gibbons, and Wu (2017) are likewise background here; do not cite either as grounding the Decider/lens identity.

## Monoidal composition of Deciders

Deciders compose: two Deciders combine into a single Decider with product state and sum command/event types.

Given `Decider<C₁, S₁, E₁>` and `Decider<C₂, S₂, E₂>`, construct `Decider<C₁ + C₂, S₁ × S₂, E₁ + E₂>`:

```haskell
data SumCmd c1 c2 = Left1 c1 | Right1 c2
data SumEvent e1 e2 = Left2 e1 | Right2 e2
type ProductState s1 s2 = (s1, s2)

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

This composition satisfies the monoidal axioms — associativity up to isomorphism, with a trivial unit Decider acting as identity:

```haskell
combine (combine d1 d2) d3 ≅ combine d1 (combine d2 d3)

unitDecider = Decider
  { decide = \_ _ -> []
  , evolve = \_ _ -> ()
  , initialState = ()
  , isTerminal = \_ -> False
  }

combine d unitDecider ≅ d
combine unitDecider d ≅ d
```

Deciders thus form a monoidal category: objects are type triples `(Command, State, Event)`, morphisms are Decider implementations, the monoidal product is `combine`, and the unit object is the trivial Decider.
The product distributes command sums over state products: `(C₁ + C₂) × (S₁ × S₂) -> List(E₁ + E₂)`.

Concretely, an audit-log Decider composes with an account Decider to yield an account-with-audit-trail aggregate without hand-written sum/product plumbing:

```haskell
type CombinedCmd   = SumCmd AccountCmd AuditCmd
type CombinedState = (AccountState, AuditState)
type CombinedEvent = SumEvent AccountEvent AuditEvent

combinedDecider :: Decider CombinedCmd CombinedState CombinedEvent
combinedDecider = combine accountDecider auditDecider
```

Monoidal composition lets you build complex aggregates from simpler Deciders, test each sub-Decider independently, reuse a Decider across aggregate contexts, and grow an aggregate incrementally.

## Product monoid for aggregate state

When aggregate state is a product of monoidal fields, the state itself forms a monoid, which simplifies `evolve`.

A *monoid* is a type with an associative binary operation `<>` and an identity element `mempty`.
If each field of a state record is a monoid, the record is a monoid pointwise: the identity is the tuple of identities, and the operation combines fieldwise.

```haskell
data OrderState = OrderState
  { items            :: Map ProductId Quantity  -- Map is a monoid (pointwise merge)
  , totalPrice       :: Sum Money               -- Sum monoid (addition)
  , status           :: Last OrderStatus        -- Last monoid (most recent wins)
  , appliedDiscounts :: Set DiscountCode        -- Set monoid (union)
  }
```

When the state is a monoid, `evolve` collapses to "convert the event to a partial state, then monoidally append":

```haskell
evolve :: OrderState -> OrderEvent -> OrderState
evolve state event = state <> eventToState event
  where
    eventToState (ItemAdded prodId qty price) = mempty
      { items = Map.singleton prodId qty, totalPrice = Sum price }
    eventToState (StatusChanged s) = mempty
      { status = Last (Just s) }
    eventToState (DiscountApplied code discount) = mempty
      { appliedDiscounts = Set.singleton code, totalPrice = Sum (negate discount) }
```

This eliminates complex case analysis in `evolve`, reducing bugs and cognitive load.
It works when fields are independent, append semantics match the domain, and conflicts resolve monoidally; it does not work when there are cross-field invariants, non-commutative updates beyond what the monoid captures, or transitions that must examine multiple fields together.
When every field is a *commutative* monoid, the aggregate state is structurally a CRDT, enabling eventual consistency in distributed scenarios.
For the monoid laws and how to property-test them, see preferences-algebraic-laws.

## Event sourcing as algebraic duality

At the system level, event sourcing represents both construction (algebra) and observation (coalgebra) perspectives at once.
The event log is a *free monoid* over event types — a universal construction that preserves complete history while enabling arbitrary interpretations via monoid homomorphisms — and state reconstruction proceeds via the catamorphism guaranteed by initiality.

```haskell
data Event
  = UserRegistered UserId Email
  | EmailVerified UserId
  | OrderPlaced OrderId UserId
  | OrderShipped OrderId

newtype EventLog = EventLog [Event]

instance Monoid EventLog where
  mempty = EventLog []
  mappend (EventLog xs) (EventLog ys) = EventLog (xs ++ ys)
```

The free monoid `Free(S)` over a set `S` is the initial algebra for the list functor `ListF X = 1 + (S × X)`, the same initiality that underlies recursive data types.
Its universal property says that for any monoid `m` and any generator map `Event -> m`, there is a *unique* homomorphism realized as a fold:

```haskell
foldEvents :: Monoid m => (Event -> m) -> EventLog -> m
foldEvents f (EventLog events) = foldMap f events
```

Initiality therefore guarantees arbitrarily many projections, each a monoid homomorphism from the log into a target monoid, and the append-only structure is enforced by the monoid axioms (associativity preserves order; identity gives a starting point).

This duality manifests as CQRS: the command side (contravariant in commands) and the query side (covariant in views) both factor through the event log as a shared pivot, splitting the algebra side (write model, the left fold) from the coalgebra side (read models, the projections) and promoting that split to an architectural boundary.
The *projection* — the read-model fold from the log into a target monoid — is a monoid homomorphism, and that homomorphism law is itself a recoverable theorem rather than an instrumentation convention.
That law, and the cofree-comonad gloss on the observation-annotated log, are owned by the observability-as-theorem reference file in this skill; consult it rather than restating them here.
For operational event-sourcing patterns — process managers, schema evolution, snapshot strategy — see preferences-event-sourcing.

## Aggregates and optics: foundations only

Optics give a compositional vocabulary for reaching into and updating the internals of an aggregate while preserving encapsulation; this file keeps only the foundations and defers aggregate-design mechanics to preferences-domain-modeling.

A *lens* focuses a component of a product (a record field):

```haskell
data Lens s a = Lens
  { view   :: s -> a           -- getter
  , update :: (a, s) -> s      -- setter
  }

-- laws:
--   GetPut: update (view s, s) = s
--   PutGet: view (update (a, s)) = a
--   PutPut: update (a', update (a, s)) = update (a', s)
```

Lens composition is covariant in the focus direction: composing a `Lens' Person Address` with a `Lens' Address String` yields a `Lens' Person String`, moving deeper into the structure along the flow of access.

A *prism* is the dual, focusing a case of a sum:

```haskell
data Prism s a = Prism
  { match :: s -> Either a s   -- extract if it matches
  , build :: a -> s            -- inject
  }

-- laws (dual to lens laws):
--   MatchBuild: match (build a) = Right a
--   BuildMatch: either build id (match s) = s
```

Lenses and prisms sit in a small hierarchy — `Iso` above both, `Traversal` below for multiple foci, `Fold` for read-only access — giving a uniform interface for navigating product and sum structure.
The parametrized-maps-and-bidirectional-processes (Para/optics) family resemblance to the Decider is adjacent background only, as flagged in the lens-bridge section above; it is not a load-bearing identity here.

## Reactive components and comonads

Reactive signal systems exhibit *comonadic* structure, the categorical dual of monads.
Where monads model effect production (building context through sequenced computations), comonads model context consumption (extracting and transforming values from a surrounding context).
This duality is what makes the server-side / client-side split principled, and it is treated only at a glance here.

A *comonad* `W` is a functor with `extract : W a -> a` and `extend : (W a -> b) -> W a -> W b` (equivalently `duplicate : W a -> W (W a)`):

```haskell
class Functor w => Comonad w where
  extract   :: w a -> a
  extend    :: (w a -> b) -> w a -> w b
  duplicate :: w a -> w (w a)
```

For a reactive signal, `extract` reads the current value, `extend f` derives a new signal whose every point computes `f` over the signal's context, and `duplicate` exposes the neighborhood at each point.
The comonad laws (dual to the monad laws) are what guarantee that derived signals compose: deriving `C` from `B` from `A` equals deriving `C` directly from `A` with the composed derivation, which is why signal graphs can be built incrementally without worrying about evaluation order.

The monad/comonad duality explains an architectural split that recurs in event-sourced reactive systems: server-side event sourcing is monadic (effects flow inward, are produced), client-side reactivity is comonadic (values flow outward, are consumed).
A web component, observed as a Moore machine `S -> (Output, Input -> S)`, is the coalgebraic readout end of that pipeline — the same Moore/coalgebra shape this file uses for the Decider, here pointed the other way.

Keep this at the level of the connection only.
For the foundational FRP treatment — why signals are comonadic, why event sourcing is monadic, reactive-stream and backpressure semantics — see preferences-functional-reactive-programming.
For the cofree-comonad-of-the-log gloss specifically (the observation-annotated event stream whose `extract` reads the current folded state and whose `duplicate` yields every replay point), see the observability-as-theorem reference file in this skill, which owns it under the explicit linear-stream-functor reading it requires.

## Where to go next

The foundations files in this skill are optional depth for everything above: the adjunction framing of abstraction, the conjectural unifying internal language, and the graded-effects/coeffects axis live there and are not needed to apply the Decider.
For the read-model homomorphism law and the cofree gloss, go to observability-as-theorem in this skill.
For laws and property tests, see preferences-algebraic-laws.
For aggregate and domain design, see preferences-domain-modeling.
For operational event sourcing, see preferences-event-sourcing.
For FRP and reactive streams, see preferences-functional-reactive-programming.
For the Lean-to-Rust round trip that turns these specifications into checked implementations, see refinement-driven-development, which owns all verification process.
