# Progressive enhancement layers

Hypermedia documents are built by progressively activating layers of capability.
Each layer adds functionality without breaking the layers below it.
A document should be functional and meaningful at layer 0 (pure HTML) and gain enhanced presentation and interactivity as layers are added.
This is a concrete application of the progressive enhancement property defined in `preferences-web-platform-foundations`.

The purpose of the document determines which layers to activate (see the purpose parameterization in SKILL.md).

## Layer 0: semantic HTML

The foundation.
Every document begins as valid, semantic HTML.
Content is readable as a plain scrollable document without any CSS or JavaScript.

Key practices:

- Use semantic elements: `<article>`, `<section>`, `<nav>`, `<header>`, `<footer>`, `<aside>`, `<figure>`, `<figcaption>`, `<details>`, `<summary>`
- Every `<section>` has an `id` attribute for URL-fragment linking (preserves *addressable* property)
- Use `<details>`/`<summary>` for collapsible content (native interactivity without JS)
- Use `<dialog>` for modal content, `popover` attribute for non-modal overlays
- Use native form elements with built-in validation (`required`, `pattern`, `type="email"`)
- Heading hierarchy (`h1` through `h6`) structures the document outline
- Alt text on images, `<title>` and `<desc>` in SVG elements

This layer alone produces a document that is accessible, indexable, printable, and linkable.

## Layer 1: CSS scroll-snap

Transforms the document from a continuous scroll into a paged experience.

```css
main {
  overflow-x: scroll;
  scroll-snap-type: x mandatory;
  display: flex;
}

main > section {
  min-inline-size: 100vw;
  scroll-snap-align: start;
}
```

For vertical paging:

```css
main {
  overflow-y: scroll;
  scroll-snap-type: y mandatory;
}

main > section {
  min-block-size: 100dvh;
  scroll-snap-align: start;
}
```

Properties preserved: all 15.
The document remains navigable via scroll, touch, or keyboard (Tab + Space).
CSS counters provide automatic section numbering without JS.
`:target` enables direct URL-fragment navigation to any section.

## Layer 2: modern CSS

Adds presentation-layer reactivity using CSS features that are baseline or near-baseline.

`:has()` for cross-document state:

```css
/* Style slide container when a checkbox is checked */
main:has(#notes-toggle:checked) .speaker-notes {
  display: block;
}
```

`@starting-style` for entry animations:

```css
.slide {
  opacity: 1;
  transition: opacity 0.3s;
  @starting-style {
    opacity: 0;
  }
}
```

Container queries for responsive content:

```css
.slide {
  container-type: inline-size;
}

@container (inline-size > 60rem) {
  .slide .two-column {
    grid-template-columns: 1fr 1fr;
  }
}
```

`@container scroll-state()` for active section detection (Chrome 133+):

```css
main {
  container-type: scroll-state;
}

@container scroll-state(snapped: inline) {
  section {
    /* Style the actively snapped section */
    opacity: 1;
  }
}
```

This is a progressive enhancement.
Sections are visible regardless; this layer adds visual emphasis to the active one.

CSS anchor positioning + popover for annotations:

```css
.footnote-trigger {
  anchor-name: --fn-1;
}

.footnote-content {
  position-anchor: --fn-1;
  position-area: block-end span-inline-end;
}
```

Properties preserved: all 15.
No JavaScript is involved.
Everything degrades gracefully in browsers that do not support a given feature.

## Layer 3: view transitions

Adds animated state changes.

Same-document transitions (baseline, all browsers since Oct 2025):

```js
function navigateToSlide(index) {
  document.startViewTransition(() => {
    // update active slide
  });
}
```

Cross-document transitions for multi-page documents (Chrome/Edge/Safari):

```css
@view-transition {
  navigation: auto;
}

::view-transition-old(root) {
  animation: slide-out 0.3s ease;
}
::view-transition-new(root) {
  animation: slide-in 0.3s ease;
}
```

Properties preserved: all 15.
View transitions are purely visual enhancement.
Navigation works without them.

## Layer 4: native carousel UI (Chrome 142+)

The browser generates navigation controls for scroll-snap containers.

```css
main::scroll-button(previous) {
  content: "\2190";
}
main::scroll-button(next) {
  content: "\2192";
}

main {
  scroll-marker-group: after;
}
section::scroll-marker {
  content: "";
  inline-size: 0.75rem;
  block-size: 0.75rem;
  border-radius: 50%;
  background: var(--color-muted);
}
section::scroll-marker:target-current {
  background: var(--color-accent);
}
```

This is the most progressive layer.
Chrome-only as of 2026.
The browser handles focus management, keyboard interaction, and ARIA roles automatically.
In unsupported browsers, the document still works via scroll and touch (layer 1).

Properties preserved: all 15.

## Layer 5: minimal JavaScript

The irreducible set of interactive behaviors that CSS cannot express.

Keyboard navigation maps arrow keys to scroll-snap positions.
Hash persistence stores the current section index in the URL hash via `history.replaceState`.
A presenter timer displays elapsed time.
A slide counter displays an "n / total" indicator.

```js
document.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowRight') scrollToNext();
  if (e.key === 'ArrowLeft') scrollToPrev();
});
```

This JS is a progressive enhancement.
The document is fully navigable without it via scroll, touch, or Tab.
Keep the script minimal.
The ericmjl html-presentations pattern uses approximately 200 lines for this layer; modern CSS (layers 2-4) reduces the JS needed.

Properties preserved: all 15 (JS failure degrades to CSS-only navigation).

## Layer 6: Lit web components

For content that exceeds the DOM's declarative model.

Data-driven DOM covers content rendered from data that updates:

- Charts (wrapping ECharts, Observable Plot, or similar)
- Dynamic tables with sorting and filtering
- Interactive diagrams

Imperative contexts cover APIs that require JS:

- WebGPU compute or rendering
- Three.js / TypeGPU scenes
- Audio visualization
- Canvas-based editors

Key practices for web components in documents:

- Use Light DOM so CSS cascade layers and Open Props tokens flow through (see `01-design-system.md`)
- Communicate via attributes (in) and CustomEvents (out) following "props down, events up"
- Mark components with `data-ignore-morph` if used alongside Datastar to prevent morphing interference
- Clean up resources in `disconnectedCallback` (WebGL contexts, animation frames, event listeners)
- Components are guests in the document and should not take over layout or navigation

For detailed web component patterns, see `~/.claude/skills/preferences-hypermedia-development/05-web-components.md`.

## Layer 7: Datastar (server connectivity)

When the document needs state that originates outside the browser, Datastar provides the bridge.
At this point, the document transitions from standalone to server-connected.

Datastar (~15KB) adds:

- SSE connection for server-pushed HTML fragments and signal updates
- `data-*` attributes for declarative reactivity (`data-signals`, `data-bind`, `data-show`, `data-on`)
- Backend actions (`@get`, `@post`) for client-to-server communication

Activating this layer means a backend is required (Ironstar/Rust, Stario/Python, Go, or any language with a Datastar SDK).
The preceding layers 0-6 remain in effect.
Datastar enhances the document; it does not replace its foundation.

For detailed Datastar patterns, see `~/.claude/skills/preferences-hypermedia-development/03-datastar.md`.

## Layer activation by purpose

| Purpose | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---------|---|---|---|---|---|---|---|---|
| Experiment | x | | selective | | | selective | selective | |
| Presentation | x | x | x | x | progressive | x | optional | |
| Visualization | x | | x | | | | x | |
| Interactive demo | x | | x | x | | x | x | |
| Server-connected | x | x | x | x | progressive | x | x | x |

"x" indicates a layer that is typically activated.
"selective" indicates that activation depends on what is being tested.
"progressive" indicates that the layer is applied as a progressive enhancement only where supported.
"optional" indicates activation only if needed.
