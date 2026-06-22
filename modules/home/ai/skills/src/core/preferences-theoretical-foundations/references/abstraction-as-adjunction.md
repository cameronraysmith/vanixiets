# Abstraction as adjunction

This file is on the foundations spine.
It develops one claim: when a best abstraction exists, abstraction is an adjunction, and the generalization of that fact to a free-forgetful adjunction is the design framing the rest of the skill routes through.

The order-theoretic case is a theorem.
The free-forgetful generalization for a domain-specific language is a design framing, not a theorem.
The slogan "factor every concern through an adjunction" is a labelled routing heuristic.
Keeping those three altitudes distinct is the whole discipline of this file.

## The order-theoretic case: a Galois connection is an adjunction

A monotone Galois connection between two posets is *exactly* an adjunction between them viewed as thin (2-enriched) categories.
Concretely, a pair of monotone maps `α` (abstraction) and `γ` (concretion) forms a Galois connection precisely when

```
α(x) ⊑ y   ⟺   x ⊑ γ(y)
```

holds for all `x`, `y`.
A poset is a category with at most one morphism between any two objects, so the biconditional above is the thin-category instance of the hom-set isomorphism `Hom(α x, y) ≅ Hom(x, γ y)` that defines `α ⊣ γ`.
In this degenerate setting the hom-sets are truth values, so the natural isomorphism collapses to a biconditional and there is no proof-relevant content to track.

Under this reading "abstraction = Galois connection `α ⊣ γ`" is a correct *definition* for order-theoretic abstraction.
Cousot–Cousot abstract interpretation (1977) is the canonical citable instance: a concrete semantics is abstracted to a more tractable domain, and soundness of the analysis follows from the connection itself rather than from a separate correctness argument.

The defining laws of the adjunction are the falsification handle.
The left adjoint `α` preserves joins (least upper bounds); the right adjoint `γ` preserves meets (greatest lower bounds).
The round trips are idempotent: `γ ∘ α` is a closure (inflationary, monotone, idempotent on the concrete side) and `α ∘ γ` is a kernel on the abstract side, which is why the triangle identities specialize to

```
α ∘ γ ∘ α = α
γ ∘ α ∘ γ = γ
```

To test whether a candidate abstraction *is* the adjoint, exhibit the specific defining law for that concern and check it, rather than asserting the adjunction abstractly.
If the would-be left adjoint fails to preserve the relevant joins, there is no Galois connection and no best abstraction.

## Mandatory qualification: not every abstraction is a full connection

The honest form of the claim is conditional: *when* a best abstraction exists, it is the left adjoint of a Galois connection.
This is a sufficiency statement, not a necessity statement.

Not every useful abstraction is a full Galois connection.
Cousot–Cousot's own later concretization-only (`γ`-only) and partial-connection frameworks handle domains where no best `α` exists, precisely because the joins that a left adjoint would have to preserve are not preserved in those domains.
Writing "abstraction requires a Galois connection" overstates the result and would misattribute the necessity direction to Cousot–Cousot, who developed the `γ`-only machinery to cover exactly the cases where it fails.
Cousot–Cousot grounds the order-theoretic instance, not the general slogan.

## Re-homing the CQRS materialized-view instance

Read models and materialized views in CQRS and event-sourcing architectures realize this order-theoretic case directly.
The event log and the derived view sit in two posets, and projection is the abstraction map.

Projecting event logs to queryable views is the abstraction-concretion pair.

```haskell
-- Abstraction: project events to view (loses information)
project :: EventLog -> ReadModel

-- Concretion: what events could produce this view (gains uncertainty)
reconstruct :: ReadModel -> Set EventLog
```

The two posets and the Galois condition are:

```haskell
abstract :: EventLog -> ReadModel
concrete :: ReadModel -> EventLog

-- Poset structures:
-- EventLog ordered by prefix: e1 ⊑_E e2 iff e1 is prefix of e2
-- ReadModel ordered by refinement: m1 ⊑_M m2 iff m1 refines/extends m2

-- Galois condition: for all e, m
abstract(e) ⊑_M m  ⟺  e ⊑_E concrete(m)
```

Here `abstract` (the projection) is the left adjoint and `concrete` (the reconstruction) is the right adjoint.
The abstraction-concretion pair preserves and reflects the ordering structure between event sequences and their derived views.
For event sourcing, `abstract` collapses event sequences into aggregated views and `concrete` maps views back to the minimal event sequences that produce them.

The adjunction laws appear as the round-trip idempotents:

```haskell
-- Projection is surjective onto its image
abstract . concrete . abstract = abstract

-- Reconstruction is injective on views
concrete . abstract . concrete = concrete
```

Multiple event sequences can produce the same view, so `abstract` is many-to-one.
Views can be rebuilt from events, but events cannot be recovered from views.
This is why event logs are the source of truth: views are derived, disposable, and rebuildable.

A caveat carries over from the projection-as-monoid-homomorphism result.
The per-event projection is a monoid homomorphism only over an exact aggregation monoid; IEEE-754 float addition is not associative, so a float-aggregating view is not a true homomorphism and resharded rollups can disagree.
The strict-homomorphism statement and its exact-monoid precondition live with the observability claim; see preferences-event-sourcing for the read-model-as-projection treatment and the algebraic-laws sibling below for the property test that exercises it.

## Query caching as memoization

Caching query results is memoization of a query function, and cache invalidation is naturality of that function under updates.

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

A cached result is valid exactly when the naturality square commutes:

```
Model_old ───query(p)───▶ Result_old
    │                          │
 update                     same?
    │                          │
    v                          v
Model_new ───query(p)───▶ Result_new
```

If `update` changes data relevant to query `p`, the cache entry is invalid.
This is why cache invalidation is hard: determining the affected queries requires understanding which naturality squares fail to commute.

Practical invalidation strategies trade precision against cost:

```haskell
-- Time-based invalidation (eventual consistency)
cachedWithTTL :: Duration -> Cache -> Query -> Result

-- Event-based invalidation (strong consistency)
invalidateOn :: [EventType] -> Cache -> Query -> Result

-- Dependency tracking (precise invalidation)
cachedWithDeps :: DependencyGraph -> Cache -> Query -> Result
```

## Crossing the altitude boundary: free-forgetful adjunctions

The move from a posetal Galois connection to a proper free-forgetful adjunction `F ⊣ U` is a generalization across an altitude boundary, not an identity.
A Galois connection is the degenerate, proof-irrelevant special case: hom-sets are truth values, so the natural isomorphism is a mere biconditional.
A free-forgetful adjunction `F ⊣ U` for a language lives in genuine categories with non-trivial morphisms, where the defining datum is a hom-set natural isomorphism rather than a biconditional.

"A domain-specific language is the free-forgetful adjunction `F ⊣ U`" is a *design framing*, not a theorem.
It is grounded in Lawvere's functorial semantics, under which the syntax of an algebraic theory is the initial (free) object and the model functor is the forgetful one, so a model is recovered as the left adjoint applied to a generating signature.
The framing is a construal of what a language *is*, and it is honest only as such: languages with equations, variable binding, or effects need monads, PROPs, sketches, or essentially-algebraic theories beyond a plain `F ⊣ U`.
Do not cite Lawvere for the slogan, for an arbitrary-DSL identity, or for any limit-point decoding; functorial semantics grounds the initial/free reading, not the unqualified equation.

The order-theoretic case is the meet of these two: a Galois connection is the free-forgetful adjunction collapsed to proof-irrelevant, boolean-enriched categories.
That is why the same defining-law falsification handle applies at both altitudes: exhibit the join the left adjoint must preserve, or the meet the right adjoint must preserve, and check it.

## The routing heuristic, explicitly labelled

"Factor every concern through an adjunction" is a routing heuristic, not a mathematical claim.
It is not supported by either Cousot–Cousot or Lawvere, and it is not a theorem about software architecture.
It earns its place by directing attention: when a concern resists clean factoring, ask whether a left adjoint (a free construction generating the concern from a smaller signature) and a right adjoint (a forgetful map back) can be named, and whether the would-be adjoint preserves the joins or meets it must.
The payoff is the falsification handle, not a guarantee.
When the adjoint laws fail, the concern is telling you it has no best abstraction, and the conditional form of the order-theoretic claim above is the warning that this is allowed to happen.

## Where the adjacent material lives

The strict monoid-homomorphism statement for projections, its exact-monoid precondition, and the property test `project(xs ++ ys) == project(xs) <> project(ys)` belong to the laws and event-sourcing siblings; see preferences-algebraic-laws for functor, monad, and monoid laws and property-based testing, and preferences-event-sourcing for operational projection patterns.
The conjectural unifying calculus this adjunction framing feeds into, including the initiality (not limit-point) universal property of a syntax presenting a doctrine, is developed in the internal-language material of this skill, not here.
For the conceptual altitude that frames why a single typed calculus is the asymptote we approach rather than a built artifact, see the skill's own thesis material; this file supplies only the adjunction altitude beneath it.
