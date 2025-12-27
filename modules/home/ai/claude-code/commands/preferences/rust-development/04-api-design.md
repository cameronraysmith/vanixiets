# API design

This section integrates Microsoft's pragmatic Rust guidelines with FDM principles to create APIs that are discoverable, testable, and type-safe.

## Naming conventions

Symbol names should be free of weasel words that don't meaningfully add information.
Common offenders include `Service`, `Manager`, and `Factory`.

```rust
// Bad: Weasel words obscure intent
pub struct BookingService { }
pub struct CacheManager { }
pub struct ConnectionFactory { }

// Good: Domain vocabulary reveals purpose
pub struct Booking { }
pub struct Cache { }
pub struct ConnectionBuilder { }
```

Domain-specific names make smart constructors and state machines self-documenting.
A type named `CalibrationResult` is clearer than `CalibrationService` or `CalibrationManager`.

## Function organization

Essential functionality should be implemented as inherent methods on types, not just as trait implementations.
Traits should forward to inherent functions.

```rust
pub struct Dataset { /* ... */ }

// Core functionality discoverable without imports
impl Dataset {
    pub fn add_observation(&mut self, obs: Observation) -> Result<(), Error> {
        // Implementation here
    }
}

// Optional: trait for generic programming forwards to inherent method
pub trait DatasetOps {
    fn add_observation(&mut self, obs: Observation) -> Result<(), Error>;
}

impl DatasetOps for Dataset {
    fn add_observation(&mut self, obs: Observation) -> Result<(), Error> {
        // Forward to inherent implementation
        Dataset::add_observation(self, obs)
    }
}
```

**Prefer regular functions over associated functions** for operations that don't create instances.
Associated functions should primarily be used for instance creation (constructors, builders).

```rust
// Good: regular function for computation
pub fn calculate_uncertainty(value: f64, baseline: f64) -> f64 {
    (value - baseline).abs()
}

// Good: associated function for construction
impl Measurement {
    pub fn new(value: f64, uncertainty: f64) -> Result<Self, ValidationError> {
        // Smart constructor
    }
}
```

Inherent methods make smart constructors and aggregate methods immediately discoverable.
Users don't need to know which trait to import to access core domain operations.

## Dependency injection hierarchy

When designing APIs that accept dependencies, follow this escalation ladder (prefer earlier options):

1. **Concrete types** - for domain logic and when only one implementation exists
2. **Enums** - for testable I/O abstraction (sans-io pattern)
3. **Generics** - for algorithm parameters or when caller needs flexibility
4. **dyn Trait** - last resort, only for true runtime polymorphism needs

**Level 1: Concrete types (preferred for domain logic)**

```rust
// Domain logic uses concrete types
pub struct CalibrationModel {
    baseline: f64,
    threshold: f64,
}

impl CalibrationModel {
    pub fn calibrate(&self, raw: RawValue) -> CalibratedValue {
        // Concrete implementation
    }
}

pub fn process_data(
    model: &CalibrationModel,  // Concrete type, not generic
    data: &[RawValue]
) -> Vec<CalibratedValue> {
    data.iter().map(|v| model.calibrate(*v)).collect()
}
```

**Level 2: Enums for testable I/O (sans-io pattern)**

Use enums to provide both real and mock implementations without trait objects.

```rust
// I/O abstraction as enum
pub enum FileSystem {
    Real,
    #[cfg(feature = "test-util")]
    Mock(MockFsCtrl),
}

impl FileSystem {
    pub fn read_file(&self, path: &Path) -> std::io::Result<Vec<u8>> {
        match self {
            Self::Real => std::fs::read(path),
            #[cfg(feature = "test-util")]
            Self::Mock(mock) => mock.read_file(path),
        }
    }
}

#[cfg(feature = "test-util")]
pub mod mock {
    use std::sync::Arc;

    // Clone-able mock controller (follows M-SERVICES-CLONE)
    #[derive(Clone)]
    pub struct MockFsCtrl {
        inner: Arc<MockFsCtrlInner>,
    }

    struct MockFsCtrlInner {
        files: std::sync::Mutex<HashMap<PathBuf, Vec<u8>>>,
    }

    impl MockFsCtrl {
        pub fn read_file(&self, path: &Path) -> std::io::Result<Vec<u8>> {
            self.inner.files.lock().unwrap()
                .get(path)
                .cloned()
                .ok_or_else(|| std::io::Error::new(
                    std::io::ErrorKind::NotFound,
                    "file not found in mock"
                ))
        }

        pub fn add_file(&self, path: PathBuf, contents: Vec<u8>) {
            self.inner.files.lock().unwrap().insert(path, contents);
        }
    }
}

// Return mock controller via tuple for testability
pub struct DataProcessor {
    fs: FileSystem,
}

impl DataProcessor {
    pub fn new() -> Self {
        Self { fs: FileSystem::Real }
    }

    #[cfg(feature = "test-util")]
    pub fn new_mocked() -> (Self, mock::MockFsCtrl) {
        let ctrl = mock::MockFsCtrl::new();
        let processor = Self { fs: FileSystem::Mock(ctrl.clone()) };
        (processor, ctrl)
    }
}
```

**Level 3: Generics for algorithm parameters**

Use generics when caller needs to provide algorithm details or when the API benefits from flexibility without runtime cost.

```rust
// Generic for calibration function, concrete for data
pub fn calibrate<F>(
    calibration_fn: F,  // Algorithm parameter: generic
    threshold: f64,     // Simple parameter: concrete
    data: &[RawValue],  // Data: concrete
) -> Result<Vec<CalibratedValue>, CalibrationError>
where
    F: Fn(RawValue) -> (f64, f64),  // Returns (value, quality)
{
    let mut results = Vec::new();
    for &raw in data {
        let (value, quality) = calibration_fn(raw);
        if quality < threshold {
            return Err(CalibrationError::QualityTooLow { quality, threshold });
        }
        results.push(CalibratedValue { value, quality });
    }
    Ok(results)
}
```

**Level 4: dyn Trait (last resort)**

Only use trait objects when you need runtime polymorphism and cannot use enums or generics.

```rust
// Only when you truly need runtime selection of implementation
pub trait Database {
    fn load(&self, id: &str) -> Result<Data, DbError>;
    fn save(&self, id: &str, data: &Data) -> Result<(), DbError>;
}

// Wrapper that hides Arc<dyn Trait> implementation detail
pub struct DynamicDatabase(Arc<dyn Database + Send + Sync>);

impl DynamicDatabase {
    pub fn new<T: Database + Send + Sync + 'static>(db: T) -> Self {
        Self(Arc::new(db))
    }
}

// But prefer enum approach when possible
pub enum DatabaseImpl {
    Postgres(PostgresDb),
    Sqlite(SqliteDb),
    #[cfg(feature = "test-util")]
    Mock(MockDb),
}
```

This hierarchy supports FDM by preferring concrete types for domain logic (level 1), using enums for I/O boundaries (level 2), reserving generics for true abstraction needs (level 3), and avoiding trait objects unless necessary (level 4).

## Serialization boundaries

### Principle

Domain types should remain ignorant of serialization concerns.
This preserves persistence ignorance and keeps domain logic independent of infrastructure choices.
For conceptual foundation, see `~/.claude/commands/preferences/architectural-patterns.md` (Onion/hexagonal architecture, infrastructure layer responsibilities).

### DTO separation pattern

Separate Data Transfer Objects (DTOs) from domain types to maintain clear boundaries:

**Domain types**:
- Enforce invariants via smart constructors
- Provide getter methods for private fields
- Never derive Serialize/Deserialize
- Contain business logic

**DTOs**:
- Plain structs with public fields
- Derive Serialize and Deserialize
- No business logic or validation
- Exist solely for serialization

```rust
// Domain type: smart constructor, private fields, no Serde
pub struct Email {
    value: String,
}

impl Email {
    pub fn new(s: impl AsRef<str>) -> Result<Self, ValidationError> {
        let value = s.as_ref();
        if !value.contains('@') {
            return Err(ValidationError::InvalidEmail(value.to_string()));
        }
        Ok(Self { value: value.to_string() })
    }

    pub fn as_str(&self) -> &str {
        &self.value
    }
}

// DTO: public fields, Serde derives, no validation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmailDto {
    pub value: String,
}
```

### Conversion patterns

**Domain → DTO (infallible)**:

Conversion from validated domain types to DTOs always succeeds because domain invariants are already enforced.
Use `From<DomainType>` for infallible conversions.

```rust
impl From<Email> for EmailDto {
    fn from(email: Email) -> Self {
        EmailDto {
            value: email.as_str().to_string(),
        }
    }
}

// More complex example with nested types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserDto {
    pub email: String,
    pub age: u32,
}

impl From<User> for UserDto {
    fn from(user: User) -> Self {
        UserDto {
            email: user.email().as_str().to_string(),
            age: user.age().into(),
        }
    }
}
```

**DTO → Domain (fallible)**:

Conversion from DTOs to domain types validates at the boundary.
Use `TryFrom<DomainTypeDto>` for fallible conversions that enforce invariants.

```rust
impl TryFrom<EmailDto> for Email {
    type Error = ValidationError;

    fn try_from(dto: EmailDto) -> Result<Self, Self::Error> {
        Email::new(dto.value)  // Re-validates via smart constructor
    }
}

// More complex example with nested validation
impl TryFrom<UserDto> for User {
    type Error = ValidationError;

    fn try_from(dto: UserDto) -> Result<Self, Self::Error> {
        let email = Email::new(dto.email)?;
        let age = Age::new(dto.age)?;
        Ok(User::new(email, age))
    }
}
```

### Module organization

Separate domain and DTO modules to enforce the boundary:

```rust
// src/domain/user.rs - domain types
pub struct User {
    email: Email,
    age: Age,
}

impl User {
    pub fn email(&self) -> &Email { &self.email }
    pub fn age(&self) -> &Age { &self.age }
}

// src/dto/user.rs - DTOs with Serde
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserDto {
    pub email: String,
    pub age: u32,
}

// Conversions in either module or dedicated conversions module
impl From<User> for UserDto { /* ... */ }
impl TryFrom<UserDto> for User { /* ... */ }
```

This organization makes it clear:
- `#[derive(Serialize, Deserialize)]` appears only in `dto/` modules
- Domain types in `domain/` have no Serde dependencies
- Conversion implementations explicitly document the boundary

## Command and event struct patterns

### Principle

Workflows have typed inputs (commands) and outputs (events) that document intent and outcomes.
Commands represent actions to perform; events represent facts about what occurred.
For conceptual foundation, see `~/.claude/commands/preferences/architectural-patterns.md` (Commands and events as workflow boundaries).

**Local vs. distributed semantics**: The command/event pattern here describes in-process workflow documentation.
When commands or events cross service boundaries (HTTP, gRPC, message queues), additional concerns apply:

- Idempotency keys for exactly-once semantics
- Correlation IDs for distributed tracing
- Schema evolution for event contracts
- Delivery guarantees (at-least-once vs. exactly-once)

See ./12-distributed-systems.md for distributed command/event patterns.

### Command conventions

Commands represent intent to perform an action:

**Naming**: Use imperative verb phrases
- `ProcessObservations`, `TrainModel`, `ValidateInput`
- NOT `ProcessObservationsCommand` (redundant suffix)

**Structure**: Include operation data and metadata
- Data needed to perform the operation
- Timestamp, request ID, user context for tracing
- Immutable (no `mut` methods)

**Derives**: Typical derives for commands
```rust
#[derive(Debug, Clone)]
pub struct ProcessObservationsCommand {
    pub request_id: RequestId,
    pub timestamp: DateTime<Utc>,
    pub observations: Vec<RawObservation>,
    pub user_id: UserId,
}
```

Optionally derive `Serialize`/`Deserialize` if commands cross API boundaries (HTTP, message queue).
For internal commands, `Debug` and `Clone` usually suffice.

### Event conventions

Events represent facts about what happened:

**Naming**: Use past-tense verb phrases
- `ObservationsProcessed`, `ModelTrained`, `ValidationCompleted`
- NOT `ProcessingSuccessEvent` (awkward, redundant)

**Structure**: Include result data
- Data needed by downstream consumers
- Timestamp, correlation IDs for tracing
- Immutable

**Multiple events**: Workflows may emit multiple events
```rust
#[derive(Debug, Clone)]
pub enum ProcessingEvent {
    ObservationsValidated {
        count: usize,
        quality_score: f64,
        timestamp: DateTime<Utc>,
    },
    CalibrationCompleted {
        model_version: String,
        timestamp: DateTime<Utc>,
    },
    ProcessingFailed {
        reason: String,
        timestamp: DateTime<Utc>,
    },
}
```

### Complete example

```rust
use chrono::{DateTime, Utc};

// Command: imperative naming, contains input data
#[derive(Debug, Clone)]
pub struct ProcessObservationsCommand {
    pub request_id: RequestId,
    pub timestamp: DateTime<Utc>,
    pub observations: Vec<RawObservation>,
    pub user_id: UserId,
}

// Events: past-tense naming, contain result data
#[derive(Debug, Clone)]
pub enum ProcessingEvent {
    ObservationsValidated {
        count: usize,
        quality_score: f64,
    },
    CalibrationCompleted {
        model_version: String,
    },
    ProcessingFailed {
        reason: String,
    },
}

// Workflow signature: Command → Result<Vec<Event>, Error>
pub fn process_observations(
    calibration_model: &CalibrationModel,
    command: ProcessObservationsCommand,
) -> Result<Vec<ProcessingEvent>, ProcessingError> {
    let mut events = Vec::new();

    // Validate observations
    let validated = validate_observations(&command.observations)?;
    events.push(ProcessingEvent::ObservationsValidated {
        count: validated.len(),
        quality_score: calculate_quality(&validated),
    });

    // Calibrate
    let calibrated = calibration_model.calibrate(&validated)?;
    events.push(ProcessingEvent::CalibrationCompleted {
        model_version: calibration_model.version().to_string(),
    });

    Ok(events)
}
```

This pattern supports FDM by making workflow boundaries explicit, documenting I/O contracts in types, and enabling event-driven architectures.

## Builder pattern

Use builder pattern when types support 4 or more initialization parameters, especially when some are optional.

**When to use builders**:
- 4+ parameters in constructor
- Multiple optional parameters
- Complex initialization with validation steps
- Need to provide incremental construction

**Pattern: Builder with validation**

```rust
pub struct CalibrationConfig {
    baseline: f64,
    threshold: QualityScore,
    model_path: PathBuf,
    max_iterations: Option<usize>,
}

pub struct CalibrationConfigBuilder {
    baseline: Option<f64>,
    threshold: Option<QualityScore>,
    model_path: Option<PathBuf>,
    max_iterations: Option<usize>,
}

impl CalibrationConfigBuilder {
    pub fn new() -> Self {
        Self {
            baseline: None,
            threshold: None,
            model_path: None,
            max_iterations: None,
        }
    }

    pub fn baseline(mut self, baseline: f64) -> Self {
        self.baseline = Some(baseline);
        self
    }

    pub fn threshold(mut self, threshold: QualityScore) -> Self {
        self.threshold = Some(threshold);
        self
    }

    pub fn model_path(mut self, path: impl AsRef<Path>) -> Self {
        self.model_path = Some(path.as_ref().to_path_buf());
        self
    }

    pub fn max_iterations(mut self, max: usize) -> Self {
        self.max_iterations = Some(max);
        self
    }

    pub fn build(self) -> Result<CalibrationConfig, String> {
        let baseline = self.baseline.ok_or("baseline is required")?;
        let threshold = self.threshold.ok_or("threshold is required")?;
        let model_path = self.model_path.ok_or("model_path is required")?;

        Ok(CalibrationConfig {
            baseline,
            threshold,
            model_path,
            max_iterations: self.max_iterations,
        })
    }
}
```

## Input flexibility

Accept `impl AsRef<T>` for path and string-like parameters to provide flexibility without cost.

```rust
// Accepts &str, String, &Path, PathBuf, and more
pub fn load_model(path: impl AsRef<Path>) -> Result<Model, IoError> {
    let path = path.as_ref();
    // ...
}

// Accepts File, TcpStream, &[u8], and many more
pub fn parse_data(data: impl std::io::Read) -> Result<Data, ParseError> {
    // ...
}
```

## Avoiding visible complexity

Hide implementation complexity behind simple public APIs.

```rust
// Bad: Exposes Arc in public API
pub struct Database {
    pub connection: Arc<Mutex<Connection>>,
}

// Good: Hides Arc, provides clean API
pub struct Database {
    connection: Arc<Mutex<Connection>>,
}

impl Database {
    pub fn query(&self, sql: &str) -> Result<QueryResult, DbError> {
        // Internal complexity hidden
    }
}
```

**Concurrency consideration**: Before using `Arc<Mutex<T>>` or `Arc<RwLock<T>>`, consider whether an actor pattern with channels would better preserve capability-secure concurrency.
See ./11-concurrency.md for the concurrency primitive hierarchy and when shared mutable state is genuinely necessary versus when it indicates a missing architectural abstraction.

## API design principles summary

These principles support FDM by:
- Making domain vocabulary explicit in type names
- Keeping core operations discoverable without trait imports
- Providing testability through enums rather than trait objects
- Hiding complexity behind simple, type-safe interfaces
- Using builders for complex construction with validation
- Accepting flexible input types without performance cost

## See also

- ./01-functional-domain-modeling.md (functional domain modeling patterns)
- ./02-error-handling.md (error handling and Result types)
- ./03-panic-semantics.md (panic handling and safety)
- ./05-testing.md (testing patterns and mocking)
- ./06-documentation.md (documentation practices)
- ./07-performance.md (performance optimization)
- ./08-structured-logging.md (structured logging)
- ./09-unsafe-code.md (unsafe code patterns)
- ./10-tooling.md (code quality and dependencies)
- ./11-concurrency.md (capability-secure concurrency patterns)
- domain-modeling.md (universal domain modeling patterns)
- architectural-patterns.md (application structure patterns)
