# Rust development

This guide integrates functional domain modeling (FDM) with pragmatic Rust practices from Microsoft engineers.

**Primary lens:** Functional domain modeling - type-driven design encoding business logic in the type system, making invariants explicit and violations compile-time errors.

**Complementary guidance:** Microsoft Pragmatic Rust Guidelines - industry best practices for API design, testing, performance, and safety.

**Philosophical reconciliations:**

- *Panic semantics*: Panics for true programming bugs only (contract violations, impossible states).
Domain and infrastructure errors use Result types.
Good type design reduces both panic surface and error handling complexity.
- *Dependency injection*: Prefer concrete types for domain logic, enums for testable I/O (sans-io), generics for algorithm parameters, dyn Trait only for true runtime polymorphism.
This hierarchy complements FDM's emphasis on explicit, type-safe dependencies.
- *Type-driven design*: Both approaches emphasize making invalid states unrepresentable.
Smart constructors, state machines, and strong types eliminate bug categories.

**Role in multi-language architectures:** Rust often serves as the base IO/Result layer in multi-language monad transformer stacks, providing memory-safe, high-performance foundations for effect composition.

## Functional domain modeling in Rust

This section demonstrates implementing FDM patterns in Rust.
For pattern descriptions, see domain-modeling.md.
For theoretical foundations, see theoretical-foundations.md.

### Pattern 1: Smart constructors with newtype pattern

Use newtype pattern (tuple structs) to create types with guaranteed invariants.

**Example: Validated measurement types**

```rust
use std::fmt;

// Newtype for quality score with constrained range [0,1]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct QualityScore(f64);

impl QualityScore {
    /// Smart constructor that validates range
    pub fn new(value: f64) -> Result<Self, String> {
        if !(0.0..=1.0).contains(&value) {
            return Err(format!("quality score must be in [0,1], got {}", value));
        }
        Ok(QualityScore(value))
    }

    pub fn value(&self) -> f64 {
        self.0
    }
}

// Newtype for uncertainty with positive constraint
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Uncertainty(f64);

impl Uncertainty {
    /// Smart constructor that validates positivity
    pub fn new(value: f64) -> Result<Self, String> {
        if value <= 0.0 {
            return Err(format!("uncertainty must be positive, got {}", value));
        }
        Ok(Uncertainty(value))
    }

    pub fn value(&self) -> f64 {
        self.0
    }
}

// Composite type with validated components
#[derive(Debug, Clone, PartialEq)]
pub struct Measurement {
    value: f64,
    uncertainty: Uncertainty,
    quality_score: QualityScore,
}

impl Measurement {
    /// Smart constructor with cross-field validation
    pub fn new(
        value: f64,
        uncertainty: f64,
        quality_score: f64,
    ) -> Result<Self, String> {
        let unc = Uncertainty::new(uncertainty)?;
        let qual = QualityScore::new(quality_score)?;

        // Cross-field validation
        if uncertainty.abs() > value.abs() * 10.0 {
            return Err(format!(
                "uncertainty {} too large relative to value {}",
                uncertainty, value
            ));
        }

        Ok(Measurement {
            value,
            uncertainty: unc,
            quality_score: qual,
        })
    }

    pub fn value(&self) -> f64 {
        self.value
    }

    pub fn uncertainty(&self) -> &Uncertainty {
        &self.uncertainty
    }

    pub fn quality_score(&self) -> &QualityScore {
        &self.quality_score
    }
}

// Usage
let measurement = Measurement::new(10.0, 0.5, 0.95)?;
// measurement is guaranteed valid - no need to re-check
```

**See also**: domain-modeling.md#pattern-2-smart-constructors-for-invariants

### Pattern 2: State machines with enums

Use enums with associated data to model entity lifecycles.

**Example: Data processing pipeline states**

```rust
use std::collections::HashMap;

// State 1: Raw observations
#[derive(Debug, Clone)]
pub struct RawObservations {
    values: Vec<f64>,
    metadata: HashMap<String, String>,
}

// State 2: Calibrated data
#[derive(Debug, Clone)]
pub struct CalibratedData {
    measurements: Vec<Measurement>,
    calibration_params: HashMap<String, f64>,
}

// State 3: Inferred results
#[derive(Debug, Clone)]
pub struct InferredResults {
    parameters: HashMap<String, f64>,
    log_likelihood: f64,
    convergence_info: HashMap<String, bool>,
}

// State 4: Validated model
#[derive(Debug, Clone)]
pub struct ValidatedModel {
    parameters: HashMap<String, f64>,
    diagnostics: HashMap<String, f64>,
    validation_timestamp: String,
}

// State machine as enum
#[derive(Debug, Clone)]
pub enum DataState {
    Raw(RawObservations),
    Calibrated(CalibratedData),
    Inferred(InferredResults),
    Validated(ValidatedModel),
}
```

**State transitions as functions**

```rust
use thiserror::Error;

// Error types for each transition
#[derive(Error, Debug)]
pub enum CalibrationError {
    #[error("quality {0} below threshold {1}")]
    QualityBelowThreshold(f64, f64),
    #[error("calibration failed: {0}")]
    Failed(String),
}

#[derive(Error, Debug)]
pub enum InferenceError {
    #[error("inference failed: {0}")]
    Failed(String),
}

#[derive(Error, Debug)]
pub enum ValidationError {
    #[error("diagnostics failed: {0:?}")]
    DiagnosticsFailed(HashMap<String, f64>),
}

// Transition 1: Raw → Calibrated
pub fn calibrate<F>(
    calibration_model: F,
    quality_threshold: f64,
    raw: RawObservations,
) -> Result<CalibratedData, CalibrationError>
where
    F: Fn(f64, &HashMap<String, String>) -> (f64, f64, f64),
{
    let mut measurements = Vec::new();

    for &raw_value in &raw.values {
        let (value, uncertainty, quality) = calibration_model(raw_value, &raw.metadata);

        if quality < quality_threshold {
            return Err(CalibrationError::QualityBelowThreshold(
                quality,
                quality_threshold,
            ));
        }

        measurements.push(
            Measurement::new(value, uncertainty, quality)
                .map_err(|e| CalibrationError::Failed(e))?,
        );
    }

    Ok(CalibratedData {
        measurements,
        calibration_params: [("model".to_string(), 1.0)]
            .iter()
            .cloned()
            .collect(),
    })
}

// Transition 2: Calibrated → Inferred
pub fn infer<F>(
    inference_algorithm: F,
    calibrated: CalibratedData,
) -> Result<InferredResults, InferenceError>
where
    F: Fn(&[Measurement]) -> (HashMap<String, f64>, f64, HashMap<String, bool>),
{
    let (parameters, log_likelihood, convergence) =
        inference_algorithm(&calibrated.measurements);

    Ok(InferredResults {
        parameters,
        log_likelihood,
        convergence_info: convergence,
    })
}

// Transition 3: Inferred → Validated
pub fn validate_model(
    validation_metrics: &HashMap<String, Box<dyn Fn(&HashMap<String, f64>) -> f64>>,
    inferred: InferredResults,
) -> Result<ValidatedModel, ValidationError> {
    let mut diagnostics = HashMap::new();

    for (name, metric_fn) in validation_metrics {
        diagnostics.insert(name.clone(), metric_fn(&inferred.parameters));
    }

    if !diagnostics.values().all(|&v| v > 0.9) {
        return Err(ValidationError::DiagnosticsFailed(diagnostics));
    }

    Ok(ValidatedModel {
        parameters: inferred.parameters,
        diagnostics,
        validation_timestamp: chrono::Utc::now().to_rfc3339(),
    })
}
```

**See also**: domain-modeling.md#pattern-3-state-machines-for-entity-lifecycles

### Pattern 3: Workflows with dependencies

Model workflows as functions with explicit dependencies using function parameters or traits.

**Example: Complete processing workflow**

```rust
use thiserror::Error;

// Dependency types as trait bounds
pub trait CalibrationModel {
    fn calibrate(&self, raw: f64, metadata: &HashMap<String, String>) -> (f64, f64, f64);
}

pub trait InferenceAlgorithm {
    fn infer(
        &self,
        measurements: &[Measurement],
    ) -> (HashMap<String, f64>, f64, HashMap<String, bool>);
}

// Unified error type for workflow
#[derive(Error, Debug)]
pub enum ProcessingError {
    #[error("calibration: {0}")]
    Calibration(#[from] CalibrationError),
    #[error("inference: {0}")]
    Inference(#[from] InferenceError),
    #[error("validation: {0}")]
    Validation(#[from] ValidationError),
}

// Complete processing workflow with dependency injection
pub fn process_observations<C, I>(
    calibration_model: &C,
    quality_threshold: f64,
    inference_algorithm: &I,
    validation_metrics: &HashMap<String, Box<dyn Fn(&HashMap<String, f64>) -> f64>>,
    raw: RawObservations,
) -> Result<ValidatedModel, ProcessingError>
where
    C: CalibrationModel,
    I: InferenceAlgorithm,
{
    // Compose steps using ? operator for error propagation
    let calibrated = calibrate(
        |v, m| calibration_model.calibrate(v, m),
        quality_threshold,
        raw,
    )?;

    let inferred = infer(
        |measurements| inference_algorithm.infer(measurements),
        calibrated,
    )?;

    let validated = validate_model(validation_metrics, inferred)?;

    Ok(validated)
}
```

**See also**:
- domain-modeling.md#pattern-4-workflows-as-type-safe-pipelines
- architectural-patterns.md#workflow-pipeline-architecture

### Pattern 4: Aggregates with consistency

Group related entities that must change together atomically.

**Example: Dataset aggregate with observations**

```rust
use chrono::{DateTime, Utc};

// Entity within aggregate
#[derive(Debug, Clone)]
pub struct Observation {
    timestamp: DateTime<Utc>,
    value: f64,
    metadata: HashMap<String, String>,
}

// Value object for aggregate ID
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct DatasetId(String);

impl DatasetId {
    pub fn new(id: String) -> Result<Self, String> {
        if id.is_empty() {
            return Err("dataset ID cannot be empty".to_string());
        }
        Ok(DatasetId(id))
    }

    pub fn value(&self) -> &str {
        &self.0
    }
}

// Computed value object
#[derive(Debug, Clone)]
pub struct SummaryStatistics {
    count: usize,
    mean: f64,
    std_dev: f64,
    min_value: f64,
    max_value: f64,
}

// Aggregate root
#[derive(Debug, Clone)]
pub struct Dataset {
    id: DatasetId,
    observations: Vec<Observation>,
    statistics: SummaryStatistics,
    protocol_id: String, // Reference to other aggregate (by ID only)
}

impl Dataset {
    /// Smart constructor that enforces invariants
    pub fn new(
        id: DatasetId,
        observations: Vec<Observation>,
        protocol_id: String,
    ) -> Result<Self, String> {
        if observations.is_empty() {
            return Err("must provide at least one observation".to_string());
        }

        // Sort chronologically
        let mut sorted = observations;
        sorted.sort_by_key(|obs| obs.timestamp);

        // Compute statistics
        let values: Vec<f64> = sorted.iter().map(|obs| obs.value).collect();
        let count = values.len();
        let mean = values.iter().sum::<f64>() / count as f64;
        let variance = values.iter()
            .map(|&v| (v - mean).powi(2))
            .sum::<f64>() / count as f64;

        let statistics = SummaryStatistics {
            count,
            mean,
            std_dev: variance.sqrt(),
            min_value: values.iter().copied().fold(f64::INFINITY, f64::min),
            max_value: values.iter().copied().fold(f64::NEG_INFINITY, f64::max),
        };

        Ok(Dataset {
            id,
            observations: sorted,
            statistics,
            protocol_id,
        })
    }

    /// Update operation that maintains invariants (returns new dataset)
    pub fn add_observation(self, observation: Observation) -> Result<Self, String> {
        let mut new_observations = self.observations;
        new_observations.push(observation);
        Dataset::new(self.id, new_observations, self.protocol_id)
    }

    pub fn statistics(&self) -> &SummaryStatistics {
        &self.statistics
    }
}
```

**See also**: domain-modeling.md#pattern-5-aggregates-as-consistency-boundaries

### Pattern 5: Error classification

Distinguish domain errors from infrastructure errors using error enums.

**Example: Error type hierarchy**

```rust
use thiserror::Error;

// Domain errors: Part of problem domain logic
#[derive(Error, Debug)]
pub enum DomainValidationError {
    #[error("{field} out of range: {message}")]
    OutOfRange { field: String, message: String },
    #[error("{field} has invalid format: {message}")]
    InvalidFormat { field: String, message: String },
    #[error("{field} is required")]
    MissingRequired { field: String },
}

#[derive(Error, Debug)]
pub enum DomainCalibrationError {
    #[error("calibration failed: {reason}, quality {quality_score} below threshold {threshold}")]
    BelowThreshold {
        reason: String,
        quality_score: f64,
        threshold: f64,
    },
}

#[derive(Error, Debug)]
pub enum DomainConvergenceError {
    #[error("model failed to converge after {iterations} iterations, final loss: {final_loss}")]
    FailedToConverge {
        iterations: usize,
        final_loss: f64,
    },
}

// Infrastructure errors: Technical/architectural concerns
#[derive(Error, Debug)]
pub enum InfrastructureDatabaseError {
    #[error("database operation '{operation}' failed: {exception}")]
    OperationFailed { operation: String, exception: String },
}

#[derive(Error, Debug)]
pub enum InfrastructureNetworkError {
    #[error("network request to '{url}' failed with status {status_code:?}: {exception}")]
    RequestFailed {
        url: String,
        status_code: Option<u16>,
        exception: String,
    },
}

// Unified error types
#[derive(Error, Debug)]
pub enum DomainError {
    #[error(transparent)]
    Validation(#[from] DomainValidationError),
    #[error(transparent)]
    Calibration(#[from] DomainCalibrationError),
    #[error(transparent)]
    Convergence(#[from] DomainConvergenceError),
}

#[derive(Error, Debug)]
pub enum InfrastructureError {
    #[error(transparent)]
    Database(#[from] InfrastructureDatabaseError),
    #[error(transparent)]
    Network(#[from] InfrastructureNetworkError),
}

#[derive(Error, Debug)]
pub enum WorkflowError {
    #[error(transparent)]
    Domain(#[from] DomainError),
    #[error(transparent)]
    Infrastructure(#[from] InfrastructureError),
}
```

**See also**: domain-modeling.md#pattern-6-domain-errors-vs-infrastructure-errors

### Complete example: Temporal data processing

**Key takeaways**:

1. **Types enforce invariants**: Newtypes prevent mixing incompatible values
2. **State machines explicit**: Enum variants for each pipeline stage
3. **Dependencies via traits**: Type-safe dependency injection
4. **Errors typed**: Domain vs Infrastructure distinction with thiserror
5. **Zero-cost abstractions**: Rust compiles to efficient code
6. **Ownership guarantees**: Compile-time memory safety

**See also**:
- domain-modeling.md for pattern details
- architectural-patterns.md for application structure
- railway-oriented-programming.md for Result composition

## Error handling

Rust error handling centers on `Result<T, E>` and the question mark operator `?` for composable, type-safe error propagation.
This section describes designing error types aligned with FDM principles.

### Result<T, E> and the ? operator

Use `Result<T, E>` for operations that can fail.
The `?` operator propagates errors up the call stack, converting upstream errors via `From` trait implementations.

```rust
use std::fs;
use std::io;

fn read_config(path: &str) -> Result<String, io::Error> {
    // ? operator: if Err, return early; if Ok, unwrap value
    let contents = fs::read_to_string(path)?;
    Ok(contents)
}

// Compose multiple operations that can fail
fn parse_config(path: &str) -> Result<Config, ConfigError> {
    let contents = read_config(path)?; // io::Error -> ConfigError via From
    let config = serde_json::from_str(&contents)?; // serde_json::Error -> ConfigError via From
    Ok(config)
}
```

### Library error types: thiserror

Libraries should define situation-specific error structs using `thiserror` to reduce boilerplate.

**Key principles**:

1. Create situation-specific structs, not generic ErrorKind enums in public API
2. Include `Backtrace` field for debugging (captured when `RUST_BACKTRACE=1`)
3. Store upstream error cause via `#[source]` for error chains
4. Expose `is_xxx()` helper methods for classification, not raw ErrorKind
5. Implement `Display` with context, `Error` trait, and `From` conversions

**Pattern: Simple library error**

```rust
use std::backtrace::Backtrace;

#[derive(Debug, thiserror::Error)]
#[error("configuration loading failed")]
pub struct ConfigurationError {
    backtrace: Backtrace,
}

impl ConfigurationError {
    pub(crate) fn new() -> Self {
        Self {
            backtrace: Backtrace::capture(),
        }
    }
}
```

**Pattern: Library error with multiple failure modes**

Use internal `ErrorKind` enum not exposed in public API.
Provide `is_xxx()` methods for callers to classify errors.

```rust
use std::backtrace::Backtrace;
use std::path::{Path, PathBuf};

// Internal enum - not part of public API
#[derive(Debug)]
pub(crate) enum ErrorKind {
    Io(std::io::Error),
    Parse(serde_json::Error),
    Validation(String),
}

#[derive(Debug, thiserror::Error)]
pub struct ConfigError {
    kind: ErrorKind,
    config_path: PathBuf,
    backtrace: Backtrace,
}

impl ConfigError {
    // Public helpers for error classification
    pub fn is_io(&self) -> bool {
        matches!(self.kind, ErrorKind::Io(_))
    }

    pub fn is_parse(&self) -> bool {
        matches!(self.kind, ErrorKind::Parse(_))
    }

    pub fn is_validation(&self) -> bool {
        matches!(self.kind, ErrorKind::Validation(_))
    }

    pub fn config_path(&self) -> &Path {
        &self.config_path
    }

    // Internal constructors
    pub(crate) fn new_io(err: std::io::Error, path: PathBuf) -> Self {
        Self {
            kind: ErrorKind::Io(err),
            config_path: path,
            backtrace: Backtrace::capture(),
        }
    }

    pub(crate) fn new_validation(msg: String, path: PathBuf) -> Self {
        Self {
            kind: ErrorKind::Validation(msg),
            config_path: path,
            backtrace: Backtrace::capture(),
        }
    }
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "configuration error at {}: ", self.config_path.display())?;
        match &self.kind {
            ErrorKind::Io(e) => write!(f, "I/O error: {}", e)?,
            ErrorKind::Parse(e) => write!(f, "parse error: {}", e)?,
            ErrorKind::Validation(msg) => write!(f, "validation failed: {}", msg)?,
        }
        write!(f, "\n{}", self.backtrace)
    }
}

impl std::error::Error for ConfigError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match &self.kind {
            ErrorKind::Io(e) => Some(e),
            ErrorKind::Parse(e) => Some(e),
            ErrorKind::Validation(_) => None,
        }
    }
}
```

**Why this pattern**:
- Callers handle specific errors via `is_xxx()` without coupling to internal representation
- Library can add error kinds without breaking API (new `is_xxx()` methods are additive)
- Backtrace captured at error construction for debugging async code
- Error chains preserved via `source()` for root cause analysis

**Using thiserror to reduce boilerplate**:

```rust
use std::backtrace::Backtrace;

#[derive(Debug, thiserror::Error)]
pub enum ProcessingError {
    #[error("calibration failed: quality {quality_score} below threshold {threshold}")]
    CalibrationFailed {
        quality_score: f64,
        threshold: f64,
        backtrace: Backtrace,
    },

    #[error("inference failed after {iterations} iterations")]
    InferenceFailed {
        iterations: usize,
        backtrace: Backtrace,
    },

    #[error("I/O error")]
    Io {
        #[from]
        source: std::io::Error,
        backtrace: Backtrace,
    },
}
```

### Application error types: anyhow

Applications (binaries, not libraries) should use `anyhow` for simplified error handling.
The `anyhow::Result<T>` type automatically converts any error implementing `std::error::Error`.

```rust
use anyhow::{Context, Result};

fn load_and_process_config(path: &str) -> Result<ProcessedConfig> {
    // Automatically converts ConfigError, IoError, etc.
    let config = load_config(path)
        .context("failed to load configuration")?;

    let processed = process_config(&config)
        .context("failed to process configuration")?;

    Ok(processed)
}
```

### Context propagation with .context()

Add context as errors propagate to explain what operation failed.

```rust
use anyhow::{Context, Result};

fn process_pipeline(input_path: &str) -> Result<Summary> {
    let raw_data = read_file(input_path)
        .with_context(|| format!("failed to read input file: {}", input_path))?;

    let calibrated = calibrate(raw_data)
        .context("calibration step failed")?;

    let validated = validate(calibrated)
        .context("validation step failed")?;

    Ok(validated.summary())
}
```

### Error composition and transformation

**Map errors with .map_err()**

```rust
fn load_config(path: &str) -> Result<Config, AppError> {
    let contents = std::fs::read_to_string(path)
        .map_err(|e| AppError::IoFailed {
            path: path.to_string(),
            source: e,
        })?;

    serde_json::from_str(&contents)
        .map_err(|e| AppError::ParseFailed {
            path: path.to_string(),
            source: e,
        })
}
```

**Compose with From trait for automatic conversion**

```rust
#[derive(Error, Debug)]
pub enum WorkflowError {
    #[error(transparent)]
    Calibration(#[from] CalibrationError),
    #[error(transparent)]
    Inference(#[from] InferenceError),
    #[error(transparent)]
    Validation(#[from] ValidationError),
}

// ? automatically converts via From
fn workflow() -> Result<Output, WorkflowError> {
    let cal = calibrate()?;  // CalibrationError -> WorkflowError
    let inf = infer(cal)?;   // InferenceError -> WorkflowError
    let val = validate(inf)?; // ValidationError -> WorkflowError
    Ok(val)
}
```

### Railway-oriented programming with Result

Use applicative patterns to collect multiple errors rather than failing on first error.

```rust
// Sequential (fail-fast): stops at first error
fn validate_user_sequential(
    email: &str,
    name: &str,
    age: i32,
) -> Result<ValidUser, ValidationError> {
    let email = validate_email(email)?;  // Stops here if invalid
    let name = validate_name(name)?;
    let age = validate_age(age)?;
    Ok(ValidUser { email, name, age })
}

// Parallel (collect all errors): accumulates all validation errors
fn validate_user_parallel(
    email: &str,
    name: &str,
    age: i32,
) -> Result<ValidUser, Vec<ValidationError>> {
    let email_result = validate_email(email);
    let name_result = validate_name(name);
    let age_result = validate_age(age);

    let mut errors = Vec::new();

    let email = match email_result {
        Ok(e) => e,
        Err(e) => {
            errors.push(e);
            return Err(errors);
        }
    };

    let name = match name_result {
        Ok(n) => n,
        Err(e) => {
            errors.push(e);
            return Err(errors);
        }
    };

    let age = match age_result {
        Ok(a) => a,
        Err(e) => {
            errors.push(e);
            return Err(errors);
        }
    };

    if !errors.is_empty() {
        return Err(errors);
    }

    Ok(ValidUser { email, name, age })
}
```

For more sophisticated applicative patterns, consider libraries like `validation` or `garde`.

See `~/.claude/commands/preferences/railway-oriented-programming.md` for comprehensive patterns including bind, apply, and effect signatures.

### Error handling best practices

1. **Use Result, not panic**: Reserve `panic!`, `unwrap()`, and `expect()` for programmer errors (bugs), not recoverable failures
2. **Capture backtraces**: Include `Backtrace` in library error types for debugging async and complex call chains
3. **Add context as errors propagate**: Use `.context()` or `.with_context()` to explain what operation failed
4. **Design errors for callers**: Provide `is_xxx()` helpers and contextual accessors
5. **Distinguish error categories**: Separate domain errors (expected) from infrastructure errors (technical) from panics (bugs)
6. **Compose errors via From**: Implement `From<UpstreamError>` to enable `?` operator automatic conversions
7. **Document failure modes**: Include `# Errors` sections in doc comments

Domain errors become part of state machine documentation, workflow specifications, and aggregate invariants.
See Pattern 5 above for complete error classification examples.

## Panic semantics

Panics in Rust are not exceptions or error communication.
A panic means program termination - stop execution immediately because the system entered an invalid state from which it cannot meaningfully continue.

### Core principle

Following Microsoft guideline M-PANIC-IS-STOP: panics suggest immediate program termination.
Although code must be panic-safe (survived panics may not lead to inconsistent state), invoking a panic means this program should stop now.
Never use panics to communicate errors upstream or as control flow.

### When panics are appropriate

Panics are appropriate only when:

**1. Detected programming errors (contract violations)** - When an unrecoverable programming error has been detected, code must panic to request program termination.
No Error type should be introduced or returned, as such errors cannot be acted upon at runtime.

```rust
// Contract violation detected during existing check
pub fn divide_non_zero(numerator: i32, denominator: i32) -> i32 {
    assert!(denominator != 0, "denominator must be non-zero");
    numerator / denominator
}

// Broken invariant in internal state
pub fn get_validated_data(&self) -> &Data {
    self.validated_data.as_ref()
        .expect("invariant broken: validated_data must be Some after validation")
}

// Index known to be in bounds by construction
fn process_matrix_cell(&self, row: usize, col: usize) -> f64 {
    debug_assert!(row < self.rows && col < self.cols,
        "programming error: indices out of bounds");
    self.data[row * self.cols + col]
}
```

**2. Const contexts** - Operations invoked from const contexts that cannot return Result must panic on failure.

```rust
const CONFIG_VERSION: u32 = const {
    parse_version("1.0.0").unwrap()  // Must be valid at compile time
};
```

**3. User-requested panics** - When providing API methods explicitly documented to panic, typically unwrap-style convenience methods.

```rust
impl QualityScore {
    /// Returns the inner value.
    ///
    /// Panics if the Result is an error.
    pub fn unwrap(self) -> f64 {
        match self {
            QualityScore::Valid(value) => value,
            QualityScore::Invalid(reason) => panic!("called unwrap on invalid score: {}", reason),
        }
    }
}
```

**4. Poison detection** - When encountering a poisoned lock, which signals another thread already panicked.

```rust
let data = lock.lock()
    .unwrap();  // Appropriate: poisoned lock indicates corrupted state
```

### When panics are inappropriate

Never use panics for these scenarios - use Result instead:

**1. User input validation** - Parseable data from users should return validation errors, not panic.

```rust
// BAD: User input should not panic
pub fn create_email(input: &str) -> EmailAddress {
    assert!(input.contains('@'), "email must contain @");
    EmailAddress(input.to_string())
}

// GOOD: Return Result for validation
pub fn create_email(input: &str) -> Result<EmailAddress, ValidationError> {
    if !input.contains('@') {
        return Err(ValidationError::InvalidFormat {
            field: "email".to_string(),
            message: "must contain @".to_string(),
        });
    }
    Ok(EmailAddress(input.to_string()))
}
```

**2. I/O operations** - File operations, network requests, database queries should return Result.

**3. Parseable data** - Parsing structured data that might be malformed should return Result.

### Integration with FDM error classification

Panic semantics align with three-tier error classification:

**Domain errors → Result** - Expected outcomes of domain operations that subject matter experts recognize.

```rust
#[derive(Error, Debug)]
pub enum CalibrationError {
    #[error("quality {quality_score} below threshold {threshold}")]
    BelowThreshold { quality_score: f64, threshold: f64 },
}

pub fn calibrate(
    quality_threshold: f64,
    raw: RawObservations,
) -> Result<CalibratedData, CalibrationError> {
    // Domain error: quality too low (not a panic)
    if quality_score < quality_threshold {
        return Err(CalibrationError::BelowThreshold {
            quality_score,
            threshold: quality_threshold,
        });
    }
    Ok(CalibratedData { /* ... */ })
}
```

**Infrastructure errors → Result or propagate** - Technical failures in supporting systems.

**Panics → true programming bugs only** - Broken invariants, impossible states reached.

```rust
pub struct Dataset {
    observations: Vec<Observation>,
    statistics: SummaryStatistics,
}

impl Dataset {
    /// Smart constructor enforces invariant: at least one observation
    pub fn new(observations: Vec<Observation>) -> Result<Self, String> {
        if observations.is_empty() {
            return Err("must provide at least one observation".to_string());
        }
        Ok(Self {
            observations,
            statistics: Self::compute_stats(&observations),
        })
    }

    /// This method's precondition is guaranteed by smart constructor
    pub fn mean(&self) -> f64 {
        // Panic is appropriate: empty dataset violates invariant
        assert!(!self.observations.is_empty(),
            "invariant broken: dataset cannot be empty");
        self.statistics.mean
    }
}
```

### The relationship between types and panics

Good type design reduces panic surface by making invalid states unrepresentable.

**Anti-pattern: Runtime checks with panics**

```rust
pub struct PositiveFloat(f64);

impl PositiveFloat {
    pub fn new(value: f64) -> Self {
        assert!(value > 0.0, "must be positive");
        PositiveFloat(value)
    }

    pub fn value(&self) -> f64 {
        assert!(self.0 > 0.0, "invariant: must be positive");  // Redundant!
        self.0
    }
}
```

**Better: Smart constructor guarantees invariant**

```rust
pub struct PositiveFloat(f64);

impl PositiveFloat {
    /// Smart constructor validates once
    pub fn new(value: f64) -> Result<Self, String> {
        if value <= 0.0 {
            return Err(format!("must be positive, got {}", value));
        }
        Ok(PositiveFloat(value))
    }

    /// No assertion needed: constructor guarantees invariant
    pub fn value(&self) -> f64 {
        self.0  // Safe by construction
    }
}
```

**Best: Type system enforces constraint**

```rust
use std::num::NonZeroU32;

pub struct PositiveCount(NonZeroU32);

impl PositiveCount {
    pub fn new(value: u32) -> Result<Self, String> {
        NonZeroU32::new(value)
            .map(PositiveCount)
            .ok_or_else(|| "count must be positive".to_string())
    }

    pub fn value(&self) -> u32 {
        self.0.get()  // Type system guarantees non-zero
    }
}
```

### Decision tree for error handling

When designing error handling, follow this decision process:

**Step 1: Can the caller prevent this?**
- Yes, with correct input → Document precondition, return Result for validation
- No, it's a logic error → Panic

**Step 2: Would a subject matter expert recognize this error?**
- Yes → Domain error, model explicitly with Result
- No → Continue to step 3

**Step 3: Can the program meaningfully continue?**
- Yes → Infrastructure error, consider Result or propagate exception
- No → Panic

### Make it correct by construction

While panicking on detected programming error is the least bad option, your panic might still ruin someone's day.
For any user input or calling sequence that would otherwise panic, explore using the type system to avoid panicking code paths altogether.

```rust
// Anti-pattern: panics possible
pub fn process_data(values: Vec<f64>, count: usize) -> Summary {
    assert!(count > 0, "count must be positive");
    assert!(values.len() == count, "length must match count");
    // ...
}

// Better: smart constructor prevents panics
pub struct ValidatedInput {
    values: NonEmptyVec<f64>,
}

impl ValidatedInput {
    pub fn new(values: Vec<f64>) -> Result<Self, ValidationError> {
        NonEmptyVec::new(values)
            .map(|v| Self { values: v })
            .map_err(|_| ValidationError::EmptyInput)
    }
}

pub fn process_data(input: ValidatedInput) -> Summary {
    // No panics possible: type guarantees valid state
    // ...
}
```

**See also**:
- domain-modeling.md Pattern 6 for error classification framework
- railway-oriented-programming.md for Result composition patterns
- architectural-patterns.md for effect isolation at boundaries
- Microsoft Rust Guidelines M-PANIC-IS-STOP and M-PANIC-ON-BUG

## API design

This section integrates Microsoft's pragmatic Rust guidelines with FDM principles to create APIs that are discoverable, testable, and type-safe.

### Naming conventions

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

### Function organization

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

### Builder pattern

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

### Input flexibility

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

### Avoiding visible complexity

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

### API design principles summary

These principles support FDM by:
- Making domain vocabulary explicit in type names
- Keeping core operations discoverable without trait imports
- Providing testability through enums rather than trait objects
- Hiding complexity behind simple, type-safe interfaces
- Using builders for complex construction with validation
- Accepting flexible input types without performance cost

## Testing

### Unit tests and test organization

Write unit tests in the same file using `#[cfg(test)]` modules.
This keeps tests close to implementation and allows testing private functions.

```rust
pub fn process_data(input: &[u8]) -> Result<Vec<u8>, ProcessingError> {
    // implementation
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_process_data_valid_input() {
        let input = b"test data";
        let result = process_data(input);
        assert!(result.is_ok());
    }

    #[test]
    fn test_process_data_invalid_input() {
        let input = b"";
        let result = process_data(input);
        assert!(result.is_err());
    }
}
```

Create integration tests in `tests/` directory.
These verify public API works correctly without access to private implementation details.

### Mockable I/O pattern (sans-io)

Any user-facing type doing I/O or system calls with side effects should be mockable to these effects.
This includes file and network access, clocks, entropy sources.
More generally, any operation that is non-deterministic, reliant on external state, depending on hardware or environment, or otherwise fragile should be mockable.

Libraries supporting inherent mocking should implement it using runtime abstraction via enum with `Native` and `Mock` variants.

**Pattern: Library returns (Lib, MockHandle) tuple**

```rust
pub struct Library {
    core: LibraryCore  // Encapsulates syscalls, I/O
}

impl Library {
    pub fn new() -> Self {
        Self {
            core: LibraryCore::Native,
        }
    }

    #[cfg(feature = "test-util")]
    pub fn new_mocked() -> (Self, MockCtrl) {
        let mock_ctrl = MockCtrl::new();
        let lib = Self {
            core: LibraryCore::Mocked(mock_ctrl.clone()),
        };
        (lib, mock_ctrl)
    }

    pub fn read_data(&self) -> Vec<u8> {
        self.core.read_data()
    }
}

// Dispatches calls either to operating system or mocking controller
enum LibraryCore {
    Native,

    #[cfg(feature = "test-util")]
    Mocked(MockCtrl),
}

impl LibraryCore {
    fn read_data(&self) -> Vec<u8> {
        match self {
            Self::Native => {
                // Actual I/O operation
                std::fs::read("data.bin").unwrap_or_default()
            }
            #[cfg(feature = "test-util")]
            Self::Mocked(m) => m.read_data(),
        }
    }
}

#[cfg(feature = "test-util")]
#[derive(Clone)]
pub struct MockCtrl {
    inner: std::sync::Arc<MockCtrlInner>,
}

#[cfg(feature = "test-util")]
impl MockCtrl {
    fn new() -> Self {
        Self {
            inner: std::sync::Arc::new(MockCtrlInner {
                data: std::sync::Mutex::new(Vec::new()),
            }),
        }
    }

    pub fn set_data(&self, data: Vec<u8>) {
        *self.inner.data.lock().unwrap() = data;
    }

    fn read_data(&self) -> Vec<u8> {
        self.inner.data.lock().unwrap().clone()
    }
}

#[cfg(feature = "test-util")]
struct MockCtrlInner {
    data: std::sync::Mutex<Vec<u8>>,
}
```

**Why tuple return `(Lib, MockHandle)` instead of accepting MockHandle**: Prevents state ambiguity if multiple instances shared a single controller.

**When to use traits vs enums for abstraction**:

1. **Enum with Native/Mock variants (preferred for testing)**: If the other implementation is only concerned with providing sans-io implementation for testing, implement your type as an enum.
2. **Traits (for extensibility)**: If users are expected to provide custom implementations beyond just testing, introduce narrow traits.
3. **Dynamic dispatch (last resort)**: Only when generics become a nesting problem, consider `dyn Trait`.

**Sans-io for one-shot I/O**: Functions that only need one-shot I/O during initialization should accept `impl Read` or `impl Write` rather than concrete file types.

```rust
// Good: Accepts File, TcpStream, &[u8], and many more
fn parse_data(data: impl std::io::Read) -> Result<Data, ParseError> {
    // ...
}
```

For async functions targeting multiple runtimes, use `futures::io::AsyncRead` and `futures::io::AsyncWrite`.

### Feature-gated test utilities

Testing functionality must be guarded behind a feature flag to prevent production builds from accidentally bypassing safety checks.

**Use single feature flag named `test-util`**

```toml
# Cargo.toml
[features]
test-util = []
```

**What to gate behind `test-util`**:
- Mocking functionality (mock controllers, mock variants)
- Ability to inspect sensitive data
- Safety check overrides
- Fake data generators

```rust
impl HttpClient {
    pub fn get(&self, url: &str) -> Result<Response, Error> {
        // Normal implementation with certificate verification
    }

    #[cfg(feature = "test-util")]
    pub fn bypass_certificate_checks(&mut self) {
        // Only available in test builds
    }
}

#[cfg(feature = "test-util")]
pub fn generate_fake_user(seed: u64) -> User {
    // Deterministic fake data generation for tests
}
```

### Testing domain models from FDM patterns

#### Testing smart constructor validation

Smart constructors enforce invariants at creation time.
Test both valid construction and validation failures.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quality_score_accepts_valid_range() {
        let score = QualityScore::new(0.5);
        assert!(score.is_ok());
        assert_eq!(score.unwrap().value(), 0.5);
    }

    #[test]
    fn quality_score_rejects_above_one() {
        let score = QualityScore::new(1.5);
        assert!(score.is_err());
    }

    #[test]
    fn measurement_enforces_cross_field_validation() {
        // Uncertainty too large relative to value should fail
        let result = Measurement::new(10.0, 150.0, 0.95);
        assert!(result.is_err());
    }
}
```

#### Testing state machine transitions

Test valid transitions and verify impossible transitions are prevented by the type system.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_transition_raw_to_calibrated() {
        let raw = RawObservations {
            values: vec![1.0, 2.0, 3.0],
            metadata: HashMap::new(),
        };

        let calibration_model = |v: f64, _: &HashMap<String, String>| {
            (v * 1.1, v * 0.05, 0.95)
        };

        let result = calibrate(calibration_model, 0.8, raw);
        assert!(result.is_ok());
    }

    #[test]
    fn calibration_fails_below_quality_threshold() {
        let raw = RawObservations {
            values: vec![1.0],
            metadata: HashMap::new(),
        };

        // Model returns quality below threshold
        let calibration_model = |v: f64, _: &HashMap<String, String>| {
            (v, v * 0.05, 0.5)  // quality = 0.5
        };

        let result = calibrate(calibration_model, 0.8, raw);
        assert!(result.is_err());
        match result {
            Err(CalibrationError::QualityBelowThreshold(quality, threshold)) => {
                assert_eq!(quality, 0.5);
                assert_eq!(threshold, 0.8);
            }
            _ => panic!("Expected QualityBelowThreshold error"),
        }
    }

    // Note: Invalid transitions like "deploy unvalidated model" are
    // prevented by the type system and won't compile, so no test needed
}
```

#### Property-based testing for invariants

Use `proptest` or `quickcheck` to verify invariants hold across many generated examples.

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn quality_score_always_in_range(value in 0.0f64..=1.0) {
        let score = QualityScore::new(value).unwrap();
        prop_assert!(score.value() >= 0.0 && score.value() <= 1.0);
    }

    #[test]
    fn dataset_statistics_consistent(
        values in prop::collection::vec(any::<f64>(), 1..100)
    ) {
        let observations: Vec<Observation> = values.iter().map(|&v| {
            Observation {
                timestamp: Utc::now(),
                value: v,
                metadata: HashMap::new(),
            }
        }).collect();

        let dataset = Dataset::new(
            DatasetId::new("test".to_string()).unwrap(),
            observations,
            "protocol-001".to_string(),
        ).unwrap();

        let stats = dataset.statistics();
        prop_assert_eq!(stats.count, values.len());

        // Mean should be between min and max
        prop_assert!(stats.mean >= stats.min_value);
        prop_assert!(stats.mean <= stats.max_value);
    }
}
```

Property-based testing is especially valuable for:
- Smart constructor invariants (value ranges, format constraints)
- Aggregate consistency (computed values match underlying data)
- Workflow composition (chaining operations maintains type safety)
- Round-trip properties (serialize then deserialize equals original)

#### Testing domain errors vs infrastructure errors

Test that domain errors are returned in expected scenarios and contain appropriate context.

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn domain_error_calibration_low_quality() {
        let raw = create_low_quality_observations();
        let result = calibrate(calibration_model, 0.95, raw);

        assert!(result.is_err());
        let err = result.unwrap_err();

        match err {
            CalibrationError::QualityBelowThreshold { quality_score, threshold } => {
                assert!(quality_score < threshold);
            }
            _ => panic!("Expected CalibrationError::QualityBelowThreshold"),
        }
    }

    #[test]
    #[cfg(feature = "test-util")]
    fn infrastructure_error_database_unavailable() {
        let (mut repo, mock) = Repository::new_mocked();
        mock.set_database_available(false);

        let result = repo.save_model(test_model());

        assert!(matches!(
            result,
            Err(InfrastructureError::Database(_))
        ));
    }
}
```

### Test execution and tooling

Use `cargo test` to run all tests before committing.

Consider `cargo nextest` for faster test execution with better output:

```bash
cargo nextest run
```

Benefits: runs tests in parallel more efficiently, cleaner output, better failure reporting, JUnit output for CI.

### Doc tests

Write doc tests to ensure documentation examples stay current and compile.

```rust
/// Processes observations through calibration pipeline.
///
/// # Examples
///
/// ```
/// use my_crate::{RawObservations, calibrate};
///
/// let raw = RawObservations {
///     values: vec![1.0, 2.0, 3.0],
///     metadata: Default::default(),
/// };
///
/// let result = calibrate(
///     |v, _| (v * 1.1, v * 0.05, 0.95),
///     0.8,
///     raw,
/// );
/// assert!(result.is_ok());
/// ```
pub fn calibrate<F>(
    calibration_model: F,
    quality_threshold: f64,
    raw: RawObservations,
) -> Result<CalibratedData, CalibrationError>
where
    F: Fn(f64, &HashMap<String, String>) -> (f64, f64, f64),
{
    // implementation
}
```

Doc tests automatically run with `cargo test` and serve dual purpose as documentation and verification.

### Test coverage

Aim for high test coverage, especially for:
- Public APIs (all public functions should have tests)
- Smart constructor validation logic
- State transition functions
- Error handling paths
- Domain invariant enforcement

Use `cargo tarpaulin` or `cargo llvm-cov` to measure coverage:

```bash
# Using tarpaulin
cargo tarpaulin --out Html

# Using llvm-cov
cargo llvm-cov --html
```

Focus coverage efforts on domain logic, public API surface, error paths, and boundary conditions.
Less critical: simple getters/setters, trivial type conversions, generated code.

### Testing patterns summary

- **Unit tests**: Same file, `#[cfg(test)]` modules, test private implementation
- **Integration tests**: `tests/` directory, verify public API
- **Mockable I/O**: Enum with `Native`/`Mock` variants, feature-gated mock utilities
- **Sans-io**: Accept `impl Read`/`impl Write` for composability
- **Smart constructors**: Test valid construction and validation failures
- **State machines**: Test valid transitions, rely on type system to prevent invalid ones
- **Property-based**: Use proptest/quickcheck to verify invariants
- **Domain errors**: Test expected failure scenarios return appropriate error variants
- **Doc tests**: Ensure examples compile and demonstrate correct usage
- **Coverage**: Focus on domain logic, public APIs, and error paths

## Documentation

Write comprehensive documentation using Rust's canonical doc comment structure.
Documentation is part of the API contract and serves both human readers and AI coding assistants.

### Canonical doc comment sections

Public library items must include canonical doc sections.
Summary sentence always required.
Extended documentation and examples strongly encouraged.
Other sections present when applicable.

```rust
/// Summary sentence of less than 15 words.
///
/// Extended documentation in free form providing context, background,
/// and usage guidance.
/// Explain what the function does and why callers would use it.
/// Reference related functions and types using markdown links like [`OtherType`].
///
/// # Examples
///
/// ```
/// use crate::QualityScore;
///
/// let score = QualityScore::new(0.95)?;
/// assert_eq!(score.value(), 0.95);
/// # Ok::<(), String>(())
/// ```
///
/// # Errors
///
/// Returns `Err` if the value is outside the valid range [0,1].
///
/// # Panics
///
/// Panics if the value is NaN or infinite.
///
/// # Safety
///
/// (For unsafe functions) Callers must ensure that the pointer is
/// valid and properly aligned.
/// The referenced memory must remain valid for the lifetime of the returned reference.
pub fn example_function() -> Result<(), Error> {
    Ok(())
}
```

**Section ordering**: Summary, extended docs, Examples, Errors, Panics, Safety, Abort.

**Summary line requirements**:
- Descriptive and complete, not just repeat function name
- Under 15 words for readability in listings
- Avoid implementation details; focus on what, not how
- Does not end with a period (by convention)

**Examples section**:
- Include runnable code demonstrating common use cases
- Examples run as doc tests with `cargo test`
- Use `#` prefix to hide setup code that clutters rendered example
- Show both success and error cases when relevant

**Errors section**:
- Document all error conditions that can be returned
- Explain when and why each error variant occurs
- Link to error type documentation

**Panics section**:
- Document all conditions that can cause panic
- Required for any function that may panic, even transitively

**Safety section**:
- Required for all `unsafe` functions
- Must list all invariants callers must uphold
- Be explicit and precise about memory safety requirements

### Parameter documentation

Do not create parameter tables.
Explain parameters in natural prose, referencing them with backticks.

```rust
// Bad: Parameter table
/// Copies a file.
///
/// # Parameters
/// - src: The source file
/// - dst: The destination file
fn copy(src: File, dst: File) {}

// Good: Natural prose
/// Copies a file from `src` to `dst`.
///
/// If `dst` already exists, it will be overwritten.
/// The source file is not modified or removed.
/// Metadata like permissions are copied when possible.
fn copy(src: File, dst: File) {}
```

### Module-level documentation

Every public module must have `//!` module documentation.
First sentence must follow same 15-word guideline as item docs.

```rust
//! Contains FFI abstractions for external library integration.
//!
//! This module provides safe wrappers around unsafe FFI calls to the
//! external C library.
//! All functions validate invariants and convert C errors to Rust Result types.
//!
//! # Examples
//!
//! ```
//! use crate::ffi::initialize;
//!
//! initialize()?;
//! # Ok::<(), Box<dyn std::error::Error>>(())
//! ```

pub mod ffi {
    // module contents
}
```

### Re-exported items

Use `#[doc(inline)]` for items re-exported via `pub use` to integrate them into your module's documentation.

```rust
// Re-export items from internal module
#[doc(inline)]
pub use internal::ImportantType;

#[doc(inline)]
pub use internal::important_function;
```

Do not use `#[doc(inline)]` for `std` or third-party types.

### Doc tests as executable examples

Doc tests run with `cargo test` and verify examples stay current.

```rust
/// Validates and creates a new quality score.
///
/// # Examples
///
/// Valid score:
/// ```
/// # use crate::QualityScore;
/// let score = QualityScore::new(0.95)?;
/// assert_eq!(score.value(), 0.95);
/// # Ok::<(), String>(())
/// ```
///
/// Invalid score returns error:
/// ```should_panic
/// # use crate::QualityScore;
/// QualityScore::new(1.5).unwrap(); // panics: out of range
/// ```
pub fn new(value: f64) -> Result<QualityScore, String> {
    // implementation
}
```

**Doc test annotations**:
- `# ` prefix hides lines from rendered docs but they still run
- `# Ok::<(), Error>(())` at end allows using `?` in examples
- `should_panic` attribute for examples that demonstrate panics
- `no_run` for examples that compile but shouldn't execute
- `ignore` for pseudo-code that doesn't compile

### Documentation for FDM patterns

#### Smart constructor validation rules

Document all validation rules in constructor's Errors section.
List each constraint explicitly.

```rust
/// Creates a new validated measurement with quality score.
///
/// # Examples
///
/// ```
/// # use crate::Measurement;
/// let m = Measurement::new(10.0, 0.5, 0.95)?;
/// assert_eq!(m.value(), 10.0);
/// # Ok::<(), String>(())
/// ```
///
/// # Errors
///
/// Returns `Err` if:
/// - `uncertainty` is not positive
/// - `quality_score` is not in range [0,1]
/// - `uncertainty` exceeds `value.abs() * 10.0` (cross-field validation)
pub fn new(
    value: f64,
    uncertainty: f64,
    quality_score: f64,
) -> Result<Self, String> {
    // Smart constructor implementation
}
```

#### State machine transitions

Document valid transitions and their preconditions.

```rust
/// Transitions raw observations to calibrated data.
///
/// This transition applies the calibration model to each raw value and
/// validates that resulting quality scores meet the threshold.
///
/// # Examples
///
/// ```
/// # use crate::{RawObservations, calibrate};
/// let raw = RawObservations { values: vec![1.0, 2.0], metadata: Default::default() };
/// let calibrated = calibrate(|v, _| (v * 1.1, v * 0.05, 0.95), 0.8, raw)?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
///
/// # Errors
///
/// Returns [`CalibrationError::QualityBelowThreshold`] if any measurement's
/// quality score falls below `quality_threshold`.
pub fn calibrate<F>(
    calibration_model: F,
    quality_threshold: f64,
    raw: RawObservations,
) -> Result<CalibratedData, CalibrationError>
where
    F: Fn(f64, &HashMap<String, String>) -> (f64, f64, f64),
{
    // Implementation
}
```

#### Workflow preconditions and postconditions

Document dependencies, ordering requirements, and guarantees.

```rust
/// Processes raw observations through complete validation workflow.
///
/// The workflow executes three stages:
/// 1. Calibration: applies model and validates quality
/// 2. Inference: estimates parameters from calibrated data
/// 3. Validation: checks model diagnostics meet thresholds
///
/// # Examples
///
/// ```
/// # use crate::{process_observations, RawObservations};
/// let raw = RawObservations { values: vec![1.0, 2.0, 3.0], metadata: Default::default() };
/// let model = DefaultCalibrationModel;
/// let algorithm = DefaultInferenceAlgorithm;
/// let metrics = create_validation_metrics();
///
/// let result = process_observations(&model, 0.8, &algorithm, &metrics, raw)?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
///
/// # Errors
///
/// Returns [`ProcessingError::Calibration`] if calibration fails quality checks.
/// Returns [`ProcessingError::Inference`] if inference algorithm fails to converge.
/// Returns [`ProcessingError::Validation`] if model diagnostics fail validation.
///
/// # Type Parameters
///
/// - `C`: Calibration model implementation
/// - `I`: Inference algorithm implementation
pub fn process_observations<C, I>(
    calibration_model: &C,
    quality_threshold: f64,
    inference_algorithm: &I,
    validation_metrics: &HashMap<String, Box<dyn Fn(&HashMap<String, f64>) -> f64>>,
    raw: RawObservations,
) -> Result<ValidatedModel, ProcessingError>
where
    C: CalibrationModel,
    I: InferenceAlgorithm,
{
    // Implementation
}
```

## Performance

### Hot path identification and profiling discipline

Identify hot paths through profiling before optimizing.

Use profiling tools:
- `cargo flamegraph` - generates flame graphs showing where time is spent
- `perf` (Linux) - detailed CPU profiling
- `Instruments` (macOS) - Apple's profiling tools
- `cargo bench` with criterion - statistical benchmarking

```bash
# Generate flame graph
cargo flamegraph --bin my_app

# Run with perf
perf record -g ./target/release/my_app
perf report
```

Only optimize code proven to be performance-critical through profiling.

### Throughput optimization for batch processing

For batch operations processing many items:

```rust
// Good: Process batch in single operation
pub fn process_batch(items: &[Item]) -> Vec<Result> {
    items.par_iter()  // Parallel iteration with rayon
        .map(|item| process_item(item))
        .collect()
}

// Avoid: Individual operations with repeated overhead
pub fn process_one(item: &Item) -> Result {
    // Each call pays setup/teardown cost
}
```

Use `rayon` for data parallelism when operations are independent.

### Async cooperative scheduling and yield points

Async functions must yield regularly to prevent blocking the executor.

```rust
use tokio::task::yield_now;

pub async fn process_large_dataset(data: &[Item]) -> Result<Summary, Error> {
    let mut results = Vec::new();

    for (i, item) in data.iter().enumerate() {
        results.push(process_item(item).await?);

        // Yield every 100 iterations to allow other tasks to run
        if i % 100 == 0 {
            yield_now().await;
        }
    }

    Ok(compute_summary(&results))
}
```

Without yield points, long-running async functions starve other tasks.

### Memory efficiency and allocation strategies

**Reuse allocations**:

```rust
// Good: Reuse buffer across iterations
let mut buffer = Vec::with_capacity(1024);
for item in items {
    buffer.clear();
    process_into_buffer(item, &mut buffer);
    use_buffer(&buffer);
}

// Avoid: Allocate on each iteration
for item in items {
    let buffer = Vec::new();  // New allocation every loop
    process_into_buffer(item, &mut buffer);
}
```

**Pre-allocate when size known**:

```rust
// Good: Pre-allocate with known capacity
let mut results = Vec::with_capacity(items.len());
for item in items {
    results.push(process(item));
}

// Avoid: Repeated reallocations as vector grows
let mut results = Vec::new();
for item in items {
    results.push(process(item));  // May reallocate multiple times
}
```

### Allocator considerations

Consider alternative allocators for specific workloads:

```rust
// Use jemalloc for multi-threaded applications with frequent allocations
#[global_allocator]
static GLOBAL: jemallocator::Jemalloc = jemallocator::Jemalloc;

// Or mimalloc for high-performance scenarios
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;
```

Profile before switching allocators - gains vary by workload.

### Benchmarking and measurement

Use `criterion` for statistical benchmarking:

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_process_data(c: &mut Criterion) {
    let data = create_test_data();

    c.bench_function("process_data", |b| {
        b.iter(|| {
            process_data(black_box(&data))
        })
    });
}

criterion_group!(benches, bench_process_data);
criterion_main!(benches);
```

Run benchmarks:

```bash
cargo bench
```

Criterion provides statistical analysis, outlier detection, and comparison across runs.

### Performance documentation

Document performance characteristics in function docs when relevant:

```rust
/// Processes observations in parallel using all available CPU cores.
///
/// # Performance
///
/// - Time complexity: O(n) where n is the number of observations
/// - Space complexity: O(n) for result storage
/// - Parallelism: Uses rayon thread pool, scales with core count
/// - Allocation: Pre-allocates result vector, no per-item allocation
///
/// For small datasets (< 100 items), use [`process_sequential`] to avoid
/// threading overhead.
pub fn process_parallel(observations: &[Observation]) -> Vec<Result> {
    // Implementation
}
```

## Structured logging

### Message templates over string formatting

Use message templates with named fields rather than string formatting.

```rust
use tracing::{event, Level};

// Good: Message template with structured fields
event!(
    name: "calibration.completed",
    Level::INFO,
    observation.count = measurements.len(),
    quality.threshold = threshold,
    processing.duration_ms = duration.as_millis(),
    "completed calibration of {{observation.count}} observations with quality threshold {{quality.threshold}} in {{processing.duration_ms}}ms"
);

// Avoid: String formatting loses structured data
event!(
    Level::INFO,
    "completed calibration of {} observations with quality threshold {} in {}ms",
    measurements.len(), threshold, duration.as_millis()
);
```

Message templates enable log aggregation, filtering, and analysis tools to extract structured data.

### Event naming conventions

Use hierarchical dot-separated names: `component.operation.outcome`

```rust
// Component.operation.outcome pattern
event!(name: "calibration.process.started", Level::INFO, "starting calibration");
event!(name: "calibration.process.completed", Level::INFO, "calibration succeeded");
event!(name: "calibration.process.failed", Level::WARN, "calibration failed");

event!(name: "database.query.started", Level::DEBUG, "executing query");
event!(name: "database.query.completed", Level::INFO, "query succeeded");
event!(name: "database.connection.failed", Level::ERROR, "connection failed");
```

This enables hierarchical filtering: `calibration.*`, `*.failed`, etc.

### Spans for operation context

Use spans to group related log events:

```rust
use tracing::{instrument, event, Level};

#[instrument(
    name = "calibration.workflow",
    skip(raw_data),
    fields(data.count = raw_data.len())
)]
async fn calibrate_workflow(
    model: &CalibrationModel,
    threshold: f64,
    raw_data: Vec<RawMeasurement>
) -> Result<Vec<ValidatedMeasurement>, WorkflowError> {
    event!(
        name: "calibration.started",
        Level::INFO,
        quality.threshold = threshold,
        "starting calibration workflow"
    );

    let measurements = raw_data
        .into_iter()
        .map(|raw| model.calibrate(raw))
        .collect::<Result<Vec<_>, _>>()?;

    event!(
        name: "calibration.completed",
        Level::INFO,
        result.count = measurements.len(),
        "calibration workflow completed successfully"
    );

    Ok(measurements)
}
```

Spans automatically propagate context to all events within the span.

### OpenTelemetry semantic conventions

Use OpenTelemetry semantic conventions for standard attributes:

```rust
event!(
    name: "http.request.completed",
    Level::INFO,
    http.request.method = "GET",
    http.response.status_code = 200,
    url.scheme = "https",
    url.path = "/api/data",
    server.address = "api.example.com",
    "HTTP request completed"
);

event!(
    name: "db.query.completed",
    Level::INFO,
    db.system = "postgresql",
    db.namespace = "experiments",
    db.operation.name = "SELECT",
    db.query.text = query,
    "database query completed"
);
```

Common conventions:
- **HTTP**: `http.request.method`, `http.response.status_code`, `url.scheme`, `url.path`, `server.address`
- **File**: `file.path`, `file.directory`, `file.name`, `file.extension`, `file.size`
- **Database**: `db.system`, `db.namespace`, `db.operation.name`, `db.query.text`
- **Errors**: `error.type`, `error.message`, `exception.type`, `exception.stacktrace`

### Sensitive data redaction

Never log sensitive data in plain text.
Redact or hash sensitive information before logging.

```rust
use data_privacy::redact_email;

// Good: Redact sensitive parts
event!(
    name: "user.operation.started",
    Level::INFO,
    user.email.redacted = redact_email(&user.email),
    user.id = user.id,  // Non-sensitive identifier
    "processing request for user {{user.email.redacted}} (id={{user.id}})"
);
```

**Never log**: Passwords, API keys, auth tokens, session IDs, email addresses (redact or hash), file paths revealing user identity, file contents containing PII, credit card numbers, SSNs, database connection strings with credentials, cryptographic keys or secrets.

### Logging as an effect at boundaries

In FDM, logging is an effect isolated at architectural boundaries (see architectural-patterns.md).

**Domain layer** (pure logic): No logging - pure functions return values.

**Application layer** (workflows): Log workflow entry/exit with spans, state transitions, validation failures.

**Infrastructure layer** (I/O): Log external service calls, database operations, network requests, file system operations.

```rust
// Domain layer: Pure function, no logging
fn validate_measurement(
    threshold: f64,
    measurement: Measurement
) -> Result<ValidatedMeasurement, ValidationError> {
    if measurement.quality < threshold {
        Err(ValidationError::BelowThreshold {
            quality: measurement.quality,
            threshold,
        })
    } else {
        Ok(ValidatedMeasurement(measurement))
    }
}

// Application layer: Workflow with logging at boundaries
#[instrument(
    name = "calibration.workflow",
    skip(raw_data),
    fields(data.count = raw_data.len())
)]
async fn calibrate_workflow(
    model: &CalibrationModel,
    threshold: f64,
    raw_data: Vec<RawMeasurement>
) -> Result<Vec<ValidatedMeasurement>, WorkflowError> {
    event!(
        name: "calibration.started",
        Level::INFO,
        quality.threshold = threshold,
        "starting calibration workflow"
    );

    let measurements = raw_data
        .into_iter()
        .map(|raw| model.calibrate(raw))
        .collect::<Result<Vec<_>, _>>()?;

    let validated = measurements
        .into_iter()
        .map(|m| validate_measurement(threshold, m))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| {
            event!(
                name: "calibration.validation.failed",
                Level::WARN,
                error.type = %e,
                "validation failed: {e}"
            );
            WorkflowError::from(e)
        })?;

    event!(
        name: "calibration.completed",
        Level::INFO,
        result.count = validated.len(),
        "calibration workflow completed successfully"
    );

    Ok(validated)
}

// Infrastructure layer: Database operation with logging
#[instrument(name = "db.save_results", skip(db, results))]
async fn save_results(
    db: &Database,
    results: &[ValidatedMeasurement]
) -> Result<(), DatabaseError> {
    event!(
        name: "db.insert.started",
        Level::DEBUG,
        db.system = "postgresql",
        db.namespace = "experiments",
        record.count = results.len(),
        "inserting results into database"
    );

    let start = std::time::Instant::now();
    db.insert_many(results).await?;

    event!(
        name: "db.insert.completed",
        Level::INFO,
        db.system = "postgresql",
        record.count = results.len(),
        duration.ms = start.elapsed().as_millis(),
        "inserted {{record.count}} records in {{duration.ms}}ms"
    );

    Ok(())
}
```

This layered approach ensures:
- Domain logic remains pure and testable without logging infrastructure
- Logging effects explicit in function signatures (async, Result)
- Tracing context propagates automatically through spans
- Infrastructure operations observable at boundaries

**See also**:
- architectural-patterns.md#effect-composition-and-signatures for effect isolation
- Message Templates Specification: https://messagetemplates.org/
- OpenTelemetry Semantic Conventions: https://opentelemetry.io/docs/specs/semconv/

## Unsafe code

Rust's safety guarantees make it ideal for implementing the type-safe foundations described in domain-modeling.md.
However, `unsafe` code deliberately lowers compiler guardrails, transferring correctness responsibilities to the programmer.
This section defines when unsafe is permissible and the validation requirements that apply.

### Fundamental principle: unsafe implies undefined behavior risk

The `unsafe` keyword may only mark functions and traits where misuse creates risk of undefined behavior (UB).
Never use `unsafe` to mark functions that are merely dangerous for other reasons.

```rust
// Valid: dereferencing raw pointer risks UB if pointer invalid
unsafe fn print_string(x: *const String) {
    println!("{}", *x);
}

// Invalid: deleting database is dangerous but cannot cause UB
unsafe fn delete_database() {
    std::fs::remove_dir_all("/var/db")
}
```

Reserve `unsafe` exclusively for its technical meaning in Rust's memory safety model.

### Valid reasons for unsafe code

You must have one of exactly three valid reasons to use `unsafe`:

**1. Novel abstractions** - Creating new foundational types the standard library does not provide:
- Custom smart pointers (Arc variants, intrusive linked lists)
- Custom allocators or memory management
- Low-level data structures (lock-free queues, concurrent maps)

**2. Performance optimization** - Removing bounds checks or other safety overhead after proving correctness:
- Using `.get_unchecked()` in hot paths after validating indices
- Bypassing UTF-8 validation when constructing known-valid strings
- Manual vectorization or SIMD operations

**3. FFI and platform calls** - Interfacing with external code:
- Calling C libraries or system APIs
- Implementing bindings to native libraries
- Direct kernel interactions

If your use case does not fit these categories, find a safe alternative.

### Invalid reasons for unsafe code

Never use ad-hoc `unsafe` (embedded in otherwise unrelated code) to:

**Bypass type system constraints** - Type bounds exist to prevent misuse:
```rust
// NEVER: Bypassing Send bounds
struct NotSendable {
    ptr: *const u8,
}

// This is unsound - creates undefined behavior
unsafe impl Send for NotSendable {}
```

**Simplify safe operations** - Convenience never justifies unsafe:
```rust
// NEVER: Transmuting enums for "simplicity"
enum Status {
    Pending = 0,
    Active = 1,
    Done = 2,
}

fn status_from_int_bad(x: u8) -> Status {
    // Unsound if x > 2
    unsafe { std::mem::transmute(x) }
}

// ALWAYS: Use safe matching
fn status_from_int_good(x: u8) -> Option<Status> {
    match x {
        0 => Some(Status::Pending),
        1 => Some(Status::Active),
        2 => Some(Status::Done),
        _ => None,
    }
}
```

**Bypass lifetime requirements** - Lifetimes encode essential relationships.

Ad-hoc unsafe is never acceptable.
If you need these capabilities, design a proper abstraction with sound encapsulation.

### Relationship to functional domain modeling

Good type design reduces the need for unsafe code.
The patterns in domain-modeling.md show how to make invalid states unrepresentable using safe Rust.

Before reaching for unsafe, ask: "Can I encode this invariant in the type system?"
Good domain modeling eliminates entire classes of unsafe operations.

**Smart constructors eliminate unsafe validation shortcuts**:

Instead of bypassing validation with transmute, use smart constructor pattern (safe).

**State machines prevent unsafe state manipulation**:

Instead of unsafely setting state flags, use enum state machine (safe).

**Type-level invariants reduce unchecked operations**:

Instead of `get_unchecked` assuming non-empty, use `NonEmpty` type with guaranteed length (safe).

### Novel abstractions: validation requirements

When building foundational abstractions requiring unsafe, follow these requirements without exception:

**1. Verify no established alternative exists**

Search crates.io and consult with team.
Prefer proven libraries over custom implementations.

**2. Design must be minimal and testable**

Extract unsafe core into smallest possible module.
Provide safe wrappers for all public APIs.

```rust
// Good: Minimal unsafe core with safe wrapper
mod ffi {
    // Private unsafe core
    unsafe fn raw_query(sql: *const u8, len: usize) -> i32 { }
}

pub mod database {
    // Public safe API
    pub fn query(sql: &str) -> Result<QueryResult, DbError> {
        unsafe { ffi::raw_query(sql.as_ptr(), sql.len()) }
        // ... error handling ...
    }
}
```

**3. Harden against adversarial code**

Assume all safe traits can misbehave.
Your unsafe code must remain sound even when:

- Closures panic mid-execution
- `Deref` implementations return different values each call
- `Clone` implementations produce invalid copies
- `Drop` implementations panic or access global state

Test with intentionally misbehaving implementations.

If a closure panics, your abstraction must become invalid (e.g., poisoned like `Mutex`), but must never cause undefined behavior.

**4. Document safety invariants in plain text**

Every `unsafe` block requires a comment explaining:
- What invariants must hold for safety
- Why those invariants are satisfied in this context
- What would happen if they were violated

```rust
pub fn process_measurements(data: &[f64]) -> f64 {
    if data.is_empty() {
        return 0.0;
    }

    // SAFETY: data.len() > 0 verified by check above.
    // get_unchecked avoids redundant bounds check in tight loop.
    // Would cause UB if data were empty, but that case handled.
    unsafe {
        data.get_unchecked(0)
    }
}
```

The reasoning must be detailed enough for reviewers to verify correctness.

**5. Pass Miri including adversarial tests**

[Miri](https://github.com/rust-lang/miri) is Rust's undefined behavior detector.
All unsafe code must pass Miri without warnings:

```bash
cargo +nightly miri test
```

Run Miri on normal test cases, edge cases, and adversarial tests.
Miri failures indicate undefined behavior that must be fixed before merging.

**6. Follow official unsafe code guidelines**

Study and follow the [Rust Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/).

Key resources:
- [The Rustonomicon](https://doc.rust-lang.org/nightly/nomicon/)
- [Unsafe Code Guidelines Reference](https://rust-lang.github.io/unsafe-code-guidelines/)
- [Adversarial Code Patterns](https://cheats.rs/#adversarial-code)

### Performance: validation requirements

Using unsafe for performance requires same rigor as novel abstractions plus benchmark evidence:

**1. Benchmark first**

Prove unsafe optimization provides meaningful benefit.

Only proceed if:
- Unsafe version shows significant improvement (>20% faster)
- Operation is in a verified hot path (profiling data)
- Safe alternatives have been exhausted

**2. Document safety reasoning**

Same requirements as novel abstractions: plain-text explanation of invariants.

**3. Pass Miri**

Performance-related unsafe must pass Miri.

**4. Consider safe alternatives first**

Before using unsafe for performance:
- Profile to identify actual bottlenecks
- Try algorithmic improvements
- Use better data structures
- Enable link-time optimization (LTO)
- Try `#[inline]` and other safe optimizations

Many "necessary" unsafe optimizations become unnecessary with proper profiling and algorithm choice.

### FFI: validation requirements

When calling foreign functions:

**1. Prefer established interop libraries**

Use proven bindings when available:
- Windows API: `windows` crate
- POSIX systems: `libc` crate
- Common C libraries: search crates.io first

Only create custom FFI bindings when no maintained alternative exists.

**2. Document permissible call patterns**

Generated bindings are unsafe by default.
Document which patterns are safe in practice:

```rust
extern "C" {
    // SAFETY: ptr must point to valid, initialized MyStruct.
    // The struct must remain valid for the entire call.
    // Not thread-safe: must not be called concurrently with other API calls.
    fn external_process(ptr: *mut MyStruct) -> i32;
}

pub fn process(data: &mut MyStruct) -> Result<(), ExternalError> {
    // SAFETY: data is a valid reference, therefore points to valid MyStruct.
    // Borrow checker ensures it remains valid for the call.
    // We hold the mutex, so no concurrent calls possible.
    let result = unsafe { external_process(data as *mut MyStruct) };

    if result == 0 {
        Ok(())
    } else {
        Err(ExternalError::from_code(result))
    }
}
```

**3. Follow unsafe code guidelines**

FFI code must follow same safety requirements as novel abstractions.

### Zero-tolerance policy for unsound code

Unsound code is _safe-looking_ code that can cause undefined behavior when called from safe code.

**What is unsoundness**:

A function is unsound if:
1. Its signature does not use the `unsafe` keyword, AND
2. Any calling pattern can cause undefined behavior

This applies even if causing UB requires "weird code" or "remote theoretical possibility."
The standard is strict: if UB is possible from safe code, the abstraction is unsound.

**How to fix unsound code**:

If you cannot safely encapsulate something, expose an `unsafe` function and document proper usage, or better: use safe wrapper with Result, or best: use type to encode requirement.

**No exceptions**:

While most guidelines permit exceptions with sufficient justification, unsoundness has no exceptions.
Unsound code is never acceptable under any circumstances.

If you discover unsound code:
1. File a critical bug immediately
2. Mark affected code `unsafe` if temporary fix is needed
3. Redesign the abstraction to be sound or remove it

Zero-tolerance policy exists because unsound abstractions create undefined behavior without warning, making debugging nearly impossible and creating severe security vulnerabilities.

### Summary: unsafe checklist

Before using `unsafe`, verify:

- [ ] I have one of the three valid reasons (novel abstraction, performance, FFI)
- [ ] I have verified no safe alternative exists
- [ ] I have benchmarked if using for performance
- [ ] The unsafe code is in a minimal, isolated module
- [ ] Every unsafe block has detailed safety documentation
- [ ] I have written adversarial test cases
- [ ] All tests pass under Miri
- [ ] The public API is safe (no unsafe leaking to callers)
- [ ] The abstraction is sound (cannot cause UB from safe code)

If any item is unchecked, do not proceed with unsafe.
Burden of proof is on the author to demonstrate safety.

**See also**:
- domain-modeling.md - Type-safe domain modeling patterns
- architectural-patterns.md - Isolating effects and unsafe code at boundaries
- theoretical-foundations.md - Category-theoretic foundations for safety reasoning

## Code quality and linting

- Address all `clippy` warnings before committing - run `cargo clippy --all-targets --all-features`
- Use `cargo fmt` to format code according to Rust style guidelines
- Enable additional clippy lint groups: `#![warn(clippy::all, clippy::pedantic)]`
- Consider stricter lints for critical code: `clippy::unwrap_used`, `clippy::expect_used`
- Run `cargo check` frequently during development for fast feedback

## Dependencies

- Minimize dependencies and audit them regularly with `cargo audit`
- Prefer well-maintained crates with strong type safety
- Use `cargo tree` to understand dependency graphs
- Pin versions appropriately in Cargo.toml
- Keep dependencies updated but test thoroughly after updates

## References

### Primary sources

This document integrates guidance from:

- **Functional domain modeling**: See domain-modeling.md for universal patterns, architectural-patterns.md for application structure, railway-oriented-programming.md for error composition
- **Microsoft Pragmatic Rust Guidelines**: https://microsoft.github.io/rust-guidelines/agents/all.txt - comprehensive production Rust guidance from Microsoft engineers
- **Rust API Guidelines**: https://rust-lang.github.io/api-guidelines/ - official Rust API design checklist

### Related documents

- theoretical-foundations.md - category-theoretic underpinnings
- algebraic-data-types.md - sum/product type patterns
