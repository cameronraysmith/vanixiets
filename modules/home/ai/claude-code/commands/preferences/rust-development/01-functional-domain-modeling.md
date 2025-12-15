# Functional domain modeling in Rust

This section demonstrates implementing FDM patterns in Rust.
For pattern descriptions, see domain-modeling.md.
For theoretical foundations, see theoretical-foundations.md.

## Pattern 1: Smart constructors with newtype pattern

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

## Pattern 2: State machines with enums

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

## Pattern 3: Workflows with dependencies

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

## Pattern 4: Aggregates with consistency

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

## Pattern 5: Error classification

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

## Complete example: Temporal data processing

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
- ./02-error-handling.md for Result composition
