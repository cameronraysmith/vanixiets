# Structured logging and telemetry

## OpenTelemetry SDK for Node.js

The `@opentelemetry/sdk-node` package provides the standard telemetry foundation for Node.js applications.
NodeSDK initializes TracerProvider, MeterProvider, and LoggerProvider through a single entry point, consolidating telemetry setup into one configuration site.
Configure OTLP exporters via `@opentelemetry/exporter-trace-otlp-grpc` and `@opentelemetry/exporter-metrics-otlp-grpc` for gRPC transport, or the `-http` variants for HTTP/protobuf.
Auto-instrumentation via `@opentelemetry/auto-instrumentations-node` provides HTTP, Express, Fastify, Koa, database client, and gRPC span creation without manual code changes.
Register the SDK before any application imports to ensure instrumentation patches apply to library modules at load time.

## Tracer and span creation

Access the tracer via `trace.getTracer('service-name')`.
Create spans for significant operations using the active span pattern:

```typescript
tracer.startActiveSpan('order.process', (span) => {
  span.setAttribute('order.id', orderId);
  try {
    const result = processOrder(order);
    span.setStatus({ code: SpanStatusCode.OK });
    return result;
  } catch (error) {
    span.recordException(error);
    span.setStatus({ code: SpanStatusCode.ERROR });
    throw error;
  } finally {
    span.end();
  }
});
```

The active span context propagates automatically through async operations in Node.js via `AsyncLocalStorage`.
Always call `span.end()` to finalize timing.
Record errors with `span.recordException(error)` followed by `span.setStatus({ code: SpanStatusCode.ERROR })`.

## Event naming conventions

Follow the hierarchical dot-separated pattern: `component.operation.outcome`.

```typescript
// Component.operation.outcome pattern
logger.info({ name: 'calibration.process.started' }, 'starting calibration');
logger.info({ name: 'calibration.process.completed' }, 'calibration succeeded');
logger.warn({ name: 'calibration.process.failed' }, 'calibration failed');
```

Use OpenTelemetry semantic conventions for standard span and log attributes: `http.request.method`, `http.response.status_code`, `url.path`, `db.system`, `db.operation.name`, `db.query.text`, `rpc.service`, `rpc.method`.
This enables hierarchical filtering (`calibration.*`, `*.failed`) and consistent attribute names across services.

## Structured logging with pino

Use `pino` as the structured logger for Node.js applications.
Configure pino to emit JSON with trace context fields (`trace_id`, `span_id`) extracted from the active span context.

The `pino-opentelemetry-transport` package bridges pino logs into the OTel log pipeline, sending structured log records alongside traces and metrics through a unified OTLP exporter.
Alternatively, `@opentelemetry/instrumentation-pino` auto-injects trace context into pino log records without requiring explicit configuration in each log call.

```typescript
import pino from 'pino';
import { trace } from '@opentelemetry/api';

const logger = pino({
  mixin() {
    const span = trace.getActiveSpan();
    if (span) {
      const ctx = span.spanContext();
      return { trace_id: ctx.traceId, span_id: ctx.spanId };
    }
    return {};
  },
});
```

Avoid `console.log` for production telemetry.
Unstructured output cannot be correlated with traces, filtered by severity, or aggregated by log management systems.

## Effect-TS telemetry integration

For codebases using Effect-TS, telemetry integrates through the Effect runtime rather than manual span management.
Effect's `Tracer` module provides span creation that participates in the Effect fiber context, propagating trace context through `flatMap`, `map`, and `zip` compositions automatically.
The `@effect/opentelemetry` package bridges Effect spans to OpenTelemetry spans, allowing Effect-based services to emit traces compatible with any OTel-consuming backend.

Effects that perform I/O (database queries, HTTP requests, message queue operations) should be wrapped in spans at the service layer.
Domain effects representing pure computation should not create spans.
Apply the same layered discipline described in `preferences-architectural-patterns`: domain logic remains free of telemetry concerns, and observability attaches at the boundaries where effects execute.

## Metrics

Access the meter via `metrics.getMeter('service-name')`.
Create instruments matched to the measurement semantics:

```typescript
const requestCounter = meter.createCounter('http.server.requests');
const latencyHistogram = meter.createHistogram('http.server.request.duration', {
  unit: 'ms',
});
const poolGauge = meter.createObservableGauge('db.connection.pool.size');

poolGauge.addCallback((result) => {
  result.observe(pool.activeConnections(), { db.system: 'postgresql' });
});
```

Counters track monotonically increasing values (request counts, error counts).
Histograms capture distributions (latency, payload sizes).
Observable gauges report current values via callbacks invoked at collection time (connection pool sizes, queue depths).

## Context propagation across async boundaries

Node.js uses `AsyncLocalStorage` (via `@opentelemetry/context-async-hooks`) to propagate span context across async boundaries automatically.
This covers `async/await`, promises, timers, and event emitters within a single process.

For cross-process propagation (message queues, task workers, event buses), inject context into message headers on the producer side and extract on the consumer side:

```typescript
import { propagation, context } from '@opentelemetry/api';

// Producer: inject trace context into message headers
const headers: Record<string, string> = {};
propagation.inject(context.active(), headers);
await queue.publish({ payload, headers });

// Consumer: extract trace context from message headers
const extractedContext = propagation.extract(context.active(), message.headers);
context.with(extractedContext, () => {
  tracer.startActiveSpan('message.process', (span) => {
    handleMessage(message.payload);
    span.end();
  });
});
```

This creates a continuous trace across service boundaries, linking the producing span to the consuming span through shared trace context.

## Architectural integration

Follow the layered pattern from `preferences-architectural-patterns`:

The domain layer contains pure functions with no telemetry imports.
Domain logic returns values and errors through the type system; it never creates spans or emits log events.

The application and service layer creates spans for workflow orchestration and records business events as span attributes.
This is where `tracer.startActiveSpan` calls belong, wrapping the composition of domain operations and infrastructure calls.

The infrastructure layer is auto-instrumented by OTel SDK wrappers (HTTP clients, database drivers, gRPC channels) via the corresponding `@opentelemetry/instrumentation-*` packages.

The presentation and handler layer receives root request spans from framework middleware (Express, Fastify, Koa instrumentation), which become the parent for all downstream spans within the request lifecycle.

This layered approach ensures domain logic remains pure and testable, logging effects are explicit at boundaries, and infrastructure operations are observable without manual instrumentation.

**See also**:
- preferences-architectural-patterns for effect isolation and layered architecture
- preferences-observability-engineering/02-instrumentation-patterns.md for the general instrumentation progression
- OpenTelemetry Semantic Conventions: https://opentelemetry.io/docs/specs/semconv/
