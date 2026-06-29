---
title: Observability as a monoid homomorphism
---

This file is on the practitioner spine and is loadable on its own without the foundations-spine references.
It states the one structural fact a read-model fold must satisfy, casts it as a checkable theorem rather than an instrumentation convention, and gives the design rule that follows.
For the laws-and-property-testing machinery (functor, monad, and monoid laws as specifications) see preferences-algebraic-laws; for the operational mechanics of event-sourced projections see preferences-event-sourcing; for the structured-event/trace/SLO discipline that observability rests on operationally see preferences-observability-engineering.

## The CQRS split as an architectural boundary

The committed event log is a single append-only stream.
The write model is its left fold, and every read model is a projection of that same stream.
CQRS is exactly that split between the algebra side (the fold that derives state) and the coalgebra side (the stream the projections observe), promoted from an implementation detail to an architectural boundary.
This much is standard.

A projection is best understood as a structure-preserving map out of the event stream rather than as ad-hoc query code.
The earlier monolith framing called each projection a functor from event streams to read models, with natural transformations between projections expressing consistency; that framing is fine as an altitude-raising gloss, but the load-bearing structural claim it gestures at is sharper and lives one level down, in the monoid the fold lands in.
The next section states it as a theorem.

## The theorem: a read model is a monoid homomorphism

A CQRS read model that folds an event log into a target monoid *M* via a per-event observation *f* is a monoid homomorphism from the free monoid of events (lists under concatenation) into *M*.
Concretely:

```
project (xs ++ ys) = project xs <> project ys
```

This is the universal property of the free monoid — the `foldMap` homomorphism law — not a logging convention.
It is proven in the worked example: `references/worked-example/Limit.lean` proves the general law `fmap_hom` by list induction at lines 217-221 and instantiates it for the read model as `project_hom` at lines 242-244, and `references/worked-example/limit.py` exercises it as a runtime property check at lines 217-219.
In this precise sense observability for the read-model fold is recovered as a *theorem*: telemetry is not a side discipline bolted onto the system but a consequence of the projection's algebraic shape.

This is the genuinely novel framing relative to the monolith, which states "projections as functors" but never states the homomorphism law as a checkable theorem.

## The proof needs only associativity and identity

The proof of `fmap_hom` uses only that *M*'s binary operation is associative and has an identity — that *M* is a monoid.
It is *not* a commutative monoid: the worked example's `CMonoid` class, despite the name, declares only `op_assoc`, `e_op`, and `op_e` (Limit.lean lines 204-209) and the proof never invokes commutativity.

Commutativity is therefore a strictly *separate* requirement.
It is needed not for the homomorphism equality but only for shard-order and reorder invariance: if the rollup is computed across shards whose results are merged in a nondeterministic order, the merge operation must commute for the answer to be well-defined.
The homomorphism law alone guarantees that splitting a stream at any single point and recombining gives the same answer; commutativity additionally guarantees that *which* split, and in which order the pieces recombine, does not matter.
Keep the two requirements distinct: a totally-ordered append-only log needs only the monoid, and only a reorder-tolerant distributed rollup additionally needs commutativity.

## The load-bearing caveat: float addition is not associative

IEEE-754 floating-point addition is not associative.
A read model that aggregates over floats is therefore *not* a true monoid homomorphism, and reordered or resharded rollups of the same events can disagree.
This is why the worked example deliberately aggregates into a `Nat` monoid rather than a float (Limit.lean lines 200-202): the same reason real telemetry pipelines must pick an exact aggregation monoid to make sharded rollups agree.
Choose an exact aggregation monoid — integer counts, exact or decimal arithmetic, or a canonical-order reduction — whenever the homomorphism property is meant to hold.

## Design rule

Property-test the homomorphism directly:

```
project(xs ++ ys) == project(xs) <> project(ys)
```

Never aggregate a read model over a non-associative operation silently.
If the natural target carrier is floating point, either switch to an exact monoid or accept and document that the projection is an approximation, not a homomorphism, and that resharded rollups may diverge.
This is the practitioner discharge of the theorem above; for how to site such a property test within the project's check tiers and confidence-promotion calibration see preferences-validation-assurance, and for the law-as-specification stance generally see preferences-algebraic-laws.

## On the "lax-monoidal 2-cell" slogan

The source sometimes bills this result as "a lax-monoidal projection 2-cell off the committed event coalgebra."
Treat that phrasing as a decorative slogan, not a constructed result.
The proven structure is a *strict* monoid homomorphism: `project (xs ++ ys) = project xs <> project ys` holds on the nose, with the unit preserved definitionally, equivalently a strict monoidal functor between one-object categories.
No 2-category, no coalgebra of observations, and no actual 2-cell is constructed anywhere in the artifact.
Calling it *lax* is doubly wrong, because the proven structure is strict rather than merely lax.
Use "the read-model projection is a (strict) monoid homomorphism" as the claim; the slogan is something the source itself cashes out as exactly this homomorphism.

## A defensible cofree-comonad gloss

There is one further categorical reading that earns its place, provided it is stated as a gloss and not as event-sourcing doctrine.
It is the author's novel synthesis riding on citable substrates (the final coalgebra of the stream functor; the algebra/coalgebra split above), not existing doctrine, and it holds only for the linear stream functor.

Pin the event functor to the linear one-more-event form `F X = E × X`.
Then the *observation-annotated* stream — each prefix decorated with its folded state — carries the parametrized final coalgebra `Cofree F a = νX. a × F X`.
Its `extract` reads the current folded state (the fold up to now), and its `duplicate` yields the stream of all prefixes: the complete set of replayable snapshot and resume points.
This is what makes snapshot and replay structural rather than metaphorical.

The qualifications are mandatory.
Always name the annotation step rather than equating "the log" with "the cofree comonad": the bare uninterpreted log is most directly the carrier of the final coalgebra of the stream functor, and the cofree comonad is its observation-annotated enrichment.
The identification holds only for the linear stream functor — a branching event functor gives a tree of possible futures, not a single committed log.
This cofree identification is novel synthesis on citable substrates; do not present it as established event-sourcing doctrine.

## Views as quotients of the event monoid

The same homomorphism perspective explains materialized views.
Equivalent event sequences that produce the same view are identified by the projection: because `project` is a monoid homomorphism out of the free monoid of events, it factors through the quotient of that free monoid by the kernel congruence "produces the same view."

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

The quotient is the coequalizer of all equivalent event sequences, with `π` the projection to equivalence classes:

```
EventLog ──π──▶ EventLog/≡ ≅ View
```

This is the structural justification for log compaction (drop events that do not change the equivalence class), snapshot optimization (store view state instead of replaying), and parallel projection (events that commute can be processed concurrently — note this is again the *commutativity* requirement, separate from the homomorphism law).

```haskell
commute :: Event -> Event -> Bool
commute (Deposit a1) (Deposit a2) = True            -- deposits commute
commute (Deposit _) (Withdraw _) = False            -- these don't commute
commute (SetField f1 _) (SetField f2 _) = f1 /= f2  -- different fields commute
```

The abstraction/concretion pair of a Galois connection — the general adjunction underlying "abstract a concrete domain to a view and back" — is owned elsewhere; see the abstraction-as-adjunction reference for that pair.
Here the operative fact is narrower and concrete: the view is a quotient of the event monoid because the projection is a monoid homomorphism.

## Projections, functors, and consistency

Each projection is a structure-preserving map from the event stream to a read model.
Multiple projections from one source enable polyglot persistence: distinct read models, each its own homomorphism, all driven from the same committed log.
Eventual consistency is the temporary failure of agreement between a projection and its source — the projected view lags the stream — and converges once the fold catches up.
The homomorphism law is what makes that convergence well-defined: any prefix already folded agrees with any longer prefix on the events they share, so a lagging projection is always a *correct projection of a shorter stream*, never a wrong one.
