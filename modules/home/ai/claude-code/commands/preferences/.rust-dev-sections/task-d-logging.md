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
