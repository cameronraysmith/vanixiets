# Hypermedia architecture

## Philosophy

Hypermedia architecture inverts the single-page application (SPA) model by making the server the source of truth for application state and UI rendering.
The server generates HTML fragments and sends them to the browser, which renders them natively using the DOM.
This approach eliminates the duplication of state management, validation logic, and business rules that occurs when both client and server attempt to maintain authoritative views of application state.

The fundamental contrast with SPA architectures:

- **Hypermedia**: `Server → HTML → Browser native DOM`
- **SPA**: `Server → JSON → Client framework → Virtual DOM → Render`

In hypermedia systems, HTML is the data format.
The server uses hypermedia as the engine of application state (HATEOAS), controlling what actions users can take next through links, forms, and HTML fragments embedded in responses.

## Server-first UI generation

The server generates complete or partial HTML representations of application state and transmits them to the browser for direct rendering.
This means the server owns the presentation layer, not just the data layer.

Key principles:

- Backend is the single source of truth for both application state and its visual representation
- Server determines which UI elements to update, when to update them, and what content to display
- Browser acts as a rendering target, not an application runtime with duplicated business logic
- UI updates are server-driven patches to specific DOM elements identified by selectors

Contrast this with SPA frameworks where the client receives abstract data (JSON) and must reconstruct UI state using client-side rendering logic.
In hypermedia systems, the client receives concrete UI (HTML) ready for immediate display.

## Effect boundaries and functional architecture

Hypermedia architecture aligns naturally with functional programming's treatment of effects as explicit boundaries rather than pervasive concerns.

### Domain layer

Pure functions with no I/O dependencies:

- Business logic expressed as transformations of algebraic data types
- Validation rules that produce Result/Either types indicating success or domain errors
- Computations that are deterministic and referentially transparent
- No database calls, no network requests, no file system access

Example domain function signature (language-agnostic):

```
validateOrder : OrderRequest -> Result<Order, ValidationError>
calculateTotal : Order -> Money
applyDiscount : (DiscountRule, Order) -> Result<Order, DiscountError>
```

### Application layer

The async/sync boundary where effects are coordinated:

- Orchestrates domain logic with infrastructure concerns
- Sequences I/O operations (database queries, external API calls, message publishing)
- Translates infrastructure results into domain types
- Handles transaction boundaries and error recovery
- **Generates HTML fragments from domain model results**

This layer is where the synchronous domain logic meets asynchronous infrastructure.
The application layer coordinates effects but delegates their implementation to infrastructure.

Example application layer orchestration:

```
async handleCheckout(request):
  # Parse request into domain type (sync)
  orderReq = parseCheckoutRequest(request)

  # Validate using pure domain logic (sync)
  order = validateOrder(orderReq)
  if order is Error:
    return renderValidationError(order.error)  # HTML fragment

  # Effect: persist to database (async)
  saved = await orderRepository.save(order.value)

  # Effect: publish event (async)
  await eventBus.publish(OrderCreated(saved.id))

  # Generate HTML response (sync)
  return renderOrderConfirmation(saved)  # HTML fragment
```

### Infrastructure layer

Concrete implementations of effects:

- Database adapters that execute queries and map results to domain types
- HTTP clients that communicate with external services
- Message brokers (pub/sub systems like Redis, NATS, Kafka)
- File system operations
- WebSocket and Server-Sent Events (SSE) transport mechanisms

The infrastructure layer should not contain business logic.
It translates between external protocols (SQL, HTTP, binary formats) and domain types defined in the domain layer.

### The async/sync boundary as the effect boundary

The transition from synchronous domain logic to asynchronous infrastructure operations marks the effect boundary.

Pure domain logic remains synchronous and side-effect-free.
Application logic becomes asynchronous when coordinating effects.
Infrastructure operations are inherently asynchronous (network I/O, disk I/O, concurrency).

This boundary creates a natural separation:

- **Inside the boundary**: referentially transparent functions that can be tested without mocks, composed freely, and reasoned about algebraically
- **Outside the boundary**: effectful operations that require runtime context (database connections, API credentials, message queues)

Hypermedia architecture makes this boundary explicit because HTML generation happens *after* domain logic completes and *before* infrastructure delivers the response.
The rendering step transforms pure domain results into hypermedia representations without introducing additional effects.

## Hypermedia as the engine of application state (HATEOAS)

HATEOAS is a constraint of REST architecture stating that clients interact with applications entirely through hypermedia provided dynamically by servers.

In practice, this means:

- Server responses include not just data but also available actions (links, forms, buttons)
- The server controls application flow by determining what the user can do next
- Clients do not construct URLs or assume API structure; they follow links provided by the server
- Application state transitions are discovered at runtime, not hardcoded in client logic

Example: after successfully creating an order, the server returns HTML containing:

- A confirmation message
- A link to view the order details
- A link to return to the product catalog
- Possibly a form to cancel the order (if cancellation is allowed in the current state)

The client does not "know" these actions exist in advance.
The server includes them in the response because they are valid state transitions from the current application state.

Benefits:

- Server can evolve available actions without breaking clients (as long as HTML semantics remain stable)
- Authorization logic lives on the server; unauthorized actions simply do not appear as links/forms
- API exploration is self-documenting through hyperlinks

## Streaming updates via Server-Sent Events

Server-Sent Events (SSE) provide a unidirectional transport for pushing HTML fragments from server to client over HTTP.

SSE characteristics:

- Lightweight compared to WebSockets (HTTP/1.1 long-polling or HTTP/2 streaming)
- Automatic reconnection with configurable retry intervals
- Event-based protocol with named event types and data payloads
- Browser-native `EventSource` API with wide compatibility

Hypermedia over SSE workflow:

1. Client establishes SSE connection to server endpoint
2. Server sends events containing HTML fragments and metadata (target selectors, merge strategies)
3. Client's hypermedia library patches the DOM using the provided instructions
4. Connection remains open for subsequent updates (real-time notifications, live data)

Use cases:

- Live dashboards where metrics update without polling
- Collaborative editing where changes from other users appear in real-time
- Progress indicators for long-running operations
- Notifications and alerts pushed from server

Contrast with polling:

- SSE eliminates client-initiated request cycles
- Server pushes updates when state changes occur, not on a fixed interval
- Reduces latency (no waiting for next poll) and bandwidth (no empty responses)

See `02-sse-patterns.md` for SSE streaming implementation details and `03-signals.md` for reactive state synchronization.

## Anti-patterns to avoid

### Client-side reactivity frameworks alongside hypermedia

Hypermedia systems derive their architectural benefits from server-driven state management.
Introducing client-side reactive frameworks (React, Vue, Svelte, SolidJS) defeats this purpose by reintroducing duplicated state on the client.

Problems with hybrid approaches:

- Two competing sources of truth: server-driven HTML updates vs. client-side reactive state
- Developers must decide which layer owns each piece of state, creating cognitive overhead
- Client-side validation and business logic duplicate server-side implementations
- Framework bundle sizes negate the bandwidth savings from hypermedia's HTML-over-wire approach

If you find yourself needing React to manage client state, reconsider whether the server should own that state and push updates via SSE.

Exceptions where limited client-side JavaScript is acceptable:

- Progressive enhancement for accessibility (keyboard navigation, focus management)
- Optimistic UI feedback that shows immediate response before server confirmation (with clear loading states)
- Client-only ephemeral state (dropdown menu open/closed, modal visibility) that never syncs to server

### WASM SPA frameworks in hypermedia contexts

WebAssembly (WASM) SPA frameworks like Leptos (Rust), Dioxus (Rust), or Blazor (C#) compile server-side languages to run in the browser, creating a client-side reactive runtime.

These frameworks contradict hypermedia architecture:

- They move application logic to the client, eliminating the server-as-source-of-truth model
- They bundle large WASM payloads that must download and initialize before UI renders
- They require complex hydration or client-side routing that conflicts with server-driven navigation
- They reintroduce the SPA problem space (state synchronization, client-side validation, bundle optimization)

Use WASM for computationally intensive client-side tasks (image processing, cryptography, games), not as a UI framework in hypermedia applications.

### Optimistic updates that deceive users

Optimistic updates assume an operation will succeed and immediately show the success state in the UI before receiving server confirmation.

This pattern is problematic:

- It creates a dishonest UI that displays states that have not actually occurred
- When operations fail, the UI must "undo" the optimistic change, creating jarring transitions
- Users may take subsequent actions based on false information (e.g., believing an order submitted when it failed)

Prefer honest loading indicators:

- Show a spinner or progress message during server operations
- Display the actual result only after server confirmation
- Use SSE to push the updated state when ready

Optimistic updates are occasionally justified for extremely high-latency operations where user research demonstrates that immediate feedback significantly improves perceived performance.
Even then, the optimistic state should be visually distinct (grayed out, labeled "pending") to signal uncertainty.

### Hardcoded URLs and API assumptions

Clients that construct URLs or assume API endpoint structures violate HATEOAS principles.

Bad pattern:

```javascript
// Client hardcodes URL structure
const deleteUrl = `/api/orders/${orderId}/delete`;
fetch(deleteUrl, { method: 'POST' });
```

Good pattern:

The server includes the delete action as a hyperlink or form in the order detail HTML:

```html
<button hx-post="/orders/12345/cancel" hx-target="#order-status">
  Cancel Order
</button>
```

The client does not construct the URL; it follows the link provided by the server.
If the server changes the URL scheme or decides cancellation is no longer allowed for this order, it simply omits the button from the response.

### Premature abstraction of server-side rendering

Hypermedia architecture requires servers to generate HTML.
Avoid creating elaborate templating abstractions or component frameworks unless justified by actual duplication.

Start with simple template rendering:

- Use the server language's native templating (Go templates, Jinja2, ERB, Razor)
- Inline small fragments directly in handler functions for trivial cases
- Extract reusable templates only when you observe repeated patterns

Premature abstraction risks:

- Inventing a component model that mimics React, defeating the simplicity of hypermedia
- Creating indirection that obscures the server's control over HTML generation
- Over-engineering template composition when most responses are unique

The server's role is to generate correct HTML for the current application state.
Keep rendering logic as direct and obvious as possible.

## Integration with functional domain modeling

Hypermedia architecture complements functional domain modeling by maintaining clear boundaries between pure domain logic and effectful infrastructure.

Workflow:

1. **Parse request** into domain types using smart constructors that return `Result<DomainType, ValidationError>`
2. **Execute domain logic** using pure functions that transform domain types
3. **Persist or publish** results using infrastructure effects (async boundary)
4. **Render HTML** from domain types using templates or HTML builder libraries
5. **Stream response** via HTTP or SSE

The domain model never depends on HTTP, HTML, or database concerns.
The application layer orchestrates these dependencies without leaking them into domain logic.

Example with smart constructor validation:

```
# Domain layer (sync, pure)
type Email = Email of string  # private constructor

validateEmail : string -> Result<Email, ValidationError>
validateEmail raw =
  if Regex.isMatch(emailPattern, raw) then
    Ok(Email(raw))
  else
    Error("Invalid email format")

# Application layer (async, effectful)
async handleSignup(request):
  emailResult = validateEmail(request.email)
  if emailResult is Error:
    return renderError(emailResult.error)  # HTML fragment

  user = await userRepository.create(emailResult.value)
  return renderWelcome(user)  # HTML fragment
```

The domain function `validateEmail` knows nothing about HTTP or HTML.
The application layer translates validation errors into HTML error messages.

See `domain-modeling.md` for smart constructor patterns and `railway-oriented-programming.md` for Result-based error handling.

## Architectural decision criteria

Choose hypermedia architecture when:

- The server is the authoritative source of application state and business logic
- UI updates can tolerate server round-trip latency (most CRUD applications, dashboards, content sites)
- You want to minimize client-side complexity and JavaScript bundle sizes
- The team has strong backend expertise and prefers server-side rendering
- Real-time updates are needed but can be server-pushed (SSE) rather than client-initiated

Reconsider hypermedia when:

- The application requires offline-first functionality (service workers with local state)
- Extremely low-latency interactions are critical (collaborative drawing, real-time gaming)
- The UI is highly stateful and interactive with complex client-side transitions (video editor, CAD tool)
- The team has invested heavily in SPA tooling and expertise

Hybrid approaches (hypermedia for navigation, SPA islands for complex widgets) are possible but introduce cognitive overhead and dual state management.
Prefer committing to one model unless you have a compelling reason to mix paradigms.

## Progressive enhancement and accessibility

Hypermedia architecture enables progressive enhancement because the server sends semantic HTML that works without JavaScript.

Progressive enhancement layers:

1. **Base layer**: HTML forms and links that work with zero JavaScript (full page reloads)
2. **Enhanced layer**: Hypermedia library intercepts form submissions and link clicks, replaces full reload with targeted DOM updates
3. **Optimized layer**: SSE adds real-time updates and server-pushed notifications

If JavaScript fails to load or is disabled, the application degrades gracefully to full page navigation.
The server handles both traditional form submissions and hypermedia-enhanced requests using the same backend logic.

Accessibility benefits:

- Semantic HTML ensures screen readers and assistive technology receive meaningful markup
- Server-generated HTML can include ARIA attributes based on application state
- Focus management and keyboard navigation work natively without framework-specific abstractions

Avoid client-side rendering that generates empty `<div id="root"></div>` containers requiring JavaScript to display content.
The server should always send meaningful HTML in the initial response.

## Comparison with SPA architectures

| Dimension | Hypermedia | SPA |
|-----------|-----------|-----|
| State authority | Server | Client + Server (dual) |
| Data format | HTML | JSON |
| Rendering location | Server | Client (browser) |
| Client bundle | Minimal (hypermedia lib ~10KB) | Large (framework + app code 100KB-1MB+) |
| Navigation | Server-driven links/forms | Client-side routing |
| Real-time updates | Server-Sent Events (push) | Polling or WebSockets |
| Effect boundary | Application layer (server) | Scattered across client + server |
| Offline support | Requires service worker + cache | Native (client state) |
| SEO | Excellent (server renders HTML) | Requires SSR workarounds |
| Initial page load | Fast (HTML + minimal JS) | Slow (download + parse + execute framework) |
| Backend complexity | Higher (HTML generation) | Lower (JSON APIs) |
| Frontend complexity | Lower (no state management) | Higher (state synchronization) |

Hypermedia trades backend templating complexity for drastically reduced frontend complexity.
SPAs trade large client bundles and dual state management for richer client-side interactions and offline capabilities.

## Related documents

- `02-sse-patterns.md` - Server-Sent Events streaming patterns and error handling
- `03-signals.md` - Reactive state synchronization between server and client
- `04-testing.md` - Testing strategies for hypermedia applications
- `~/.claude/commands/preferences/domain-modeling.md` - Functional domain modeling with algebraic types
- `~/.claude/commands/preferences/railway-oriented-programming.md` - Result-based error handling patterns
- `~/.claude/commands/preferences/architectural-patterns.md` - General architectural principles
