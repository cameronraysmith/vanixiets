---
title: Capability interfaces, handlers, and why not transformer stacks
---

## Contents

- [Where this file sits on the foundations spine](#where-this-file-sits-on-the-foundations-spine)
- [Workflows as morphisms in a Kleisli category](#workflows-as-morphisms-in-a-kleisli-category)
- [The Functor, Applicative, Monad hierarchy as universal-property framing](#the-functor-applicative-monad-hierarchy-as-universal-property-framing)
- [Capability interfaces: the same pattern as finally-tagless](#capability-interfaces-the-same-pattern-as-finally-tagless)
- [A transformer stack is one interpreter, not the interface](#a-transformer-stack-is-one-interpreter-not-the-interface)
- [The transformer-stack defect list is engineering experience, not a theorem](#the-transformer-stack-defect-list-is-engineering-experience-not-a-theorem)
- [Algebraic effects and handlers as the modern discharge](#algebraic-effects-and-handlers-as-the-modern-discharge)
- [Higher-order and scoped effects](#higher-order-and-scoped-effects)
- [Indexed monads: one tool for typestate, not the organizing principle](#indexed-monads-one-tool-for-typestate-not-the-organizing-principle)
- [There is no single canonical category of effects](#there-is-no-single-canonical-category-of-effects)
- [Why you do not build the transformer tower](#why-you-do-not-build-the-transformer-tower)

## Where this file sits on the foundations spine

This file lands the keystone correction of the skill: the organizing primitive for effects is a *capability interface discharged by handlers*, not a monad-transformer stack.
A capability interface is an effect signature — a set of operations — together with the discipline that meaning is supplied by an interpreter chosen separately from the program text.
A concrete monad-transformer stack is one interpreter of such an interface, and a leaky one, not the interface itself and not a theoretical ideal that better engineering converges on.

The thesis of the parent skill is that good architecture factors every concern through an adjunction `F ⊣ U` and converges asymptotically on a single typed calculus — the conjectural internal language of compositional software architecture, which does not yet exist as one calculus.
This file's job is to remove the false ideal that stood in that calculus's place: the idea that the ideal is an indexed monad transformer stack.
It is not.
The transformer stack is merely one non-canonical interpreter of a capability interface.
For the initial/final duality that organizes the calculus, see internal-language.md; for the resource-semiring grading that types the two faces of effect and coeffect, see graded-effects-coeffects.md.

This file is on the foundations spine.

## Workflows as morphisms in a Kleisli category

The foundational framing for effectful composition is the Kleisli category.

In the base category of types, objects are types and morphisms are ordinary functions `f : A → B`, composing associatively with identities.
The practical problem is that functions returning effectful results do not compose with ordinary function composition.

```haskell
validateOrder :: UnvalidatedOrder -> Result ValidatedOrder ValidationError
priceOrder    :: ValidatedOrder   -> Result PricedOrder   PricingError
```

These do not compose because the output type `Result B` does not match the input type `B`.

The categorical solution is the Kleisli category for a monad `M`.
Its objects are the same types as the base category, its morphisms are the *Kleisli arrows* `A → M B`, its composition is Kleisli composition `>=>` (implemented via bind), and its identity is `return : A → M A`.

```haskell
(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> (a -> m c)
f >=> g = \x -> f x >>= g
```

The practical consequence is that bind enables composition of effectful computations while preserving category laws.
The railway-oriented composition of `Result`-returning functions is exactly Kleisli composition in the `Result` monad; for that operational treatment see preferences-railway-oriented-programming.

## The Functor, Applicative, Monad hierarchy as universal-property framing

The three central interfaces form a hierarchy of compositional power.

```haskell
class Functor f where
  fmap :: (a -> b) -> f a -> f b

class Functor f => Applicative f where
  pure  :: a -> f a
  (<*>) :: f (a -> b) -> f a -> f b

class Applicative m => Monad m where
  return :: a -> m a   -- same as pure
  (>>=)  :: m a -> (a -> m b) -> m b
```

A functor lets you map a function over a wrapped value; an applicative lets you combine independent wrapped values in parallel; a monad lets you chain operations where each step depends on the previous result.
The practical reading: use `fmap` to transform a success without touching the error channel, use applicative to validate independent fields in parallel and collect every error, and use bind to chain dependent computations that short-circuit on the first failure.

The laws that make these interfaces well-behaved — the functor laws, the applicative homomorphism law, and the monad laws that make Kleisli composition a genuine category — are owned by preferences-algebraic-laws, which also covers how to property-test them.
This file uses the hierarchy only as the universal-property framing for effects; it does not re-teach the laws.

## Capability interfaces: the same pattern as finally-tagless

An mtl-style capability constraint such as `MonadReader r m`, `MonadState s m`, or `MonadError e m` is the same design pattern as a finally-tagless encoding (Carette, Kiselyov, and Shan 2009): operations are overloaded over an abstract carrier `m`, and the concrete meaning is supplied by instance selection — that is, by an interpreter.

```haskell
processOrder
  :: (MonadReader Config m, MonadState Ledger m, MonadError OrderError m)
  => Command -> m Receipt
```

The signature names a *capability interface*: the operations the program may use, with no commitment to how they are realized.
The carrier `m` is opaque; only the operations the constraints expose are available; the program is a term over those operations, and its meaning arrives when a concrete `m` is selected.
That is precisely the finally-tagless discipline — operations over an opaque carrier, meaning by instance selection.

Two wording cautions are mandatory.
The correspondence is "an instance of / the same pattern as," never an identity proved by Carette, Kiselyov, and Shan 2009.
That paper's subject is the embedding of typed object languages; it does not mention Haskell's mtl, so it grounds the *technique* and the *final pole* of the encoding, not the equation, and you must never write that it proves mtl is tagless-final.
The correspondence is also not a structural isomorphism: mtl additionally commits to monadic carriers and a `MonadTrans`/`lift` default-instance discipline that the tagless-final framework does not require.

The deeper structure underneath both is the initial-versus-final duality.
A free, coproduct-of-functors encoding (Swierstra 2008, *Data Types à la Carte*) represents the program as inspectable data — an initial algebra over the effect signature that you can reorder, optimize, and re-interpret.
A tagless-final encoding is the Church-style encoding that represents the program as an opaque, directly-interpretable term.
These are dual presentations and neither universally dominates: the free side buys introspectability and reorderability, the final side buys interpretation efficiency and open extensibility, and the choice is made per use site.
For the full initial/final treatment see internal-language.md.

## A transformer stack is one interpreter, not the interface

Once the capability interface is the primitive, a concrete monad-transformer stack is just one interpreter of it.

```haskell
type App a = ReaderT Config (StateT Ledger (ExceptT OrderError IO)) a
```

This stack discharges the `MonadReader`/`MonadState`/`MonadError` capabilities above, but it is not the only carrier that can.
A `ReaderT`-over-`IO` carrier holding a *handler record* discharges the same interface and dispatches each operation through a field of the record.
An algebraic-effect runner built from delimited continuations (Plotkin and Pretnar's handlers of algebraic effects) discharges it by interpreting the operations of an effect set.
The capability interface (the effect signature) is the stable design primitive; any of these carriers is one non-canonical interpreter, and the transformer stack holds no privileged status among them.

The original framing called this an "indexed monad transformer stack."
Drop the "indexed" qualifier: it carries no weight in this argument, the reasoning is identical for plain transformer stacks, and indexing is a separate concern treated below under typestate.

## The transformer-stack defect list is engineering experience, not a theorem

The transformer-stack carrier family has a well-known defect list, and it is real, but it is *engineering experience about one carrier family*, not a theorem and not a universal property of capability interpreters.

The recurring complaints are that the stack is a leaky abstraction (the layering shows through in `lift` calls and in which operations are reachable), that the layers do not commute (`StateT s (ExceptT e m)` discards state on error while `ExceptT e (StateT s m)` retains it, so the order is a semantic commitment), that the naive encoding does not fuse, and that accessing a deep layer costs an `O(n²)` chain of `lift` calls as the stack grows.

These are genuine, and they motivate preferring shallow stacks or another carrier entirely.
But they are properties of *this carrier family*, not of capability interfaces, and several entries have explicit counterexamples.
The `fused-effects` library fuses by construction, so the non-fusion complaint does not hold there.
A handler-record or `ReaderT`-over-`IO` carrier dispatches each operation in `O(1)` through a record field or the reader environment, so the `O(n²)`-lift complaint does not hold there either.
Present the defect list as practitioner experience about the transformer-stack interpreter, never as a theorem from any cited paper and never as a property of capability interpreters in general.

## Algebraic effects and handlers as the modern discharge

The modern discharge of a capability interface is an algebraic effect with handlers.

```haskell
-- Effect signature (the capability interface)
data FileSystem :: Effect where
  ReadFile  :: FilePath -> FileSystem String
  WriteFile :: FilePath -> String -> FileSystem ()

-- Program over the signature, no transformer stack
processFile :: FilePath -> Eff '[FileSystem, Error] Result
processFile path = do
  contents <- readFile path
  validate contents
  writeFile outputPath result
  return result

-- Discharge the capability at the edge
runFileSystem :: Eff '[FileSystem, Error] a -> IO (Either Error a)
```

A handler is the interpreter for the operations of an effect set.
Because handlers interpret an effect *set* rather than peeling a fixed stack of layers, effects can be reordered more flexibly, there is no `lift` boilerplate, the handlers are individually modular, and type inference is typically better than for deep transformer stacks.
The trade is maturity: algebraic effects are research-stage in most languages, production-ready in OCaml's runtime effect handlers, and available as libraries such as Polysemy and `fused-effects` in Haskell, ZIO in Scala, and Effect-TS in TypeScript.

A handler is an algebra homomorphism: it sends the operations of the effect signature to a target carrier while preserving composition and identity.

```haskell
handle :: Effect a -> Target a
handle (e1 >> e2) = handle e1 >> handle e2
handle (return x) = return x
```

The payoff is that one program over a capability interface admits many interpretations — production versus test, pure versus `IO` — chosen by swapping the handler.
This is the same many-interpreters property as the tagless-final encoding above, which is the point: the capability interface is the invariant and the handler is the variable.

## Higher-order and scoped effects

First-order algebraic effects model operations whose continuations are first-order, but many real operations are *higher-order*: their arguments are themselves computations.
Exception catching, local environment modification, resource bracketing, and concurrency all take a sub-computation as an argument, and the naive algebraic-effects presentation cannot express them as plain operations of a signature.

Two lines extend the framework to cover them.
Wu, Schrijvers, and Hinze 2014 (*Effect handlers in scope*) introduce *scoped* effects, which add an explicit scoping construct so that an operation can delimit a sub-computation it interprets.
Bach Poulsen and van der Rest 2023 (*Hefty algebras*) give *hefty algebras*, a presentation in which higher-order operations are first-class, recovering modular handlers for the higher-order case and elaborating hefty trees down to ordinary algebraic effects.
The practical upshot is that the capability-interface-plus-handler discipline scales to the higher-order operations a transformer stack would otherwise be reached for, without reintroducing the tower.

## Indexed monads: one tool for typestate, not the organizing principle

Indexed monads are one tool for typestate and protocol tracking, not the organizing principle for effects.

An indexed monad threads a pair of type-level indices through bind, letting the type record a state transition rather than only a value.

```haskell
class IxMonad m where
  ireturn :: a -> m i i a
  ibind   :: m i j a -> (a -> m j k b) -> m i k b
```

The indices `i, j, k` track a typestate at the input, an intermediate point, and the output, which lets the type system enforce a protocol — for example, that a file is opened before it is read and closed after.

```haskell
openFile  :: FilePath -> FileHandle Closed Opened Handle
readFile  :: FileHandle Opened Opened String
closeFile :: Handle -> FileHandle Opened Closed ()
-- the type rejects reading after close
```

This is genuinely useful, and it is exactly where indexed monads earn their cost: enforcing a critical safety protocol at the type level.
It is not the organizing principle for effects in general.
The cost is real — most languages lack the support, inference becomes intractable, ergonomics suffer under heavy annotation, and library support is thin — so reserve indexed monads for the safety properties that warrant them and discharge ordinary effects through the capability-interface-plus-handler route above.

For typestate framed as *making illegal states unrepresentable*, see preferences-domain-modeling; for the resource-grade index that types how much of a capability a computation uses, see graded-effects-coeffects.

## There is no single canonical category of effects

There is no single canonical category of effects; there is a plurality of presentations, and which one applies depends on what you need to track.

The free monad over a signature presents a program as inspectable data — the initial algebra over the effect signature — and is the natural home for reorder-and-reinterpret.
A Lawvere theory presents effects as operations *with equations*, capturing the algebraic laws an effect must satisfy (for example, that two writes to the same cell collapse to the second), which the bare free monad does not record.
Graded presentations refine these with an index drawn from a resource semiring, so the type records *which* effects and *how much*; the graded story is owned by graded-effects-coeffects.
Premonoidal and Freyd categories model effectful computation where the tensor is not fully functorial — exactly the situation when effect order matters and `f ⊗ g` differs from `g ⊗ f` — which is the categorical statement of the layer-ordering commitment discussed above.
And the higher-order story (scoped and hefty effects) sits above all of these for operations whose arguments are computations.

These are complementary presentations of the same subject, not competing claims to be *the* category of effects.
You can model effects as morphisms in a monoidal category and read effect composition as the tensor, but the concrete realization depends on the interpreter you choose — `ExceptT e (StateT s m)` and `StateT s (ExceptT e m)` are different objects — which is again the premonoidal observation that the tensor is order-sensitive, not a defect to be normalized away.

## Why you do not build the transformer tower

The original skill framed a fully indexed monad transformer tower as the *theoretical ideal* that pragmatic code approximates.
That framing is superseded.
The tower is one interpreter of a capability interface, and a leaky one; the ideal it stood in for is the conjectural typed calculus of internal-language.md, approached asymptotically and partially realized today by keeping a type-checkable Lean specification beside the implementation.
The practical advice below therefore explains why you do *not* build the tower, not how to perfect it.

The practical challenges with deep transformer stacks are the ones in the defect list: the compiler cannot infer complex stacked types, the annotations metastasize, most libraries do not support deep stacks, compilation slows, and the type errors become unreadable.
The pragmatic response is a ladder of carriers chosen by what a given piece of code actually needs.

Most code uses simple, specialized effect types and documents the effect in the signature without indexing it.

```haskell
type AsyncResult a e = Async (Result a e)
processData :: Config -> Data -> AsyncResult ProcessedData Error
```

Where an effect system is available, use it — Effect-TS's `Effect<A, E, R>`, ZIO's `ZIO[R, E, A]`, or a Haskell effects library — so the capability interface and its handlers carry the structure instead of a hand-rolled stack.
Where a transformer stack is genuinely the right carrier, keep it shallow (two or three effects at most) and hide it behind a type alias.
Reserve indexed monads for the critical safety properties of the typestate section above.

The best practices reduce to a single discipline: make the capability interface explicit in the type, prefer specialized types or an effects library over a general stack, keep any stack shallow, and write handlers for both production and test so the same program over the interface admits both interpretations.
For effect composition in architectural practice see preferences-architectural-patterns; for operational event-sourcing where these effects are committed and replayed see preferences-event-sourcing; for the read-model fold that recovers observability as a strict monoid homomorphism see observability-as-theorem.md; and for the calibration of how thoroughly to verify each of these claims see preferences-validation-assurance, with the Lean-to-Rust round trip itself owned by refinement-driven-development.
