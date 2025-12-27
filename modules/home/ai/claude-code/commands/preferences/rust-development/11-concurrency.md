# Concurrency

This section establishes a capability-secure mental model for concurrent Rust programming.
The goal is not merely to avoid data races, but to reason about concurrency in terms of what capabilities you *deny* to the rest of the system, aligning Rust's ownership model with the theoretical foundations of capability-secure concurrency.

For pattern descriptions, see domain-modeling.md.
For theoretical foundations, see theoretical-foundations.md.

## Emergent typestate from Rust's primitives

Rust's typestate capability is not a pattern added on top of the language—it emerges naturally from three core primitives working together:

1. **Affine types**: Values can be used *at most once* (move semantics)
2. **Nominal types**: Types are distinct by name, not structure
3. **Phantom type parameters**: Zero-cost state tracking via `PhantomData<S>`

The original Rust language had an explicit typestate system, but it was removed because these primitives made it redundant.
As Graydon Hoare noted in [a retrospective on Rust's design](https://graydon2.dreamwidth.org/307291.html): "There was a typestate system that turns out to be redundant once you have affine types, nominal types and phantom type parameters."

```rust
use std::marker::PhantomData;

// State markers (nominal - distinct by name alone)
struct Disconnected;
struct Connected;
struct Authenticated;

// State carried at zero runtime cost
struct Connection<S> {
    inner: TcpStream,
    _state: PhantomData<S>,
}

// Affine consumption: `self` moved, old state ceases to exist
impl Connection<Disconnected> {
    fn connect(self, addr: &str) -> io::Result<Connection<Connected>> {
        // self consumed - cannot use Disconnected connection after this
        Ok(Connection {
            inner: TcpStream::connect(addr)?,
            _state: PhantomData,
        })
    }
}

impl Connection<Connected> {
    fn authenticate(self, token: &str) -> Result<Connection<Authenticated>, AuthError> {
        // self consumed - cannot skip authentication
        validate_token(token)?;
        Ok(Connection {
            inner: self.inner,
            _state: PhantomData,
        })
    }
}

impl Connection<Authenticated> {
    fn send(&mut self, data: &[u8]) -> io::Result<()> {
        // Only authenticated connections can send
        self.inner.write_all(data)
    }
}
```

The `self` consumption in state transitions is the key insight.
It implements the Curry-Howard correspondence for protocols: a proof of `Connected` is *consumed* to produce a proof of `Authenticated`.
You cannot reuse the old proof—this is linear logic in action.

**Compositionality limits**: Nominal types can limit polymorphism over states.
For complex state machines with many states or composed protocols, consider whether the type-level encoding remains tractable.
Sometimes runtime state (enum) is more practical than compile-time state (phantom types).
See Pattern 2a in ./01-functional-domain-modeling.md for guidance on when to use each approach.

## The deny capabilities mental model

Invert the typical mental model.
Instead of asking "what can I do with this reference?", ask:

> "What am I *denying* to the rest of the system by holding this?"

This framing aligns with [Pony's deny capabilities](https://www.ponylang.io/media/papers/fast-cheap.pdf), which achieves data-race freedom by construction through a capability lattice.

| Rust Construct | What You Deny to Others |
|----------------|------------------------|
| `T` (owned) | Everything—existence itself |
| `&mut T` | All access (read and write) |
| `&T` | Mutation only |
| `Arc<T>` | Nothing (capability leak) |

The moment you reach for `Arc<Mutex<T>>`, you have exited the capability-secure world.
This should trigger architectural reconsideration—not because `Arc<Mutex<T>>` is wrong, but because it represents a choice to abandon compile-time race freedom for runtime synchronization.

### Capability lattice mapping

Pony achieves data-race freedom through a six-capability lattice.
Map this mental model to Rust:

| Pony | Rust Analogue | Semantics |
|------|---------------|-----------|
| `iso` | `T` + `Send` | Unique, transferable across threads |
| `val` | `Arc<T>` where `T` has no interior mutability | Deeply immutable, shareable |
| `ref` | `&mut T` | Exclusive, not sendable |
| `box` | `&T` | Read-only view |
| `tag` | `*const ()` / identity only | Can alias, cannot read |
| `trn` | No direct analogue | Transition capability |

**Heuristic**: Stay in the upper rows.
Every step down is a capability you are *failing to deny*.

## Concurrency primitive hierarchy

Before introducing any synchronization primitive, apply this litmus test (prefer earlier options):

1. **Own exclusively** — Can this state live in one task/thread? *(Best)*
2. **Transfer linearly** — Can I transfer ownership via channel? *(Good)*
3. **Share immutably** — Can I make it deeply immutable? (`Arc<T>` where T has no interior mutability)
4. **Shared mutable state** — Do I *really* need `Mutex`/`RwLock`? *(Last resort)*

If you reach option 4, ask: Is there a missing actor?
An inverted dependency?
Shared mutable state often indicates architectural issues rather than inherent requirements.

```rust
// Level 1: Own exclusively (best)
fn process_data(data: Vec<Item>) -> Summary {
    // data owned by this function, no synchronization needed
    data.iter().fold(Summary::default(), |acc, item| acc.merge(item))
}

// Level 2: Transfer linearly (good)
fn spawn_processor(data: Vec<Item>) -> JoinHandle<Summary> {
    // Ownership transferred to spawned task
    tokio::spawn(async move {
        process_data(data)
    })
}

// Level 3: Share immutably
fn share_config(config: Config) -> Arc<Config> {
    // Config is immutable after construction
    // No interior mutability, safe to share
    Arc::new(config)
}

// Level 4: Shared mutable (last resort)
fn shared_counter() -> Arc<Mutex<u64>> {
    // Consider: could this be an actor instead?
    Arc::new(Mutex::new(0))
}
```

## Pattern 1: Actor ownership patterns

The actor pattern recovers `iso` semantics from Pony by ensuring each actor *owns* its state exclusively.
Actors communicate through message passing, not shared memory.

### Message enum pattern

Define actor messages as an enum with variants for each operation:

```rust
use tokio::sync::{mpsc, oneshot};

// Messages the actor can receive
enum CounterMessage {
    Increment,
    Decrement,
    Get { respond_to: oneshot::Sender<u64> },
    Shutdown,
}

// Actor handle (cheap to clone, send to multiple tasks)
#[derive(Clone)]
struct CounterHandle {
    tx: mpsc::Sender<CounterMessage>,
}

impl CounterHandle {
    fn new() -> (Self, JoinHandle<()>) {
        let (tx, rx) = mpsc::channel(32);
        let handle = tokio::spawn(counter_actor(rx));
        (Self { tx }, handle)
    }

    async fn increment(&self) {
        let _ = self.tx.send(CounterMessage::Increment).await;
    }

    async fn get(&self) -> u64 {
        let (respond_to, response) = oneshot::channel();
        let _ = self.tx.send(CounterMessage::Get { respond_to }).await;
        response.await.unwrap_or(0)
    }

    async fn shutdown(&self) {
        let _ = self.tx.send(CounterMessage::Shutdown).await;
    }
}

// Actor owns its state exclusively—no Arc<Mutex<_>>
async fn counter_actor(mut rx: mpsc::Receiver<CounterMessage>) {
    let mut count: u64 = 0;  // Owned! No synchronization!

    while let Some(msg) = rx.recv().await {
        match msg {
            CounterMessage::Increment => count += 1,
            CounterMessage::Decrement => count = count.saturating_sub(1),
            CounterMessage::Get { respond_to } => {
                let _ = respond_to.send(count);
            }
            CounterMessage::Shutdown => break,
        }
    }
}
```

**Benefits**:
- State owned exclusively by actor task (recovers `iso`)
- Handle is `Clone + Send` (cheap to distribute)
- No locks, no deadlocks
- Natural backpressure via bounded channel

### Graceful shutdown pattern

Use cancellation tokens or sentinel messages for coordinated shutdown:

```rust
use tokio_util::sync::CancellationToken;

struct ActorHandle {
    tx: mpsc::Sender<Message>,
    cancel: CancellationToken,
    join: JoinHandle<()>,
}

impl ActorHandle {
    async fn shutdown(self) -> Result<(), JoinError> {
        self.cancel.cancel();
        self.join.await
    }
}

async fn actor_with_cancellation(
    mut rx: mpsc::Receiver<Message>,
    cancel: CancellationToken,
) {
    loop {
        tokio::select! {
            _ = cancel.cancelled() => {
                // Perform cleanup
                break;
            }
            Some(msg) = rx.recv() => {
                handle_message(msg).await;
            }
        }
    }
}
```

## Pattern 2: Channel-first heuristic

Session types arise from process calculi where communication *is* the primitive.
Before reaching for shared state, ask:

> "Could I replace this shared mutable state with a channel?"

```rust
// Anti-pattern: Shared state leaks capability
let counter = Arc::new(Mutex::new(0));
let counter2 = counter.clone();
tokio::spawn(async move {
    *counter2.lock().await += 1;
});

// Better: Actor owns state exclusively
let (tx, mut rx) = mpsc::channel::<()>(32);
let handle = tokio::spawn(async move {
    let mut count = 0;  // Owned! No mutex!
    while let Some(()) = rx.recv().await {
        count += 1;
    }
    count
});
tx.send(()).await?;
```

The actor *owns* its state exclusively—this recovers `iso` semantics.

## Pattern 3: tokio::sync primitive selection

Choose the right primitive for your communication pattern:

| Primitive | Pattern | Use When |
|-----------|---------|----------|
| `mpsc` | Many-to-one | Multiple producers, single consumer (actor inbox) |
| `oneshot` | Request-response | Single value, single consumer (RPC response) |
| `watch` | Broadcast latest | Many consumers need latest value (config updates) |
| `broadcast` | Broadcast all | Many consumers need every value (event bus) |
| `Semaphore` | Resource limiting | Limit concurrent access to resource |
| `Mutex` | Shared mutable | Last resort when actor pattern impractical |

### Selection decision tree

```
Need to send data between tasks?
├── One response to one request? → oneshot
├── Many producers, one consumer? → mpsc
├── One producer, many consumers?
│   ├── Consumers need every value? → broadcast
│   └── Consumers need only latest? → watch
└── Shared mutable state unavoidable? → Mutex/RwLock
```

### mpsc with backpressure

Bounded channels provide natural backpressure:

```rust
// Bounded channel: sender blocks when full
let (tx, rx) = mpsc::channel::<Work>(100);

// Producer respects backpressure
async fn producer(tx: mpsc::Sender<Work>) {
    for work in work_stream() {
        // Blocks if consumer is slow
        tx.send(work).await?;
    }
}

// Consumer processes at its own pace
async fn consumer(mut rx: mpsc::Receiver<Work>) {
    while let Some(work) = rx.recv().await {
        process(work).await;
    }
}
```

### oneshot for request-response

```rust
async fn query_actor(
    handle: &ActorHandle,
    query: Query,
) -> Result<Response, QueryError> {
    let (respond_to, response) = oneshot::channel();
    handle.tx.send(Message::Query { query, respond_to }).await?;

    // Await response with timeout
    match tokio::time::timeout(Duration::from_secs(5), response).await {
        Ok(Ok(resp)) => Ok(resp),
        Ok(Err(_)) => Err(QueryError::ActorDropped),
        Err(_) => Err(QueryError::Timeout),
    }
}
```

### watch for configuration

```rust
use tokio::sync::watch;

// Config broadcaster
let (tx, rx) = watch::channel(Config::default());

// Updater (single writer)
async fn config_updater(tx: watch::Sender<Config>) {
    loop {
        let new_config = load_config().await;
        tx.send(new_config).ok();
        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}

// Consumer (many readers, only sees latest)
async fn worker(mut rx: watch::Receiver<Config>) {
    loop {
        rx.changed().await?;
        let config = rx.borrow().clone();
        apply_config(config);
    }
}
```

## Pattern 4: Structured concurrency

Use `JoinSet` and cancellation tokens to manage task lifetimes hierarchically.

### JoinSet for dynamic task groups

```rust
use tokio::task::JoinSet;

async fn process_batch(items: Vec<Item>) -> Vec<Result<Output, Error>> {
    let mut set = JoinSet::new();

    for item in items {
        set.spawn(async move {
            process_item(item).await
        });
    }

    let mut results = Vec::new();
    while let Some(result) = set.join_next().await {
        match result {
            Ok(output) => results.push(output),
            Err(join_error) => {
                // Task panicked or was cancelled
                results.push(Err(Error::TaskFailed(join_error)));
            }
        }
    }
    results
}
```

### Cancellation propagation

```rust
use tokio_util::sync::CancellationToken;

async fn supervisor(cancel: CancellationToken) {
    let mut set = JoinSet::new();

    // Spawn workers with shared cancellation
    for i in 0..4 {
        let child_cancel = cancel.child_token();
        set.spawn(async move {
            worker(i, child_cancel).await
        });
    }

    // Wait for cancellation or completion
    tokio::select! {
        _ = cancel.cancelled() => {
            set.abort_all();
        }
        _ = async {
            while set.join_next().await.is_some() {}
        } => {
            // All workers completed naturally
        }
    }
}

async fn worker(id: usize, cancel: CancellationToken) {
    loop {
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = do_work(id) => {}
        }
    }
}
```

## Error handling in concurrent contexts

### Cancellation as infrastructure error

Cancellation is an infrastructure concern, not a domain error:

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ProcessingError {
    #[error("validation failed: {0}")]
    Validation(#[from] ValidationError),

    #[error("inference failed: {0}")]
    Inference(#[from] InferenceError),

    // Infrastructure errors
    #[error("operation cancelled")]
    Cancelled,

    #[error("task panicked: {0}")]
    TaskPanic(String),

    #[error("channel closed")]
    ChannelClosed,
}

impl From<tokio::sync::oneshot::error::RecvError> for ProcessingError {
    fn from(_: tokio::sync::oneshot::error::RecvError) -> Self {
        ProcessingError::ChannelClosed
    }
}
```

### Panic propagation in tasks

Spawned tasks isolate panics—use `JoinError` to detect them:

```rust
async fn spawn_with_panic_handling<F, T>(f: F) -> Result<T, ProcessingError>
where
    F: Future<Output = T> + Send + 'static,
    T: Send + 'static,
{
    match tokio::spawn(f).await {
        Ok(result) => Ok(result),
        Err(join_error) if join_error.is_panic() => {
            let panic_info = join_error
                .into_panic()
                .downcast::<String>()
                .map(|s| *s)
                .unwrap_or_else(|_| "unknown panic".to_string());
            Err(ProcessingError::TaskPanic(panic_info))
        }
        Err(join_error) => {
            // Task was cancelled
            Err(ProcessingError::Cancelled)
        }
    }
}
```

## Testing concurrent code

### Deterministic simulation

For complex concurrent systems, consider deterministic simulation testing:

```rust
// Production: real time and I/O
#[cfg(not(feature = "test-util"))]
pub type Time = tokio::time::Instant;

// Test: controlled time
#[cfg(feature = "test-util")]
pub type Time = mock::MockTime;

// Sans-io pattern extends to async
pub enum AsyncEffect {
    Sleep(Duration),
    Send { channel: ChannelId, message: Message },
    Recv { channel: ChannelId },
}

// Deterministic test driver
#[cfg(test)]
async fn test_with_controlled_time() {
    tokio::time::pause();

    let handle = spawn_actor();

    // Advance time deterministically
    tokio::time::advance(Duration::from_secs(60)).await;

    // Assert state after exactly 60 seconds
    assert_eq!(handle.get().await, expected);
}
```

### Property testing for concurrency

Use proptest with async runtime:

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn actor_handles_concurrent_operations(
        ops in prop::collection::vec(any::<Operation>(), 1..100)
    ) {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let (handle, join) = ActorHandle::new();

            // Apply operations concurrently
            let futures: Vec<_> = ops.iter()
                .map(|op| apply_operation(&handle, op))
                .collect();

            futures::future::join_all(futures).await;

            handle.shutdown().await;
            join.await.unwrap();
        });
    }
}
```

## When runtime state beats compile-time state

Phantom types provide excellent compile-time safety but have limits:

**Prefer phantom types when**:
- States are finite and known at compile time
- Transitions are deterministic (no runtime branching)
- API ergonomics benefit from type-level documentation
- You need zero runtime overhead

**Prefer enum state when**:
- State is determined by runtime conditions
- You need to inspect current state dynamically
- State space is large or grows with features
- Cross-module polymorphism over states is needed
- Error recovery may return to previous states

```rust
// Phantom: states known statically, transitions deterministic
impl Connection<Connected> {
    fn authenticate(self, token: &str) -> Result<Connection<Authenticated>, AuthError>;
}

// Enum: runtime state inspection needed
enum ConnectionState {
    Disconnected,
    Connected(TcpStream),
    Authenticated { stream: TcpStream, user: UserId },
}

impl Connection {
    fn state(&self) -> &ConnectionState {
        &self.state
    }

    fn can_send(&self) -> bool {
        matches!(self.state, ConnectionState::Authenticated { .. })
    }
}
```

## Summary: The concurrency mantra

> "Own exclusively, transfer linearly, share immutably, mutate never (across boundaries)."

This will not give you Pony's compile-time guarantees for all concurrent code, but it keeps you in the *subset* of Rust that is morally equivalent to capability-secure concurrency.

The preference hierarchy:
1. Ownership (best) — data lives in one place
2. Channels (good) — ownership transferred linearly
3. Immutable sharing (acceptable) — `Arc<T>` where T has no interior mutability
4. Synchronized mutation (last resort) — `Arc<Mutex<T>>` when architecture truly requires it

When you find yourself at level 4, pause and ask: Is there a missing actor?
Could this be a channel?
Is the shared state actually configuration that could be immutable?

## See also

- ./01-functional-domain-modeling.md - Pattern 2a for phantom types and typestate
- ./02-error-handling.md - Error composition and railway-oriented programming
- ./04-api-design.md - Dependency injection hierarchy, command/event patterns
- ./05-testing.md - Sans-io pattern for testable I/O
- ./07-performance.md - Async yield points and throughput optimization
- domain-modeling.md - Universal domain modeling patterns
- architectural-patterns.md - Effect isolation at boundaries

## References

- [Graydon Hoare's retrospective on Rust](https://graydon2.dreamwidth.org/307291.html) - Typestate as emergent property
- [Deny Capabilities for Safe, Fast Actors](https://www.ponylang.io/media/papers/fast-cheap.pdf) - Pony's capability model
- [Ferrite: Session Types in Rust](https://www.cs.cmu.edu/~balzers/publications/ferrite.pdf) - Session types implementation
- [Propositions as Sessions (Wadler)](https://homepages.inf.ed.ac.uk/wadler/papers/propositions-as-sessions/propositions-as-sessions.pdf) - Curry-Howard for concurrency
