# Instrumentation patterns

## OpenTelemetry component model

OpenTelemetry defines a layered architecture that separates instrumentation from implementation and export.
Understanding the components and their boundaries is essential for designing instrumentation that is portable, maintainable, and decoupled from any specific backend.

The API is the specification layer.
It defines the interfaces for creating spans, recording metrics, and emitting logs.
Application code and library authors instrument against the API, which carries no implementation.
Code instrumented against the OTel API works regardless of which backend (or no backend) is configured at runtime.

The SDK is the concrete implementation that backs the API.
It manages state: tracking the current active span, batching telemetry for export, applying sampling decisions, and managing resource attribution.
The SDK is configured once at application startup and is invisible to instrumented code.

The Tracer is the SDK component that tracks the current active span.
When instrumented code creates a child span, the Tracer automatically sets its parent to the current active span, building the trace tree without explicit parent references in application code.

The Meter is the SDK component that tracks metric instruments (counters, gauges, histograms).
Metric instruments are created once and reused across the application's lifetime.
The Meter aggregates measurements according to the instrument type and exports them at configured intervals.

Context propagation is the mechanism that stitches traces across service boundaries.
On the receiving side, it deserializes trace context from incoming request headers (W3C TraceContext or B3 format).
During request processing, it tracks the current request context so that spans created anywhere in the call stack are correctly parented.
On the outgoing side, it serializes context into outgoing request headers so the downstream service can continue the trace.

The Exporter is a plugin that translates in-memory telemetry objects into a wire format and transmits them to a destination.
OTLP (OpenTelemetry Protocol) is the default wire protocol.
Exporters for other formats exist for backward compatibility with existing backends.

The Collector is a standalone binary that receives telemetry from applications, processes it (filtering, transforming, sampling), and routes it to one or more backends.
The Collector decouples applications from backends: applications export to the Collector using OTLP, and the Collector handles the complexity of routing to multiple destinations, retrying on failure, and buffering during backend outages.

## Instrumentation progression

Instrumentation is best adopted incrementally rather than comprehensively from the start.

Start with automatic instrumentation.
OTel provides wrappers for common frameworks and libraries: HTTP servers, HTTP clients, gRPC, database drivers, message queue clients.
These wrappers create spans for every inbound and outbound call automatically, providing the skeleton of who-calls-whom across services.
Automatic instrumentation alone reveals service dependencies, latency distribution across the call graph, and error rates per service boundary.

Add custom attributes to auto-instrumented spans.
The auto-generated spans capture transport-level details (HTTP method, status code, URL) but lack business logic context.
Adding attributes for client ID, tenant ID, shard ID, feature flag state, shopping cart ID, or other domain-specific identifiers transforms generic transport spans into rich business events.
This is the highest-leverage instrumentation step: minimal code for maximum debugging value.

Create sub-spans for expensive internal operations.
When a service performs multiple sequential or parallel operations within a single request (database queries, cache lookups, computation, external API calls), sub-spans provide a waterfall view showing where time is spent.
Sub-spans are most valuable for operations where latency is a concern and the internal breakdown is not obvious from the auto-instrumented service boundary spans alone.

Record process-wide metrics as span attributes when possible.
Rather than maintaining separate metric counters for values that are meaningful in request context (queue depth at time of processing, connection pool utilization, thread pool saturation), record them as attributes on the request span.
This co-locates the metric with the request context, enabling correlation during investigation.
Standalone metrics are appropriate for values that exist outside request context (total memory usage, garbage collection frequency, process uptime).

## Structured event lifecycle

The structured event is the conceptual foundation of rich telemetry, whether it manifests as a wide span, a structured log line, or a dedicated event record.

Initialize an empty map when a request enters the service.
Pre-populate it with request parameters (method, path, query parameters, headers), environmental information (service name, version, instance ID, region, availability zone), and runtime internals (language runtime version, garbage collector state, thread pool size).

During request execution, append every interesting detail as it becomes available.
User ID after authentication.
Tenant ID after routing.
Shopping cart ID or order ID after context resolution.
Remote call results (status codes, latencies, retry counts) for each downstream dependency.
Intermediate computed values that would be useful during debugging.
Feature flag evaluation results.
Cache hit/miss status.

At request exit, append the final details: total duration, response status code, error message if present, bytes sent.
Emit the completed map to the telemetry pipeline.

The cost of adding a field to a structured event is negligible once the infrastructure exists.
The cost of not having a field when debugging an incident is high: it means shipping new instrumentation and waiting for the problem to recur.
The bias should be toward including information rather than excluding it, with the understanding that sampling and storage tiering manage the volume cost.

## Metrics types and naming

Three fundamental metric types serve different measurement needs.

Counters are monotonically increasing values that track cumulative totals: requests served, bytes transmitted, errors encountered.
Counters only go up (or reset to zero on process restart).
The rate of change of a counter is computed at query time, not recording time.

Gauges are point-in-time values that can increase or decrease: queue depth, active connections, memory usage, temperature.
Gauges represent the current state of something, not a cumulative total.

Histograms record the distribution of values: request latency, response size, batch processing time.
Histograms capture the full shape of the distribution (minimum, maximum, percentiles, counts per bucket) rather than reducing it to a single summary statistic.

Naming conventions should be established early and enforced organization-wide.
Metric names form a schema: changing them retroactively breaks dashboards, alerts, and queries across every consumer.
A consistent naming pattern (service.subsystem.metric_name with units in the name, e.g., `http.server.request.duration_ms`) makes metrics discoverable and prevents the proliferation of inconsistent names that mean the same thing.

## RED and USE methods

The RED method applies to every service boundary in the system.
Rate measures requests per second flowing through the service.
Errors measures failed requests per second.
Duration measures the latency distribution of requests.
RED answers the question: is this service healthy from the perspective of its callers?

The USE method applies to every significant resource in the system.
Utilization measures the proportion of the resource that is busy (CPU percentage, disk bandwidth usage, connection pool occupancy).
Saturation measures the degree of queuing or backpressure (run queue length, request queue depth, thread pool pending tasks).
Errors measures error events per unit time for that resource (disk errors, network errors, allocation failures).
USE answers the question: is this resource constrained in a way that could affect service health?

RED and USE are complementary.
RED detects symptoms (the service is slow or erroring) and USE identifies resource-level causes (the database connection pool is saturated, the disk is at capacity).
Together, they provide a structured framework for both detection and initial diagnosis.

## Schema management

At smaller scales, manage telemetry schemas with constants or enums in code.
A shared library defining span names, attribute keys, and metric names ensures consistency across services and prevents schema drift.

At larger scales, telemetry pipelines can normalize schemas: renaming attributes, adding missing fields with defaults, and rejecting events that do not conform to the schema.
Pipeline-based normalization is useful when multiple teams instrument independently and consistency must be enforced centrally.

The key principle is that naming conventions are cheaper to establish early than to retrofit later.
Renaming instrumentation retroactively requires updating every producer (application code), every consumer (queries, dashboards, alerts), and maintaining backward compatibility during the transition.

## Iterative instrumentation

Do not attempt to instrument everything at once.
The initial investment in automatic instrumentation and custom attributes on key services provides a foundation.
From there, instrumentation grows iteratively: whenever an engineer investigates an incident and discovers a gap in telemetry, the first action should be to add the missing instrumentation.

After two or three iterations of this pattern, the value becomes self-evident.
The services that are investigated most often become the most richly instrumented, which is exactly the right allocation of instrumentation effort.
Services that never cause problems remain lightly instrumented, which is appropriate because the investment in deeper telemetry would not pay for itself.

This iterative approach also ensures that instrumentation reflects actual debugging needs rather than hypothetical ones.
Engineers instrument what they actually needed to know during real incidents, not what they imagined they might need.
The result is a telemetry suite that is tuned to the system's actual failure modes.

## Instrumentation as code review concern

Instrumentation quality should be a standard code review dimension.
When reviewing a change that adds a new code path, request handler, or external integration, the reviewer should consider whether the change includes adequate telemetry.
A new API endpoint without spans, a new database query without timing attributes, or a new error path without context capture are all instrumentation gaps that will cost debugging time later.

This review practice does not require extensive instrumentation expertise.
The basic question is straightforward: "If this code fails in production, does the telemetry capture enough context to investigate without reproducing the failure locally?"
If the answer is no, the change should add the missing instrumentation before merging.
This shifts instrumentation from a reactive practice (add it after the first incident) to a proactive one (add it as part of development), which is the observability-driven development approach described in the main skill document.
