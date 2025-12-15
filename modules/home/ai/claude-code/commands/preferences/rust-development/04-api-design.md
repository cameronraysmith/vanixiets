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
- domain-modeling.md (universal domain modeling patterns)
- architectural-patterns.md (application structure patterns)
