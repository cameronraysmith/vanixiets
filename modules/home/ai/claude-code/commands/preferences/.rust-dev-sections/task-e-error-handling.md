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
