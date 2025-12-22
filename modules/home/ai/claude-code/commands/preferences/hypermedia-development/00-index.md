# Hypermedia development

This guide covers server-first hypermedia architecture for building web applications where the backend is the source of truth for both application state and UI rendering.

**Primary paradigm:** Server-driven UI - the server generates HTML fragments and pushes them to the browser via Server-Sent Events (SSE), eliminating client-side state management complexity.

**Core philosophy (Tao of Datastar):**
- Most state should live in the backend as the single source of truth
- In Morph We Trust: send large DOM chunks, let morphing handle minimal updates
- Use loading indicators rather than optimistic updates that deceive users
- CQRS pattern: single long-lived SSE for reads, short-lived requests for writes

**Contrast with SPA architectures:**
- Hypermedia: `Server → HTML → Browser native DOM`
- SPA: `Server → JSON → Client framework → Virtual DOM → Render`

This paradigm complements functional domain modeling by maintaining clear effect boundaries: pure domain logic (sync), application orchestration (async/SSE), and infrastructure (I/O).

## Contents

| File | Description |
|------|-------------|
| [01-architecture.md](./01-architecture.md) | Server-first philosophy, effect boundaries, HATEOAS principles, anti-patterns (client-side reactivity duplication, WASM SPAs, optimistic updates) |
| [02-sse-patterns.md](./02-sse-patterns.md) | SSE protocol fundamentals, event types (PatchElements, PatchSignals), connection lifecycle, reconnection resilience, lag handling, resource cleanup |
| [03-datastar.md](./03-datastar.md) | Datastar framework patterns: signal system, data attributes, backend actions, SDK event types, ReadSignals pattern, real-time updates |
| [04-css-architecture.md](./04-css-architecture.md) | Design tokens with Open Props, cascade layers, `light-dark()` theming, container queries, PostCSS configuration, Light DOM requirement |
| [05-web-components.md](./05-web-components.md) | Thin wrapper pattern for third-party libraries (charts, editors, maps), vanilla vs Lit, morph exclusion, event design, memory cleanup |
| [06-templating.md](./06-templating.md) | Type-safe server-side templating, lazy vs eager evaluation, ID strategy for morphing, security (escaping, sanitization), testing patterns |

## When to use hypermedia architecture

**Choose hypermedia when:**
- Server is authoritative for application state and business logic
- UI updates can tolerate server round-trip latency (CRUD apps, dashboards, content sites)
- You want minimal client-side JavaScript and bundle sizes
- Real-time updates are server-pushed (notifications, live data)

**Reconsider when:**
- Application requires offline-first functionality
- Ultra-low-latency interactions are critical (collaborative drawing, real-time gaming)
- UI is highly stateful with complex client-side transitions (video editor, CAD tool)

## Technology ecosystem

**Hypermedia frameworks:** Datastar, htmx, Turbo (Hotwire)

**Backend SDKs (Datastar):** Go, Rust, PHP, Python, .NET, Ruby, Java, Kotlin, TypeScript, Clojure

**CSS architecture:** Open Props (design tokens), Open Props UI (copy-paste components)

**Web component approaches:** Vanilla web components, Lit (for complex lifecycle management)

**Templating (by language):**
- Rust: hypertext (lazy), maud (eager), askama (file-based)
- Go: templ (type-safe)
- Python: htpy (type-safe), Jinja2 (ecosystem standard)
- TypeScript: JSX/TSX with TypeScript

## Related documents

- `~/.claude/commands/preferences/architectural-patterns.md` - onion/hexagonal architecture, effect boundaries
- `~/.claude/commands/preferences/domain-modeling.md` - functional domain modeling, smart constructors
- `~/.claude/commands/preferences/railway-oriented-programming.md` - Result-based error handling
- `~/.claude/commands/preferences/rust-development/` - Rust-specific patterns (integrates with Datastar-Rust/hypertext)
- `~/.claude/commands/preferences/typescript-nodejs-development.md` - TypeScript patterns for Node.js backends
