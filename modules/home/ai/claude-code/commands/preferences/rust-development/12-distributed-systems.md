# Distributed systems in Rust

This section provides Rust-specific implementations for distributed systems patterns.
For theoretical foundations and decision frameworks, see `distributed-systems.md`.
For local concurrency patterns, see `./11-concurrency.md`.

## Aggregates in distributed context

Extend the local aggregate pattern (01-FDM Pattern 4) to distributed systems.

### Local vs distributed boundaries

An aggregate is a consistency boundary.
Within a single service, transactions across aggregates are technically possible but discouraged.
Across services, they're architecturally forbidden—use eventual consistency via events instead.

```rust
// Local aggregate - single-service transaction OK
pub struct OrderAggregate {
    order_id: OrderId,
    items: Vec<OrderItem>,
    total: Money,
    // Invariant: total == sum(items.price)
}

// Cross-service coordination - eventual consistency required
pub enum OrderPlaced {
    order_id: OrderId,
    customer_id: CustomerId,
    items: Vec<OrderItem>,
}

pub enum PaymentProcessed {
    payment_id: PaymentId,
    order_id: OrderId,
    amount: Money,
}
```

### Why "distributed transaction across aggregates" fails

Two-phase commit (2PC) across services creates distributed locks and tight coupling.
Compensating transactions (sagas) are more resilient but require careful design.

Prefer choreography (events) over orchestration (commands) when services have clear ownership.
Use orchestration (saga pattern) when you need visibility into multi-step workflows.

### Event sourcing authority model

When aggregate state must be reconstructed from events, the event log is the authority.
Projections are derived views, not the source of truth.

```rust
pub trait EventStore {
    async fn append_events(
        &self,
        stream_id: &StreamId,
        expected_version: Version,
        events: Vec<DomainEvent>,
    ) -> Result<Version, AppendError>;

    async fn read_events(
        &self,
        stream_id: &StreamId,
        from_version: Version,
    ) -> Result<Vec<DomainEvent>, ReadError>;
}

pub struct Aggregate<S> {
    state: S,
    version: Version,
    uncommitted_events: Vec<DomainEvent>,
}

impl<S> Aggregate<S>
where
    S: Default + Apply<DomainEvent>,
{
    pub fn reconstruct(events: Vec<DomainEvent>) -> Self {
        let state = events
            .iter()
            .fold(S::default(), |state, event| state.apply(event));
        let version = events.len();

        Self {
            state,
            version: Version(version),
            uncommitted_events: Vec::new(),
        }
    }
}
```

Reference `./01-functional-domain-modeling.md` for aggregate design within a single consistency boundary.

## Idempotency key pattern

Idempotency keys ensure duplicate requests produce identical results without side effects.
Critical for "at-least-once" delivery semantics in distributed systems.

### Type-safe idempotency keys

```rust
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct IdempotencyKey(String);

impl IdempotencyKey {
    pub fn new(value: impl Into<String>) -> Result<Self, ValidationError> {
        let value = value.into();
        if value.len() < 16 || value.len() > 64 {
            return Err(ValidationError::InvalidLength);
        }
        Ok(Self(value))
    }

    pub fn generate() -> Self {
        Self(Uuid::new_v4().to_string())
    }
}
```

### Storage trait abstraction

```rust
#[async_trait]
pub trait IdempotencyStore {
    async fn store_result(
        &self,
        key: &IdempotencyKey,
        result: &[u8],
        ttl: Duration,
    ) -> Result<(), StoreError>;

    async fn get_result(
        &self,
        key: &IdempotencyKey,
    ) -> Result<Option<Vec<u8>>, StoreError>;
}

// In-memory implementation for tests
pub struct InMemoryIdempotencyStore {
    store: Arc<RwLock<HashMap<IdempotencyKey, Vec<u8>>>>,
}

// Production implementation using Redis
pub struct RedisIdempotencyStore {
    client: redis::Client,
}
```

### Tower/axum middleware integration

```rust
use axum::{
    extract::State,
    http::{Request, StatusCode},
    middleware::Next,
    response::Response,
};

pub async fn idempotency_middleware<B>(
    State(store): State<Arc<dyn IdempotencyStore>>,
    req: Request<B>,
    next: Next<B>,
) -> Result<Response, StatusCode> {
    let idempotency_key = req
        .headers()
        .get("Idempotency-Key")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| IdempotencyKey::new(s).ok());

    let Some(key) = idempotency_key else {
        return Ok(next.run(req).await);
    };

    if let Some(cached_response) = store.get_result(&key).await.ok().flatten() {
        // Return cached response
        return deserialize_response(&cached_response);
    }

    let response = next.run(req).await;
    let serialized = serialize_response(&response);
    store.store_result(&key, &serialized, Duration::from_secs(86400)).await.ok();

    Ok(response)
}
```

Keep middleware focused on coordination—delegate business logic to handlers.

## Saga orchestration pattern

Sagas coordinate multi-step workflows with compensating transactions for rollback.
Use when you need centralized visibility into workflow state.

### State machine for saga coordinator

```rust
#[derive(Debug, Clone)]
pub enum SagaState {
    Created,
    ProcessingStep(StepId),
    Compensating(StepId),
    Completed,
    Failed,
}

pub struct SagaCoordinator<C> {
    saga_id: SagaId,
    state: SagaState,
    context: C,
    completed_steps: Vec<StepId>,
}

impl<C> SagaCoordinator<C> {
    pub fn transition(
        &mut self,
        event: SagaEvent,
    ) -> Result<Vec<SagaCommand>, SagaError> {
        match (&self.state, event) {
            (SagaState::Created, SagaEvent::Started) => {
                self.state = SagaState::ProcessingStep(StepId(0));
                Ok(vec![SagaCommand::ExecuteStep(StepId(0))])
            }
            (SagaState::ProcessingStep(step), SagaEvent::StepCompleted(completed_step))
                if step == &completed_step =>
            {
                self.completed_steps.push(completed_step);
                let next_step = StepId(completed_step.0 + 1);
                if self.has_more_steps(next_step) {
                    self.state = SagaState::ProcessingStep(next_step);
                    Ok(vec![SagaCommand::ExecuteStep(next_step)])
                } else {
                    self.state = SagaState::Completed;
                    Ok(vec![])
                }
            }
            (SagaState::ProcessingStep(_), SagaEvent::StepFailed(failed_step)) => {
                self.state = SagaState::Compensating(failed_step);
                let compensation_commands = self
                    .completed_steps
                    .iter()
                    .rev()
                    .map(|step| SagaCommand::CompensateStep(*step))
                    .collect();
                Ok(compensation_commands)
            }
            _ => Err(SagaError::InvalidTransition),
        }
    }
}
```

### Command and compensation types

```rust
pub enum SagaCommand {
    ExecuteStep(StepId),
    CompensateStep(StepId),
}

pub trait SagaStep {
    type Context;
    type Output;
    type CompensationData;

    async fn execute(
        &self,
        context: &Self::Context,
    ) -> Result<(Self::Output, Self::CompensationData), StepError>;

    async fn compensate(
        &self,
        context: &Self::Context,
        data: Self::CompensationData,
    ) -> Result<(), CompensationError>;
}
```

### Error handling: compensate vs retry

```rust
pub enum StepError {
    Transient(String),      // Retry
    Permanent(String),      // Compensate
    ValidationError(String), // Fail fast, no compensation needed
}

impl StepError {
    pub fn should_retry(&self) -> bool {
        matches!(self, StepError::Transient(_))
    }

    pub fn requires_compensation(&self) -> bool {
        matches!(self, StepError::Permanent(_))
    }
}
```

Transient errors (network timeout, temporary unavailability) warrant retry with exponential backoff.
Permanent errors (business rule violation, insufficient funds) require immediate compensation.
Validation errors indicate programmer error—fail fast without compensation.

### Integration with tokio channels

```rust
pub struct SagaExecutor {
    command_tx: mpsc::Sender<SagaCommand>,
    event_tx: mpsc::Sender<SagaEvent>,
}

impl SagaExecutor {
    pub async fn run(
        mut command_rx: mpsc::Receiver<SagaCommand>,
        event_tx: mpsc::Sender<SagaEvent>,
    ) {
        while let Some(command) = command_rx.recv().await {
            match command {
                SagaCommand::ExecuteStep(step_id) => {
                    let result = execute_step(step_id).await;
                    let event = match result {
                        Ok(_) => SagaEvent::StepCompleted(step_id),
                        Err(_) => SagaEvent::StepFailed(step_id),
                    };
                    event_tx.send(event).await.ok();
                }
                SagaCommand::CompensateStep(step_id) => {
                    compensate_step(step_id).await.ok();
                }
            }
        }
    }
}
```

Keep saga coordinator focused on workflow state—delegate actual work to step implementations.

## Transactional outbox pattern

The outbox pattern ensures atomic writes to database and message queue.
Write events to an outbox table in the same transaction as domain state changes, then publish asynchronously.

### Outbox table schema

```sql
CREATE TABLE outbox (
    id UUID PRIMARY KEY,
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

CREATE INDEX idx_outbox_unprocessed ON outbox (created_at)
WHERE processed_at IS NULL;
```

### Within-transaction event capture

```rust
pub async fn process_order(
    tx: &mut Transaction<'_, Postgres>,
    order: Order,
) -> Result<OrderId, ProcessError> {
    // 1. Persist domain state
    sqlx::query!(
        "INSERT INTO orders (id, customer_id, total) VALUES ($1, $2, $3)",
        order.id.as_uuid(),
        order.customer_id.as_uuid(),
        order.total.amount(),
    )
    .execute(&mut **tx)
    .await?;

    // 2. Write event to outbox in same transaction
    let event = OrderPlaced {
        order_id: order.id,
        customer_id: order.customer_id,
        items: order.items.clone(),
    };

    sqlx::query!(
        "INSERT INTO outbox (id, aggregate_id, event_type, payload)
         VALUES ($1, $2, $3, $4)",
        Uuid::new_v4(),
        order.id.as_uuid(),
        "OrderPlaced",
        serde_json::to_value(&event)?,
    )
    .execute(&mut **tx)
    .await?;

    Ok(order.id)
}
```

If the transaction fails, neither domain state nor event is written.
If it succeeds, both are written atomically.

### Outbox processor using tokio interval

```rust
pub struct OutboxProcessor {
    db_pool: PgPool,
    message_bus: Arc<dyn MessageBus>,
    interval: Duration,
}

impl OutboxProcessor {
    pub async fn run(self) {
        let mut interval = tokio::time::interval(self.interval);

        loop {
            interval.tick().await;

            if let Err(e) = self.process_batch().await {
                tracing::error!("Outbox processing failed: {}", e);
            }
        }
    }

    async fn process_batch(&self) -> Result<(), ProcessError> {
        let mut tx = self.db_pool.begin().await?;

        let events = sqlx::query!(
            "SELECT id, event_type, payload FROM outbox
             WHERE processed_at IS NULL
             ORDER BY created_at
             LIMIT 100
             FOR UPDATE SKIP LOCKED"
        )
        .fetch_all(&mut *tx)
        .await?;

        for event in events {
            self.message_bus
                .publish(&event.event_type, &event.payload)
                .await?;

            sqlx::query!(
                "UPDATE outbox SET processed_at = NOW() WHERE id = $1",
                event.id
            )
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }
}
```

`FOR UPDATE SKIP LOCKED` enables multiple processor instances without contention.

### At-least-once delivery semantics

Outbox processor provides at-least-once delivery: events may be published multiple times if processor crashes between publish and marking processed.
Message consumers must be idempotent (see Idempotency Key Pattern above).

Exactly-once is theoretically impossible in distributed systems.
At-least-once with idempotent consumers is the practical solution.

## Event sourcing integration

Event sourcing stores all state changes as an immutable event log.
Current state is derived by replaying events from the beginning.

For comprehensive event sourcing patterns, Hoffman's laws, and theoretical foundations, see `event-sourcing.md`.
This section provides Rust-specific implementation guidance.

### When to use event sourcing in Rust

Consider event sourcing when:
- Audit trail is a hard requirement (financial, medical, legal domains)
- Time-travel queries are valuable (debug past states, analytical projections)
- Event-driven architecture already exists

Avoid event sourcing when:
- Simple CRUD suffices (most applications)
- Schema evolution is uncertain (event versioning is hard)
- Team lacks distributed systems expertise

Cross-reference `./11-concurrency.md` actor patterns for stateful event processing.

### Event store trait abstraction

```rust
#[async_trait]
pub trait EventStore {
    async fn append_events(
        &self,
        stream_id: &StreamId,
        expected_version: Version,
        events: Vec<DomainEvent>,
    ) -> Result<Version, AppendError>;

    async fn read_events(
        &self,
        stream_id: &StreamId,
        from_version: Version,
    ) -> Result<Vec<DomainEvent>, ReadError>;

    async fn subscribe(
        &self,
        subscription_id: &str,
        handler: Box<dyn EventHandler>,
    ) -> Result<(), SubscribeError>;
}

#[derive(Debug, Clone, Copy)]
pub struct Version(usize);

pub enum AppendError {
    ConcurrencyConflict { expected: Version, actual: Version },
    StreamNotFound,
    SerializationError(String),
}
```

Optimistic concurrency via `expected_version` prevents lost updates.
If append fails due to version mismatch, read latest events and retry command.

### Projection patterns

Projections are derived views of event streams, optimized for reads.

```rust
#[async_trait]
pub trait Projection {
    type Event;
    type State;

    async fn apply(
        &self,
        state: Self::State,
        event: &Self::Event,
    ) -> Result<Self::State, ProjectionError>;

    async fn load_state(&self, stream_id: &StreamId) -> Result<Self::State, LoadError>;

    async fn save_state(
        &self,
        stream_id: &StreamId,
        state: &Self::State,
    ) -> Result<(), SaveError>;
}

pub struct ProjectionRunner<P: Projection> {
    projection: P,
    event_store: Arc<dyn EventStore>,
}

impl<P: Projection> ProjectionRunner<P> {
    pub async fn rebuild(&self, stream_id: &StreamId) -> Result<(), RebuildError> {
        let events = self.event_store.read_events(stream_id, Version(0)).await?;

        let state = events
            .iter()
            .try_fold(P::State::default(), |state, event| {
                self.projection.apply(state, event)
            })
            .await?;

        self.projection.save_state(stream_id, &state).await?;
        Ok(())
    }
}
```

Projections can be rebuilt from scratch if corrupted or schema changes.
Keep projection logic pure—no side effects, just state transformations.

### Golem's hybrid approach

Golem uses event sourcing for durable execution (workflow coordination) but not for all application state.
Workers maintain in-memory state between invocations via snapshots + event replay.

This hybrid model is often more practical than full event sourcing:
- Event-source the coordination layer (workflows, sagas)
- Use traditional persistence for domain aggregates
- Reference `./11-concurrency.md` for worker/actor patterns

## Crate ecosystem

Brief overview of relevant crates for distributed systems in Rust.

### Async runtime and RPC

- **tokio**: async runtime, TCP/UDP, timers, channels
- **tonic**: gRPC client and server with generated Rust types from protobuf
- **tarpc**: alternative RPC framework with less boilerplate than gRPC

### Message brokers

- **rdkafka**: Kafka client (high-throughput event streaming)
- **lapin**: RabbitMQ/AMQP client (traditional message queue)
- **redis**: Redis client (pub/sub, streams, distributed locks)

### Database and persistence

- **sqlx**: async SQL with compile-time checked queries (transactional outbox)
- **sea-orm**: async ORM (less boilerplate than sqlx for CRUD)
- **redb**: embedded database (LSM tree, faster than SQLite for some workloads)

### Event sourcing

Rust event sourcing ecosystem is immature compared to JVM (Akka, Axon).
Most production systems build custom event stores on top of Postgres or Kafka.

**Pattern references for study** (not recommended as dependencies):

- **cqrs-es**: lightweight framework with Aggregate trait, command/event separation, optimistic concurrency.
  Good reference for understanding the trait-based approach to aggregates.
  Supported persistence: PostgreSQL, MySQL, DynamoDB.

- **esrs** (event_sourcing.rs): pure sync aggregates without async runtime dependency.
  Demonstrates upcaster patterns for event schema migration.
  Useful for understanding how to version events in Rust's type system.

- **sqlite-es**: SQLite-backed event store with simple schema.
  Good reference for the minimal event store table structure.

- **kameo_es**: actor-based event sourcing using kameo actors.
  Demonstrates integration between actor supervision and event persistence.
  Alpha quality but illustrates actor + ES composition.

**Choosing framework vs custom implementation**:

Prefer custom implementation when:
- You need full control over event serialization and versioning
- Your aggregate patterns don't fit the framework's Aggregate trait
- You're using an event store not supported by existing crates
- You need to integrate with existing persistence infrastructure

Consider framework adoption when:
- You're starting a greenfield project with standard patterns
- Your team is new to event sourcing and needs structural guidance
- The framework's supported persistence matches your infrastructure
- You're building a prototype to validate ES for your domain

**Minimal event store schema** (PostgreSQL example):

```sql
CREATE TABLE events (
    id UUID PRIMARY KEY,
    stream_id UUID NOT NULL,
    version BIGINT NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSONB NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (stream_id, version)
);

CREATE INDEX idx_events_stream ON events (stream_id, version);
```

The `(stream_id, version)` unique constraint enforces optimistic concurrency.
Append with `INSERT ... WHERE NOT EXISTS (SELECT 1 FROM events WHERE stream_id = $1 AND version >= $2)`.

Cross-reference `event-sourcing.md` for event schema evolution patterns (upcasting, versioning).

## Testing distributed patterns

Distributed systems are hard to test because real networks are unreliable and timing is nondeterministic.

### Deterministic simulation approach

Use sans-IO pattern (see `./05-testing.md`) to separate protocol logic from I/O.
Drive protocol with synthetic events in controlled order.

```rust
pub struct SagaCoordinator<C> {
    // No tokio channels, no async
    saga_id: SagaId,
    state: SagaState,
    context: C,
}

impl<C> SagaCoordinator<C> {
    // Pure state transition function
    pub fn handle_event(&mut self, event: SagaEvent) -> Vec<SagaCommand> {
        // Deterministic logic
    }
}

#[test]
fn saga_compensates_on_step_failure() {
    let mut saga = SagaCoordinator::new(saga_id, context);

    saga.handle_event(SagaEvent::Started);
    saga.handle_event(SagaEvent::StepCompleted(StepId(0)));

    let commands = saga.handle_event(SagaEvent::StepFailed(StepId(1)));

    assert_eq!(commands, vec![
        SagaCommand::CompensateStep(StepId(0)),
    ]);
}
```

No flaky timeouts, no race conditions, no network dependencies.

### Property testing for distributed invariants

Use `proptest` or `quickcheck` to verify invariants hold across arbitrary event sequences.

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn saga_never_leaves_partial_state(events: Vec<SagaEvent>) {
        let mut saga = SagaCoordinator::new(saga_id, context);

        for event in events {
            saga.handle_event(event);
        }

        // Invariant: saga is either Completed or Failed, never stuck in ProcessingStep
        assert!(
            matches!(saga.state, SagaState::Completed | SagaState::Failed)
        );
    }
}
```

Property tests find edge cases that manual tests miss.

### Failure injection patterns

For integration tests with real I/O, inject failures to verify resilience.

```rust
pub struct FlakyMessageBus {
    inner: Arc<dyn MessageBus>,
    failure_rate: f64,
}

#[async_trait]
impl MessageBus for FlakyMessageBus {
    async fn publish(&self, topic: &str, payload: &[u8]) -> Result<(), PublishError> {
        if rand::random::<f64>() < self.failure_rate {
            return Err(PublishError::NetworkTimeout);
        }
        self.inner.publish(topic, payload).await
    }
}
```

Test that retry logic, circuit breakers, and compensations work under realistic failure scenarios.

### Integration test strategies

Integration tests for distributed systems should:
- Use testcontainers for databases, message brokers, etc. (ephemeral, isolated)
- Run against local network only (CI environments are flaky enough)
- Use liberal timeouts (10s+) to avoid race conditions
- Clean up state between tests (truncate tables, delete topics)

```rust
#[tokio::test]
async fn outbox_processor_publishes_events() {
    let container = testcontainers::clients::Cli::default()
        .run(Postgres::default());

    let db_url = format!("postgres://postgres@localhost:{}", container.get_host_port(5432));
    let pool = PgPool::connect(&db_url).await.unwrap();

    // Run schema migrations
    sqlx::migrate!().run(&pool).await.unwrap();

    // Test outbox processor
    let processor = OutboxProcessor::new(pool.clone(), mock_bus);

    // Insert event into outbox
    insert_test_event(&pool).await;

    // Run one batch
    processor.process_batch().await.unwrap();

    // Assert event was published
    assert_eq!(mock_bus.published_events().len(), 1);
}
```

Keep integration tests focused on critical paths—unit tests cover edge cases.

## See also

- `event-sourcing.md` (comprehensive event sourcing patterns, Hoffman's laws, CQRS)
- `distributed-systems.md` (universal decision framework and theory)
- `./11-concurrency.md` (local concurrency patterns, actors, workers)
- `./01-functional-domain-modeling.md` (aggregates, state machines, domain events)
- `./04-api-design.md` (command/event patterns, API versioning)
- `./05-testing.md` (sans-IO testing, property testing, integration tests)
- `./02-error-handling.md` (Result types, error design for distributed contexts)
