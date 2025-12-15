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

## Application error types: anyhow

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
- domain-modeling.md - Universal domain modeling patterns
- railway-oriented-programming.md - Result composition patterns
- architectural-patterns.md - Effect isolation at boundaries
