# Templating

Server-side HTML templating is the primary interface between domain logic and the browser in hypermedia applications.
Templates generate complete HTML fragments that are sent via SSE to update specific parts of the page.
This document covers templating strategies with emphasis on type-safety, lazy evaluation, and integration with morphing-based updates.

## Philosophy

### Server-side rendering primacy

Hypermedia applications generate HTML on the server, not in the browser.
Templates are not just for initial page load—they generate every incremental update sent via SSE.
The template layer is the serialization boundary between typed domain models and HTML wire format.

### Complete elements

Templates must produce well-formed HTML elements with opening and closing tags.
Morphing libraries (idiomorph, morphdom) require complete elements with stable IDs to target updates correctly.
Fragments without closing tags or malformed HTML cause morphing to fail or produce incorrect results.

### No hydration needed

Unlike SPA frameworks, hypermedia applications do not need hydration.
Event handlers are attached via data attributes or traditional progressive enhancement.
SSE pushes updates directly to the DOM via morphing, bypassing the hydration complexity of frameworks like React or Vue.
This eliminates hydration mismatch bugs and reduces client-side JavaScript requirements.

## Type-safety

### Compile-time checking

Prefer templating systems that catch errors at compile time rather than runtime.
Type-safe templates use the host language's type system to validate template data.
IDE support (autocomplete, go-to-definition, refactoring) becomes available when templates are part of the type system.

### Typed template data

Pass structured, typed data to templates rather than untyped dictionaries or maps.
Define explicit data transfer objects or view models with named fields.
The compiler enforces that templates receive the correct data shape.

Example (pseudocode):
```
struct UserView {
  id: String,
  name: String,
  email: String,
}

fn render_user_card(user: UserView) -> Html {
  // Template can only access id, name, email
  // Typos in field names caught at compile time
}
```

### Template syntax validation

Choose template engines that validate syntax at compile time or build time.
File-based templates with external syntax (Jinja2, Handlebars) often defer validation to runtime.
Embedded DSLs (maud, hypertext, JSX) integrate with language tooling for immediate feedback.

## Evaluation strategies

### Eager evaluation

Most template engines evaluate eagerly: calling the template function immediately produces the rendered HTML string.
The result is ready to send to the client without further processing.
Mental model is straightforward: template call = HTML output.

Example (pseudocode):
```
fn render_greeting(name: String) -> String {
  format!("<p>Hello, {}</p>", escape(name))
}

let html = render_greeting("Alice"); // html = "<p>Hello, Alice</p>"
```

### Lazy evaluation

Lazy templating returns a closure or thunk instead of the rendered result.
Rendering is deferred until the template is actually consumed (converted to string, written to stream).
This aligns with functional programming: templates as suspended computations.

Benefits:
- Composability: combine templates without rendering intermediate results
- Conditional rendering: avoid wasted work for branches not taken
- Streaming: render directly to output stream without allocating intermediate strings

Example (pseudocode):
```
fn render_greeting(name: String) -> Template {
  template! { <p>Hello, {name}</p> } // Returns thunk
}

let tmpl = render_greeting("Alice"); // No rendering yet
let html = tmpl.to_string(); // Render now: "<p>Hello, Alice</p>"
```

### Choosing evaluation strategy

Eager evaluation is simpler and sufficient for most use cases.
Lazy evaluation provides optimization opportunities for complex compositions or streaming contexts.
The correctness of the application does not depend on this choice—it is a performance and architecture consideration.

## Language-specific options

### Rust

**hypertext**: Lazy rendering with maud-compatible syntax, compile-time checked, returns composable thunks.

**maud**: Eager rendering, embedded DSL, very popular, excellent performance.

**askama**: File-based templates with Jinja2-like syntax, compile-time validation.

Recommendation: hypertext for lazy evaluation, maud for simplicity and ecosystem maturity.

### Go

**templ**: Type-safe templates compiled to Go functions, fast, IDE support via LSP.

**html/template**: Standard library, text-based, runtime errors, less type-safe.

Recommendation: templ for type-safety and performance.

### Python

**Jinja2**: Dominant ecosystem choice, flexible, runtime validation only.

**htpy**: Python DSL for HTML generation, type-safe via type hints.

Recommendation: htpy for type-safety, Jinja2 for ecosystem compatibility when type-safety is less critical.

### TypeScript/Node.js

**JSX/TSX**: Type-safe when used with TypeScript, requires transpilation, excellent IDE support.

**Marko**: Compiled templates with partial hydration support (usually unnecessary for hypermedia).

Recommendation: JSX with TypeScript for type-safety and tooling.

## Integration with SSE

### Rendering pipeline

The template layer sits between domain logic and SSE transport:
```
Domain Model → Template Function → HTML String → PatchElements → SSE Event → Browser Morphing
```

Domain models are transformed into view models or passed directly to templates.
Templates render to HTML strings.
PatchElements constructs SSE events with element IDs and HTML content.
Browser receives events and morphs targeted elements.

See `02-sse-patterns.md` for PatchElements event format details.

### Partial templates (components)

Break templates into small, reusable functions representing UI components.
Each function accepts typed data and returns a complete HTML element.
Compose larger templates by calling smaller template functions.

Example (pseudocode):
```
fn user_avatar(user: User) -> Html {
  template! { <img id={"avatar-" + user.id} src={user.avatar_url} /> }
}

fn user_card(user: User) -> Html {
  template! {
    <div id={"user-card-" + user.id}>
      {user_avatar(user)}
      <span>{user.name}</span>
    </div>
  }
}
```

### ID strategy for morphing

Every top-level element in a template should have a stable ID.
Morphing libraries use IDs to target which elements to update.
Generate IDs from domain identifiers (user ID, entity ID, resource ID) to ensure stability across renders.

Avoid random IDs that change on every render—morphing will replace the entire element instead of patching it.

Example ID patterns:
- `user-card-{user_id}`
- `comment-{comment_id}`
- `status-panel-{session_id}`

When rendering lists, each item needs a unique ID:
```
fn render_user_list(users: Vec<User>) -> Html {
  template! {
    <ul id="user-list">
      @for user in users {
        <li id={"user-" + user.id}>{user.name}</li>
      }
    </ul>
  }
}
```

## Security

### Escaping by default

All user-generated content must be HTML-escaped by default.
Templates should escape variable interpolation automatically to prevent XSS attacks.
Explicit opt-in is required for raw HTML injection (e.g., rendering sanitized markdown).

Example (pseudocode):
```
// Automatic escaping
template! { <p>{user_input}</p> } // <p>&lt;script&gt;alert('xss')&lt;/script&gt;</p>

// Explicit raw injection (use with extreme caution)
template! { <div>{raw(sanitized_html)}</div> }
```

### Attribute escaping

Template engines must also escape HTML attributes, not just text content.
Attributes like `href`, `src`, `data-*` can contain user input.

Example:
```
template! { <a href={user_profile_url}>{user_name}</a> }
```

Both `user_profile_url` and `user_name` must be escaped appropriately for their contexts.

### Sanitization

If rendering user-provided HTML (e.g., markdown comments, rich text), sanitize before passing to templates.
Use a dedicated HTML sanitization library (DOMPurify, ammonia) to strip dangerous tags and attributes.
Never trust user input, even when escaped—sanitization is a separate layer of defense.

## Testing

### Unit tests

Render templates with test data and assert on the HTML structure.
Check for presence of expected elements, correct IDs, and escaped content.

Example (pseudocode):
```
#[test]
fn test_user_card_rendering() {
  let user = User { id: "123", name: "Alice", email: "alice@example.com" };
  let html = render_user_card(user).to_string();

  assert!(html.contains("id=\"user-card-123\""));
  assert!(html.contains("Alice"));
  assert!(!html.contains("alice@example.com")); // Email should not appear
}
```

### Snapshot testing

Use snapshot testing to detect unintended changes in template output.
Store the expected HTML output and compare against future renders.
Useful for catching regressions when refactoring templates.

### Escaping tests

Explicitly test that user input is escaped correctly.
Pass potentially dangerous input (script tags, HTML entities) and verify it appears escaped in output.

Example (pseudocode):
```
#[test]
fn test_xss_prevention() {
  let user = User { id: "123", name: "<script>alert('xss')</script>" };
  let html = render_user_card(user).to_string();

  assert!(!html.contains("<script>"));
  assert!(html.contains("&lt;script&gt;"));
}
```

### Integration tests with SSE

Test the full pipeline: domain model → template → SSE event → browser morphing.
Use a headless browser (Playwright, Puppeteer) to verify that SSE events correctly update the DOM.
These tests validate that IDs are stable and morphing works as expected.

See `02-sse-patterns.md` for SSE testing patterns.

## Performance considerations

### String allocation

Eager templates allocate intermediate strings for each template call.
In high-throughput scenarios, consider streaming templates directly to response writer.
Lazy templates can render directly to output without allocating intermediate buffers.

### Caching

Cache rendered HTML for static or rarely-changing content.
Key cache by template name + data hash to avoid stale content.
Invalidate cache when underlying data changes.

Dynamic content (user-specific, real-time updates) should not be cached—render fresh on every request.

### Partial rendering

Only render the parts of the page that changed.
Send targeted SSE events to update specific elements rather than re-rendering entire sections.
This is the core advantage of hypermedia over full-page reloads.

Example:
- User updates profile → render only `user-card-{id}` template → send PatchElements for that card
- New comment posted → render only `comment-{id}` template → send PatchElements to append to list

## Cross-references

See `01-architecture.md` for domain/application layer separation and where templates fit in the architecture.

See `02-sse-patterns.md` for PatchElements event construction and SSE transport integration.

See `03-morphing.md` for idiomorph configuration and how stable IDs enable efficient DOM updates.

See `04-css-architecture.md` for composition primitives (Stack, Cluster, Sidebar, etc.) that provide semantic layout classes for use in templates:

```html
<!-- Prefer composition classes for layout structure -->
<div class="center">
  <article class="stack">
    <h1>{title}</h1>
    <div class="cluster">
      {tags.map(tag => <span class="tag">{tag}</span>)}
    </div>
    <p>{content}</p>
  </article>
</div>
```

See `04-progressive-enhancement.md` for data attributes and event handling without hydration.

See `05-state-management.md` for session state and how it flows into template rendering.
