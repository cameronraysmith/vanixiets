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
