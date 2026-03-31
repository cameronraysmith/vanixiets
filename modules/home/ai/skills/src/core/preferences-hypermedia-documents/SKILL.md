---
name: preferences-hypermedia-documents
description: Standalone hypermedia document authoring with Open Props, CUBE CSS, progressive enhancement, inline SVG, MathML, scroll-snap presentations, and Lit web component islands for imperative contexts. Load when creating HTML documents, slide presentations, interactive experiments, data visualizations, or SVG diagrams without a server backend.
---

# Hypermedia documents

This skill addresses the authoring of standalone web documents that respect the web platform's intrinsic properties without requiring a server backend.
The task class spans a parameter space from simple experiments to rich presentations to interactive visualizations.
All instances share the same foundational stack: HTML as the document, Open Props as the design token vocabulary, CUBE CSS as the organizational methodology, and progressive enhancement as the layering principle.
When server connectivity is needed, the document transitions into the domain of `preferences-hypermedia-development`.

The distinction between a "document" and an "application" is not binary but positional along the progressive enhancement axis.
A document becomes an application when it requires server-side state management, real-time data streams, or bidirectional communication.
Most of the work described here stays within the document regime, where the browser is the runtime and the filesystem (or a static host) is the server.

This skill covers the standalone (no server) case.
For server-connected hypermedia applications, see `~/.claude/skills/preferences-hypermedia-development/SKILL.md`.
For the shared vocabulary of web platform properties and the paradigm routing framework, see `~/.claude/skills/preferences-web-platform-foundations/SKILL.md`.

## Contents

| File | Description |
|------|-------------|
| [01-design-system.md](01-design-system.md) | Open Props design tokens, CUBE CSS methodology, cascade layers, `light-dark()` theming, composition primitives |
| [02-progressive-layers.md](02-progressive-layers.md) | Seven progressive enhancement layers from semantic HTML through modern CSS to Lit web components, each evaluated against the 15 platform properties |
| [03-document-composition.md](03-document-composition.md) | Document structure patterns (single-file, modular directory, multi-page), SVG authoring and import, MathML for mathematics, mapping from Typst/Beamer features |
| [04-presentations.md](04-presentations.md) | Scroll-snap slide presentations as a parameterization: navigation, active-slide detection, transitions, speaker notes, print export |

## Purpose parameterization

The purpose of a document determines which progressive enhancement layers to activate and which structural patterns to apply.
Each purpose below identifies the relevant layers from the seven-layer progressive enhancement model defined in `02-progressive-layers.md`:

| Layer | Name | Key capabilities |
|-------|------|-----------------|
| 0 | Semantic HTML | Document structure, accessibility, SEO, zero-dependency baseline |
| 1 | Basic CSS | Open Props tokens, CUBE CSS methodology, cascade layers |
| 2 | Modern CSS | Container queries, `has()`, `light-dark()`, subgrid, nesting |
| 3 | View transitions | Cross-page and same-document animated transitions |
| 4 | Scroll-driven animations | Timeline-linked animations, scroll-snap navigation |
| 5 | Minimal JS | `IntersectionObserver`, keyboard handlers, `matchMedia` listeners |
| 6 | Lit web components | Shadow DOM islands for imperative rendering (canvas, WebGPU, charts) |
| 7 | Datastar / SSE | Server-connected reactivity (transitions to application domain) |

### Experimentation

Purpose: testing approaches, libraries, or web platform features in isolation.
Layers activated: 0 (HTML), selectively from 1-6 depending on what is being tested.
Structure: typically single-file or small modular directory.
Examples: testing a CSS scroll-driven animation, prototyping a Lit web component wrapping Three.js, experimenting with MathML rendering.
Experimentation documents prioritize fast iteration over polish.
They may skip intermediate layers to focus on the specific feature under test.
A single HTML file with an inline `<style>` block and a `<script type="module">` tag is the typical starting point.

### Presentation

Purpose: slide deck for a talk, lecture, or review.
Layers activated: 0-5 (HTML through minimal JS), optionally 6 (web components for charts or diagrams).
Structure: single-file for short decks, modular directory for longer presentations with external SVG assets.
This replaces Typst/Beamer for technical presentations and reveal.js for standards-aligned needs.
The scroll-snap presentation model uses CSS `scroll-snap-type: y mandatory` on a container, with each `<section>` acting as a slide.
MathML renders equations natively without a JS math typesetting library.
Inline SVG diagrams respond to the document's theme via `currentColor` and CSS custom properties.
See `04-presentations.md` for the full presentation parameterization.

### Visualization

Purpose: displaying data, diagrams, or interactive graphics.
Layers activated: 0, 2 (modern CSS), 6 (Lit web components for chart libraries, WebGPU, Three.js/TypeGPU).
Structure: modular directory with external SVG files and ES module imports.
Visualization documents often skip the intermediate layers (1, 3-5) because CSS Grid and web components handle layout and interactivity directly.
External SVG files are preferred over inline SVG when diagrams are complex enough to warrant separate authoring and version tracking.
Lit web components wrap imperative rendering libraries (D3, Three.js, TypeGPU) to encapsulate their DOM manipulation within shadow DOM boundaries.

### Interactive demo

Purpose: showcasing UI behavior, prototyping interactions, demonstrating web APIs.
Layers activated: 0-3 (HTML through view transitions), 5-6 (JS and web components).
Structure: modular directory or multi-page for multi-step demos.
Multi-page demos use the view transitions API for cross-page navigation animations.
Each page remains a standalone HTML document that functions without JavaScript, with progressive enhancement adding the transition layer.

### Hybrid / server-connected

When Datastar or SSE is needed, activate layer 7.
At this point the document is transitioning from a standalone document into a hypermedia application.
Consult `preferences-hypermedia-development` for the server-connected patterns.
The boundary between document and application is crossed when the document requires server-side state or real-time data streams.
Indicators that this boundary has been reached include: the need for authenticated API calls, persistent user state beyond `localStorage`, real-time collaboration, or backend compute (database queries, ML inference).

## Architectural principles

The following principles govern all document types in this skill.

- The web platform is the application framework. JavaScript is a guest in a hypermedia document.
- Every layer must be a progressive enhancement: the document functions at every tier, from pure HTML to full interactivity. Removing any layer degrades gracefully rather than breaking the document.
- CSS handles all presentation-layer reactivity. JS is reserved for the irreducible set (see `preferences-web-platform-foundations`). Scroll-driven animations, container queries, `light-dark()` theming, and view transitions are CSS-first capabilities that do not require JS polyfills in modern browsers.
- Lit web components encapsulate imperative islands only where the DOM's declarative model ends. Typical imperative contexts include canvas rendering, WebGPU pipelines, and third-party library integration.
- SVG files are human-readable, external assets imported by the document rather than generated blobs. They use `currentColor` and CSS custom properties to participate in the document's theming system.
- Design decisions are evaluated against the 15 web platform properties (see `preferences-web-platform-foundations`). Each progressive enhancement layer's impact on these properties is documented in `02-progressive-layers.md`.
- No build step is required for development. ES module imports via `<script type="module">` and CDN-hosted Open Props provide the module system. Build steps are a distribution concern (bundling, minification) applied only when shipping to production.
- Signals, if used (via Datastar), live in the server. The frontend is a thin reactive layer. This principle applies only at the hybrid boundary (layer 7) and is detailed in `preferences-hypermedia-development`.
- Accessibility is structural, not remedial. Semantic HTML (layer 0) provides the accessibility baseline. Subsequent layers must not degrade keyboard navigation, screen reader compatibility, or focus management.
- Offline capability follows from the architecture. Documents that load Open Props from a vendored local file and use no server connectivity work entirely offline without a service worker.

## Technology stack

The specific technologies used across all document types in this skill are listed below.

*Design tokens:* Open Props provides CSS custom properties for typography, color, spacing, easing, and shadows.
Open Props tokens are consumed via CDN (`https://unpkg.com/open-props`) or vendored as a local CSS file for offline use.
The token set provides a consistent design vocabulary across all document types without requiring a CSS preprocessor.

*CSS methodology:* CUBE CSS (Composition, Utility, Block, Exception) organizes styles into cascade layers.
Composition styles handle layout flow, utilities provide single-purpose overrides, blocks scope component-specific styles, and exceptions handle state-driven variants.
See `01-design-system.md` for the full CUBE CSS layer architecture.

*Layout primitives:* Every Layout compositions (Stack, Box, Center, Cluster, Sidebar, Switcher, Cover, Grid) provide intrinsic-sizing layout patterns.
These primitives use CSS custom properties for configuration, making them composable without component-library overhead.

*Theming:* `color-scheme: light dark` declares system preference support.
The `light-dark()` CSS function selects values based on the resolved color scheme.
All custom colors use OKLch for perceptual uniformity across the lightness axis.

*Web components:* Lit handles data-driven DOM updates in shadow-DOM-isolated islands.
Bare `HTMLElement` extensions suffice for imperative contexts (canvas, WebGPU) that do not need Lit's reactive property system.
All web components register with `customElements.define()` and degrade to their light DOM content when JS is unavailable.

*Mathematics:* MathML provides native browser rendering for mathematical notation.
MathML reached baseline browser support in 2023 with Safari 16.4 and Chrome 109.
No JS math rendering library (MathJax, KaTeX) is needed for standard mathematical content.

*Vector graphics:* Hand-authored SVG uses `currentColor` for stroke and fill to inherit the document's text color.
CSS custom properties within SVG allow additional theme-responsive styling.
External SVG files are imported via `<img>`, `<object>`, or inline `<svg>` depending on interactivity requirements.

*Presentations:* CSS scroll-snap provides the slide navigation primitive.
`IntersectionObserver` detects the active slide for progressive JS enhancements (keyboard navigation, slide counters).
See `04-presentations.md` for the complete presentation architecture.

*Server connectivity (when needed):* Datastar (~15KB) provides SSE-driven reactivity when the document transitions to a hybrid application.

*Reference implementation:* Ironstar (`~/projects/rust-workspace/ironstar`) demonstrates the full Open Props + CUBE CSS + Datastar integration in a server-connected context.
Ironstar is primarily a server-connected application, but its CSS architecture and design token usage apply directly to standalone documents.

## File organization

Standalone documents follow one of three structural patterns depending on complexity.

A single-file document places HTML, CSS, and JS in one `.html` file.
This is appropriate for experiments and short presentations (under ~200 lines of content).
Open Props loads from a CDN `<link>` or an inline `<style>` block.

A modular directory contains an `index.html` entry point alongside separate CSS files, JS modules, and SVG assets.
This is the default for presentations, visualizations, and interactive demos.
The directory is self-contained and can be served by any static file server or opened directly from the filesystem.

A multi-page structure uses multiple HTML files linked via `<a>` tags, optionally enhanced with the view transitions API (layer 3).
Each page is independently functional.
This suits multi-step demos or documentation sites that do not warrant a static site generator.

## Related documents

- `~/.claude/skills/preferences-web-platform-foundations/SKILL.md` -- shared vocabulary: 15 platform properties, capability ladder, paradigm routing
- `~/.claude/skills/preferences-hypermedia-development/SKILL.md` -- server-connected hypermedia applications with Datastar, SSE, event architecture
- `~/.claude/skills/preferences-hypermedia-development/04-css-architecture.md` -- detailed CSS architecture reference (CUBE CSS, Open Props, cascade layers)
- `~/.claude/skills/preferences-hypermedia-development/05-web-components.md` -- detailed web component patterns (Lit, morph exclusion, event design)
- `~/.claude/skills/preferences-architectural-patterns/SKILL.md` -- onion/hexagonal architecture, effect boundaries
