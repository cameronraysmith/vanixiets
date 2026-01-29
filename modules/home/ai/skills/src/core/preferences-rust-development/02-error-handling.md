# Error handling

Rust error handling centers on `Result<T, E>` and the question mark operator `?` for composable, type-safe error propagation.
This section describes designing error types aligned with FDM principles.

## Result<T, E> and the ? operator

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

## Library error types: thiserror

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

## Application error types: anyhow and miette

Applications (binaries, not libraries) should use `anyhow` for simplified error handling.
The `anyhow::Result<T>` type automatically converts any error implementing `std::error::Error`.

For CLI tools and developer-facing applications that benefit from rich diagnostic output, consider `miette` instead.
It provides pretty-printed error reports with source code snippets, help text, and related errors.

```rust
use miette::{Diagnostic, SourceSpan};
use thiserror::Error;

#[derive(Error, Diagnostic, Debug)]
#[error("invalid configuration")]
#[diagnostic(
    code(config::invalid),
    help("check that all required fields are present")
)]
pub struct ConfigError {
    #[source_code]
    pub src: String,
    #[label("this field is invalid")]
    pub span: SourceSpan,
}
```

**When to use each**:
- **anyhow**: General applications, quick prototyping, when you just need error context chains
- **miette**: CLI tools, compilers, linters, any tool where users benefit from seeing error locations in source

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

## Context propagation with .context()

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

## Error composition and transformation

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

## Railway-oriented programming with Result

Railway-oriented programming treats error handling as a two-track railway: success track and failure track.
The `?` operator provides monadic composition (bind) for fail-fast behavior.
This section focuses on applicative composition for error accumulation.

See `~/.claude/commands/preferences/railway-oriented-programming.md` for comprehensive patterns including bind vs apply, effect signatures, and the two-track model.

### Fail-fast vs error accumulation

Choose your composition strategy based on whether operations are independent:

**When to fail-fast (monadic bind with `?`)**:
- Steps depend on previous results
- Operations are expensive (database writes, API calls)
- Want to short-circuit and avoid wasted work
- Example: validate input → reserve inventory → charge payment → create shipment

**When to accumulate (applicative validation)**:
- Validations are independent
- Want all errors at once for better UX
- Operations are cheap (field validation)
- Example: validate all form fields, show user every problem

### Manual error accumulation pattern

Validate all fields independently and collect errors:

```rust
fn validate_user(input: &UserInput) -> Result<ValidUser, Vec<ValidationError>> {
    let mut errors = Vec::new();

    let email = match Email::new(&input.email) {
        Ok(e) => Some(e),
        Err(e) => { errors.push(e.into()); None }
    };

    let age = match Age::new(input.age) {
        Ok(a) => Some(a),
        Err(e) => { errors.push(e.into()); None }
    };

    let name = match Name::new(&input.name) {
        Ok(n) => Some(n),
        Err(e) => { errors.push(e.into()); None }
    };

    if errors.is_empty() {
        Ok(ValidUser {
            email: email.unwrap(),
            age: age.unwrap(),
            name: name.unwrap(),
        })
    } else {
        Err(errors)
    }
}
```

**Why this pattern**:
- All validations run even if some fail
- User sees all problems at once
- Each validation is independent (no data dependencies)
- Pattern is explicit and easy to understand

### Generic validation collection helper

Extract the accumulation pattern into a reusable helper:

```rust
fn collect_validations<T, E>(
    results: Vec<Result<T, E>>
) -> Result<Vec<T>, Vec<E>> {
    let (oks, errs): (Vec<_>, Vec<_>) = results
        .into_iter()
        .partition(Result::is_ok);

    if errs.is_empty() {
        Ok(oks.into_iter().map(Result::unwrap).collect())
    } else {
        Err(errs.into_iter().map(|r| r.unwrap_err()).collect())
    }
}

// Usage: validate multiple items
fn validate_batch(inputs: &[UserInput]) -> Result<Vec<ValidUser>, Vec<ValidationError>> {
    let results: Vec<Result<ValidUser, ValidationError>> = inputs
        .iter()
        .map(|input| validate_user_single(input))
        .collect();

    collect_validations(results)
        .map_err(|errs| errs.into_iter().flatten().collect())
}
```

### Validation libraries

For production code, consider validation crates:

**`validator` crate** - derive-based validation:
```rust
use validator::{Validate, ValidationError};

#[derive(Debug, Validate)]
pub struct SignupForm {
    #[validate(email)]
    email: String,

    #[validate(length(min = 3, max = 50))]
    username: String,

    #[validate(range(min = 18, max = 120))]
    age: u8,
}

// Returns ValidationErrors with all field errors
fn validate_signup(form: &SignupForm) -> Result<(), ValidationErrors> {
    form.validate()
}
```

**`garde` crate** - flexible validation with better errors:
```rust
use garde::Validate;

#[derive(Debug, Validate)]
pub struct User {
    #[garde(email)]
    email: String,

    #[garde(length(min = 1, max = 100))]
    name: String,

    #[garde(custom(validate_age))]
    age: i32,
}

fn validate_age(age: &i32, _ctx: &()) -> garde::Result {
    if *age >= 18 && *age <= 120 {
        Ok(())
    } else {
        Err(garde::Error::new("age must be between 18 and 120"))
    }
}
```

**Custom implementation**:
For domain-specific validation that doesn't fit standard patterns, use manual accumulation.
This gives full control over error types and validation logic.

### Enforcing Result handling with #[must_use]

Use `#[must_use]` to make the two-track model explicit in the type system.
The compiler warns when Result values are ignored, enforcing railway-oriented discipline.

```rust
#[must_use = "validation result must be handled"]
pub fn validate(input: &Input) -> Result<Validated, ValidationError> {
    // Validation logic
}

// Compiler error if you forget to handle Result:
validate(&input);  // warning: unused `Result` that must be used

// Force explicit handling:
let _ = validate(&input);  // warning: unused `Result` that must be used
validate(&input)?;         // OK: propagates error
match validate(&input) {   // OK: explicit handling
    Ok(v) => process(v),
    Err(e) => log_error(e),
}
```

**Apply to custom Result wrappers**:

```rust
#[must_use]
pub struct ValidationResult<T> {
    inner: Result<T, ValidationError>,
}

impl<T> ValidationResult<T> {
    pub fn new(result: Result<T, ValidationError>) -> Self {
        Self { inner: result }
    }

    pub fn into_result(self) -> Result<T, ValidationError> {
        self.inner
    }
}

#[must_use = "calibration must be validated before use"]
pub fn calibrate(data: &RawData) -> ValidationResult<CalibratedData> {
    ValidationResult::new(calibrate_impl(data))
}
```

**When to apply #[must_use]**:
- Public Result-returning functions where ignoring the error would be a bug
- Operations that combine computation with validation
- Functions with important side effects encoded in the return value
- Custom Result wrapper types that carry domain errors

**Connection to ROP**:
This attribute makes the two-track railway explicit in the type system.
You cannot accidentally stay on the success track without handling potential failure.
The compiler enforces that you acknowledge both tracks exist.

## Error handling best practices

1. **Use Result, not panic**: Reserve `panic!`, `unwrap()`, and `expect()` for programmer errors (bugs), not recoverable failures
2. **Capture backtraces**: Include `Backtrace` in library error types for debugging async and complex call chains
3. **Add context as errors propagate**: Use `.context()` or `.with_context()` to explain what operation failed
4. **Design errors for callers**: Provide `is_xxx()` helpers and contextual accessors
5. **Distinguish error categories**: Separate domain errors (expected) from infrastructure errors (technical) from panics (bugs)
6. **Compose errors via From**: Implement `From<UpstreamError>` to enable `?` operator automatic conversions
7. **Document failure modes**: Include `# Errors` sections in doc comments

Domain errors become part of state machine documentation, workflow specifications, and aggregate invariants.
See ./01-functional-domain-modeling.md Pattern 5 for complete error classification examples.

## See also

- ./01-functional-domain-modeling.md - Pattern 6 for error classification framework
- ./03-panic-semantics.md - Panic semantics and when panics are appropriate
- ./04-api-design.md - API design principles
- ./05-testing.md - Testing patterns
- ./06-documentation.md - Documentation best practices
- ./08-structured-logging.md - Structured logging and logging as an effect
- ./11-concurrency.md - Error handling in concurrent contexts (cancellation, task panics, channel errors)
- domain-modeling.md - Universal domain modeling patterns
- railway-oriented-programming.md - Result composition patterns
- architectural-patterns.md - Effect isolation at boundaries
