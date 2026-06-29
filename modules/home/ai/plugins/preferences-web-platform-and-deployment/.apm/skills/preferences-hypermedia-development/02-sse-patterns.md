# Server-Sent Events streaming patterns

## Protocol fundamentals

Server-Sent Events (SSE) is the primary transport layer for hypermedia-driven applications.
Unlike WebSockets which provide bidirectional communication, SSE is unidirectional server-to-client streaming, perfectly aligned with the hypermedia model where servers push HTML updates to clients.

SSE is standardized in the WHATWG HTML Living Standard: https://html.spec.whatwg.org/multipage/server-sent-events.html

### HTTP response configuration

SSE requires specific HTTP headers to establish the event stream:

```
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
```

For HTTP/2 and HTTP/3, the `Connection: keep-alive` header is unnecessary as persistent connections are the default.

The server must immediately flush the response headers to the client to establish the stream before sending any events.
Buffering the response will cause connection timeouts.

### Event message format

Each event consists of one or more fields, each on its own line, terminated by a blank line:

```
event: message-type
id: unique-event-id
retry: 5000
data: event payload line 1
data: event payload line 2

```

Field semantics:
- `event:` - Event type name (defaults to "message" if omitted)
- `id:` - Unique identifier for this event, used for reconnection replay
- `retry:` - Milliseconds the client should wait before reconnecting after disconnect
- `data:` - Payload content (multiple data lines concatenated with newlines)

The blank line at the end is mandatory and triggers event dispatch to the client.

### Character encoding and escaping

All SSE content must be UTF-8 encoded.
Newlines within field values must be expressed as multiple field declarations (e.g., multiple `data:` lines).
There is no escape sequence for literal newlines within a single field value.

Colon characters (`:`) within field values do not require escaping.
Lines beginning with `:` are comments and ignored by the client:

```
: heartbeat comment
data: actual event data
```

## Event types for hypermedia applications

Hypermedia applications using SSE typically employ three primary event types, each serving a distinct purpose in the update model.

### Patch elements

Send HTML fragments to update specific parts of the DOM.
This is the core hypermedia pattern: server renders HTML, client merges it into the existing document.

Event structure:
```
event: patch-element
data: {"selector": "#notifications", "merge": "morph", "fragment": "<div>...</div>"}

```

Merge strategies:
- `morph` - Intelligent DOM diffing to preserve focus, scroll position, and component state
- `inner` - Replace innerHTML
- `outer` - Replace outerHTML
- `prepend` - Insert before first child
- `append` - Insert after last child
- `before` - Insert before matched element
- `after` - Insert after matched element
- `delete` - Remove matched element

The selector should be a CSS selector identifying the target element(s).
Multiple elements matching the selector should all receive the update.

### Patch signals

Send JSON to update reactive client-side state without DOM manipulation.
Signals represent application state that may influence multiple UI regions.

Event structure:
```
event: patch-signal
data: {"signal": "cart.items", "value": [{"id": 1, "quantity": 2}]}

```

Signal updates trigger reactive re-rendering in signal-aware frameworks.
This pattern allows server-side state changes to propagate to client UI without sending full HTML fragments for every affected region.

Use signals for:
- Cross-cutting state (authentication status, theme preference)
- State consumed by multiple components
- High-frequency updates where HTML rendering would be excessive

Avoid signals for:
- State that maps 1:1 with a single DOM region (use patch-element instead)
- Complex object graphs (prefer normalized structures)

### Execute script

Send JavaScript for client execution.
Use this pattern sparingly as it bypasses hypermedia principles.

Event structure:
```
event: execute-script
data: console.log("Server-initiated action");

```

Legitimate use cases:
- Triggering browser APIs unavailable via HTML (clipboard, notifications)
- Performance-critical animations
- Integration with third-party JavaScript libraries

Do not use for:
- Business logic (belongs on server)
- State management (use signals)
- DOM updates (use patch-element)

## Connection lifecycle

SSE connections follow a predictable lifecycle with automatic browser-managed reconnection.

```
┌──────────┐
│          │
│ Connecting │
│          │
└─────┬────┘
      │
      v
┌──────────┐      ┌────────────┐
│          │      │            │
│ Subscribed├─────►│Disconnected│
│          │      │            │
│(streaming)│      │            │
└──────────┘      └──────┬─────┘
      ^                   │
      │                   │
      │            ┌──────v─────┐
      │            │            │
      └────────────┤   Retry    │
                   │            │
                   │(exponential│
                   │  backoff)  │
                   └────────────┘
```

### Automatic reconnection

Browsers implement automatic reconnection with exponential backoff when SSE connections drop.
Initial retry delay defaults to 3000ms but can be customized via the `retry:` field.

The client sends the `Last-Event-ID` header on reconnection:
```
GET /events HTTP/1.1
Last-Event-ID: event-123
```

The server should replay all events since the specified ID to ensure gap-free delivery.
If the requested event ID is too old (beyond server retention window), send a full state snapshot.

### Keep-alive heartbeats

Intermediate proxies and load balancers may close idle connections.
Send periodic heartbeat comments to prevent timeouts:

```
: heartbeat
```

Recommended heartbeat interval: 15-30 seconds.
Heartbeats do not trigger client-side events but keep the TCP connection alive.

## Reconnection resilience pattern

Race conditions occur when events arrive during reconnection replay.
The resilience pattern ensures no events are lost or duplicated.

### Problem: naive replay loses events

Naive approach:
1. Client reconnects with `Last-Event-ID: 100`
2. Server queries historical events 101-150
3. Server streams historical events to client
4. Server subscribes client to live event bus
5. ❌ Events 151-155 arrived during step 3 and were missed

### Solution: subscribe before replay

Correct approach:
1. Client reconnects with `Last-Event-ID: 100`
2. Server subscribes client to live event bus immediately
3. Server queries historical events 101-150
4. Server streams historical events from query
5. Server streams live events from subscription
6. ✓ All events delivered, possible duplicates if event 150 was the latest before reconnection

The client must be idempotent with respect to duplicate event IDs.
Deduplication strategies:
- Track set of received event IDs (bounded cache, evict oldest)
- Monotonic event ID sequence allows "skip if ID <= last processed ID"

### Event ID design

Event IDs should be:
- Unique and monotonically increasing (timestamp + sequence number, or distributed ID scheme)
- Sortable to enable range queries
- Bounded in size (overly long IDs waste bandwidth)

Example ID formats:
- `<unix-millis>-<sequence>`: `1672531200000-5`
- `<ulid>`: Universally Unique Lexicographically Sortable Identifier
- `<database-sequence>`: Auto-incrementing integer from durable store

Avoid:
- Random UUIDs (not sortable, cannot replay range)
- Client-generated IDs (not authoritative)

## Lag handling

Slow consumers or high event volumes may cause clients to fall behind.
Servers maintain bounded broadcast buffers; overflow causes lag errors.

### Detecting lag

When a client reconnects requesting an event ID beyond the buffer retention window:
```
GET /events HTTP/1.1
Last-Event-ID: event-50
```

If server buffer only retains events 200-500, event 50 is too old.

Send lag error event:
```
event: error-lag
data: {"message": "Event ID too old, refresh required"}

```

Client should:
1. Close the connection
2. Request full state snapshot (e.g., page reload)
3. Establish new SSE connection

### Preventing lag

Increase buffer size for high-latency clients:
- Configure per-connection buffer (e.g., 1000 events)
- Monitor buffer utilization metrics
- Alert when buffers frequently overflow

Reduce event volume:
- Batch rapid updates (e.g., coalesce 10 price updates into single event)
- Use signals for high-frequency state instead of patching HTML every update
- Implement event prioritization (drop low-priority events under load)

## Resource cleanup

SSE connections are long-lived resources requiring explicit cleanup.

### RAII pattern

Use resource acquisition is initialization (RAII) to ensure cleanup:

```
function handleSSEConnection(request, response) {
  const subscription = eventBus.subscribe();

  response.on('close', () => {
    subscription.unsubscribe();
    activeConnections.decrement();
  });

  activeConnections.increment();

  // stream events...
}
```

The subscription is cleaned up when the response stream closes, whether from client disconnect, timeout, or server shutdown.

### Write timeout detection

Clients may disconnect without closing the TCP connection cleanly (network partition, device sleep).
Configure write timeouts to detect dead connections:

```
response.setTimeout(90000); // 90 seconds (3x heartbeat interval)

response.on('timeout', () => {
  response.end();
  // RAII cleanup triggers
});
```

Write timeout should be 2-3x the heartbeat interval to avoid false positives.

### Graceful shutdown

During server shutdown, close all active SSE connections gracefully:

```
event: server-shutdown
data: {"message": "Server restarting, please reconnect"}

```

Clients receive explicit shutdown notification and can reconnect immediately rather than waiting for timeout + backoff.

### Connection metrics

Track active connection count for monitoring:
- Increment on connection establish
- Decrement on connection close
- Export as Prometheus gauge or equivalent

Alert on:
- Sudden connection count drops (server issue)
- Connection count exceeding capacity (scale up needed)
- High connection churn rate (reconnection storm)

## Multiplexing strategies

Single SSE connection per client or multiple topic-specific connections?

### Single connection (recommended)

Pros:
- Reduced connection overhead (TCP handshakes, TLS negotiation)
- Simpler client code (one EventSource instance)
- Server can correlate all events for a session

Cons:
- Head-of-line blocking (slow processing of one event delays all)
- No per-topic backpressure

Implementation: Use `event:` field to distinguish message types, route to appropriate handlers on client.

### Multiple connections

Pros:
- Per-topic backpressure and buffering
- Parallel processing of independent streams
- Isolated failure domains

Cons:
- Connection overhead (limits scalability)
- Complex client coordination
- Server cannot easily correlate cross-topic events

Implementation: Separate EventSource instances per topic, each with distinct URL endpoint.

Recommendation: Start with single connection, switch to multiple only if profiling shows head-of-line blocking or you need per-topic backpressure control.

## Authentication and authorization

SSE connections are long-lived and require authentication.

### Initial authentication

Use standard HTTP authentication on the EventSource request:

```javascript
const eventSource = new EventSource('/events', {
  withCredentials: true // send cookies
});
```

Server validates session cookie, JWT, or other credential on connection establish.

### Session expiration

Sessions may expire during the SSE connection lifetime.
Send authentication error event:

```
event: error-auth
data: {"message": "Session expired"}

```

Client should:
1. Close EventSource
2. Redirect to login or refresh authentication
3. Reconnect with new credentials

### Authorization for filtered events

Clients may request filtered event streams (e.g., "only events for project X").
Validate authorization on connection establish and on each event before sending:

```
if (!user.canAccessProject(event.projectId)) {
  continue; // skip event
}
```

Do not rely solely on connection-time authorization; permissions may change during connection lifetime.

## Error handling

SSE error scenarios and recovery patterns.

### Client-side error event

JavaScript EventSource fires `error` event on connection failure:

```javascript
eventSource.addEventListener('error', (e) => {
  if (eventSource.readyState === EventSource.CONNECTING) {
    console.log('Reconnecting...');
  } else {
    console.error('SSE error:', e);
  }
});
```

Browser automatically reconnects unless EventSource is explicitly closed.

### Server-side error events

Send application-level errors as typed events:

```
event: error-validation
data: {"field": "email", "message": "Invalid email format"}

```

Clients handle error events distinctly from success events.

Do not use HTTP error status codes (4xx, 5xx) after the SSE connection is established, as this closes the connection.
Send errors as events within the stream.

### Unrecoverable errors

For errors requiring connection termination:

```
event: error-fatal
data: {"message": "Server capacity exceeded"}

```

Client receives the event, then server closes the response stream.
Client should display error message and not automatically reconnect.

## Scaling considerations

SSE connections are stateful and require coordination in multi-instance deployments.

### Sticky sessions

Route all reconnections from a client to the same server instance.
This simplifies event replay (each instance maintains its own event buffer).

Implement via:
- Load balancer session affinity (cookie or IP-based)
- Consistent hashing on client ID

Downside: Instance failure requires full state resync.

### Shared event bus

All instances publish and subscribe to shared message bus (Redis Pub/Sub, NATS, Kafka).
Any instance can handle reconnection and replay events from shared durable log.

Pros:
- No sticky session requirement
- Instance failure transparent to clients
- Simpler horizontal scaling

Cons:
- Additional infrastructure dependency
- Increased latency (network hop to message bus)
- Event ordering complexity in distributed log

### Event persistence

Store events in durable storage for replay beyond in-memory buffer:
- Database table with event ID, timestamp, payload
- Distributed log (Kafka, Pulsar)
- Time-series database

Retention policy should balance storage cost against reconnection window.
Typical retention: last 1000 events or last 5 minutes.

## Testing SSE streams

Strategies for testing SSE functionality.

### Manual testing with curl

```bash
curl -N -H "Accept: text/event-stream" http://localhost:3000/events
```

The `-N` flag disables buffering, showing events as they arrive.

### Automated testing

Mock EventSource in tests:

```javascript
class MockEventSource {
  constructor(url) {
    this.url = url;
    this.listeners = {};
  }

  addEventListener(event, handler) {
    this.listeners[event] = this.listeners[event] || [];
    this.listeners[event].push(handler);
  }

  // test helper: simulate event
  _emit(eventType, data) {
    (this.listeners[eventType] || []).forEach(h => h({data}));
  }
}
```

Inject mock into client code, call `_emit()` to simulate server events.

### Integration testing

Spin up test server, establish real SSE connection, assert events received:

```
1. Start test HTTP server
2. Create EventSource pointing to test server
3. Trigger server action (e.g., POST to API)
4. Assert expected event received on EventSource
5. Close EventSource and server
```

Use test framework timeout to fail if expected event doesn't arrive.

## Performance optimization

### Event batching

Coalesce rapid updates into single event:

```
// Instead of 100 events per second:
event: update
data: {"id": 1, "value": 10}

event: update
data: {"id": 1, "value": 11}

// Batch into one event per second:
event: update-batch
data: {"updates": [{"id": 1, "value": 11}]}
```

Reduces event overhead (per-event framing) and client processing load.

### Compression

Enable HTTP compression for SSE streams:

```
Content-Encoding: gzip
```

SSE text format compresses well (typical 70-90% size reduction for JSON payloads).

Caveat: Compression may delay event delivery (waiting for buffer to fill before flushing).
Configure compressor for low-latency mode or disable compression for time-critical events.

### Connection pooling

Reuse HTTP/2 or HTTP/3 connections for multiple SSE streams.
Modern browsers automatically pool connections to same origin.

Server must support concurrent streams (HTTP/2 SETTINGS_MAX_CONCURRENT_STREAMS).

## Cross-origin considerations

SSE respects CORS (Cross-Origin Resource Sharing).

For cross-origin EventSource requests, server must send:

```
Access-Control-Allow-Origin: https://example.com
Access-Control-Allow-Credentials: true
```

Preflight OPTIONS requests are not used for EventSource GET requests, but authentication headers may trigger preflight if using custom headers.

Recommendation: Serve SSE from same origin as application to avoid CORS complexity.

## Comparison with alternatives

### SSE vs WebSockets

Use SSE when:
- Communication is primarily server-to-client
- Browser compatibility is important (SSE works over HTTP/1.1)
- You want automatic reconnection (built into EventSource)
- You're building hypermedia applications (server pushes HTML)

Use WebSockets when:
- You need bidirectional communication (client sends frequent messages)
- You need binary data support
- You're building real-time multiplayer or collaborative editing

### SSE vs polling

SSE advantages over polling:
- Lower latency (events pushed immediately vs polling interval)
- Lower bandwidth (persistent connection vs repeated request overhead)
- Lower server load (one connection vs many requests)

Polling advantages over SSE:
- Works through restrictive proxies that block long-lived connections
- Simpler server implementation (stateless)
- Natural backpressure (client controls poll rate)

## Cross-references

See `01-architecture.md` for server-first hypermedia principles that motivate SSE as the primary transport layer.

See `03-datastar.md` for Datastar-specific SDK patterns that implement these SSE patterns with additional developer ergonomics.
