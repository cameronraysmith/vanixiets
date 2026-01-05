# Event catalog tooling

## Purpose

Event catalog tooling formalizes the domain events, commands, and services discovered through collaborative modeling into structured, queryable documentation.
This document provides guidance on using EventCatalog and related tools to maintain a system of record for event-driven architectures grounded in algebraic functional domain modeling.

The key principle is that event catalogs document *algebraic structure*, not object-oriented artifacts.
Events are elements of a free monoid, commands are validated functions producing events, and services are module boundaries with explicit effect signatures.
Catalogs should reflect this structure rather than imposing entity-relationship or class-hierarchy thinking that obscures the underlying algebra.

EventCatalog specifically provides visualization, discovery, and governance for event-driven systems while remaining agnostic to implementation patterns.
When populated according to the guidelines here, catalogs reinforce the Decider pattern, pure functional aggregates, and explicit effect boundaries central to our approach.

## Relationship to other documents

This document extends the collaborative modeling and event sourcing workflows with concrete tooling guidance.

*collaborative-modeling.md* describes EventStorming, Domain Storytelling, and Example Mapping techniques that discover domain events before implementation.
Event catalogs capture the outputs of these sessions as formal documentation.

*event-sourcing.md* describes the persistence model where events form the system of record.
Event catalogs document the event schema and its algebraic properties (monoid structure, Decider pattern).

*discovery-process.md* provides the eight-step DDD workflow where event catalog population occurs during step 7 (specification phase) after discovery and strategic analysis.

*domain-modeling.md* describes how discovered events map to algebraic types.
Event catalogs provide external documentation of these types for cross-team discovery.

*bounded-context-design.md* describes context boundaries and integration patterns.
Event catalogs visualize which events cross context boundaries and their ownership.

## Algebraic foundations for event documentation

Event catalogs document algebraic structure that emerges from collaborative modeling.
Understanding this structure ensures documentation captures what matters and avoids object-oriented distortions.

Events form a free monoid under concatenation.
The catalog should document each event type as an element of this monoid, emphasizing that events compose sequentially and that order matters for state reconstruction.
Documentation should capture the event's role in the temporal sequence, not treat it as an isolated "message" or "notification".

Commands are functions that validate against current state and produce events.
The catalog should document commands as function signatures with preconditions (state requirements), postconditions (events emitted), and error cases (validation failures).
Avoid documenting commands as "requests" or "messages" without their functional semantics.

The Decider pattern structures command-event relationships.
Each aggregate (consistency boundary) has a Decider with `decide` (command → state → events) and `evolve` (state → event → state) functions.
Event catalogs should document these relationships explicitly, showing which Decider owns which events and how state evolution works.

Services are module boundaries with explicit effect signatures.
Following Debasish Ghosh's module algebra pattern, services expose signatures (abstract interfaces), algebras (lawful implementations), and interpreters (effect handlers).
Event catalogs document the service boundary, not internal implementation details.

## EventCatalog usage

EventCatalog is the primary tool for documenting event-driven architectures.
It generates static documentation sites from markdown files with structured frontmatter describing events, commands, services, and their relationships.

### Local repositories

Source code and tooling for EventCatalog development:

- `~/projects/lakescope-workspace/eventcatalog` - EventCatalog core source
- `~/projects/lakescope-workspace/create-eventcatalog` - Project scaffolding CLI
- `~/projects/lakescope-workspace/eventcatalog-mcp-server` - MCP server for AI-assisted catalog queries
- `~/projects/lakescope-workspace/eventstorm-to-catalog` - EventStorming artifact conversion

For documentation queries, use context7 MCP with `/websites/eventcatalog_dev` for the official documentation.
For source code exploration, search the local repositories above.

### Event documentation structure

Event markdown files should capture algebraic properties alongside descriptive content.

```markdown
---
id: order-placed
name: OrderPlaced
version: 1.0.0
summary: Order successfully validated and recorded
owners:
  - order-aggregate
producers:
  - order-service
consumers:
  - inventory-service
  - notification-service
schemaPath: schemas/order-placed.avsc
---

## Algebraic context

This event is produced by the Order Decider when a `PlaceOrder` command
passes validation. It forms part of the order aggregate's event monoid.

### Preconditions (decide validation)

- No existing order with same idempotency key
- All line items reference valid products
- Shipping address passes validation

### State evolution (evolve)

```haskell
evolve Nothing (OrderPlaced details) = Just (PendingOrder details)
evolve state _ = state  -- idempotent for replays
```

## Schema

The event carries the validated order details as an immutable record.
Schema evolution follows append-only field addition per `schema-versioning.md`.
```

### Command documentation structure

Commands should document their functional semantics, not just payload shape.

```markdown
---
id: place-order
name: PlaceOrder
version: 1.0.0
summary: Request to create a new order
owners:
  - order-service
producesEvents:
  - order-placed
  - order-validation-failed
---

## Functional signature

```haskell
placeOrder :: PlaceOrderCommand -> OrderState -> Either OrderError [OrderEvent]
```

## Validation rules

This command validates against current aggregate state per railway-oriented
composition. Validation failures produce `OrderValidationFailed` events
rather than exceptions.

- Idempotency: Resubmitting with same key returns existing order
- Inventory: Validates product availability before acceptance
- Address: Validates shipping address format and deliverability
```

### Service documentation structure

Services document module boundaries with explicit effect signatures.

```markdown
---
id: order-service
name: Order Service
summary: Manages order lifecycle from placement through fulfillment
owners:
  - fulfillment-team
repository:
  language: Rust
  url: https://github.com/org/order-service
receives:
  - place-order
  - cancel-order
sends:
  - order-placed
  - order-cancelled
---

## Module algebra

Following Ghosh's signature/algebra/interpreter pattern, this service exposes:

### Signature (abstract interface)

```haskell
class OrderAlgebra f where
  placeOrder :: PlaceOrderCommand -> f (Either OrderError Order)
  cancelOrder :: CancelOrderCommand -> f (Either OrderError ())
  getOrder :: OrderId -> f (Maybe Order)
```

### Effect boundary

External effects isolated at service boundary:
- Event store writes (append events)
- Read model queries (projection state)
- External service calls (inventory, payment)

Internal logic remains pure; effects are pushed to interpreters.
```

## Mapping EventStorming artifacts to catalog entries

EventStorming produces visual artifacts that translate systematically to catalog entries.
The translation preserves algebraic structure while adding the metadata and cross-references that enable discovery.

Orange sticky notes (events) become event entries.
Each distinct event identified during EventStorming gets a catalog entry documenting its schema, producers, consumers, and role in the temporal flow.
The catalog entry should reference which aggregate's Decider produces the event.

Blue sticky notes (commands) become command entries.
Commands document the full functional signature including preconditions (state requirements), the events produced on success, and error events produced on validation failure.
The railway-oriented composition of validation rules appears in the command documentation.

Yellow sticky notes (aggregates) inform service and Decider documentation.
Aggregates are consistency boundaries implemented as Deciders.
The catalog documents which events belong to which aggregate and how state evolves.

Purple sticky notes (policies) become documented relationships between events and commands.
Policies represent "whenever X, then Y" choreography.
The catalog documents these as event-to-command mappings with the policy logic described.

Pink sticky notes (hotspots) become documentation TODOs or notes.
Unresolved questions from EventStorming should appear as annotations in the catalog until clarified through subsequent sessions.

## Schema governance

Event schemas require governance because events are immutable once persisted.
The catalog documents schema versions and evolution strategies aligned with Hoffman's Law 2: "Events are immutable. Period."

### Versioning strategy

Event schemas evolve through additive changes only.
New fields can be added with defaults; existing fields cannot be removed or have their types changed.
The catalog documents each schema version and the migration path for consumers.

```markdown
## Version history

| Version | Changes | Migration notes |
|---------|---------|-----------------|
| 1.0.0 | Initial schema | - |
| 1.1.0 | Added `expedited` flag | Defaults to `false` for existing events |
| 1.2.0 | Added `giftMessage` field | Nullable, absent in pre-1.2 events |
```

### Breaking changes

When breaking changes are unavoidable, create a new event type rather than versioning the existing one.
The catalog documents both events and their relationship (supersedes/deprecated-by).

```markdown
---
id: order-placed-v2
name: OrderPlacedV2
deprecates: order-placed
summary: Order placed with enhanced address validation
---

This event supersedes `OrderPlaced` (v1) with breaking schema changes.
Both events may coexist during migration; consumers should handle both.
```

## Anti-patterns to avoid

Event catalogs can inadvertently impose object-oriented thinking that obscures algebraic structure.
Recognizing these anti-patterns prevents documentation from misleading implementers.

### Entity-centric organization

Organizing catalogs around "entities" (Order, Customer, Product) rather than bounded contexts and Deciders obscures consistency boundaries.
Events don't belong to entities; they belong to aggregates (Deciders) that enforce invariants.
Document events by their owning Decider, not by the "entity" they happen to reference.

### Request/response framing

Documenting commands as "requests" and events as "responses" suggests synchronous RPC semantics.
Commands are validated function calls; events are historical facts.
The temporal ordering and potential for multiple events per command gets lost in request/response framing.

### Class hierarchy documentation

Documenting event "inheritance" or "polymorphism" imports OOP concepts that don't apply.
Events are sum type variants, not class hierarchies.
Document the discriminated union structure explicitly rather than implying inheritance.

### Missing Decider context

Documenting events without their Decider context loses the algebraic relationship.
Every event should reference which Decider's `evolve` function handles it and how state changes.
Orphan events without Decider ownership suggest incomplete modeling.

### Implicit effects

Documenting services without explicit effect boundaries enables hidden side effects.
Service documentation should clearly state which effects occur at the boundary (event store, external calls) and which logic is pure.
Following Ghosh's interpreter pattern, effects belong in the service documentation, not scattered through event descriptions.

## Integration with development workflow

Event catalogs integrate with the development workflow at multiple points.

### Discovery phase

During collaborative modeling (EventStorming, Domain Storytelling), capture events and commands in rough form.
The catalog serves as the formal record of discoveries, replacing photographs of sticky notes with structured documentation.

### Specification phase

After strategic analysis determines investment levels, formalize event schemas in the catalog.
Core domain events get full algebraic documentation; supporting domain events may have lighter documentation.

### Implementation phase

Developers reference the catalog for event schemas and Decider structure.
The catalog serves as the contract between teams producing and consuming events.
Schema changes go through catalog review before implementation.

### Evolution phase

As the system evolves, the catalog tracks schema versions and deprecations.
The catalog provides the audit trail for schema governance decisions.

## Future considerations

This document may evolve into an `event-driven-development/` subdirectory if additional topics warrant expanded coverage.
Potential future documents include:

*Event Modeling* (Greg Young, Adam Dymitruk) as a complementary technique to EventStorming focusing on swimlane visualization and specification by example.
Event Modeling produces artifacts that translate directly to catalog entries with additional temporal structure.

*AsyncAPI* for machine-readable event schema documentation that complements human-readable EventCatalog entries.

*Schema Registry* integration for runtime schema validation and evolution in production systems.

For now, this single document covers EventCatalog usage within the algebraic functional domain modeling approach.
The subdirectory pattern from `rust-development/` and `hypermedia-development/` provides the template for expansion when warranted.
