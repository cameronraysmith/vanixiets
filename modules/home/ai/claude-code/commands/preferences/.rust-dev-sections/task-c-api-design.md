## API design

This section integrates Microsoft's pragmatic Rust guidelines with functional domain modeling principles to create APIs that are discoverable, testable, and type-safe.

### Naming conventions

Symbol names should be free of weasel words that don't meaningfully add information.
Common offenders include `Service`, `Manager`, and `Factory`.

**Bad: Weasel words obscure intent**

```rust
pub struct BookingService {
    client: HttpClient,
    db: Database,
}

pub struct CacheManager {
    entries: HashMap<String, String>,
}

pub struct ConnectionFactory {
    config: Config,
}
```

**Good: Domain vocabulary reveals purpose**

```rust
// Use domain vocabulary instead of "Service"
pub struct Booking {
    client: HttpClient,
    db: Database,
}

// Use specific action instead of "Manager"
pub struct Cache {
    entries: HashMap<String, String>,
}

// Use builder pattern instead of "Factory"
pub struct ConnectionBuilder {
    config: Config,
}
```

The same principle applies to functions:

```rust
// Bad: generic verb + weasel word
impl Database {
    pub fn manage_connection(&self) { ... }
    pub fn process_service(&self) { ... }
}

// Good: specific domain action
impl Database {
    pub fn connect(&self) { ... }
    pub fn execute_query(&self, query: Query) { ... }
}
```

**Integration with FDM**: Domain-specific names make smart constructors and state machines self-documenting.
A type named `CalibrationResult` is clearer than `CalibrationService` or `CalibrationManager`.

### Function organization

Essential functionality should be implemented as inherent methods on types, not just as trait implementations.
Traits should forward to inherent functions.

**Bad: Core functionality hidden in trait**

```rust
pub struct Dataset { /* ... */ }

// User must know to import DatasetOps to use add_observation
pub trait DatasetOps {
    fn add_observation(&mut self, obs: Observation) -> Result<(), Error>;
}

impl DatasetOps for Dataset {
    fn add_observation(&mut self, obs: Observation) -> Result<(), Error> {
        // Implementation here
    }
}
```

**Good: Essential methods inherent, trait forwards**

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
// Bad: associated function for computation
impl Measurement {
    pub fn calculate_uncertainty(value: f64, baseline: f64) -> f64 {
        (value - baseline).abs()
    }
}

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

**Integration with FDM**: Inherent methods make smart constructors and aggregate methods immediately discoverable.
Users don't need to know which trait to import to access core domain operations.

### Dependency injection hierarchy

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

    pub fn write_file(&self, path: &Path, data: &[u8]) -> std::io::Result<()> {
        match self {
            Self::Real => std::fs::write(path, data),
            #[cfg(feature = "test-util")]
            Self::Mock(mock) => mock.write_file(path, data),
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

        pub fn write_file(&self, path: &Path, data: &[u8]) -> std::io::Result<()> {
            self.inner.files.lock().unwrap()
                .insert(path.to_path_buf(), data.to_vec());
            Ok(())
        }

        // Test helper methods
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

// Usage with different calibration algorithms
let linear_result = calibrate(|v| (v * 1.1, 0.95), 0.8, &data)?;
let nonlinear_result = calibrate(|v| (v.powi(2), 0.90), 0.8, &data)?;
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

**Integration with FDM**: This hierarchy supports functional domain modeling by preferring concrete types for domain logic (level 1), using enums for I/O boundaries (level 2), reserving generics for true abstraction needs (level 3), and avoiding trait objects unless necessary (level 4).
The result is APIs that are testable, composable, and don't pay runtime costs for unused flexibility.

### Builder pattern

Use builder pattern when types support 4 or more initialization parameters, especially when some are optional.

**When to use builders**:
- 4+ parameters in constructor
- Multiple optional parameters
- Complex initialization with validation steps
- Need to provide incremental construction

**Builder naming**: `FooBuilder` for type `Foo`.

```rust
// Complex type with many parameters
pub struct ModelConfig {
    architecture: Architecture,
    learning_rate: f64,
    batch_size: usize,
    epochs: usize,
    optimizer: Optimizer,
    regularization: Option<Regularization>,
    checkpoint_dir: Option<PathBuf>,
    early_stopping: Option<EarlyStopping>,
}

// Builder with chainable methods
pub struct ModelConfigBuilder {
    architecture: Option<Architecture>,
    learning_rate: Option<f64>,
    batch_size: Option<usize>,
    epochs: Option<usize>,
    optimizer: Option<Optimizer>,
    regularization: Option<Regularization>,
    checkpoint_dir: Option<PathBuf>,
    early_stopping: Option<EarlyStopping>,
}

impl ModelConfigBuilder {
    pub fn new() -> Self {
        Self {
            architecture: None,
            learning_rate: None,
            batch_size: None,
            epochs: None,
            optimizer: None,
            regularization: None,
            checkpoint_dir: None,
            early_stopping: None,
        }
    }

    // Chainable setters
    pub fn architecture(mut self, arch: Architecture) -> Self {
        self.architecture = Some(arch);
        self
    }

    pub fn learning_rate(mut self, lr: f64) -> Self {
        self.learning_rate = Some(lr);
        self
    }

    pub fn batch_size(mut self, size: usize) -> Self {
        self.batch_size = Some(size);
        self
    }

    pub fn epochs(mut self, epochs: usize) -> Self {
        self.epochs = Some(epochs);
        self
    }

    pub fn optimizer(mut self, opt: Optimizer) -> Self {
        self.optimizer = Some(opt);
        self
    }

    // Optional parameters
    pub fn regularization(mut self, reg: Regularization) -> Self {
        self.regularization = Some(reg);
        self
    }

    pub fn checkpoint_dir(mut self, dir: PathBuf) -> Self {
        self.checkpoint_dir = Some(dir);
        self
    }

    pub fn early_stopping(mut self, es: EarlyStopping) -> Self {
        self.early_stopping = Some(es);
        self
    }

    // Build with validation (smart constructor)
    pub fn build(self) -> Result<ModelConfig, ValidationError> {
        let architecture = self.architecture
            .ok_or(ValidationError::MissingField("architecture"))?;
        let learning_rate = self.learning_rate
            .ok_or(ValidationError::MissingField("learning_rate"))?;
        let batch_size = self.batch_size
            .ok_or(ValidationError::MissingField("batch_size"))?;
        let epochs = self.epochs
            .ok_or(ValidationError::MissingField("epochs"))?;
        let optimizer = self.optimizer
            .unwrap_or(Optimizer::Adam); // Default for optional

        // Validation
        if learning_rate <= 0.0 || learning_rate >= 1.0 {
            return Err(ValidationError::InvalidLearningRate(learning_rate));
        }

        if batch_size == 0 {
            return Err(ValidationError::InvalidBatchSize(batch_size));
        }

        Ok(ModelConfig {
            architecture,
            learning_rate,
            batch_size,
            epochs,
            optimizer,
            regularization: self.regularization,
            checkpoint_dir: self.checkpoint_dir,
            early_stopping: self.early_stopping,
        })
    }
}

// Usage
let config = ModelConfigBuilder::new()
    .architecture(Architecture::ResNet50)
    .learning_rate(0.001)
    .batch_size(32)
    .epochs(100)
    .optimizer(Optimizer::Adam)
    .regularization(Regularization::L2 { lambda: 0.01 })
    .build()?;
```

**Integration with FDM**: Builders work naturally with smart constructors.
The `build()` method acts as the smart constructor, validating invariants before creating the type.
This is especially useful for aggregates and complex value objects with many fields.

### Input flexibility

Make APIs flexible by accepting trait bounds instead of concrete types for common conversions.

**Accept `impl AsRef<T>` for borrowed data**

```rust
// Bad: forces caller to provide exact type
pub fn load_config(path: &Path) -> Result<Config, Error> { ... }

// Good: accepts &Path, &PathBuf, &&Path, etc.
pub fn load_config(path: impl AsRef<Path>) -> Result<Config, Error> {
    let path = path.as_ref();
    // Use path...
}

// Usage flexibility
load_config(&path_buf)?;           // &PathBuf
load_config(path)?;                // &Path
load_config("config.toml")?;       // &str (via AsRef<Path>)
```

**Accept `impl RangeBounds<T>` for ranges**

```rust
use std::ops::RangeBounds;

// Bad: forces specific range type
pub fn select_range(data: &[f64], range: Range<usize>) -> &[f64] {
    &data[range]
}

// Good: accepts any range type
pub fn select_range<R>(data: &[f64], range: R) -> &[f64]
where
    R: RangeBounds<usize>,
{
    use std::ops::Bound;

    let start = match range.start_bound() {
        Bound::Included(&n) => n,
        Bound::Excluded(&n) => n + 1,
        Bound::Unbounded => 0,
    };

    let end = match range.end_bound() {
        Bound::Included(&n) => n + 1,
        Bound::Excluded(&n) => n,
        Bound::Unbounded => data.len(),
    };

    &data[start..end]
}

// Usage flexibility
select_range(data, 0..10);      // Range
select_range(data, 0..=9);      // RangeInclusive
select_range(data, 5..);        // RangeFrom
select_range(data, ..10);       // RangeTo
select_range(data, ..);         // RangeFull
```

**Accept `impl Read`/`impl Write` for I/O (sans-io pattern)**

Functions that perform I/O should accept trait objects to decouple business logic from I/O source.

```rust
use std::io::{Read, Write};

// Bad: forces caller to use File
pub fn parse_data(file: File) -> Result<Data, Error> { ... }

// Good: accepts any Read implementation
pub fn parse_data(mut reader: impl Read) -> Result<Data, Error> {
    let mut buffer = String::new();
    reader.read_to_string(&mut buffer)?;
    // Parse buffer...
}

// Usage flexibility
parse_data(File::open("data.txt")?)?;           // File
parse_data(std::io::stdin())?;                  // Stdin
parse_data(data_bytes.as_slice())?;             // &[u8]
parse_data(TcpStream::connect("server:8080")?)?; // Network
```

**Integration with FDM**: Input flexibility complements smart constructors by making them easier to call.
A smart constructor for `FilePath` that accepts `impl AsRef<Path>` is more ergonomic than one requiring `&Path`.

### Avoiding visible complexity

Hide implementation details that don't add value for users.

**Hide smart pointers in APIs**

Don't expose `Arc`, `Rc`, `Box` in public APIs unless the ownership semantics are essential.

```rust
// Bad: exposes Arc in API
pub struct Database {
    connection: Arc<Connection>,
}

pub fn query_database(db: Arc<Database>, query: &str) -> Result<Data, Error> {
    // ...
}

// Good: hides Arc internally, presents simple interface
pub struct Database {
    connection: Arc<Connection>, // Internal detail
}

impl Database {
    pub fn query(&self, query: &str) -> Result<Data, Error> {
        // Use self.connection internally
    }
}

// Clone Database cheaply (Arc internally)
impl Clone for Database {
    fn clone(&self) -> Self {
        Self {
            connection: Arc::clone(&self.connection),
        }
    }
}

// Usage: simple, no Arc visible
let db1 = Database::connect("localhost")?;
let db2 = db1.clone(); // Cheap clone via internal Arc
let result = db1.query("SELECT * FROM users")?;
```

**Services are Clone** (M-SERVICES-CLONE pattern): Heavyweight service types should implement `Clone` with shared ownership semantics internally.

```rust
// Service with internal Arc for cheap cloning
pub struct MetricsCollector {
    inner: Arc<MetricsInner>,
}

struct MetricsInner {
    storage: Mutex<HashMap<String, f64>>,
}

impl Clone for MetricsCollector {
    fn clone(&self) -> Self {
        Self {
            inner: Arc::clone(&self.inner),
        }
    }
}

impl MetricsCollector {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(MetricsInner {
                storage: Mutex::new(HashMap::new()),
            }),
        }
    }

    pub fn record(&self, name: String, value: f64) {
        self.inner.storage.lock().unwrap().insert(name, value);
    }
}

// Usage: can clone and share service cheaply
fn spawn_worker(metrics: MetricsCollector) {
    std::thread::spawn(move || {
        metrics.record("worker_started".to_string(), 1.0);
    });
}

let metrics = MetricsCollector::new();
spawn_worker(metrics.clone());
spawn_worker(metrics.clone());
```

**Minimize nested type parameters**

Don't expose complex nested generics in primary API surface.

```rust
// Bad: complex nested types visible to user
pub fn process<T, E, F>(
    data: Vec<Result<Option<T>, E>>,
    transform: F,
) -> Result<Vec<T>, ProcessingError<E>>
where
    F: Fn(T) -> Result<T, E>,
{ ... }

// Good: hide complexity with type aliases and simpler interface
pub type ProcessingResult<T> = Result<Vec<T>, ProcessingError>;

pub fn process<T>(
    data: Vec<T>,
    transform: impl Fn(T) -> Result<T, ValidationError>,
) -> ProcessingResult<T>
{ ... }
```

**Integration with FDM**: Hiding complexity makes domain types easier to use.
A smart constructor should present a simple interface even if it uses complex validation internally.
An aggregate should expose clean methods even if it uses locks or other synchronization primitives internally.

### How these principles support FDM

API design principles work synergistically with functional domain modeling:

1. **Domain vocabulary (naming)** makes types and functions self-documenting
   - `CalibrationResult` instead of `CalibrationService`
   - `calibrate()` instead of `manage_calibration()`
   - Types speak the problem domain language

2. **Inherent methods (organization)** make smart constructors discoverable
   - `Measurement::new()` available without trait imports
   - Core domain operations immediately visible
   - Traits extend, don't replace, inherent functionality

3. **Dependency hierarchy** preserves domain purity
   - Domain logic uses concrete types (level 1)
   - I/O abstracted with enums (level 2)
   - Generics for true algorithm flexibility (level 3)
   - Trait objects only when necessary (level 4)

4. **Builders** enable complex smart constructors
   - Aggregates with many fields use builders
   - Validation in `build()` method enforces invariants
   - Chainable API improves ergonomics

5. **Input flexibility** makes APIs more composable
   - `impl AsRef<Path>` works with domain types
   - `impl RangeBounds<T>` accepts rich range vocabulary
   - Sans-io pattern decouples domain logic from I/O

6. **Hidden complexity** focuses users on domain concepts
   - Internal `Arc` enables cheap cloning without exposing ownership
   - Type aliases hide complex effect stacks
   - Users work with domain types, not infrastructure primitives

**Complete example: FDM + API design**

```rust
use std::path::Path;
use std::io::Read;

// Domain type with smart constructor
#[derive(Debug, Clone)]
pub struct QualityScore(f64);

impl QualityScore {
    // Smart constructor (inherent method)
    pub fn new(value: f64) -> Result<Self, ValidationError> {
        if !(0.0..=1.0).contains(&value) {
            return Err(ValidationError::OutOfRange {
                field: "quality_score".to_string(),
                value,
                range: (0.0, 1.0),
            });
        }
        Ok(Self(value))
    }

    pub fn value(&self) -> f64 {
        self.0
    }
}

// Complex domain type uses builder
pub struct CalibrationConfig {
    baseline: f64,
    threshold: QualityScore,
    model_path: PathBuf,
}

pub struct CalibrationConfigBuilder {
    baseline: Option<f64>,
    threshold: Option<QualityScore>,
    model_path: Option<PathBuf>,
}

impl CalibrationConfigBuilder {
    pub fn new() -> Self {
        Self {
            baseline: None,
            threshold: None,
            model_path: None,
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

    // Flexible input: accepts any AsRef<Path>
    pub fn model_path(mut self, path: impl AsRef<Path>) -> Self {
        self.model_path = Some(path.as_ref().to_path_buf());
        self
    }

    // Smart constructor in build()
    pub fn build(self) -> Result<CalibrationConfig, ValidationError> {
        Ok(CalibrationConfig {
            baseline: self.baseline
                .ok_or(ValidationError::MissingRequired {
                    field: "baseline".to_string(),
                })?,
            threshold: self.threshold
                .ok_or(ValidationError::MissingRequired {
                    field: "threshold".to_string(),
                })?,
            model_path: self.model_path
                .ok_or(ValidationError::MissingRequired {
                    field: "model_path".to_string(),
                })?,
        })
    }
}

// Service uses enum for I/O abstraction
pub enum Calibrator {
    Real { config: CalibrationConfig },
    #[cfg(feature = "test-util")]
    Mock(mock::MockCalibratorCtrl),
}

impl Calibrator {
    // Constructor for production
    pub fn new(config: CalibrationConfig) -> Self {
        Self::Real { config }
    }

    // Constructor for testing returns mock controller
    #[cfg(feature = "test-util")]
    pub fn new_mocked(config: CalibrationConfig) -> (Self, mock::MockCalibratorCtrl) {
        let ctrl = mock::MockCalibratorCtrl::new();
        (Self::Mock(ctrl.clone()), ctrl)
    }

    // Sans-io: accepts any Read implementation
    pub fn calibrate(
        &self,
        data: impl Read,
    ) -> Result<CalibratedData, CalibrationError> {
        match self {
            Self::Real { config } => {
                // Real implementation reads from data
            }
            #[cfg(feature = "test-util")]
            Self::Mock(mock) => mock.calibrate(data),
        }
    }
}

// Usage combining all principles
fn example() -> Result<(), Box<dyn std::error::Error>> {
    // Build config with flexible inputs
    let config = CalibrationConfigBuilder::new()
        .baseline(1.0)
        .threshold(QualityScore::new(0.95)?)
        .model_path("models/calibration.bin")  // &str via AsRef<Path>
        .build()?;

    // Create calibrator
    let calibrator = Calibrator::new(config);

    // Use with flexible I/O
    let result = calibrator.calibrate(File::open("data.csv")?)?;

    Ok(())
}
```

This example demonstrates:
- Domain vocabulary: `QualityScore`, `Calibrator` (not `CalibrationService`)
- Smart constructors: `QualityScore::new()` validates range
- Builder pattern: `CalibrationConfigBuilder` for complex construction
- Enum for I/O: `Calibrator` enum enables testing without trait objects
- Input flexibility: `impl AsRef<Path>`, `impl Read`
- Hidden complexity: No `Arc` in public API even if used internally

**See also**:
- domain-modeling.md for pattern descriptions
- architectural-patterns.md for dependency injection
- rust-development.md for implementation examples
