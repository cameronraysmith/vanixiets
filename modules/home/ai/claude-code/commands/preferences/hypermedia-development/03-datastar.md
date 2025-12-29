# Datastar framework patterns

Datastar is a hypermedia framework providing reactive signals, SSE-driven DOM updates, and backend-controlled frontend state management.
This document covers Datastar-specific patterns for building hypermedia applications.
See `02-sse-patterns.md` for underlying SSE mechanics and `01-hypermedia-architecture.md` for general hypermedia principles.

## The Tao of Datastar

Most state should live in the backend, which remains the single source of truth.
The server drives the frontend by patching elements and signals rather than the frontend maintaining independent state.
Use signals sparingly - favor fetching current state from the backend over assuming frontend state is current.

In Morph We Trust: send large DOM chunks and let the morphing algorithm handle minimal updates efficiently.
Avoid manual DOM manipulation or trying to optimize what to send - morphing is fast and handles edge cases better than custom logic.

Use loading indicators rather than optimistic updates.
Do not deceive users by pretending an action succeeded before the server confirms it.
Show loading state, wait for server response, then update UI with actual results.

CQRS pattern for network architecture: maintain a single long-lived SSE connection for reads (state updates from server), and use short-lived HTTP requests for writes (user actions).
This separates the read model (passive updates) from the write model (intentional commands).

**See also**: For event sourcing architectures where SSE streams project events from an authoritative event log, see `07-event-architecture.md`.

## Signal system

Signals are reactive variables denoted with `$` prefix syntax: `$signalName`.
All signals are sent to the backend with every request by default - this ensures server always has full context.
Signals can be nested using dot-notation: `$user.profile.name` creates a structured object.

**Theoretical foundation**: Signals exhibit comonadic structure—they hold current values (extract) and support derived computations (extend).
This is the categorical dual of the monadic event channel delivering updates from the server.
See `theoretical-foundations.md` section "Reactive systems and comonads" for the formal model of signals as comonads and signal graphs as free categories.

Local signals use underscore prefix `$_local` and are never sent to backend.
Use local signals for pure UI state like dropdown open/closed, current tab selection, or animation states.

Computed signals derive values from other signals using `data-computed`:

```html
<div data-signals='{"quantity": 1, "price": 10}'>
  <input data-bind:quantity type="number">
  <span data-computed:total="$quantity * $price" data-text="$total"></span>
</div>
```

Two-way binding with `data-bind` updates signals when form inputs change:

```html
<input data-bind:username type="text">
<span data-text="$username"></span>
```

## Data attributes reference

### Signal initialization

`data-signals` initializes signal values as JSON on page load:

```html
<div data-signals='{"user": "alice", "count": 0}'>
  <!-- $user and $count available in scope -->
</div>
```

### Rendering signals

`data-text` renders signal value as text content (HTML-escaped):

```html
<span data-text="$username"></span>
```

`data-html` renders signal value as HTML (use cautiously with trusted content only):

```html
<div data-html="$renderedContent"></div>
```

### Form binding

`data-bind:signalName` creates two-way binding with form inputs:

```html
<input data-bind:email type="email">
<textarea data-bind:message></textarea>
<select data-bind:category>
  <option value="a">Category A</option>
  <option value="b">Category B</option>
</select>
```

### Conditional rendering

`data-show` toggles element visibility based on signal truthiness:

```html
<div data-show="$isLoggedIn">
  Welcome back!
</div>
```

`data-class` applies CSS classes conditionally:

```html
<button data-class:disabled="$isProcessing">
  Submit
</button>
```

### Dynamic attributes

`data-attr:*` sets element attributes from signals:

```html
<a data-attr:href="$profileUrl">Profile</a>
<img data-attr:src="$imageUrl" data-attr:alt="$imageAlt">
```

### Event handlers

`data-on:event` binds event handlers to backend actions:

```html
<button data-on:click="@post('/api/increment')">
  Increment
</button>

<form data-on:submit="@post('/api/save')">
  <input data-bind:title type="text">
  <button type="submit">Save</button>
</form>
```

### Loading indicators

`data-indicator` sets a signal to true during request lifecycle:

```html
<button data-on:click="@post('/api/process')" data-indicator:isLoading>
  <span data-show="!$isLoading">Process</span>
  <span data-show="$isLoading">Processing...</span>
</button>
```

### Morph control

`data-ignore-morph` excludes element and its children from morphing algorithm:

```html
<div data-ignore-morph>
  <!-- Third-party library manages this DOM -->
  <custom-element id="external-widget"></custom-element>
</div>
```

Use this for third-party libraries that maintain their own DOM state.
See `05-web-components.md` for integration patterns with external components.

## Backend action attributes

Backend actions send HTTP requests with current signal state.

`@get(url)` sends GET request with signals in query parameter:

```html
<button data-on:click="@get('/search')">Search</button>
```

`@post(url)`, `@put(url)`, `@patch(url)`, `@delete(url)` send signals as JSON body:

```html
<form data-on:submit="@post('/api/items')">
  <input data-bind:name type="text">
  <button type="submit">Create</button>
</form>
```

All signals in scope are sent with every request automatically.
The server receives full state context without manual serialization.

## SDK event types

Datastar SDKs provide three core event types for server-to-client communication over SSE.

### PatchElements

`PatchElements` updates DOM with HTML fragments using morphing algorithm.

Modes control how fragments are applied:

- `morph` (default): Intelligently update element while preserving focus, form state, and event listeners
- `inner`: Morph element's children only
- `outer`: Morph entire element including tag and attributes
- `replace`: Replace element without morphing (destroys state)
- `prepend`: Insert before first child
- `append`: Insert after last child
- `before`: Insert before element
- `after`: Insert after element
- `delete`: Remove element

Selector targeting finds elements to patch:

```go
sse.PatchElements(html, sse.WithSelector("#notification-list"), sse.WithSettleDuration(300))
```

Element ID matching patches elements by matching IDs in fragment:

```go
// Patches all elements in HTML that have matching IDs in DOM
sse.PatchElements(`<div id="counter">5</div><div id="status">Updated</div>`)
```

`WithSettleDuration` adds CSS class during morph for transition effects.
`WithUseViewTransition` enables View Transitions API for smooth animations.

### PatchSignals

`PatchSignals` updates signal values using JSON Merge Patch (RFC 7386).

Add or update signals:

```go
sse.PatchSignals(map[string]any{
  "count": 42,
  "user": map[string]string{
    "name": "Alice",
    "role": "admin",
  },
})
```

Remove signals by setting to null:

```go
sse.PatchSignals(map[string]any{
  "temporaryState": nil, // Removes $temporaryState
  "user.sessionId": nil, // Removes nested field
})
```

Merge semantics preserve existing signal structure:

```go
// First patch
sse.PatchSignals(map[string]any{
  "user": map[string]any{
    "name": "Alice",
    "email": "alice@example.com",
  },
})

// Second patch merges, does not replace
sse.PatchSignals(map[string]any{
  "user": map[string]any{
    "role": "admin", // Adds role, preserves name and email
  },
})
```

### ExecuteScript

`ExecuteScript` runs JavaScript in client context.

Use sparingly and only when no declarative alternative exists:

```go
sse.ExecuteScript("console.log('Server-sent log message')")
```

Prefer `PatchElements` and `PatchSignals` over `ExecuteScript` for maintainability and security.
Scripts bypass the declarative model and create implicit coupling.

## SDK implementation requirements

Datastar SDKs must implement `ServerSentEventGenerator` abstraction for ordered, immediate event delivery.

Thread safety ensures events are serialized in order across concurrent goroutines/threads.
Immediate flush after each event prevents buffering delays - client receives events as soon as server sends them.

Support `eventId` option for client-side event deduplication and reconnection:

```go
sse.PatchSignals(data, sse.WithEventId("update-123"))
```

Support `retryDuration` option to control client reconnection timing:

```go
sse.PatchSignals(data, sse.WithRetryDuration(5000)) // 5 second retry
```

SDKs should provide typed builders for event options rather than raw string manipulation.
Validate JSON serialization at SDK level to catch errors before transmission.

## ReadSignals pattern

Backend handlers must parse signals from incoming requests to access frontend state.

For GET requests, signals arrive in `datastar` query parameter as JSON:

```go
func handler(w http.ResponseWriter, r *http.Request) {
  signalsJSON := r.URL.Query().Get("datastar")
  var signals map[string]any
  json.Unmarshal([]byte(signalsJSON), &signals)

  searchTerm := signals["searchTerm"].(string)
  // Process search...
}
```

For POST/PUT/PATCH/DELETE requests, signals arrive in JSON request body:

```go
func handler(w http.ResponseWriter, r *http.Request) {
  var signals map[string]any
  json.NewDecoder(r.Body).Decode(&signals)

  itemName := signals["itemName"].(string)
  // Create item...
}
```

SDKs should provide `ReadSignals` helpers that unmarshal into typed structures:

```go
type SearchSignals struct {
  SearchTerm string `json:"searchTerm"`
  Page       int    `json:"page"`
}

func handler(w http.ResponseWriter, r *http.Request) {
  var signals SearchSignals
  datastar.ReadSignals(r, &signals)

  results := search(signals.SearchTerm, signals.Page)
  // Render results...
}
```

Type safety at unmarshal boundary prevents runtime errors and documents expected signal schema.

## SSE response pattern

Handlers for SSE endpoints should set appropriate headers and use SDK generators:

```go
func sseHandler(w http.ResponseWriter, r *http.Request) {
  sse := datastar.NewSSE(w, r)

  // Send initial state
  sse.PatchSignals(map[string]any{
    "connected": true,
    "timestamp": time.Now(),
  })

  // Stream updates
  ticker := time.NewTicker(1 * time.Second)
  defer ticker.Stop()

  for {
    select {
    case <-ticker.C:
      sse.PatchSignals(map[string]any{
        "serverTime": time.Now().Format(time.RFC3339),
      })
    case <-r.Context().Done():
      return
    }
  }
}
```

Always respect request context cancellation to clean up resources when client disconnects.
Use `defer` to ensure cleanup code runs even on early returns or panics.

## Fragment rendering pattern

Render HTML fragments using template engine of choice, then send via `PatchElements`:

```go
func updateItem(w http.ResponseWriter, r *http.Request) {
  sse := datastar.NewSSE(w, r)

  var signals struct {
    ItemID string `json:"itemId"`
  }
  datastar.ReadSignals(r, &signals)

  item := db.GetItem(signals.ItemID)

  var buf bytes.Buffer
  templates.ExecuteTemplate(&buf, "item.html", item)

  sse.PatchElements(buf.String(), datastar.WithSelector("#item-" + signals.ItemID))
}
```

Template should include element ID for reliable targeting:

```html
<div id="item-{{ .ID }}" class="item">
  <h3>{{ .Name }}</h3>
  <p>{{ .Description }}</p>
  <span data-text="$itemCount"></span>
</div>
```

Morphing preserves signal state and event listeners automatically.

## Error handling pattern

Send error state via signals and render error UI via fragments:

```go
func createItem(w http.ResponseWriter, r *http.Request) {
  sse := datastar.NewSSE(w, r)

  var signals struct {
    ItemName string `json:"itemName"`
  }
  datastar.ReadSignals(r, &signals)

  if signals.ItemName == "" {
    sse.PatchSignals(map[string]any{
      "error": "Item name is required",
    })

    var buf bytes.Buffer
    templates.ExecuteTemplate(&buf, "error.html", map[string]string{
      "message": "Item name is required",
    })
    sse.PatchElements(buf.String(), datastar.WithSelector("#error-container"))
    return
  }

  // Clear error state on success
  sse.PatchSignals(map[string]any{
    "error": nil,
  })

  // Proceed with creation...
}
```

Frontend shows errors conditionally:

```html
<div id="error-container" data-show="$error">
  <div class="error" data-text="$error"></div>
</div>
```

Always clear error state when subsequent operations succeed.

## Multi-step form pattern

Use signals to track form state across multiple steps without page navigation:

```html
<div data-signals='{"step": 1, "formData": {}}'>
  <div data-show="$step === 1">
    <input data-bind:formData.name type="text">
    <button data-on:click="$$step = 2">Next</button>
  </div>

  <div data-show="$step === 2">
    <input data-bind:formData.email type="email">
    <button data-on:click="$$step = 1">Back</button>
    <button data-on:click="@post('/api/submit')" data-indicator:submitting>
      Submit
    </button>
  </div>
</div>
```

`$$signalName = value` syntax updates signals client-side without server round-trip.
Use for pure UI state transitions where server input is unnecessary.

Backend receives complete `formData` object when user submits:

```go
func submitForm(w http.ResponseWriter, r *http.Request) {
  var signals struct {
    FormData struct {
      Name  string `json:"name"`
      Email string `json:"email"`
    } `json:"formData"`
  }
  datastar.ReadSignals(r, &signals)

  // Validate and process...
}
```

## Real-time updates pattern

Combine long-lived SSE endpoint with event-driven backend to push updates:

```go
var clients = make(map[string]chan Event)

func subscribeSSE(w http.ResponseWriter, r *http.Request) {
  sse := datastar.NewSSE(w, r)

  clientID := uuid.New().String()
  events := make(chan Event, 10)
  clients[clientID] = events
  defer delete(clients, clientID)

  for {
    select {
    case event := <-events:
      var buf bytes.Buffer
      templates.ExecuteTemplate(&buf, "notification.html", event)
      sse.PatchElements(buf.String(), datastar.WithSelector("#notifications"), datastar.WithMode("prepend"))

    case <-r.Context().Done():
      return
    }
  }
}

func broadcastEvent(event Event) {
  for _, ch := range clients {
    select {
    case ch <- event:
    default:
      // Client buffer full, skip
    }
  }
}
```

Use buffered channels to prevent slow clients from blocking broadcasts.
Implement timeout or max buffer size to disconnect unresponsive clients.

## Optimistic updates anti-pattern

Do not implement optimistic updates where UI changes before server confirms:

```html
<!-- WRONG: Updates UI immediately then hopes server succeeds -->
<button data-on:click="$$count = $count + 1; @post('/increment')">
  Increment
</button>
```

Instead, show loading state and update after server response:

```html
<!-- CORRECT: Shows loading, server patches count signal on success -->
<button data-on:click="@post('/increment')" data-indicator:incrementing>
  <span data-show="!$incrementing">Increment</span>
  <span data-show="$incrementing">Incrementing...</span>
</button>
<span data-text="$count"></span>
```

Server handler updates count and patches signal:

```go
func increment(w http.ResponseWriter, r *http.Request) {
  sse := datastar.NewSSE(w, r)

  newCount := db.IncrementCounter()

  sse.PatchSignals(map[string]any{
    "count": newCount,
  })
}
```

This ensures UI always reflects actual backend state, not hopeful predictions.

## Reference documentation

Official Datastar documentation: https://data-star.dev
Reference implementations and SDK source code provide authoritative patterns.

SDKs available for: Go, Rust, PHP, Python, .NET, Ruby, Java, Kotlin, TypeScript, Clojure.
Each SDK implements common event types and signal handling with language-appropriate idioms.

Cross-reference `02-sse-patterns.md` for SSE protocol details and connection management.
Cross-reference `05-web-components.md` for integrating third-party libraries with `data-ignore-morph`.
