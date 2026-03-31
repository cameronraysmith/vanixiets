---
name: preferences-web-platform-foundations
description: Web platform properties, capability ladder from HTML through CSS to JavaScript, and paradigm routing between hypermedia and SPA approaches. Load when making web architecture decisions, evaluating framework choices, or reasoning about progressive enhancement.
---

# Web platform foundations

This skill defines the shared vocabulary and decision framework for all web development work.
It establishes the properties that the web platform satisfies, the capability boundaries between HTML, CSS, and JavaScript, and the criteria for choosing between architectural paradigms.
All web-related skills reference this document for terminology and decision criteria.

## Web platform properties

Each property has a short reference label used across the web skill set, a one-sentence definition, and a concrete example.

**Fault-tolerant.**
HTML and CSS ignore what they do not understand; JavaScript fails hard.
An unrecognized HTML element renders its children normally; an unrecognized JS method throws a TypeError.

**Backwards-compatible.**
Content authored decades ago still renders in modern browsers.
A page written in 1996 with `<table>` layout displays in Chrome 2026.

**Progressively enhanceable.**
Enhancement is additive, not conditional; a document works at every capability tier.
A form submits via native POST without JS; JS adds inline validation when available.

**Late-binding.**
Final output is resolved at consumption time (viewport, preferences, capabilities), not authoring time.
A `<picture>` element with multiple `<source>` children lets the browser select the appropriate image at render time.

**User-sovereign.**
The browser is a user agent acting on the user's behalf; users can override styles, block scripts, and adjust fonts.
A user stylesheet overriding `font-size` takes effect regardless of author intent.

**Addressable.**
Every resource has a URI.
A specific section of a document is reachable via `https://example.com/doc#section-3`.

**Linkable.**
Hyperlinks are permissionless and unidirectional; no coordination is required to link to a resource.
Any page can link to any other page without the target's knowledge or consent.

**Stateless at the protocol level.**
Each HTTP request-response cycle is independent.
A server can respond to any request without knowledge of prior requests from the same client.

**Content-negotiable.**
The same URI can serve different representations based on Accept headers.
`Accept: application/json` returns JSON; `Accept: text/html` returns an HTML page for the same endpoint.

**Media-independent.**
One document can render across screen, print, screen reader, and other modalities.
A `@media print` stylesheet hides navigation and reformats content for paper output.

**Inspectable.**
View Source is a first-class platform feature; the platform is learnable by examination.
Right-clicking any element and selecting "Inspect" reveals its markup, styles, and behavior.

**Layered with independent failure modes.**
HTML, CSS, and JS fail separately; a CSS error does not break HTML structure, and a JS error does not prevent CSS from applying.
A syntax error in a `<script>` block leaves the styled document fully intact.

**Decentralized.**
No app store, no gatekeeper; anyone can publish a document at a URL.
A static HTML file hosted on any web server is immediately accessible worldwide.

**Cacheable.**
HTTP caching is a first-class architectural concern with standardized headers.
`Cache-Control: max-age=31536000, immutable` on a hashed asset eliminates revalidation for one year.

**Composable across origins.**
Cross-origin embedding (images, scripts, iframes) is the default.
An `<img>` tag can reference an image hosted on a different domain without any server configuration.

These properties are not aspirational goals; they are load-bearing characteristics of the existing platform.
They serve as acceptance criteria throughout the web skill set.
When a design choice preserves or violates a property, name it explicitly.

Several properties cluster into reinforcing groups.
Fault-tolerance, backwards-compatibility, and progressive enhancement form a resilience cluster: content degrades gracefully across time, capability, and failure.
Addressability, linkability, and decentralization form a distribution cluster: content is locatable, referenceable, and publishable without gatekeepers.
Late-binding, user-sovereignty, and media-independence form an adaptation cluster: output adjusts to context rather than being fixed at authoring time.
Recognizing these clusters helps identify when a single architectural decision threatens multiple properties simultaneously.

## Capability ladder

The web platform is layered.
Each layer extends the previous one, and there are concrete boundaries where one layer's expressiveness ends and the next begins.
Understanding these boundaries prevents reaching for JavaScript when HTML or CSS suffices, and clarifies when JavaScript is genuinely required.

### HTML alone

HTML provides document structure, semantic meaning, built-in interactive elements (`details`/`summary`, `dialog`, `popover`, `input` types, intra-page navigation via fragment identifiers), forms with native validation, and the accessibility tree.
These capabilities are substantial: a multi-page form with required fields, radio groups, date pickers, and submission handling requires zero JavaScript.

HTML's interactivity is strictly local and hierarchical.
It cannot style based on state elsewhere in the document.
It cannot react to scroll position, viewport size, or cross-element relationships.
These limitations define the boundary where CSS becomes necessary.

### HTML + CSS

CSS adds visual presentation, layout (flexbox, grid), responsive design (container queries, media queries), state-reactive styling (`:has()`, `:checked`, `:target`), custom properties as a state bus, scroll-driven animations, `@starting-style` for entry animations, `@layer` for cascade control, `light-dark()` for color scheme adaptation, and `scroll-snap` for paged navigation.

The combination of `:has()` and custom properties is particularly significant.
`:has()` allows any element to react to the state of any other element in the document, enabling patterns that previously required JavaScript: tabs, accordions, conditional visibility, and form-state-dependent layouts.
Custom properties propagate through the cascade and can be toggled by pseudo-class selectors, creating a declarative state bus without scripting.

CSS reaches three walls where it ends.
First, CSS cannot create or destroy DOM nodes.
Second, CSS cannot perform general computation.
Third, CSS cannot communicate with anything outside the document: no network access, no storage, no inter-document messaging.

### Web components

`class extends HTMLElement` provides encapsulation, lifecycle callbacks, attribute observation, Shadow DOM (optional), and the Custom Elements registry.
Web components are the platform's native abstraction boundary: they define new HTML elements with custom behavior while participating in the standard DOM lifecycle.

Lit adds over bare custom elements a reactive property system and efficient tagged template literal rendering with DOM diffing.
The reactive property system triggers re-renders when observed properties change, similar to a signal-based reactivity model but scoped to the component boundary.

Heuristic: use Lit for data-driven DOM where the component's visual output is a function of its properties (charts, dynamic tables, list renderers).
Use bare custom elements for imperative context wrappers where the component manages a non-DOM rendering context (Three.js scenes, WebGPU pipelines, audio graphs).

### The JS irreducible set

Some capabilities require JavaScript because no combination of HTML, CSS, and declarative standards can express them.
This irreducible set includes:

- Imperative rendering contexts: Canvas 2D, WebGL, WebGPU
- Network communication: fetch, Server-Sent Events, WebSocket
- Dynamic DOM instantiation from data (template cloning, list rendering from arrays)
- System APIs: clipboard, filesystem, audio, media capture
- Keyboard navigation beyond Tab/Enter (arrow key handling, keyboard shortcuts)
- Programmatic scroll control and scroll position observation
- View Transitions API initiation (the API is JS-triggered, though the animations themselves are CSS)
- Concurrency primitives: Web Workers, SharedArrayBuffer

The boundary test is: can this behavior be expressed as a pure function of document state and CSS selectors?
If yes, prefer HTML + CSS.
If no, JavaScript is required.

Note that this irreducible set is smaller than most web developers assume.
Many interactions commonly implemented in JavaScript (tooltips, accordions, tabs, carousels, form validation feedback, dark mode toggling, scroll-linked animations) can now be expressed in HTML + CSS alone.
The capability ladder should be re-evaluated against the current CSS feature baseline before reaching for JavaScript.

### The server connection

When a document needs state that originates outside the browser (server-computed data, database queries, multi-user collaboration, authentication), two architectural paths diverge.

The hypermedia path has the server own state and push HTML fragments, often via SSE.
The client receives pre-rendered content and the browser's native rendering pipeline handles presentation.
This preserves the platform's fault-tolerance, progressive enhancement, and inspectability properties.

The SPA path has the client own a state copy, fetch JSON, and reconcile with a virtual DOM.
The client reconstructs presentation from data, taking ownership of rendering that the server would otherwise perform.
This trades several platform properties for client-side interactivity and offline capability.

The paradigm routing section below provides the decision criteria for choosing between these paths.

## Paradigm routing

Three architectural paradigms address different requirements.
The choice is driven by where state lives, what latency is tolerable, and which platform properties the project values.
This is a decision framework, not a ranking.

### Hypermedia-first (server-driven)

Preserves all 15 platform properties.

The server renders HTML and pushes fragments via SSE.
The browser handles presentation.
Datastar serves as the thin reactivity layer at approximately 15KB, providing declarative attribute-based bindings for SSE consumption, DOM morphing, and signal-driven reactivity without a virtual DOM.

Choose this paradigm when the server is authoritative for state, UI updates tolerate a server round-trip, minimal client JavaScript is valued, and real-time updates are server-pushed.
This is the default paradigm for new projects unless specific requirements demand otherwise.

Reference: `~/.claude/skills/preferences-hypermedia-development/SKILL.md`

### Standalone document (static)

Preserves all 15 platform properties.

The architecture is HTML + CSS with optional JavaScript and no server dependency.
Progressive enhancement layers from pure HTML through modern CSS to Lit web components.
This paradigm is appropriate for content that is complete at authoring time: documentation, presentations, data visualizations, interactive explorations.

Choose this paradigm when content is self-contained, no server state is needed, or the use case is experimentation or presentation.
Static documents can be hosted anywhere (CDN, local filesystem, embedded in other documents) because they have no runtime dependencies beyond the browser.

Reference: `~/.claude/skills/preferences-hypermedia-documents/SKILL.md`

### SPA (client-driven)

Trades progressive enhancement, layered failure, inspectability, and media independence.
Gains client-side interactivity, offline capability, and complex client state management.

React, Vue, or Svelte renders via virtual DOM, fetches JSON from an API, and the client owns state.
The application assumes JavaScript execution and typically requires a build step that transforms source into browser-executable bundles.

Choose this paradigm when an offline-first requirement exists, ultra-low-latency interactions are needed, complex client-side state is unavoidable (video editor, CAD, collaborative canvas), or existing React ecosystem investment makes migration impractical.

Reference: `~/.claude/skills/preferences-react-tanstack-ui-development/SKILL.md`

### Decision procedure

When evaluating a new project or feature, walk the capability ladder from bottom to top.
Start by asking what HTML alone provides for the use case.
Then ask what HTML + CSS adds.
Then ask whether web components (Lit or bare) close the remaining gaps.
Only after exhausting declarative options, determine whether the JS irreducible set is needed and whether the required state lives on the server or the client.
The answer to the state location question determines the paradigm.

This procedure is not about minimizing JavaScript for its own sake.
It ensures that the chosen architecture inherits the maximum number of platform properties by default, trading them away only when concrete requirements demand it.

### Paradigm mixing

The hypermedia and SPA paths are architecturally opposed.
Mixing them (e.g., pairing React with Datastar) creates two competing reactivity graphs: one driven by server-pushed HTML mutations and one driven by client-side state reconciliation.
Choose one paradigm per application boundary.

When a project contains both paradigms (e.g., a marketing site with a hypermedia architecture and an embedded SPA editor), draw an explicit boundary.
The SPA lives in an iframe or a dedicated route prefix with its own entry point.
The two paradigms do not share a reactivity layer.

## Modern CSS feature baseline

A reference table of modern CSS features relevant to architectural decisions, with browser support status as of 2026.

| Feature | Baseline status (2026) | What it enables |
|---------|----------------------|-----------------|
| CSS scroll-snap | Widely Available | Paged navigation without JS |
| `:has()` selector | Widely Available | Parent-aware, cross-document state styling |
| Container queries (size) | Widely Available | Component-responsive layout |
| `@starting-style` | Baseline | Entry animations from `display:none` |
| Same-document view transitions | Baseline (Oct 2025) | Animated state changes within a page |
| Popover API | Newly Available | Overlay content without JS positioning |
| CSS anchor positioning | Near-baseline (Interop 2025) | Element-relative positioning |
| `@container scroll-state()` | Chrome 133+ only | Active scroll-snap target detection without JS |
| `::scroll-marker` / `::scroll-button` | Chrome 142+ only | Native carousel navigation |
| Cross-document view transitions | Chrome/Edge/Safari, no Firefox | Animated MPA page navigation |
| Scroll-driven animations | Chrome/Edge/Safari | Scroll-linked visual effects |
| CSS `if()` function | Chrome 137+ only | Conditional property values |

Features marked "Widely Available" or "Baseline" can be used without fallback.
Features with partial support should be applied as progressive enhancements that gracefully degrade.
When a feature is Chrome-only, document the degraded experience for other browsers alongside the enhanced version.

## Related documents

- `~/.claude/skills/preferences-hypermedia-development/SKILL.md` — server-connected hypermedia applications
- `~/.claude/skills/preferences-hypermedia-documents/SKILL.md` — standalone document authoring
- `~/.claude/skills/preferences-react-tanstack-ui-development/SKILL.md` — client-driven SPA development
- `~/.claude/skills/preferences-functional-reactive-programming/SKILL.md` — theoretical foundations (signals as comonads, web components as coalgebras)
- `~/.claude/skills/preferences-architectural-patterns/SKILL.md` — onion/hexagonal architecture, effect boundaries
