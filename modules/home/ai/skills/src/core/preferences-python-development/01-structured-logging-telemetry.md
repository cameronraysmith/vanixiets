# Structured logging and telemetry

## OpenTelemetry SDK for Python

The `opentelemetry-sdk` package provides TracerProvider and MeterProvider as the standard telemetry foundation.
Configure OTLP exporters via `opentelemetry-exporter-otlp-proto-grpc` or `opentelemetry-exporter-otlp-proto-http`.
Auto-instrumentation via `opentelemetry-instrumentation` with framework-specific instrumentors (`opentelemetry-instrumentation-fastapi`, `-requests`, `-sqlalchemy`, `-httpx`) provides span creation without manual code.
Initialize the SDK before importing application modules to ensure monkey-patching applies at import time.

## Tracer and span creation

Access the tracer via `trace.get_tracer('service-name')`.
The context manager pattern ensures proper span lifecycle:

```python
from opentelemetry import trace
from opentelemetry.trace import StatusCode, Status

tracer = trace.get_tracer("calibration-service")

with tracer.start_as_current_span("calibration.workflow") as span:
    span.set_attribute("data.count", len(raw_data))
    try:
        result = calibrate(raw_data, threshold)
    except CalibrationError as e:
        span.record_exception(e)
        span.set_status(Status(StatusCode.ERROR))
        raise
```

The context manager calls `span.end()` automatically.
Add attributes with `span.set_attribute` using OpenTelemetry semantic convention names.
Record errors with `span.record_exception(error)` followed by `span.set_status(Status(StatusCode.ERROR))`.

For decorator-based instrumentation, create a utility that wraps async functions in spans:

```python
from functools import wraps

def traced(name: str):
    def decorator(fn):
        @wraps(fn)
        async def wrapper(*args, **kwargs):
            with tracer.start_as_current_span(name) as span:
                return await fn(*args, **kwargs)
        return wrapper
    return decorator
```

## Event naming conventions

Follow the hierarchical dot-separated pattern: `component.operation.outcome` (e.g., `calibration.process.started`, `database.query.failed`).
Use OpenTelemetry semantic conventions for standard attributes: `http.request.method`, `http.response.status_code`, `url.path`, `db.system`, `db.operation.name`, `rpc.service`, `rpc.method`.
This enables hierarchical filtering (`calibration.*`, `*.failed`) and consistent attribute names across services.

## Structured logging with structlog

Use `structlog` as the structured logger.
Configure processors to inject trace context (`trace_id`, `span_id`) from the active OTel span into every log entry.

```python
import structlog
from opentelemetry import trace

def add_trace_context(logger, method_name, event_dict):
    span = trace.get_current_span()
    if span.is_recording():
        ctx = span.get_span_context()
        event_dict["trace_id"] = format(ctx.trace_id, "032x")
        event_dict["span_id"] = format(ctx.span_id, "016x")
    return event_dict
```

Configure structlog with `JSONRenderer` for production and `ConsoleRenderer` for development, including `add_trace_context` in the processor chain.
The `opentelemetry-instrumentation-logging` package bridges Python's standard `logging` module to the OTel log pipeline for codebases that cannot fully adopt structlog.
Avoid `print` statements and bare `logging.info` calls with unstructured strings for production telemetry.

## Basedpyright and beartype compatibility

OTel type stubs ship with `opentelemetry-api`, providing full basedpyright coverage.
Span attributes accept `AttributeValue` types: `str`, `bool`, `int`, `float`, and sequences thereof.
Ensure OTel initialization happens before beartype's import hooks to avoid instrumentation conflicts.
Stack decorators with `@beartype` outermost so runtime type checking applies to the unwrapped signature:

```python
@beartype
@traced("order.validate")
async def validate_order(order: Order) -> ValidatedOrder:
    ...
```

## Expression library integration

For codebases using the `Expression` library for railway-oriented programming, telemetry integrates at the pipeline boundary.
Pipeline functions (`map`, `bind`, `pipe`) remain pure; do not add spans inside individual stages.
Create a span at the pipeline entry point and record the final outcome as span attributes:

```python
with tracer.start_as_current_span("order.pipeline") as span:
    result = pipe(raw_order, validate_order, bind(enrich_with_pricing), bind(apply_discounts))
    match result:
        case Ok(order):
            span.set_attribute("order.id", order.id)
        case Error(e):
            span.set_attribute("error.type", type(e).__name__)
            span.set_status(Status(StatusCode.ERROR))
```

## Metrics

Access the meter via `metrics.get_meter('service-name')`.

```python
from opentelemetry import metrics

meter = metrics.get_meter("calibration-service")
request_counter = meter.create_counter("http.server.requests")
latency_histogram = meter.create_histogram("http.server.request.duration", unit="ms")
pool_gauge = meter.create_observable_gauge(
    "db.connection.pool.size",
    callbacks=[lambda options: [metrics.Observation(pool.active_count())]],
)
```

Counters track monotonically increasing values.
Histograms capture distributions (latency, payload sizes).
Observable gauges report current values via callbacks at collection time.

## Context propagation in async operations

Python's `contextvars` module propagates OTel context across `asyncio` tasks automatically, including the active span.
For cross-process propagation (message queues, task workers), inject context on the producer side and extract on the consumer:

```python
from opentelemetry import propagation, context

# Producer
headers = {}
propagation.inject(headers)
await queue.publish(payload=data, headers=headers)

# Consumer
ctx = propagation.extract(carrier=message.headers)
token = context.attach(ctx)
try:
    with tracer.start_as_current_span("message.process"):
        handle_message(message.payload)
finally:
    context.detach(token)
```

## Architectural integration

Follow the layered pattern from `preferences-architectural-patterns`.
The domain layer contains pure functions with no telemetry imports, returning values and errors through the type system.
The application layer creates spans for workflow orchestration via `tracer.start_as_current_span`, wrapping domain and infrastructure compositions.
The infrastructure layer is auto-instrumented by OTel instrumentors (`requests`, `httpx`, `sqlalchemy`, `psycopg`, ASGI frameworks).
The presentation layer receives root request spans from framework middleware (FastAPI, Django, Flask), which parent all downstream spans.
This ensures domain logic remains pure and testable, logging effects are explicit at boundaries, and infrastructure is observable without manual instrumentation.

**See also**:
- preferences-architectural-patterns for effect isolation and layered architecture
- preferences-observability-engineering/02-instrumentation-patterns.md for the general instrumentation progression
- OpenTelemetry Semantic Conventions: https://opentelemetry.io/docs/specs/semconv/
