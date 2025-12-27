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

## Pattern 1a: Const generics for compile-time constraints

Use const generics (Rust 1.51+) to enforce numeric bounds and collection sizes at compile time when values are known statically.

**When to use const generics vs runtime validation**:

- **Const generics**: Bounds known at compile time, zero runtime cost, no runtime errors possible
- **Smart constructors**: Bounds from configuration/runtime data, need Result for error handling

**Example: Bounded numeric types**

```rust
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BoundedU32<const MIN: u32, const MAX: u32>(u32);

#[derive(Debug)]
pub struct BoundsError {
    value: u32,
    min: u32,
    max: u32,
}

impl fmt::Display for BoundsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "value {} out of range [{}, {}]",
            self.value, self.min, self.max
        )
    }
}

impl<const MIN: u32, const MAX: u32> BoundedU32<MIN, MAX> {
    pub fn new(value: u32) -> Result<Self, BoundsError> {
        if value < MIN || value > MAX {
            Err(BoundsError {
                value,
                min: MIN,
                max: MAX,
            })
        } else {
            Ok(Self(value))
        }
    }

    pub fn value(&self) -> u32 {
        self.0
    }
}

// Domain-specific type aliases
type Percentage = BoundedU32<0, 100>;
type DayOfMonth = BoundedU32<1, 31>;
type HttpPort = BoundedU32<1, 65535>;

// Usage
let percentage = Percentage::new(95)?;
let day = DayOfMonth::new(15)?;
// DayOfMonth::new(0)?;  // Compile-time type documents valid range
```

**Example: Fixed-size validated collections**

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct FixedVec<T, const N: usize>([T; N]);

impl<T, const N: usize> FixedVec<T, N> {
    pub fn new(items: [T; N]) -> Self {
        Self(items)
    }

    pub fn get(&self, index: usize) -> Option<&T> {
        self.0.get(index)
    }

    pub fn len(&self) -> usize {
        N
    }
}

// Exactly 3 RGB components, enforced at compile time
type RgbColor = FixedVec<u8, 3>;
type Coordinate3D = FixedVec<f64, 3>;

// Usage
let color = RgbColor::new([255, 128, 0]);
// let invalid = RgbColor::new([255, 128]); // Compile error: expected array of 3 elements
```

**Limitations and when to fall back to runtime validation**:

1. **Runtime bounds**: When limits come from configuration or user input, use smart constructors
2. **Complex constraints**: Const generics don't support all expressions yet (e.g., `MIN < MAX` assertion)
3. **API compatibility**: When interfacing with APIs expecting primitive types, add conversion methods

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

## Pattern 2a: Phantom types for zero-cost state tracking

Use phantom types as an alternative to enum-based state machines when state is known at compile time and you want zero runtime overhead.

**Emergent typestate**: Rust's typestate capability is not a pattern added on top of the language—it emerges naturally from three core primitives: affine types (move semantics), nominal types (types distinct by name), and phantom type parameters (`PhantomData<S>`).
As Graydon Hoare noted: "There was a typestate system that turns out to be redundant once you have affine types, nominal types and phantom type parameters."
The explicit typestate feature was removed from early Rust because these primitives made it redundant.
For concurrency applications of this insight, see ./11-concurrency.md.

**When to use phantom types vs enums**:

- **Phantom types**: State known at compile time, no runtime branching needed, zero-cost abstraction, impossible to inspect state at runtime
- **Enums**: Runtime state inspection needed, state not known until runtime, pattern matching required, enables dynamic behavior

**Example: Typestate pattern for document workflow**

```rust
use std::marker::PhantomData;

// State markers (zero-sized types)
pub struct Unvalidated;
pub struct Validated;
pub struct Approved;

// Document parameterized by state
pub struct Document<State> {
    content: String,
    _state: PhantomData<State>,
}

// Operations available only on unvalidated documents
impl Document<Unvalidated> {
    pub fn new(content: String) -> Self {
        Document {
            content,
            _state: PhantomData,
        }
    }

    pub fn validate(self) -> Result<Document<Validated>, ValidationError> {
        // Validation logic
        if self.content.is_empty() {
            return Err(ValidationError("content cannot be empty".to_string()));
        }

        Ok(Document {
            content: self.content,
            _state: PhantomData,
        })
    }
}

// Operations available only on validated documents
impl Document<Validated> {
    pub fn approve(self, approver: &User) -> Document<Approved> {
        // In real code, record approver info
        Document {
            content: self.content,
            _state: PhantomData,
        }
    }
}

// Operations available only on approved documents
impl Document<Approved> {
    pub fn publish(&self) -> PublishedDocument {
        PublishedDocument {
            content: self.content.clone(),
            published_at: chrono::Utc::now(),
        }
    }
}

// Common operations available in all states
impl<State> Document<State> {
    pub fn content(&self) -> &str {
        &self.content
    }
}

#[derive(Debug)]
pub struct ValidationError(String);

pub struct User {
    name: String,
}

pub struct PublishedDocument {
    content: String,
    published_at: chrono::DateTime<chrono::Utc>,
}

// Usage - invalid transitions are compile errors
fn example_workflow() -> Result<PublishedDocument, ValidationError> {
    let doc = Document::<Unvalidated>::new("content".to_string());
    let validated = doc.validate()?;
    let approver = User { name: "admin".to_string() };
    let approved = validated.approve(&approver);
    Ok(approved.publish())

    // doc.publish();  // Compile error: method not available on Unvalidated
    // validated.publish();  // Compile error: method not available on Validated
}
```

**Example: Units of measure for type-safe calculations**

```rust
use std::marker::PhantomData;

pub struct Quantity<Unit>(f64, PhantomData<Unit>);

// Unit markers
pub struct Meters;
pub struct Seconds;
pub struct MetersPerSecond;
pub struct MetersPerSecondSquared;

impl<U> Quantity<U> {
    pub fn new(value: f64) -> Self {
        Quantity(value, PhantomData)
    }

    pub fn value(&self) -> f64 {
        self.0
    }
}

// Type-safe division: distance / time = velocity
impl std::ops::Div<Quantity<Seconds>> for Quantity<Meters> {
    type Output = Quantity<MetersPerSecond>;

    fn div(self, rhs: Quantity<Seconds>) -> Self::Output {
        Quantity::new(self.0 / rhs.0)
    }
}

// Type-safe division: velocity / time = acceleration
impl std::ops::Div<Quantity<Seconds>> for Quantity<MetersPerSecond> {
    type Output = Quantity<MetersPerSecondSquared>;

    fn div(self, rhs: Quantity<Seconds>) -> Self::Output {
        Quantity::new(self.0 / rhs.0)
    }
}

// Usage
let distance = Quantity::<Meters>::new(100.0);
let time = Quantity::<Seconds>::new(9.8);
let velocity = distance / time;  // Type: Quantity<MetersPerSecond>
let acceleration = velocity / time;  // Type: Quantity<MetersPerSecondSquared>

// let invalid = distance + time;  // Compile error: no Add impl for different units
```

**Benefits of phantom types**:

1. **Zero runtime cost**: PhantomData is zero-sized, no memory overhead
2. **Compile-time safety**: Invalid state transitions impossible
3. **Documentation**: Type signature shows exactly what state is required
4. **Optimization**: Compiler can inline and eliminate all state tracking

**Limitations**:

1. **No runtime inspection**: Cannot check "what state am I in?" at runtime
2. **State must be known**: All transitions must be deterministic at compile time
3. **API ergonomics**: Generic parameters can complicate type signatures
4. **Error handling complexity**: Harder to return different states based on runtime conditions

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

**Scope: Local consistency boundaries**: Aggregates define consistency boundaries within a single service or process.
Cross-aggregate operations within the same service can use database transactions; cross-service operations cannot.
For distributed consistency across services, see distributed-systems.md.
Aggregates in different services communicate via events and accept eventual consistency as a fundamental constraint.

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

## Pattern 4a: NonEmpty collections for aggregate invariants

Use NonEmpty collections to encode "at least one" invariants in aggregate types, preventing empty states at the type level.

**The problem**: Standard collections like Vec allow empty states, but many aggregates require at least one element (Order must have at least one line, Dataset must have at least one observation).

**Example: Using nonempty crate**

```rust
use nonempty::NonEmpty;

#[derive(Debug, Clone)]
pub struct OrderLine {
    product_id: String,
    quantity: u32,
    price: f64,
}

#[derive(Debug, Clone)]
pub struct Order {
    id: String,
    lines: NonEmpty<OrderLine>,  // Guaranteed at least one
}

impl Order {
    /// Smart constructor - requires at least one line
    pub fn new(id: String, first_line: OrderLine) -> Self {
        Order {
            id,
            lines: NonEmpty::new(first_line),
        }
    }

    /// Add more lines
    pub fn add_line(&mut self, line: OrderLine) {
        self.lines.push(line);
    }

    /// Remove line - returns error if it would leave order empty
    pub fn remove_line(&mut self, idx: usize) -> Result<OrderLine, RemoveError> {
        if self.lines.len() <= 1 {
            Err(RemoveError::WouldBeEmpty)
        } else {
            // Remove from tail (index adjusted by 1 since head is separate)
            if idx == 0 {
                // Swap head with first tail element
                let old_head = std::mem::replace(&mut self.lines.head, self.lines.tail.remove(0));
                Ok(old_head)
            } else {
                Ok(self.lines.tail.remove(idx - 1))
            }
        }
    }

    /// Total price calculation always valid - guaranteed to have items
    pub fn total_price(&self) -> f64 {
        self.lines.iter().map(|line| line.price * line.quantity as f64).sum()
    }
}

#[derive(Debug)]
pub enum RemoveError {
    WouldBeEmpty,
    IndexOutOfBounds,
}
```

**Example: Custom NonEmpty implementation**

If not using the nonempty crate, implement your own:

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct NonEmpty<T> {
    head: T,
    tail: Vec<T>,
}

impl<T> NonEmpty<T> {
    pub fn new(head: T) -> Self {
        NonEmpty { head, tail: Vec::new() }
    }

    pub fn from_vec(mut vec: Vec<T>) -> Option<Self> {
        if vec.is_empty() {
            None
        } else {
            let head = vec.remove(0);
            Some(NonEmpty { head, tail: vec })
        }
    }

    pub fn push(&mut self, item: T) {
        self.tail.push(item);
    }

    pub fn head(&self) -> &T {
        &self.head
    }

    pub fn tail(&self) -> &[T] {
        &self.tail
    }

    pub fn len(&self) -> usize {
        1 + self.tail.len()
    }

    pub fn iter(&self) -> impl Iterator<Item = &T> {
        std::iter::once(&self.head).chain(self.tail.iter())
    }
}
```

**Benefits of NonEmpty**:

1. **Type-level guarantee**: Impossible to create empty aggregate
2. **Simpler logic**: No need to check for empty in aggregate methods
3. **Self-documenting**: Type signature communicates invariant
4. **Compiler enforcement**: Refactoring maintains invariant automatically

**When to use NonEmpty**:

- Aggregate root must always contain members (Order with OrderLines)
- Computation requires at least one value (mean, max, etc.)
- Business rule explicitly forbids empty state

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
