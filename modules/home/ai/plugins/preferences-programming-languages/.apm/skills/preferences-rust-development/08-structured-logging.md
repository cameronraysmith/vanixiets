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

In FDM, logging is an effect isolated at architectural boundaries (see ./04-api-design.md).

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
