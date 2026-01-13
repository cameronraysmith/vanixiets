# Event architecture for hypermedia applications

Event sourcing provides a natural architectural foundation for server-driven hypermedia applications, where the server's event log serves as the single source of truth and SSE streams act as projection channels delivering targeted DOM updates to clients.
This document bridges the theoretical foundations of event sourcing (see `theoretical-foundations.md` section "Event sourcing as algebraic duality") with the practical patterns of SSE-based hypermedia systems.

The Tao of Datastar emphasizes that the server is the source of truth, and event sourcing makes this principle explicit: the event log is the canonical state, and all views—including the DOM—are derived projections.
SSE streams become functors mapping domain events to presentation updates (PatchElements and PatchSignals), maintaining causal consistency between server state and browser representation.
This functor structure arises from functional reactive programming foundations where signals (browser state) and events (server state) form a comonad-monad duality.
See `functional-reactive-programming.md` for the categorical framework explaining why this architecture is natural.

This approach extends the patterns in `01-architecture.md` and `02-sse-patterns.md` by grounding hypermedia interactions in an immutable event log rather than mutable database state.
While not every hypermedia application requires event sourcing, understanding the architectural alignment reveals design principles applicable even in traditional CRUD contexts.

## Event authority in hypermedia

### Events as source of truth

In event-sourced hypermedia architectures, the server maintains an append-only event log as the canonical representation of system state.
Current state is computed by folding over the event history, applying each event's transformation in sequence to derive the present view.

This contrasts with traditional approaches where current state lives in mutable database tables.
The event log becomes the system of record, and what would be "the database" in a CRUD application becomes a disposable read model—a projection that can be rebuilt from events at any time.

Events are immutable facts about what happened: `OrderPlaced`, `PaymentReceived`, `ItemShipped`.
They capture intent and causation rather than just final state, preserving the "why" alongside the "what".

The append-only property means events are never updated or deleted (except through explicit compensating events like `OrderCancelled`).
This immutability provides a complete audit trail and enables temporal queries—reconstructing state at any point in history.

See `distributed-systems.md` section "Position 1: Event log as authority" for the theoretical foundations of log-based architectures.
The event log is a totally ordered sequence within each aggregate, providing the consistency boundary necessary for distributed systems.

### State derivation vs state storage

Traditional hypermedia flow: server queries mutable database tables, constructs domain objects, renders HTML templates, returns response.
State exists as rows in tables, and rendering pulls from that stored state.

Event-sourced hypermedia flow: server projects events to construct transient view models, renders HTML from projections, returns response.
State exists only as the accumulated effect of events, recomputed on demand or maintained as a materialized view.

The trade-off is query latency for auditability and temporal reasoning.
Reading current state requires either folding all events (slow) or maintaining a read model projection (fast but requires infrastructure).
Most production systems use read models for serving requests while keeping events as the authoritative source.

SSE streams invert this dynamic: rather than client requesting state, server pushes state changes as they occur.
Projections run continuously, transforming events into PatchElements and PatchSignals, and the SSE channel delivers updates to connected clients.

This model eliminates polling and reduces latency—clients receive updates as soon as events occur, without requesting.
The event log drives SSE streams directly, making the browser's DOM a live projection of server events.

### When to use event sourcing with hypermedia

Choose event sourcing when you need:
- Complete audit trail of all state changes with attribution and causation
- Temporal queries or ability to reconstruct historical state
- Complex business process replay, undo, or what-if analysis
- Eventual consistency across aggregates with event-driven integration
- Domain events as integration contract between bounded contexts

Reconsider event sourcing when:
- Application is simple CRUD with no audit requirements beyond "last updated"
- Low query latency is critical and read models add unacceptable complexity
- Domain has minimal business logic and state transitions are trivial
- Team lacks experience with event sourcing patterns and learning curve is prohibitive

Hybrid approach for SSE-based hypermedia: use event log for writes and domain events, but build specialized read models optimized for SSE projection.
Events flow into read models via projection services, and SSE endpoints query read models for initial state then subscribe to updates.

This gives you auditability and temporal reasoning for writes while maintaining query performance for real-time updates.
The read model becomes a cache of the event log, disposable and rebuildable.

## SSE as projection channel

### Mathematical model

An SSE stream is a projection function mapping the event log to a stream of patch events:

```
project : EventLog -> Stream PatchEvent
```

The event log is a free monoid—a sequence of domain events with concatenation as the binary operation and the empty log as identity.
The output stream is also a monoid, where PatchEvents compose sequentially and morphing handles idempotence.

The projection function is a monoid homomorphism: it preserves the monoidal structure, meaning `project(e1 ++ e2) = project(e1) ++ project(e2)`.
This property ensures that projecting concatenated events produces the same result as concatenating projected events, which is essential for incremental updates and reconnection semantics.

In practice, projections are stateful functions maintaining read models:

```
project : (ReadModel, Event) -> (ReadModel, [PatchEvent])
```

Each event updates the read model and optionally emits patch events.
The read model is the fold of all events, and patch events are the differential updates sent over SSE.

This formulation makes clear that SSE streams are derived views, not independent state.
The event log is the source, and the stream is the continuous materialization of that source into DOM updates.

### PatchElements as materialized view updates

A `PatchElements` event represents a targeted update to the DOM, specifying a selector and an HTML fragment to merge.
In event-sourced architecture, these are the materialized view updates—projections of domain events into presentation layer changes.

Domain event → projection logic → HTML fragment → PatchElements event → SSE stream → browser morphing.

Example in Go:

```go
func projectOrderPlaced(event OrderPlaced) datastar.PatchElements {
    fragment := renderOrderConfirmation(event.OrderID, event.Items)
    return datastar.PatchElements{
        Selector: "#order-status",
        Fragment: fragment,
        MergeMode: datastar.MergeModeUpsertAttributes,
    }
}
```

The projection function `projectOrderPlaced` transforms a domain event into a presentation update.
The domain event captures business intent (an order was placed), while the PatchElements captures presentation intent (update this DOM region with this HTML).

Projection logic lives on the server, maintaining the principle that the server controls presentation.
Clients receive only the rendered HTML, never raw domain events (except in specialized admin interfaces).

For complex projections involving multiple domain events or state from read models, projection services query the read model and emit PatchElements based on the combined view:

```go
func projectInventoryUpdate(readModel *InventoryReadModel, event ItemRestocked) []datastar.PatchElements {
    item := readModel.GetItem(event.ItemID)
    if item.Quantity > 0 {
        return []datastar.PatchElements{
            {Selector: fmt.Sprintf("#item-%s .stock-status", event.ItemID), Fragment: "<span class='in-stock'>In Stock</span>"},
            {Selector: fmt.Sprintf("#item-%s .quantity", event.ItemID), Fragment: fmt.Sprintf("<span>%d available</span>", item.Quantity)},
        }
    }
    return nil
}
```

The read model provides the current state context, and the event triggers the projection.
Multiple PatchElements can be emitted from a single event, updating different parts of the DOM.

### PatchSignals as state projection

Signals represent cross-cutting state derived from events—data like authentication status, notification counts, or active feature flags that affect multiple components.

In event-sourced systems, signals are projections just like elements, but they project to data rather than HTML.

This pattern mirrors the Decider pattern across the client-server boundary: server-side `decide` functions produce domain events that are projected to SSE streams, while client-side state management applies `evolve` logic as events arrive.
The server maintains the authoritative event log and computes state via event folding, then projects that state into signals and elements for transmission.
Clients receive these projections and update their local DOM representation, effectively running a read-only version of the `evolve` function.

See `event-sourcing.md#the-decider-pattern` for the foundational pattern that governs this server-side command handling and event application.

```rust
fn project_signal(event: &DomainEvent) -> Option<SignalPatch> {
    match event {
        DomainEvent::UserLoggedIn { user_id, .. } => Some(SignalPatch {
            signal: "auth.userId".to_string(),
            value: json!(user_id),
        }),
        DomainEvent::NotificationReceived { .. } => Some(SignalPatch {
            signal: "notifications.unreadCount".to_string(),
            value: json!(increment_counter()),
        }),
        _ => None,
    }
}
```

Not every event produces a signal update—the projection function returns `Option<SignalPatch>`.
Events that don't affect cross-cutting state return `None`, while events like login or notification receipt emit signal changes.

Signal projections maintain reactive state in the browser's data model, and Datastar expressions react to signal changes automatically.
This creates a live binding between server events and client-side reactive expressions without custom JavaScript.

Signals enable declarative reactivity: templates contain expressions like `data-text="$notifications.unreadCount"`, and the browser updates automatically when the signal changes.
The server projects events to signals, and Datastar handles DOM updates.

### Projection pipeline architecture

Complete event flow from domain event to browser update:

```
[Event Store]
    |
    | subscribe
    v
[Projection Service]
    |
    | read model update
    v
[Read Model DB]
    |
    | query + subscribe
    v
[SSE Endpoint]
    |
    | HTTP stream
    v
[Browser / Datastar]
```

The projection service subscribes to the event store (or event bus/log) and maintains read models by applying events.
As events arrive, the projection service updates its read model and may emit patch events (PatchElements or PatchSignals).

SSE endpoints query the read model to send initial state on connection, then subscribe to projection updates.
When projection service emits patch events, SSE endpoint serializes them and sends over the HTTP stream.

The browser receives SSE events and passes them to Datastar, which morphs the DOM or updates signals accordingly.

This architecture decouples event storage from presentation, allowing read models to be optimized independently.
Projection services can be scaled horizontally, with each instance handling a subset of connections or aggregates.

The event store remains the single source of truth, and all downstream components are derived views that can be rebuilt if corrupted or if projection logic changes.

## Domain events vs transport events

### Distinguishing concerns

Domain events represent business-significant facts: `OrderPlaced`, `PaymentReceived`, `InventoryReserved`.
They are versioned, durable, and form the system's permanent record.
Domain events live in the event store and survive indefinitely (or according to retention policies).

Transport events represent presentation updates: `PatchElements`, `PatchSignals`, or custom SSE event types.
They are ephemeral, sent over SSE streams, and never persisted (except in debug logs).
Transport events are projections of domain events, not sources of truth.

The distinction is crucial: domain events are the "what happened" in business terms, while transport events are the "how to display it" in UI terms.

Mixing these layers couples business logic to presentation and makes event logs brittle—changing a CSS class would require event schema migration.

Keep domain events presentation-agnostic.
Project domain events to transport events in a separate layer (projection service or SSE handler).

### Event normalization strategies

Projecting domain events to transport events involves transformations:

**One-to-many**: A single domain event produces multiple PatchElements updating different DOM regions.

```go
func projectOrderPlaced(event OrderPlaced) []datastar.ServerSentEvent {
    return []datastar.ServerSentEvent{
        datastar.PatchElements{Selector: "#order-list", Fragment: renderOrderRow(event.OrderID)},
        datastar.PatchElements{Selector: "#order-count", Fragment: fmt.Sprintf("<span>%d</span>", getOrderCount())},
        datastar.PatchSignals{Signal: "orders.lastPlacedId", Value: event.OrderID},
    }
}
```

**Many-to-one**: Multiple domain events collapse into a single PatchElements when only the final state matters.

```go
func projectInventoryUpdates(events []InventoryEvent) datastar.PatchElements {
    finalState := applyEvents(events)
    return datastar.PatchElements{
        Selector: "#inventory-summary",
        Fragment: renderInventorySummary(finalState),
    }
}
```

**Filtering**: Not all domain events require UI updates.
Projection logic filters events, emitting transport events only when relevant.

```go
func projectUserActivity(event DomainEvent) []datastar.ServerSentEvent {
    if event.AffectsUI() {
        return []datastar.ServerSentEvent{...}
    }
    return nil
}
```

**Transformation**: Domain event data is reshaped for presentation, hiding internal IDs or aggregating fields.

```go
func projectOrderDetails(event OrderPlaced) datastar.PatchElements {
    displayOrder := OrderDisplay{
        ID: event.OrderID.ToPublicID(),
        Items: summarizeItems(event.Items),
        Total: formatCurrency(event.Total),
    }
    return datastar.PatchElements{
        Selector: "#order-details",
        Fragment: renderOrder(displayOrder),
    }
}
```

These transformations isolate domain logic from presentation logic, allowing each to evolve independently.

### When to expose domain events directly

Internal admin dashboards or diagnostic tools may expose raw domain events over SSE for real-time monitoring.

```go
func sseAdminEventStream(w http.ResponseWriter, r *http.Request) {
    stream := eventStore.Subscribe("admin-stream")
    defer stream.Close()

    for event := range stream.Events() {
        sse.Event{
            Type: "domain-event",
            Data: json.Marshal(event),
        }.WriteTo(w)
    }
}
```

This is acceptable because admin users understand the domain model and need full event details for debugging.

User-facing applications should never expose domain events directly—it leaks implementation details, creates coupling, and forces clients to understand internal schemas.

Instead, project domain events to user-appropriate representations (PatchElements with rendered HTML or PatchSignals with derived state).

## Temporal consistency

### Event ordering guarantees

Within a single aggregate, events are totally ordered—each event has a unique sequence number, and applying events in order reconstructs consistent state.

Across aggregates, events may be concurrent—there is no global ordering, only causal ordering (event A causally precedes event B if B references A).

SSE streams typically project events from a single aggregate or a consistent read model, so clients receive events in the same order they were applied.
This preserves causality: if event A caused event B, the SSE stream will deliver A before B.

For cross-aggregate projections, use causal consistency: include correlation IDs or causal timestamps to enable clients (or projection services) to detect ordering issues.

See `distributed-systems.md` section "Causal consistency" for the theoretical model.

### Causal consistency in reconnection

SSE supports reconnection via `Last-Event-ID` header: when a client reconnects, it sends the ID of the last event it received, and the server resumes from that point.

Event ID design is critical—it must be:
- Monotonically increasing (sequence number or timestamp-based)
- Sortable (enables resume from last-received)
- Unique (no duplicate IDs)

Example event ID format: `<aggregate-id>-<sequence-number>` or `<timestamp-millis>-<event-uuid>`.

```go
func sseResumeStream(w http.ResponseWriter, r *http.Request) {
    lastEventID := r.Header.Get("Last-Event-ID")
    stream := eventStore.SubscribeFrom(lastEventID)
    defer stream.Close()

    for event := range stream.Events() {
        sse.Event{
            ID: event.ID,
            Type: "patch",
            Data: projectEvent(event),
        }.WriteTo(w)
    }
}
```

If the gap between `Last-Event-ID` and current position is large (many events missed), consider sending a full state snapshot instead of replaying all events.

```go
if stream.GapSize() > 100 {
    snapshot := buildSnapshot()
    sse.Event{
        ID: snapshot.ID,
        Type: "full-state",
        Data: snapshot.Data,
    }.WriteTo(w)
    return
}
```

This avoids overwhelming clients with event replay and reduces bandwidth.

### Replay semantics

When events are replayed (during reconnection or subscription startup), they must be idempotent—applying the same event multiple times produces the same result as applying it once.

Datastar's morphing handles this at the DOM level: if the same HTML fragment is applied twice with the same ID, the second application is a no-op.

For signals, idempotence requires careful design—use absolute values rather than deltas:

```rust
// Idempotent (absolute value)
SignalPatch { signal: "counter.value", value: json!(42) }

// Not idempotent (delta)
SignalPatch { signal: "counter.value", value: json!("+1") }
```

If you must use deltas, include sequence numbers so clients can detect duplicates:

```rust
SignalPatch {
    signal: "counter.value",
    value: json!({"delta": 1, "seq": 123}),
}
```

Client logic checks sequence number and ignores events with `seq <= lastSeenSeq`.

### Eventual consistency model for UI

Browser DOM is eventually consistent with the server's event log.
There is a delay between event occurrence and DOM update (event projection time + network latency + morphing time).

Users perceive this delay as lag, so design UI to communicate ongoing updates:
- Loading indicators while events are being processed
- Optimistic UI hints (disabled buttons, spinners) during command submission
- Clear visual feedback when updates complete

Avoid giving false impression of immediate consistency—if a command might be rejected, show "submitting..." rather than immediately updating the UI.

SSE provides lower latency than polling, reducing the eventual consistency window, but it remains eventual.
For interactive applications, this is acceptable—users tolerate small delays if progress is visible.

## Integration patterns

### Command handling with event emission

Commands are requests to change state: `PlaceOrder`, `CancelOrder`, `UpdateInventory`.
Command handlers validate commands against current state, then emit domain events if validation succeeds.

```go
func (h *OrderHandler) PlaceOrder(cmd PlaceOrderCommand) error {
    // Load current state from event log
    order := h.eventStore.Rebuild(cmd.OrderID)

    // Validate command
    if err := order.CanPlaceOrder(cmd); err != nil {
        return err
    }

    // Emit domain event
    event := OrderPlaced{
        OrderID: cmd.OrderID,
        Items:   cmd.Items,
        Total:   calculateTotal(cmd.Items),
    }
    return h.eventStore.Append(event)
}
```

Commands are imperative (PlaceOrder), events are past tense (OrderPlaced).
Commands may fail validation, events are immutable facts.

In hypermedia context, commands often originate from form submissions (POST requests).
The handler validates, emits events, and returns an HTTP response (often a redirect or a PatchElements fragment).

```go
func (h *OrderHandler) HandlePlaceOrder(w http.ResponseWriter, r *http.Request) {
    cmd := parseCommand(r)
    if err := h.PlaceOrder(cmd); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Immediate response with confirmation
    fragment := renderOrderConfirmation(cmd.OrderID)
    datastar.PatchElements{
        Selector: "#order-status",
        Fragment: fragment,
    }.WriteTo(w)
}
```

The HTTP response provides immediate feedback, while the event triggers SSE updates to other connected clients.

### Projection service architecture

Projection service subscribes to event store (or event bus), maintains read models, and emits patch events for SSE endpoints.

```rust
struct ProjectionService {
    event_subscription: EventSubscription,
    read_model: Arc<RwLock<ReadModel>>,
    patch_broadcaster: PatchBroadcaster,
}

impl ProjectionService {
    async fn run(&self) {
        while let Some(event) = self.event_subscription.next().await {
            let patches = self.project_event(&event).await;

            // Update read model
            self.read_model.write().await.apply(&event);

            // Broadcast patches to SSE endpoints
            for patch in patches {
                self.patch_broadcaster.send(patch).await;
            }
        }
    }

    async fn project_event(&self, event: &DomainEvent) -> Vec<PatchEvent> {
        let read_model = self.read_model.read().await;
        match event {
            DomainEvent::OrderPlaced(e) => vec![
                PatchEvent::Element(project_order_placed(e, &read_model)),
            ],
            DomainEvent::PaymentReceived(e) => vec![
                PatchEvent::Signal(project_payment_status(e)),
            ],
            _ => vec![],
        }
    }
}
```

The projection service is stateful (maintains read model) but disposable (can be rebuilt from events).
If the read model becomes corrupted, stop the service, delete the read model, and replay events from the beginning.

Projection services can be scaled horizontally by partitioning events (e.g., by aggregate ID) and running multiple instances, each handling a subset.

### SSE endpoint integration

SSE endpoints query read model for initial state, then subscribe to patch broadcaster for updates.

```go
func sseOrderUpdates(w http.ResponseWriter, r *http.Request) {
    orderID := r.URL.Query().Get("orderId")

    // Set up SSE
    flusher, ok := w.(http.Flusher)
    if !ok {
        http.Error(w, "Streaming unsupported", http.StatusInternalServerError)
        return
    }
    w.Header().Set("Content-Type", "text/event-stream")
    w.Header().Set("Cache-Control", "no-cache")

    // Send initial state from read model
    initialState := readModel.GetOrder(orderID)
    sse.Event{
        Type: "patch",
        Data: renderOrderState(initialState),
    }.WriteTo(w)
    flusher.Flush()

    // Subscribe to updates
    patchChan := patchBroadcaster.Subscribe(orderID)
    defer patchBroadcaster.Unsubscribe(orderID, patchChan)

    for patch := range patchChan {
        sse.Event{
            Type: "patch",
            Data: patch,
        }.WriteTo(w)
        flusher.Flush()
    }
}
```

Initial state provides immediate context, and subscription provides live updates.
Clients receive both without additional requests.

### End-to-end pipeline example

Complete flow from command to DOM update with error handling and correlation ID propagation:

```go
// 1. Client submits command via form POST
func handleSubmitOrder(w http.ResponseWriter, r *http.Request) {
    correlationID := uuid.New().String()
    ctx := context.WithValue(r.Context(), "correlationID", correlationID)

    cmd := parseOrderCommand(r)
    if err := orderService.PlaceOrder(ctx, cmd); err != nil {
        log.Errorf("[%s] Command failed: %v", correlationID, err)
        http.Error(w, "Order placement failed", http.StatusBadRequest)
        return
    }

    log.Infof("[%s] Order placed: %s", correlationID, cmd.OrderID)
    datastar.PatchElements{
        Selector: "#order-status",
        Fragment: "<div>Order submitted successfully</div>",
    }.WriteTo(w)
}

// 2. Command handler emits event
func (s *OrderService) PlaceOrder(ctx context.Context, cmd PlaceOrderCommand) error {
    correlationID := ctx.Value("correlationID").(string)

    event := OrderPlaced{
        OrderID:       cmd.OrderID,
        CorrelationID: correlationID,
        Items:         cmd.Items,
        Total:         calculateTotal(cmd.Items),
    }
    return s.eventStore.Append(ctx, event)
}

// 3. Projection service processes event
func (p *ProjectionService) handleEvent(event DomainEvent) {
    log.Infof("[%s] Projecting event: %s", event.CorrelationID, event.Type)

    patches := p.projectEvent(event)
    for _, patch := range patches {
        p.patchBroadcaster.Send(patch)
    }
}

// 4. SSE endpoint broadcasts patch to connected clients
func sseStream(w http.ResponseWriter, r *http.Request) {
    patchChan := patchBroadcaster.Subscribe()
    defer patchBroadcaster.Unsubscribe(patchChan)

    for patch := range patchChan {
        sse.Event{Type: "patch", Data: patch}.WriteTo(w)
        w.(http.Flusher).Flush()
    }
}
```

Correlation ID flows through the entire pipeline, enabling distributed tracing and log correlation.
Errors at any stage are logged with correlation ID for debugging.

## Anti-patterns

### Client-side event storage

**What it looks like**: Client maintains its own event log in localStorage or IndexedDB, appending events received over SSE and replaying them to reconstruct state.

**Why problematic**: Violates the principle that the server is the source of truth.
Client-side event logs create dual sources of truth, leading to inconsistencies when client and server diverge (e.g., after user clears cache, or after server event log is corrected).

Event sourcing is a server-side pattern.
Clients receive projections (rendered HTML or signals), not raw events.

**What to do instead**: Server owns all events.
Clients receive SSE updates reflecting current projections and query server for initial state on load.
If client needs to reconstruct view, it requests a new SSE stream from the server.

### Optimistic updates with event sourcing

**What it looks like**: Client immediately updates DOM when user submits command, assuming it will succeed, then reverts if server rejects the command.

**Why problematic**: Commands may fail validation (business rules, invariants, conflicts).
Optimistic update creates flickering UI—element appears, then disappears when command fails.
With event sourcing, there is no "current state" to optimistically update against; state is the fold of events, and the fold hasn't happened until the server applies the event.

**What to do instead**: Show loading indicator during command processing.
Wait for server response (either HTTP response or SSE event) before updating DOM.
Use Datastar's `data-indicator` to display spinners or disable buttons during submission.

If low latency is critical, architect command handlers to fail fast (validate synchronously before emitting events), so HTTP response can return immediately with success/failure.

### Treating PatchElements as domain events

**What it looks like**: Storing HTML fragments in the event log, or using `PatchElements` data as input to business logic.

**Why problematic**: Couples domain model to presentation layer.
Changing CSS classes or HTML structure requires event schema migration.
HTML fragments are not business facts—they are derived views, not sources of truth.

Event logs should be presentation-agnostic, containing only domain events that describe business-significant state changes.

**What to do instead**: Store domain events only (OrderPlaced, PaymentReceived).
Project domain events to PatchElements in a separate layer (projection service or SSE handler).
HTML lives in templates and projection logic, not in the event store.

If you need to audit what users saw, store snapshots separately (not in the event log), or derive them from events + projection logic at the time.

## Related documents

**Theoretical foundations**:
- `theoretical-foundations.md` - section "Event sourcing as algebraic duality" for mathematical grounding of events as free monoids and projections as catamorphisms

**Distributed systems patterns**:
- `distributed-systems.md` - event log authority, causal consistency, ordering guarantees in distributed event-sourced systems

**Hypermedia context**:
- `01-architecture.md` - foundational hypermedia principles, server authority, SSE as state delivery mechanism
- `02-sse-patterns.md` - SSE streaming patterns, reconnection semantics, merge strategies for PatchElements
- `03-datastar.md` - Datastar-specific event types (PatchElements, PatchSignals), morphing, and reactivity model

**Application patterns**:
- `architectural-patterns.md` - CQRS, command/query separation, read models as projections
- `domain-modeling.md` - aggregate boundaries, invariants, command validation patterns
