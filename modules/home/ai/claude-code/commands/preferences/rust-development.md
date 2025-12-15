# Rust development

This guide integrates functional domain modeling (FDM) with pragmatic Rust practices from Microsoft engineers.

**Primary lens:** Functional domain modeling - type-driven design that encodes business logic in the type system, making invariants explicit and violations compile-time errors.

**Complementary guidance:** Microsoft Pragmatic Rust Guidelines - industry best practices for API design, testing, performance, and safety.

**Philosophical reconciliations:**

- *Panic semantics*: Panics for true programming bugs only (contract violations, impossible states). Domain errors and infrastructure errors use Result types. These approaches align - good type design reduces both panic surface and error handling complexity.

- *Dependency injection*: Prefer concrete types for domain logic, enums for testable I/O (sans-io pattern), generics for algorithm parameters, dyn Trait only for true runtime polymorphism. This hierarchy complements FDM's emphasis on explicit, type-safe dependencies.

- *Type-driven design*: Both FDM and Microsoft guidance emphasize making invalid states unrepresentable. Smart constructors, state machines, and strong types eliminate entire categories of bugs.

**Role in multi-language architectures:** Rust often serves as the base IO/Result layer in multi-language monad transformer stacks, providing memory-safe, high-performance foundations for effect composition.
## Functional domain modeling in Rust

This section demonstrates how to implement functional domain modeling patterns in Rust.
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

// Pattern matching helper
impl DataState {
    pub fn description(&self) -> String {
        match self {
            DataState::Raw(raw) => format!("Raw: {} observations", raw.values.len()),
            DataState::Calibrated(cal) => {
                format!("Calibrated: {} measurements", cal.measurements.len())
            }
            DataState::Inferred(inf) => {
                format!("Inferred: {} parameters", inf.parameters.len())
            }
            DataState::Validated(val) => {
                format!("Validated: {} diagnostics", val.diagnostics.len())
            }
        }
    }
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

    // Check all diagnostics pass threshold
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

// Default implementations
pub struct DefaultCalibrationModel;

impl CalibrationModel for DefaultCalibrationModel {
    fn calibrate(&self, raw: f64, _metadata: &HashMap<String, String>) -> (f64, f64, f64) {
        let value = raw * 1.1;
        let uncertainty = value.abs() * 0.05;
        let quality = 0.95;
        (value, uncertainty, quality)
    }
}

pub struct DefaultInferenceAlgorithm;

impl InferenceAlgorithm for DefaultInferenceAlgorithm {
    fn infer(
        &self,
        measurements: &[Measurement],
    ) -> (HashMap<String, f64>, f64, HashMap<String, bool>) {
        let values: Vec<f64> = measurements.iter().map(|m| m.value()).collect();
        let mean = values.iter().sum::<f64>() / values.len() as f64;

        let mut parameters = HashMap::new();
        parameters.insert("mean".to_string(), mean);

        let mut convergence = HashMap::new();
        convergence.insert("converged".to_string(), true);

        (parameters, -10.0, convergence)
    }
}

// Usage
let raw = RawObservations {
    values: vec![1.0, 2.0, 3.0],
    metadata: [("source".to_string(), "sensor_1".to_string())]
        .iter()
        .cloned()
        .collect(),
};

let calibration = DefaultCalibrationModel;
let inference = DefaultInferenceAlgorithm;
let metrics: HashMap<String, Box<dyn Fn(&HashMap<String, f64>) -> f64>> = [
    ("metric1".to_string(), Box::new(|_| 0.95) as Box<_>)
]
.iter()
.cloned()
.collect();

let result = process_observations(
    &calibration,
    0.8,
    &inference,
    &metrics,
    raw,
)?;
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

// Usage
let obs1 = Observation {
    timestamp: Utc::now(),
    value: 10.0,
    metadata: [("sensor".to_string(), "A".to_string())]
        .iter()
        .cloned()
        .collect(),
};

let obs2 = Observation {
    timestamp: Utc::now(),
    value: 12.0,
    metadata: [("sensor".to_string(), "A".to_string())]
        .iter()
        .cloned()
        .collect(),
};

let dataset = Dataset::new(
    DatasetId::new("dataset-001".to_string())?,
    vec![obs1, obs2],
    "protocol-001".to_string(),
)?;

println!("Dataset created with {} observations", dataset.statistics().count);
println!("Mean: {}", dataset.statistics().mean);
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

```rust
/**
 * Complete example: Temporal data processing pipeline
 *
 * Demonstrates:
 * - Smart constructors (newtypes)
 * - State machines (enums)
 * - Workflows (dependency injection)
 * - Aggregates (dataset with observations)
 * - Error handling (domain vs infrastructure)
 */

use std::collections::HashMap;
use chrono::{DateTime, Utc};

// Dependencies encapsulated in struct
pub struct ProcessingDependencies<C, I> {
    calibration_model: C,
    quality_threshold: f64,
    inference_algorithm: I,
    validation_metrics: HashMap<String, Box<dyn Fn(&HashMap<String, f64>) -> f64>>,
}

impl<C, I> ProcessingDependencies<C, I>
where
    C: CalibrationModel,
    I: InferenceAlgorithm,
{
    pub fn new(
        calibration_model: C,
        quality_threshold: f64,
        inference_algorithm: I,
        validation_metrics: HashMap<String, Box<dyn Fn(&HashMap<String, f64>) -> f64>>,
    ) -> Self {
        Self {
            calibration_model,
            quality_threshold,
            inference_algorithm,
            validation_metrics,
        }
    }

    pub fn process(&self, raw: RawObservations) -> Result<ValidatedModel, ProcessingError> {
        process_observations(
            &self.calibration_model,
            self.quality_threshold,
            &self.inference_algorithm,
            &self.validation_metrics,
            raw,
        )
    }
}

// Command pattern
#[derive(Debug, Clone)]
pub struct ProcessDataCommand {
    raw_data: RawObservations,
    timestamp: DateTime<Utc>,
    user_id: String,
    request_id: String,
}

// Event pattern
#[derive(Debug, Clone)]
pub enum ProcessingEvent {
    DataProcessed {
        model: ValidatedModel,
        processing_time: std::time::Duration,
        timestamp: DateTime<Utc>,
    },
    ProcessingFailed {
        error: String,
        timestamp: DateTime<Utc>,
    },
}

// Handle command and emit events
pub fn handle_process_data_command<C, I>(
    deps: &ProcessingDependencies<C, I>,
    command: ProcessDataCommand,
) -> Vec<ProcessingEvent>
where
    C: CalibrationModel,
    I: InferenceAlgorithm,
{
    let start = std::time::Instant::now();

    match deps.process(command.raw_data) {
        Ok(model) => vec![ProcessingEvent::DataProcessed {
            model,
            processing_time: start.elapsed(),
            timestamp: Utc::now(),
        }],
        Err(error) => vec![ProcessingEvent::ProcessingFailed {
            error: error.to_string(),
            timestamp: Utc::now(),
        }],
    }
}

// Usage example
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let deps = ProcessingDependencies::new(
        DefaultCalibrationModel,
        0.8,
        DefaultInferenceAlgorithm,
        [("metric1".to_string(), Box::new(|_| 0.95) as Box<_>)]
            .iter()
            .cloned()
            .collect(),
    );

    let command = ProcessDataCommand {
        raw_data: RawObservations {
            values: vec![1.0, 2.0, 3.0, 4.0, 5.0],
            metadata: [
                ("source".to_string(), "sensor_A".to_string()),
                ("experiment".to_string(), "exp_001".to_string()),
            ]
            .iter()
            .cloned()
            .collect(),
        },
        timestamp: Utc::now(),
        user_id: "user_123".to_string(),
        request_id: "req_456".to_string(),
    };

    let events = handle_process_data_command(&deps, command);

    for event in events {
        match event {
            ProcessingEvent::DataProcessed {
                model,
                processing_time,
                ..
            } => {
                println!("Success! Processed in {:?}", processing_time);
                println!("Parameters: {:?}", model.parameters);
                println!("Diagnostics: {:?}", model.diagnostics);
            }
            ProcessingEvent::ProcessingFailed { error, .. } => {
                println!("Failed: {}", error);
            }
        }
    }

    Ok(())
}
```

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
This section describes how to design error types that are both ergonomic for callers and aligned with functional domain modeling principles.

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

### Library error types: Canonical error structs (thiserror)

Libraries should define situation-specific error structs following the canonical pattern described in Microsoft's M-ERRORS-CANONICAL-STRUCTS guideline.
Use the `thiserror` crate to reduce boilerplate while maintaining full control over error design.

**Key principles for library errors**:

1. Create situation-specific structs, not generic ErrorKind enums exposed in public API
2. Include `Backtrace` field for debugging (captured when `RUST_BACKTRACE=1`)
3. Store upstream error cause via `#[source]` for error chains
4. Expose `is_xxx()` helper methods for error classification, not raw ErrorKind
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

When your library has distinct failure scenarios, use an internal `ErrorKind` enum but do not expose it directly in the public API.
Instead, provide `is_xxx()` methods for callers to classify errors.

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

    // Public accessor for contextual information
    pub fn config_path(&self) -> &Path {
        &self.config_path
    }

    // Internal constructor
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
- Callers can handle specific errors via `is_xxx()` methods without coupling to internal error representation
- Library can add new error kinds without breaking API (new `is_xxx()` methods are additive)
- Backtrace captured at error construction for debugging complex async code
- Error chains preserved via `source()` for root cause analysis

**Using thiserror to reduce boilerplate**:

```rust
use std::backtrace::Backtrace;
use std::path::PathBuf;

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

    let processed = process_config(config)
        .with_context(|| format!("failed to process config from {}", path))?;

    Ok(processed)
}

fn main() -> Result<()> {
    // Application entry point returns anyhow::Result
    let config = load_and_process_config("config.toml")?;
    start_service(config)?;
    Ok(())
}
```

**Key distinction**:
- **Libraries**: Use `thiserror` to define specific error types with structured fields and helper methods
- **Applications**: Use `anyhow` to handle errors generically with context strings
- **Within repository**: Application-internal crates may use anyhow if never published

### Context propagation with .context()

Both `anyhow` and many error libraries support `.context()` for adding human-readable context to errors as they propagate.

**With anyhow**:
```rust
use anyhow::{Context, Result};

fn download_and_save(url: &str, dest: &Path) -> Result<()> {
    let response = reqwest::blocking::get(url)
        .context("failed to send HTTP request")?;

    let bytes = response.bytes()
        .context("failed to read response body")?;

    fs::write(dest, bytes)
        .with_context(|| format!("failed to write to {}", dest.display()))?;

    Ok(())
}
```

**With custom Result extension trait**:
```rust
pub trait ResultExt<T> {
    fn context(self, msg: &str) -> Result<T, String>;
    fn with_context<F: FnOnce() -> String>(self, f: F) -> Result<T, String>;
}

impl<T, E: std::fmt::Display> ResultExt<T> for Result<T, E> {
    fn context(self, msg: &str) -> Result<T, String> {
        self.map_err(|e| format!("{}: {}", msg, e))
    }

    fn with_context<F: FnOnce() -> String>(self, f: F) -> Result<T, String> {
        self.map_err(|e| format!("{}: {}", f(), e))
    }
}
```

Context helps readers understand error chains:
```
Error: failed to start service
Caused by:
    0: failed to load configuration
    1: failed to read config file
    2: No such file or directory (os error 2)
```

### Error composition and transformation

When workflows combine operations with different error types, unify them via enum or trait object.

**Pattern 1: Unified workflow error enum**

```rust
#[derive(Debug, thiserror::Error)]
pub enum WorkflowError {
    #[error(transparent)]
    Validation(#[from] ValidationError),

    #[error(transparent)]
    Processing(#[from] ProcessingError),

    #[error(transparent)]
    Database(#[from] DatabaseError),
}

fn process_order_workflow(order: UnvalidatedOrder) -> Result<OrderConfirmation, WorkflowError> {
    // ? operator automatically converts each error type via From
    let validated = validate_order(order)?; // ValidationError -> WorkflowError
    let processed = process_payment(validated)?; // ProcessingError -> WorkflowError
    let saved = save_to_database(processed)?; // DatabaseError -> WorkflowError
    Ok(saved)
}
```

**Pattern 2: Domain and infrastructure error distinction**

Following functional domain modeling principles, distinguish domain errors (expected failures in business logic) from infrastructure errors (technical failures).

```rust
// Domain errors: Part of problem domain, modeled explicitly
#[derive(Debug, thiserror::Error)]
pub enum DomainError {
    #[error("quality score {0} below threshold {1}")]
    QualityBelowThreshold(f64, f64),

    #[error("calibration failed: {0}")]
    CalibrationFailed(String),

    #[error("model failed to converge after {0} iterations")]
    ConvergenceFailed(usize),
}

// Infrastructure errors: Technical concerns outside domain logic
#[derive(Debug, thiserror::Error)]
pub enum InfrastructureError {
    #[error("database operation failed")]
    Database(#[from] DatabaseError),

    #[error("network request failed")]
    Network(#[from] NetworkError),
}

// Unified workflow error
#[derive(Debug, thiserror::Error)]
pub enum WorkflowError {
    #[error(transparent)]
    Domain(#[from] DomainError),

    #[error(transparent)]
    Infrastructure(#[from] InfrastructureError),
}
```

**Why this distinction matters**:
- Domain errors appear in type signatures to document expected failure modes
- Subject matter experts recognize domain errors as part of problem vocabulary
- Infrastructure errors may be retried or logged differently than domain errors
- Testing strategies differ: domain errors have business logic tests, infrastructure errors have resilience tests

See `~/.claude/commands/preferences/domain-modeling.md#pattern-6-domain-errors-vs-infrastructure-errors` for detailed examples.

### Railway-oriented programming with Result

Compose operations that return `Result` using monadic patterns for short-circuit error propagation.

**Monadic composition with bind (flatMap)**:

```rust
// Explicit bind pattern
fn bind<T, U, E, F>(result: Result<T, E>, f: F) -> Result<U, E>
where
    F: FnOnce(T) -> Result<U, E>,
{
    match result {
        Ok(value) => f(value),
        Err(e) => Err(e),
    }
}

// ? operator provides built-in bind
fn process_pipeline(raw: RawData) -> Result<ProcessedData, ProcessingError> {
    let validated = validate(raw)?; // Short-circuits on Err
    let calibrated = calibrate(validated)?;
    let inferred = infer(calibrated)?;
    Ok(inferred)
}
```

**Functor mapping with .map()**:

```rust
// Transform success values without affecting errors
fn parse_and_double(input: &str) -> Result<i32, ParseIntError> {
    input.parse::<i32>()
        .map(|n| n * 2) // Only applies if Ok
}
```

**Applicative validation (collecting all errors)**:

When validating independent fields, collect all errors instead of short-circuiting on first failure.

```rust
pub fn validate_user(raw: &UserInput) -> Result<ValidUser, Vec<ValidationError>> {
    let email_result = validate_email(&raw.email);
    let name_result = validate_name(&raw.name);
    let age_result = validate_age(&raw.age);

    // Collect all errors
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
4. **Design errors for callers**: Provide `is_xxx()` helpers and contextual accessors so callers can handle errors appropriately
5. **Distinguish error categories**: Separate domain errors (expected) from infrastructure errors (technical) from panics (bugs)
6. **Compose errors via From**: Implement `From<UpstreamError>` to enable `?` operator automatic conversions
7. **Document failure modes**: Include `# Errors` sections in doc comments listing when functions return Err

### Integration with functional domain modeling

Error types are part of your domain vocabulary.
When modeling domain processes, make error types explicit in function signatures to communicate what can go wrong.

```rust
// State machine transition with typed error
pub fn calibrate(
    raw: RawObservations,
    threshold: f64,
) -> Result<CalibratedData, CalibrationError> {
    // Domain logic with explicit failure mode
}

// Workflow with unified error type
pub fn process_observations(
    raw: RawObservations,
) -> Result<ValidatedModel, ProcessingError> {
    let calibrated = calibrate(raw, 0.8)?;
    let inferred = infer(calibrated)?;
    let validated = validate_model(inferred)?;
    Ok(validated)
}
```

Domain errors become part of state machine documentation, workflow specifications, and aggregate invariants.

See `~/.claude/commands/preferences/rust-development.md#pattern-5-error-classification` for complete examples showing how error types integrate with smart constructors, state machines, and aggregates.
## Panic semantics

Panics in Rust are not exceptions or a form of error communication.
A panic means program termination, a request to stop execution immediately because the system has entered an invalid state from which it cannot meaningfully continue.

### Core principle

Following Microsoft guideline M-PANIC-IS-STOP: panics suggest immediate program termination.
Although code must be panic-safe (survived panics may not lead to inconsistent state), invoking a panic means this program should stop now.
It is never valid to use panics to communicate errors upstream or as a control flow mechanism.

### When panics are appropriate

Panics are appropriate only when:

**1. Detected programming errors (contract violations)** - Following M-PANIC-ON-BUG, when an unrecoverable programming error has been detected, code must panic to request program termination.
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

**4. Poison detection** - When encountering a poisoned lock, which signals another thread has already panicked.

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

```rust
// BAD: I/O can fail for non-programming reasons
pub fn read_config() -> Config {
    let contents = std::fs::read_to_string("config.toml")
        .expect("config must exist");
    toml::from_str(&contents).expect("config must be valid")
}

// GOOD: I/O failures are infrastructure errors
pub fn read_config() -> Result<Config, ConfigError> {
    let contents = std::fs::read_to_string("config.toml")
        .map_err(|e| ConfigError::ReadFailed(e.to_string()))?;
    toml::from_str(&contents)
        .map_err(|e| ConfigError::ParseFailed(e.to_string()))
}
```

**3. Parseable data** - Parsing structured data that might be malformed should return Result.

```rust
// BAD: Parsing is not a programming error
pub fn parse_uri(s: &str) -> Uri {
    Uri::from_str(s).unwrap()
}

// GOOD: Parsing can fail legitimately
pub fn parse_uri(s: &str) -> Result<Uri, ParseError> {
    Uri::from_str(s)
}
```

### Integration with FDM error classification

Panic semantics align with the three-tier error classification from functional domain modeling:

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

```rust
#[derive(Error, Debug)]
pub enum InfrastructureError {
    #[error("database operation '{operation}' failed: {exception}")]
    DatabaseFailed { operation: String, exception: String },
}

pub async fn save_to_database(
    data: &Data,
) -> Result<SavedData, InfrastructureError> {
    db.execute(/* ... */)
        .await
        .map_err(|e| InfrastructureError::DatabaseFailed {
            operation: "save".to_string(),
            exception: e.to_string(),
        })
}
```

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
        // Panic is appropriate here: empty dataset violates invariant
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

Examples applying this tree:

```rust
// 1. Caller can prevent: return Result
pub fn create_user(email: &str, age: i32) -> Result<User, ValidationError> {
    if age < 0 {
        return Err(ValidationError::OutOfRange {
            field: "age".to_string(),
            message: "must be non-negative".to_string(),
        });
    }
    // ...
}

// 2. Domain expert recognizes: return Result
pub fn train_model(data: &TrainingData) -> Result<Model, TrainingError> {
    if !converged {
        return Err(TrainingError::FailedToConverge {
            iterations,
            final_loss,
        });
    }
    // ...
}

// 3. Cannot continue (broken invariant): panic
pub fn process_validated_batch(&self) -> Summary {
    assert!(!self.items.is_empty(),
        "invariant broken: batch must have items after validation");
    // ...
}
```

### What constitutes a violation is situational

Following M-PANIC-ON-BUG, APIs are not expected to go out of their way to detect contract violations, as such checks can be impossible or expensive.

Encountering `must_be_even == 3` during an already existing check clearly warrants a panic, while a function `parse(&str)` clearly must return a Result.

The principle: if you would already be checking this condition for correctness, and it fails, that's a programming error.
If you would need to add expensive validation solely to panic, return Result instead.

```rust
// Already checking index bounds for correctness
pub fn get_cell(&self, row: usize, col: usize) -> f64 {
    assert!(row < self.rows && col < self.cols,
        "index out of bounds");
    self.data[row * self.cols + col]
}

// Would be expensive to validate entire URI grammar just to panic
pub fn parse_uri(s: &str) -> Result<Uri, ParseError> {
    // Return Result instead of adding expensive checks + panic
    // ...
}
```

### Make it correct by construction

While panicking on a detected programming error is the least bad option, your panic might still ruin someone's day.
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

### Integration with testing

Use should_panic tests for operations that document panic conditions:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[should_panic(expected = "denominator must be non-zero")]
    fn test_divide_zero_panics() {
        divide_non_zero(10, 0);
    }

    #[test]
    fn test_divide_non_zero_succeeds() {
        assert_eq!(divide_non_zero(10, 2), 5);
    }
}
```

### Further reading

See domain-modeling.md Pattern 6 for error classification framework.
See railway-oriented-programming.md for Result composition patterns.
See architectural-patterns.md for effect isolation at boundaries.
See Microsoft Rust Guidelines M-PANIC-IS-STOP and M-PANIC-ON-BUG for authoritative guidance.
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

Create integration tests in the `tests/` directory.
These tests verify your public API works correctly without access to private implementation details.

```rust
// tests/integration_test.rs
use my_crate::PublicApi;

#[test]
fn test_public_workflow() {
    let api = PublicApi::new();
    let result = api.process();
    assert!(result.is_ok());
}
```

### Mockable I/O pattern (sans-io)

Any user-facing type doing I/O or system calls with side effects should be mockable to these effects.
This includes file and network access, clocks, entropy sources, and similar.
More generally, any operation that is non-deterministic, reliant on external state, depending on hardware or environment, or otherwise fragile should be mockable.

Libraries supporting inherent mocking should implement it using a runtime abstraction via enum with `Native` and `Mock` variants.

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

// Dispatches calls either to the operating system or to a mocking controller
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

**Why tuple return `(Lib, MockHandle)` instead of accepting MockHandle**

Return the mock controller via parameter tuple rather than accepting it.
This prevents state ambiguity if multiple instances shared a single controller.

```rust
// Good: Each library instance gets its own mock controller
pub fn new_mocked() -> (Self, MockCtrl) { ... }

// Bad: Multiple instances could share same controller causing confusion
pub fn new_mocked(ctrl: &mut MockCtrl) -> Self { ... }
```

**When to use traits vs enums for abstraction**

Follow this design escalation ladder:

1. **Enum with Native/Mock variants (preferred for testing)**: If the other implementation is only concerned with providing a sans-io implementation for testing, implement your type as an enum.
This avoids trait object overhead and keeps the API concrete.

2. **Traits (for extensibility)**: If users are expected to provide custom implementations beyond just testing, introduce narrow traits and implement them for your concrete types.

3. **Dynamic dispatch (last resort)**: Only when generics become a nesting problem, consider `dyn Trait` wrapped in a custom type.

**Sans-io for one-shot I/O**

Functions and types that only need to perform one-shot I/O during initialization should accept `impl Read` or `impl Write` rather than concrete file types.

```rust
// Bad: Forces caller to use File even if data comes from network
fn parse_data(file: std::fs::File) -> Result<Data, ParseError> {
    // ...
}

// Good: Accepts File, TcpStream, &[u8], and many more
fn parse_data(data: impl std::io::Read) -> Result<Data, ParseError> {
    // ...
}
```

For async functions targeting multiple runtimes, use `futures::io::AsyncRead` and `futures::io::AsyncWrite`.

### Feature-gated test utilities

Testing functionality must be guarded behind a feature flag to prevent production builds from accidentally bypassing safety checks.

**Use a single feature flag named `test-util`**

```toml
# Cargo.toml
[features]
test-util = []
```

**What to gate behind `test-util`**

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

impl Database {
    #[cfg(feature = "test-util")]
    pub fn inspect_query_cache(&self) -> &HashMap<String, CachedResult> {
        &self.query_cache
    }
}

#[cfg(feature = "test-util")]
pub fn generate_fake_user(seed: u64) -> User {
    // Deterministic fake data generation for tests
}
```

**Runtime abstraction with test-util**

If your library already uses runtime abstraction, extend the runtime enum with a Mock variant:

```rust
enum Runtime {
    #[cfg(feature = "tokio")]
    Tokio(tokio::Runtime),

    #[cfg(feature = "smol")]
    Smol(smol::Executor),

    #[cfg(feature = "test-util")]
    Mock(mock::MockCtrl),
}
```

### Testing domain models from functional domain modeling patterns

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
    fn quality_score_rejects_below_zero() {
        let score = QualityScore::new(-0.1);
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

    #[test]
    fn complete_workflow_valid_transitions() {
        let raw = create_test_raw_observations();
        let calibration = DefaultCalibrationModel;
        let inference = DefaultInferenceAlgorithm;
        let metrics = create_test_validation_metrics();

        let result = process_observations(
            &calibration,
            0.8,
            &inference,
            &metrics,
            raw,
        );

        assert!(result.is_ok());
        let validated = result.unwrap();
        assert!(validated.diagnostics.values().all(|&v| v > 0.9));
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
    fn uncertainty_always_positive(value in 0.01f64..100.0) {
        let uncertainty = Uncertainty::new(value).unwrap();
        prop_assert!(uncertainty.value() > 0.0);
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
    fn domain_error_model_convergence() {
        let calibrated = create_test_calibrated_data();
        let divergent_algorithm = create_divergent_algorithm();

        let result = infer(divergent_algorithm, calibrated);
        assert!(result.is_err());

        match result.unwrap_err() {
            InferenceError::Failed(msg) => {
                assert!(msg.contains("converge") || msg.contains("diverge"));
            }
        }
    }

    // Infrastructure errors might be tested differently
    // depending on whether they use Result or exceptions
    #[test]
    #[cfg(feature = "test-util")]
    fn infrastructure_error_database_unavailable() {
        let (mut repo, mock) = Repository::new_mocked();
        mock.set_database_available(false);

        let result = repo.save_model(test_model());

        // If using Result for infrastructure errors
        assert!(matches!(
            result,
            Err(InfrastructureError::Database(_))
        ));
    }
}
```

### Test execution and tooling

Use `cargo test` to run all tests before committing.

```bash
cargo test
```

Consider using `cargo nextest` for faster test execution with better output:

```bash
cargo nextest run
```

Benefits of nextest:
- Runs tests in parallel more efficiently
- Cleaner, more informative output
- Better failure reporting
- JUnit output for CI integration

### Doc tests

Write doc tests to ensure documentation examples stay current and compile.

```rust
/// Processes observations through calibration pipeline.
///
/// # Examples
///
/// ```
/// use my_crate::{RawObservations, calibrate, DefaultCalibrationModel};
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

Doc tests are automatically run with `cargo test` and serve dual purpose as both documentation and verification.

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

Focus coverage efforts on:
- Domain logic (highest value, most likely to have bugs)
- Public API surface (contract with users)
- Error paths (often undertested)
- Boundary conditions (edge cases)

Less critical to cover:
- Simple getters/setters
- Trivial type conversions
- Generated code

### Testing patterns summary

- **Unit tests**: Same file, `#[cfg(test)]` modules, test private implementation
- **Integration tests**: `tests/` directory, verify public API
- **Mockable I/O**: Enum with `Native`/`Mock` variants, feature-gated mock utilities
- **Sans-io**: Accept `impl Read`/`impl Write` for composability
- **Smart constructors**: Test valid construction and validation failures
- **State machines**: Test valid transitions, rely on type system to prevent invalid ones
- **Property-based**: Use proptest/quickcheck to verify invariants across many examples
- **Domain errors**: Test expected failure scenarios return appropriate error variants
- **Doc tests**: Ensure examples compile and demonstrate correct usage
- **Coverage**: Focus on domain logic, public APIs, and error paths
## Documentation

Write comprehensive documentation using Rust's canonical doc comment structure.
Documentation is part of the API contract and serves both human readers and AI coding assistants.

### Canonical doc comment sections

Public library items must include canonical doc sections.
The summary sentence is always required.
Extended documentation and examples are strongly encouraged.
Other sections must be present when applicable.

```rust
/// Summary sentence of less than 15 words.
///
/// Extended documentation in free form providing context, background,
/// and usage guidance. Explain what the function does and why callers
/// would use it. Reference related functions and types using markdown
/// links like [`OtherType`] and [`other_function`].
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
/// valid and properly aligned. The referenced memory must remain
/// valid for the lifetime of the returned reference.
pub fn example_function() -> Result<(), Error> {
    Ok(())
}
```

**Section ordering**: Summary, extended docs, Examples, Errors, Panics, Safety, Abort.

**Summary line requirements**:
- Must be descriptive and complete, not just repeat the function name
- Should be under 15 words for readability in listings
- Avoid implementation details; focus on what, not how
- Does not end with a period (by convention)

**Examples section**:
- Include runnable code demonstrating common use cases
- Examples run as doc tests with `cargo test`
- Use `#` prefix to hide setup code that clutters the rendered example
- Show both success and error cases when relevant

**Errors section**:
- Document all error conditions that can be returned
- Explain when and why each error variant occurs
- Link to error type documentation using markdown links

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
/// If `dst` already exists, it will be overwritten. The source file
/// is not modified or removed. Metadata like permissions are copied
/// when possible.
fn copy(src: File, dst: File) {}
```

### Module-level documentation

Every public module must have `//!` module documentation.
The first sentence must follow the same 15-word guideline as item docs.

```rust
//! Contains FFI abstractions for external library integration.
//!
//! This module provides safe wrappers around unsafe FFI calls to the
//! external C library. All functions validate invariants and convert
//! C errors to Rust Result types.
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

Use `#[doc(inline)]` for items re-exported via `pub use` to integrate them into your module's documentation instead of showing them in an opaque re-export block.

```rust
// Re-export items from internal module
#[doc(inline)]
pub use internal::ImportantType;

#[doc(inline)]
pub use internal::important_function;
```

Do not use `#[doc(inline)]` for `std` or third-party types.
These should remain as plain re-exports to make their external origin clear.

### Doc tests as executable examples

Doc tests run with `cargo test` and verify examples stay current.
Use them liberally to demonstrate API usage.

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

Document all validation rules in the constructor's Errors section.
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

Document preconditions, postconditions, and error conditions for each transition.

```rust
/// Transitions raw observations to calibrated data.
///
/// Applies the calibration model to each raw value and validates
/// that all resulting measurements meet the quality threshold.
///
/// # Examples
///
/// ```
/// # use crate::{calibrate, RawObservations};
/// let raw = RawObservations::new(vec![1.0, 2.0, 3.0]);
/// let calibrated = calibrate(
///     |v, _| (v * 1.1, v * 0.05, 0.95),
///     0.9,
///     raw
/// )?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
///
/// # Errors
///
/// Returns [`CalibrationError::QualityBelowThreshold`] if any
/// measurement's quality score falls below `quality_threshold`.
///
/// Returns [`CalibrationError::Failed`] if the calibration model
/// produces invalid measurements (negative uncertainty, out of
/// range quality score).
pub fn calibrate<F>(
    calibration_model: F,
    quality_threshold: f64,
    raw: RawObservations,
) -> Result<CalibratedData, CalibrationError>
where
    F: Fn(f64, &HashMap<String, String>) -> (f64, f64, f64),
{
    // Transition implementation
}
```

#### Workflow preconditions and postconditions

Document the full workflow contract including dependency requirements and guarantees.

```rust
/// Processes observations through calibration, inference, and validation.
///
/// This workflow composes three steps:
/// 1. Calibrate raw observations using the provided model
/// 2. Run inference algorithm on calibrated measurements
/// 3. Validate inferred results against diagnostic metrics
///
/// # Examples
///
/// ```
/// # use crate::{process_observations, DefaultCalibrationModel,
/// #            DefaultInferenceAlgorithm, RawObservations};
/// # use std::collections::HashMap;
/// let calibration = DefaultCalibrationModel;
/// let inference = DefaultInferenceAlgorithm;
/// let metrics: HashMap<String, Box<dyn Fn(_) -> f64>> =
///     [("metric1".into(), Box::new(|_| 0.95) as Box<_>)]
///         .iter().cloned().collect();
///
/// let raw = RawObservations::new(vec![1.0, 2.0, 3.0]);
/// let result = process_observations(
///     &calibration,
///     0.8,
///     &inference,
///     &metrics,
///     raw
/// )?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
///
/// # Errors
///
/// Returns error if any workflow step fails:
/// - [`ProcessingError::Calibration`] if calibration fails validation
/// - [`ProcessingError::Inference`] if inference doesn't converge
/// - [`ProcessingError::Validation`] if diagnostics fail thresholds
///
/// # Type Parameters
///
/// - `C`: Calibration model implementing [`CalibrationModel`] trait
/// - `I`: Inference algorithm implementing [`InferenceAlgorithm`] trait
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
    // Workflow implementation
}
```

### Additional guidelines

- Use markdown links for cross-references: `[`Type`]`, `[`function`]`, `[`module::item`]`
- Link to related items in extended documentation to guide readers
- Prefer prose explanations over bullet lists when describing behavior
- Document type parameters in a dedicated section for complex generics
- Use code blocks with proper syntax highlighting: `rust`, `no_run`, `ignore`
- Keep summary lines focused on what, not how or why (save that for extended docs)
- Review generated docs with `cargo doc --open` to verify formatting and links
## Performance

### Hot path identification and profiling discipline

Identify early in the development process whether your crate is performance or COGS relevant.
For performance-sensitive code, establish a regular profiling discipline from the start rather than treating optimization as an afterthought.

**Early identification checklist:**

- Identify hot paths during design phase and create benchmarks around them
- Document performance-sensitive areas in code comments and module documentation
- Set measurable performance targets (latency bounds, throughput goals, memory budgets)
- Regularly run profilers collecting CPU and allocation insights

**Profiling tools and workflow:**

- Use `cargo flamegraph` for visualizing CPU time spent in functions
- Use `perf` for detailed CPU performance counter analysis on Linux
- Profile both debug and release builds to understand optimization impact
- Profile with realistic workloads that exercise hot paths under production-like conditions
- Run benchmarks on CI to detect performance regressions

**Common hot path performance issues:**

Profiling frequently reveals these optimization opportunities:

- Short-lived allocations that could use bump allocation or arena patterns
- Memory copy overhead from cloning `String`s and collections unnecessarily
- Repeated re-hashing of equal data structures (consider `FxHashMap` for non-cryptographic hashing)
- Use of Rust's default hasher where collision resistance is not required
- Missed opportunities for zero-cost abstractions (unnecessary trait objects, excessive generics monomorphization)

Anecdotally, addressing only some `String` allocation problems can yield approximately 15% benchmark gains on hot paths, with highly optimized versions potentially achieving up to 50% improvements.

### Throughput optimization for batch processing

Optimize for throughput using items-per-CPU-cycle as the primary metric for batch processing workloads.
While latency matters and cannot be scaled horizontally the way throughput can, avoid paying for latency with empty cycles that come from single-item processing, contended locks, and frequent task switching.

**Throughput optimization principles:**

- Partition reasonable chunks of work upfront rather than discovering work incrementally
- Let individual threads and tasks deal with their slice of work independently
- Sleep or yield when no work is present rather than hot spinning
- Design your own APIs for batched operations where single-item APIs would force inefficiency
- Perform work via batched APIs where available from dependencies
- Yield within long individual items or between chunks of batches (see async cooperative scheduling below)
- Exploit CPU caches through temporal and spatial locality (access related data together, reuse recently accessed data)

**Anti-patterns to avoid:**

- Hot spinning to receive individual items faster (wastes CPU cycles, prevents other tasks from running)
- Processing work on individual items when batching is possible (increases per-item overhead, loses vectorization opportunities)
- Work stealing or similar strategies to balance individual items (introduces synchronization overhead for marginal gains)
- Single-item channel processing in tight loops (context switch overhead dominates useful work)

**Shared state considerations:**

Only use shared state when the cost of sharing (synchronization, cache coherence, false sharing) is less than the cost of re-computation or re-fetching.
Consider using thread-local copies, message passing, or immutable shared data to avoid synchronization overhead.

### Async cooperative scheduling and yield points

Long-running tasks must cooperatively yield to prevent starving other tasks of CPU time.
Futures executed in runtimes that cannot work around blocking or long-running tasks cause runtime overhead and degrade system responsiveness.

**Automatic yielding through I/O:**

Tasks performing I/O regularly utilize await points to preempt themselves automatically:

```rust
async fn process_items(items: &[Item]) {
    // Keep processing items, the runtime will preempt you automatically
    for item in items {
        read_item(item).await; // I/O operation provides natural yield point
    }
}
```

**Explicit yielding for CPU-bound work:**

Tasks performing long-running CPU operations without intermixed I/O should cooperatively yield at regular intervals:

```rust
async fn process_items(zip_file: File) {
    let items = zip_file.read().await;
    for item in items {
        decompress(item); // CPU-bound work
        tokio::task::yield_now().await; // Explicit yield point
    }
}
```

**Yield point frequency guideline:**

In thread-per-core runtime models, balance task switching overhead against systemic effects of starving unrelated tasks.
Assuming runtime task switching takes hundreds of nanoseconds plus CPU cache overhead, continuous execution between yields should be long enough that switching cost becomes negligible (less than 1% overhead).

**Recommended yield interval:** Perform 10-100 microseconds of CPU-bound work between yield points.

**Dynamic yielding with runtime budget:**

For operations with unpredictable number and duration, query the hosting runtime using APIs like `has_budget_remaining()`:

```rust
async fn process_variable_workload(items: Vec<Item>) {
    for item in items {
        process_item(item);

        // Yield only when runtime budget is exhausted
        if !tokio::task::coop::has_budget_remaining() {
            tokio::task::yield_now().await;
        }
    }
}
```

### Memory efficiency and allocation strategies

**Prefer borrowing over ownership:**

- Use `&str` over `String` when ownership is not needed
- Consider `Cow<str>` for conditional ownership (borrows when possible, clones when necessary)
- Pass slices `&[T]` instead of `Vec<T>` when function does not need ownership
- Use `AsRef<T>` and `Borrow<T>` traits to accept both owned and borrowed forms

**Pre-allocate when size is known:**

- Use `Vec::with_capacity(n)` when final size is known or estimable
- Use `HashMap::with_capacity(n)` and `HashSet::with_capacity(n)` to avoid rehashing during growth
- Consider `String::with_capacity(n)` for string building in loops

**Avoid unnecessary allocations:**

- Reuse buffers across loop iterations instead of allocating per iteration
- Use `clear()` to reset collections while preserving allocated capacity
- Consider arena allocators or bump allocation for short-lived allocations in hot paths
- Profile allocations using `cargo flamegraph` with allocation profiling or tools like `heaptrack`

**Zero-cost abstractions:**

- Prefer iterator chains over explicit loops (compiler optimizes them equivalently)
- Use generics and monomorphization for performance-critical code (generates specialized code)
- Leverage const generics and const evaluation to move computation to compile time where applicable
- Avoid trait objects (`dyn Trait`) in hot paths when static dispatch (generics) is possible

### Allocator considerations

**Use mimalloc for applications:**

Applications should set [mimalloc](https://crates.io/crates/mimalloc) as their global allocator for significant performance gains without code changes.
This frequently results in notable performance increases along allocating hot paths, with benchmark improvements up to 25% observed.

**Setting mimalloc as global allocator:**

Add mimalloc to `Cargo.toml`:

```toml
[dependencies]
mimalloc = "0.1"
```

Configure global allocator in application entry point (typically `main.rs`):

```rust
use mimalloc::MiMalloc;

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

fn main() {
    // Application code runs with mimalloc
}
```

**When to consider custom allocators:**

- Libraries should not set global allocators (leave choice to applications)
- Consider custom allocators for specialized workload patterns (arena allocation for tree structures, bump allocation for temporary allocations, pool allocation for fixed-size objects)
- Profile allocation patterns before implementing custom allocators to ensure complexity is justified
- Document allocator assumptions in crate documentation if allocation behavior is performance-critical

### Benchmarking and measurement

**Establish benchmark suite:**

- Use `criterion` crate for statistically rigorous benchmarks with regression detection
- Use `divan` crate for faster compile times and simpler benchmark definitions
- Benchmark hot paths identified during profiling and design phases
- Include both microbenchmarks (isolated functions) and macrobenchmarks (end-to-end workflows)

**Criterion benchmark example:**

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn fibonacci(n: u64) -> u64 {
    match n {
        0 => 1,
        1 => 1,
        n => fibonacci(n-1) + fibonacci(n-2),
    }
}

fn criterion_benchmark(c: &mut Criterion) {
    c.bench_function("fib 20", |b| b.iter(|| fibonacci(black_box(20))));
}

criterion_group!(benches, criterion_benchmark);
criterion_main!(benches);
```

**Divan benchmark example:**

```rust
use divan::Bencher;

#[divan::bench]
fn parse_date(bencher: Bencher) {
    bencher.bench_local(|| {
        parse_date_impl("2024-01-15")
    });
}
```

**Benchmark best practices:**

- Use `black_box()` to prevent compiler from optimizing away benchmarked code
- Run benchmarks on dedicated hardware or in controlled environments (disable CPU frequency scaling, close background applications)
- Measure allocations, not just wall-clock time, to understand memory overhead
- Compare against baseline implementations to quantify optimization impact
- Add benchmarks to CI to detect regressions automatically

### Performance documentation

**Document performance characteristics:**

- Add performance notes to public API documentation explaining expected complexity (O(n), O(log n), etc.)
- Document allocation behavior (whether functions allocate, how much, under what conditions)
- Explain trade-offs made between performance and other concerns (correctness, maintainability, API ergonomics)
- Provide guidance on performance-sensitive usage patterns

**Example performance documentation:**

```rust
/// Processes items in batches for optimal throughput.
///
/// # Performance
///
/// - Time complexity: O(n) where n is the number of items
/// - Memory: Allocates a single buffer of size `batch_size` reused across batches
/// - Throughput: Optimized for batches of 100-1000 items
/// - Yields every 50μs to prevent starving other async tasks
///
/// For latency-sensitive workloads, consider using `process_items_streaming`
/// which processes items individually with lower batching overhead.
pub async fn process_items_batched(items: &[Item], batch_size: usize) -> Result<Vec<Output>> {
    // Implementation
}
```
## Structured logging

Use the `tracing` crate for structured logging with message templates and named properties.
Structured logging provides better filtering, aggregation, and analysis compared to string-based logs.

### Message templates over string formatting

Avoid string formatting in log messages as it allocates memory at runtime.
Use message templates with named properties instead, which defer formatting until viewing time.

```rust
use tracing::{event, Level};

// Bad: String formatting causes allocations
tracing::info!("file opened: {}", path);
tracing::info!(format!("file opened: {}", path));

// Good: Message templates with named properties
event!(
    name: "file.open.success",
    Level::INFO,
    file.path = %path.display(),
    "file opened: {{file.path}}",
);
```

The `{{property}}` syntax in message templates preserves literal text while escaping Rust's format syntax.

### Event naming conventions

Name events using hierarchical dot notation: `<component>.<operation>.<state>`.

```rust
// Bad: Unnamed events
event!(
    Level::INFO,
    file.path = file_path,
    "file {{file.path}} processed successfully",
);

// Good: Named events enable grouping and filtering
event!(
    name: "file.processing.success",
    Level::INFO,
    file.path = file_path,
    "file {{file.path}} processed successfully",
);
```

Examples of good event names:
- `database.query.started`
- `http.request.completed`
- `calibration.validation.failed`
- `model.training.converged`

### Spans for operation context

Use spans to track operation duration and provide context for nested events.

```rust
use tracing::{info_span, instrument};

// Manual span creation
async fn process_file(path: &Path) -> Result<(), Error> {
    let _span = info_span!(
        "file.processing",
        file.path = %path.display(),
        file.size = tracing::field::Empty  // Filled later
    )
    .entered();

    // Events within this span automatically inherit file.path
    event!(
        name: "file.validation.started",
        Level::INFO,
        "validating file"
    );

    // ... processing ...

    Ok(())
}

// Instrument macro for automatic spans
#[instrument(
    name = "calibration.process",
    skip(data),  // Skip large data from logs
    fields(
        data.size = data.len(),
        quality.threshold = threshold
    )
)]
async fn calibrate_data(
    threshold: f64,
    data: &[f64]
) -> Result<CalibratedData, CalibrationError> {
    // Span automatically created with function name and arguments
    info!("starting calibration");
    // ... implementation ...
}
```

### OpenTelemetry semantic conventions

Follow OpenTelemetry semantic conventions for standard attributes to enable interoperability.

```rust
event!(
    name: "http.request.completed",
    Level::INFO,
    http.request.method = "POST",
    http.response.status_code = 200,
    url.path = "/api/process",
    server.address = "localhost:8080",
    duration.ms = elapsed.as_millis(),
    "request completed: {{http.request.method}} {{url.path}} → {{http.response.status_code}}"
);

event!(
    name: "db.query.executed",
    Level::DEBUG,
    db.system = "postgresql",
    db.namespace = "experiments",
    db.operation.name = "SELECT",
    db.query.text = redact_query(query),
    "executed query on {{db.system}}.{{db.namespace}}"
);
```

Common OpenTelemetry conventions:
- **HTTP**: `http.request.method`, `http.response.status_code`, `url.scheme`, `url.path`, `server.address`
- **File**: `file.path`, `file.directory`, `file.name`, `file.extension`, `file.size`
- **Database**: `db.system`, `db.namespace`, `db.operation.name`, `db.query.text`
- **Errors**: `error.type`, `error.message`, `exception.type`, `exception.stacktrace`

### Sensitive data redaction

Never log sensitive data in plain text.
Redact or hash sensitive information before logging.

```rust
use data_privacy::redact_email;

// Bad: Logs potentially sensitive data
event!(
    name: "user.operation.started",
    Level::INFO,
    user.email = user.email,  // Exposed
    user.password = password,  // Critical exposure
    auth.token = token,       // Critical exposure
    "processing request for user {{user.email}}"
);

// Good: Redact sensitive parts
event!(
    name: "user.operation.started",
    Level::INFO,
    user.email.redacted = redact_email(&user.email),
    user.id = user.id,  // Non-sensitive identifier
    "processing request for user {{user.email.redacted}} (id={{user.id}})"
);
```

**Never log these types of sensitive data**:
- Passwords, API keys, auth tokens, session IDs
- Email addresses (redact or hash)
- File paths revealing user identity
- File contents containing PII
- Credit card numbers, SSNs, other personal identifiers
- Database connection strings with credentials
- Cryptographic keys or secrets

Consider using the `data_privacy` crate for consistent redaction patterns.

### Logging as an effect at boundaries

In functional domain modeling, logging is an effect that should be isolated at architectural boundaries (see architectural-patterns.md).

**Domain layer** (pure logic):
- No logging - pure functions return values
- Pass logged events as return values if needed

**Application layer** (workflows):
- Log workflow entry/exit with spans
- Log state transitions
- Log validation failures
- Emit structured events as workflow progresses

**Infrastructure layer** (I/O):
- Log external service calls
- Log database operations
- Log network requests
- Log file system operations

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
- Logging effects are explicit in function signatures (async, Result)
- Tracing context propagates automatically through spans
- Infrastructure operations are observable at their boundaries

**See also**:
- architectural-patterns.md#effect-composition-and-signatures for effect isolation
- Message Templates Specification: https://messagetemplates.org/
- OpenTelemetry Semantic Conventions: https://opentelemetry.io/docs/specs/semconv/
- OWASP Logging Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html
## Unsafe code

Rust's safety guarantees make it ideal for implementing the type-safe foundations described in domain-modeling.md.
However, `unsafe` code deliberately lowers the compiler's guardrails, transferring correctness responsibilities to the programmer.
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

Use clear, descriptive names and documentation to communicate danger that does not involve undefined behavior.
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

**Bypass lifetime requirements** - Lifetimes encode essential relationships:
```rust
// NEVER: Extending lifetimes via transmute
fn extend_lifetime_bad<'a, 'b, T>(x: &'a T) -> &'b T {
    // Creates dangling references
    unsafe { std::mem::transmute(x) }
}

// ALWAYS: Respect lifetime bounds or redesign API
```

Ad-hoc unsafe is never acceptable.
If you need these capabilities, design a proper abstraction with sound encapsulation.

### Relationship to functional domain modeling

Good type design reduces the need for unsafe code.
The patterns in domain-modeling.md show how to make invalid states unrepresentable using safe Rust:

**Smart constructors eliminate unsafe validation shortcuts**:
```rust
// Instead of bypassing validation with transmute
pub struct QualityScore(f64); // Could use unsafe to skip checks

// Use smart constructor pattern (safe)
impl QualityScore {
    pub fn new(value: f64) -> Result<Self, String> {
        if !(0.0..=1.0).contains(&value) {
            return Err(format!("quality score must be in [0,1], got {}", value));
        }
        Ok(QualityScore(value))
    }
}
```

**State machines prevent unsafe state manipulation**:
```rust
// Instead of unsafely setting state flags
struct Model {
    state: u8, // 0=training, 1=validated, would need unsafe casts
}

// Use enum state machine (safe)
enum ModelState {
    Training(TrainingData),
    Validated(ValidationResult),
}
```

**Type-level invariants reduce unchecked operations**:
```rust
// Instead of get_unchecked assuming non-empty
fn first_element<T>(vec: &Vec<T>) -> &T {
    unsafe { vec.get_unchecked(0) } // UB if empty
}

// Use NonEmpty type with guaranteed length (safe)
pub struct NonEmpty<T> {
    head: T,
    tail: Vec<T>,
}

impl<T> NonEmpty<T> {
    pub fn first(&self) -> &T {
        &self.head // Always safe, no bounds check needed
    }
}
```

Before reaching for unsafe, ask: "Can I encode this invariant in the type system?"
Good domain modeling eliminates entire classes of unsafe operations.

### Novel abstractions: validation requirements

When building foundational abstractions requiring unsafe, follow these requirements without exception:

**1. Verify no established alternative exists**

Search crates.io and consult with team.
Prefer proven libraries over custom implementations.

**2. Design must be minimal and testable**

Extract the unsafe core into the smallest possible module.
Provide safe wrappers for all public APIs.

```rust
// Bad: Large unsafe module with mixed concerns
mod database {
    pub unsafe fn raw_query(sql: *const u8, len: usize) -> QueryResult { }
    pub unsafe fn raw_insert(data: *const u8) -> bool { }
}

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

Test with intentionally misbehaving implementations:

```rust
#[cfg(test)]
mod adversarial_tests {
    struct PanicOnSecondDeref {
        count: Cell<usize>,
        value: String,
    }

    impl Deref for PanicOnSecondDeref {
        type Target = String;
        fn deref(&self) -> &String {
            let count = self.count.get();
            self.count.set(count + 1);
            if count > 0 {
                panic!("adversarial deref");
            }
            &self.value
        }
    }

    #[test]
    fn custom_type_handles_panicking_deref() {
        let adversarial = PanicOnSecondDeref {
            count: Cell::new(0),
            value: "test".to_string(),
        };

        // Your unsafe abstraction must not cause UB here
        let result = std::panic::catch_unwind(|| {
            your_unsafe_abstraction(&adversarial)
        });

        // Either succeeds or panics, but never UB
        assert!(result.is_ok() || result.is_err());
    }
}
```

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

Insufficient documentation:
```rust
unsafe { data.get_unchecked(0) } // SAFETY: should be fine
```

The reasoning must be detailed enough for reviewers to verify correctness.

**5. Pass Miri including adversarial tests**

[Miri](https://github.com/rust-lang/miri) is Rust's undefined behavior detector.
All unsafe code must pass Miri without warnings:

```bash
cargo +nightly miri test
```

Run Miri on:
- Normal test cases
- Edge cases (empty collections, zero values, maximum sizes)
- Adversarial tests (panicking traits, misbehaving implementations)

Miri failures indicate undefined behavior that must be fixed before merging.

**6. Follow official unsafe code guidelines**

Study and follow the [Rust Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/).
Key resources:
- [The Rustonomicon](https://doc.rust-lang.org/nightly/nomicon/)
- [Unsafe Code Guidelines Reference](https://rust-lang.github.io/unsafe-code-guidelines/)
- [Adversarial Code Patterns](https://cheats.rs/#adversarial-code)

### Performance: validation requirements

Using unsafe for performance requires the same rigor as novel abstractions plus benchmark evidence:

**1. Benchmark first**

Prove the unsafe optimization provides meaningful benefit:

```rust
use criterion::{black_box, criterion_group, criterion_main, Criterion};

fn bench_safe_version(c: &mut Criterion) {
    let data: Vec<f64> = (0..1000).map(|x| x as f64).collect();
    c.bench_function("safe_get", |b| {
        b.iter(|| {
            black_box(&data)[black_box(500)]
        })
    });
}

fn bench_unsafe_version(c: &mut Criterion) {
    let data: Vec<f64> = (0..1000).map(|x| x as f64).collect();
    c.bench_function("unsafe_get", |b| {
        b.iter(|| {
            unsafe { black_box(&data).get_unchecked(black_box(500)) }
        })
    });
}

criterion_group!(benches, bench_safe_version, bench_unsafe_version);
criterion_main!(benches);
```

Only proceed if:
- The unsafe version shows significant improvement (>20% faster)
- The operation is in a verified hot path (profiling data)
- Safe alternatives have been exhausted

**2. Document safety reasoning**

Same requirements as novel abstractions: plain-text explanation of invariants.

**3. Pass Miri**

Performance-related unsafe must pass Miri.
Use Miri to verify the optimization is sound across all inputs.

**4. Consider safe alternatives first**

Before using unsafe for performance:
- Profile to identify actual bottlenecks
- Try algorithmic improvements
- Use better data structures
- Enable link-time optimization (LTO)
- Try `#[inline]` and other safe optimizations

Many "necessary" unsafe optimizations become unnecessary with proper profiling and algorithm choice.

### FFI: validation requirements

When calling foreign functions, follow these requirements:

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

FFI code must follow the same safety requirements as novel abstractions.

### Zero-tolerance policy for unsound code

Unsound code is _safe-looking_ code that can cause undefined behavior when called from safe code.

**What is unsoundness**:

A function is unsound if:
1. Its signature does not use the `unsafe` keyword, AND
2. Any calling pattern can cause undefined behavior

This applies even if causing UB requires "weird code" or "remote theoretical possibility."
The standard is strict: if UB is possible from safe code, the abstraction is unsound.

**Examples of unsound code**:

```rust
// Unsound: safe signature, but causes UB if T is smaller than u128
fn unsound_ref<T>(x: &T) -> &u128 {
    unsafe { std::mem::transmute(x) }
}

// Unsound: safe signature, but violates Send contract
struct AlwaysSend<T>(T);
unsafe impl<T> Send for AlwaysSend<T> {}
// If T is !Send (e.g., contains Rc), this creates data races

// Unsound: safe signature, but assumes Vec is non-empty
pub fn first_element<T>(vec: &Vec<T>) -> &T {
    unsafe { vec.get_unchecked(0) }
    // UB when called with empty Vec
}
```

**How to fix unsound code**:

If you cannot safely encapsulate something, expose an `unsafe` function and document proper usage:

```rust
// Sound: unsafe signature documents requirements
pub unsafe fn first_element_unchecked<T>(vec: &Vec<T>) -> &T {
    // SAFETY: Caller must ensure vec.len() > 0
    vec.get_unchecked(0)
}

// Or better: use safe wrapper with Result
pub fn first_element<T>(vec: &Vec<T>) -> Option<&T> {
    vec.first()
}

// Or best: use NonEmpty type to encode requirement
pub fn first_element<T>(vec: &NonEmpty<T>) -> &T {
    vec.first() // Always safe
}
```

**No exceptions**:

While most guidelines permit exceptions with sufficient justification, unsoundness has no exceptions.
Unsound code is never acceptable under any circumstances.

If you discover unsound code:
1. File a critical bug immediately
2. Mark affected code `unsafe` if temporary fix is needed
3. Redesign the abstraction to be sound or remove it

The zero-tolerance policy exists because unsound abstractions create undefined behavior without warning, making debugging nearly impossible and creating severe security vulnerabilities.

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
The burden of proof is on the author to demonstrate safety.

### Relationship to other type-safety patterns

The type-safety principles in domain-modeling.md and rust-development.md work together:

1. **Smart constructors** (domain-modeling.md): Encode validation in types to avoid runtime checks that might tempt unsafe shortcuts
2. **State machines** (domain-modeling.md): Make invalid states unrepresentable, eliminating need to unsafely manipulate state
3. **Result types** (rust-development.md): Explicit error handling prevents bypassing safety with unwrap/expect in unsafe contexts
4. **Ownership and borrowing** (rust-development.md): Core safety guarantees that unsafe code must preserve

Good type design makes unsafe code unnecessary in most domains.
When unsafe is genuinely required, these patterns help isolate it in minimal, well-tested modules with safe public interfaces.

### Further reading

**Official Rust resources**:
- [The Rustonomicon](https://doc.rust-lang.org/nightly/nomicon/) - The dark arts of unsafe Rust
- [Unsafe Code Guidelines](https://rust-lang.github.io/unsafe-code-guidelines/) - Official reference
- [Miri documentation](https://github.com/rust-lang/miri) - UB detection tool

**Safety concepts**:
- [Unsafe, Unsound, Undefined](https://cheats.rs/#unsafe-unsound-undefined) - Terminology reference
- [Adversarial Code Patterns](https://cheats.rs/#adversarial-code) - Testing malicious inputs

**Related documentation**:
- domain-modeling.md - Type-safe domain modeling patterns
- architectural-patterns.md - Isolating effects and unsafe code at boundaries
- theoretical-foundations.md - Category-theoretic foundations for safety reasoning
- Address all `clippy` warnings before committing - run `cargo clippy --all-targets --all-features`
- Use `cargo fmt` to format code according to Rust style guidelines
- Enable additional clippy lint groups: `#![warn(clippy::all, clippy::pedantic)]`
- Consider stricter lints for critical code: `clippy::unwrap_used`, `clippy::expect_used`
- Run `cargo check` frequently during development for fast feedback


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
- python-development.md, typescript-nodejs-development.md - FDM in other languages
