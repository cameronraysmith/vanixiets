# Document composition

Hypermedia documents range from single-file experiments to multi-page sites with shared assets and complex navigation.
This file covers structural patterns for organizing document source, vector graphics authoring and integration, mathematical notation via MathML, and the mapping from traditional academic tools like Typst and Beamer.

## Structure patterns

### Single-file

All HTML, CSS, and JS live in one `.html` file.
This is appropriate for quick experiments, short presentations, and throwaway prototypes.
Inline CSS goes in a `<style>` element, inline JS in `<script type="module">`, and inline SVG directly in the document body.
The single-file approach is trivially shareable since there is exactly one artifact to distribute.
Limitations become apparent beyond roughly 500 lines: no code reuse across documents, growing unwieldiness as content accumulates, and inability to use ES module `import` statements when opened via `file://` protocol due to CORS restrictions.

### Modular directory

An `index.html` serves as the composition root with separate CSS, JS, and SVG files organized by concern.
This is the recommended structure for any document beyond trivial size.

```
my-document/
  index.html
  styles/
    main.css          # @layer declarations, @import chain
    theme.css
    compositions.css
    blocks.css
  scripts/
    navigation.js     # ES module
  components/
    chart-widget.js   # Lit web component
  assets/
    diagram-flow.svg
  vendor/             # optional local copies of Open Props, Lit
```

The main stylesheet uses `@import` with layer assignment to compose the cascade:

```css
@layer openprops, normalize, theme, compositions, utilities, blocks, exceptions;
@import "../../vendor/open-props.min.css" layer(openprops);
@import "theme.css" layer(theme);
@import "compositions.css" layer(compositions);
@import "blocks.css" layer(blocks);
```

JS modules use import maps for bare specifiers, keeping vendor dependencies resolvable without a bundler:

```html
<script type="importmap">
{
  "imports": {
    "lit": "./vendor/lit.js",
    "lit/": "./vendor/lit/"
  }
}
</script>
<script type="module" src="./scripts/navigation.js"></script>
```

ES modules require a local HTTP server to function (`python -m http.server` suffices).
No build step is required for development.

### Multi-page

Each page is a separate HTML file linked via anchors.
Cross-document view transitions provide animated navigation between pages.
Each page is independently addressable and cacheable, which aligns well with hypermedia principles.
Cross-document view transitions require Chrome, Edge, or Safari as of 2026; Firefox does not yet support them.

## SVG authoring and import

### Authoring principles

Write SVG by hand or with minimal tooling rather than relying on GUI editor output.
Use `viewBox` for intrinsic scaling so the graphic adapts to its container without fixed dimensions.
Structure content with `<g>` groups and meaningful `id` attributes for readability and targetability.
Use `currentColor` for strokes and fills that should inherit the document text color.
Use CSS custom properties for any values that should respond to theming.

```svg
<svg viewBox="0 0 400 300" xmlns="http://www.w3.org/2000/svg"
     role="img" aria-labelledby="flow-title flow-desc">
  <title id="flow-title">Process flow</title>
  <desc id="flow-desc">Three-step data processing pipeline</desc>
  <style>
    .node { fill: var(--color-surface, #f0f0f0); stroke: var(--color-text, #333); stroke-width: 1.5; }
    .edge { stroke: var(--color-muted, #999); fill: none; marker-end: url(#arrow); }
    .label { fill: currentColor; font-family: var(--font-sans, system-ui); font-size: 14px; }
  </style>
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="10" refY="5"
            markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="var(--color-muted, #999)" />
    </marker>
  </defs>
  <g class="node" transform="translate(30, 130)">
    <rect width="100" height="40" rx="8" />
    <text class="label" x="50" y="25" text-anchor="middle">Ingest</text>
  </g>
  <path class="edge" d="M 130 150 L 160 150" />
  <g class="node" transform="translate(160, 130)">
    <rect width="100" height="40" rx="8" />
    <text class="label" x="50" y="25" text-anchor="middle">Transform</text>
  </g>
  <path class="edge" d="M 260 150 L 290 150" />
  <g class="node" transform="translate(290, 130)">
    <rect width="100" height="40" rx="8" />
    <text class="label" x="50" y="25" text-anchor="middle">Publish</text>
  </g>
</svg>
```

Include `<title>` and `<desc>` as the first children for accessibility.
Add `role="img"` and `aria-labelledby` on the root `<svg>` element.
Keep each SVG file focused on a single diagram.
Avoid Inkscape and Illustrator bloat; if using a GUI tool, clean output with svgo before committing.

### Import methods

Four methods exist for including SVG in HTML, each with distinct tradeoffs.

`<img src="diagram.svg">` renders the SVG as a static image.
The SVG is opaque to the document cascade: no CSS custom properties flow in.
Use this when the SVG is self-contained with its own color scheme.
This is the simplest method and supports `loading="lazy"` for deferred loading.

`<object data="diagram.svg" type="image/svg+xml">` loads the SVG as an interactive subdocument.
JS inside the SVG can communicate with the host page via `postMessage`.
This method is less common in documents but useful for interactive visualizations.

Inline `<svg>` places the graphic directly in the HTML.
The full CSS cascade flows through, so all custom properties and cascade layers apply.
Use this when the SVG must respond to document theming.
The disadvantage is that the SVG content is not separately cacheable and increases document size.

`<use href="sprites.svg#id">` references symbols defined in an external SVG.
Referenced symbols inherit `currentColor` from the document.
Define a sprites file with `<symbol>` elements:

```svg
<!-- sprites.svg -->
<svg xmlns="http://www.w3.org/2000/svg">
  <symbol id="icon-check" viewBox="0 0 24 24">
    <path d="M5 13l4 4L19 7" stroke="currentColor" fill="none"
          stroke-width="2" stroke-linecap="round" />
  </symbol>
  <symbol id="icon-arrow" viewBox="0 0 24 24">
    <path d="M5 12h14M12 5l7 7-7 7" stroke="currentColor" fill="none"
          stroke-width="2" stroke-linecap="round" />
  </symbol>
</svg>
```

Reference symbols in HTML:

```html
<svg width="24" height="24"><use href="sprites.svg#icon-check" /></svg>
```

For themed diagrams, prefer inline `<svg>` or `<use href>` with `currentColor`.
For static illustrations, prefer `<img>`.
For modular documents, prefer external SVG imported via `<use href>` and fall back to inline when full cascade access is needed.

### SVG animation

CSS animations apply to SVG elements the same way they apply to HTML.
The `stroke-dasharray` and `stroke-dashoffset` properties enable path drawing effects.
Scroll-driven animations bind SVG transformations to scroll progress for scroll-linked reveals.
Avoid SMIL animation attributes (`<animate>`, `<animateTransform>`), which are deprecated in favor of CSS animations and the Web Animations API.

### Dark mode SVG adaptation

For inline SVGs, the document cascade flows through directly, so `light-dark()` and custom properties apply without additional work.

For external SVGs referenced via `<use href>`, CSS custom properties resolve at render time and automatically adapt when the document switches between light and dark modes.

For SVGs loaded via `<img>`, the SVG must contain its own color scheme logic because the document cascade is inaccessible:

```svg
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <style>
    @media (prefers-color-scheme: dark) {
      .bg { fill: #1a1a2e; }
      .fg { fill: #e0e0e0; }
    }
    @media (prefers-color-scheme: light) {
      .bg { fill: #ffffff; }
      .fg { fill: #333333; }
    }
  </style>
  <rect class="bg" width="100" height="100" />
  <circle class="fg" cx="50" cy="50" r="30" />
</svg>
```

## MathML for mathematics

### When to use MathML

All major browsers support MathML Core as of 2023.
MathML requires no JS library and no build step, making it the natural choice for equations, formulas, and mathematical notation in hypermedia documents.

When MathML is insufficient: complex LaTeX macro libraries, highly custom notation, or the need for pixel-identical LaTeX output.
In those cases, consider KaTeX (faster, smaller footprint) or MathJax (more complete LaTeX coverage) as progressive enhancements.

### Core elements

`<mi>` represents an identifier: variables, function names, constants.

`<mn>` represents a number literal.

`<mo>` represents an operator or delimiter: `+`, `=`, `∑`, `∫`, `∂`, parentheses.

`<mfrac>` produces a fraction with numerator and denominator children.

`<msqrt>` wraps content in a square root.
`<mroot>` takes two children for an nth root (content, then index).

`<msup>` and `<msub>` attach superscripts and subscripts.
`<msubsup>` combines both on one base.

`<mrow>` groups elements into a single logical row for proper spacing and line-breaking.

`<munder>`, `<mover>`, and `<munderover>` place content below, above, or both below and above a base, used for limits, hats, and accents.

`<mtable>`, `<mtr>`, and `<mtd>` form matrices and aligned equation systems analogous to HTML tables.

`<mspace>` inserts explicit horizontal or vertical space.

### Inline and display math

Inline math flows within a paragraph:

```html
<p>Einstein's relation <math><mi>E</mi><mo>=</mo><mi>m</mi><msup><mi>c</mi><mn>2</mn></msup></math> unifies mass and energy.</p>
```

Display math appears as a centered block.
The Euler-Lagrange equation demonstrates nested fractions and decorated variables:

```html
<math display="block">
  <mrow>
    <mfrac>
      <mrow><mo>&#x2202;</mo><mi>L</mi></mrow>
      <mrow><mo>&#x2202;</mo><mi>q</mi></mrow>
    </mfrac>
    <mo>&#x2212;</mo>
    <mfrac>
      <mi>d</mi>
      <mrow><mi>d</mi><mi>t</mi></mrow>
    </mfrac>
    <mfrac>
      <mrow><mo>&#x2202;</mo><mi>L</mi></mrow>
      <mrow><mo>&#x2202;</mo><mover><mi>q</mi><mo>&#x02D9;</mo></mover></mrow>
    </mfrac>
    <mo>=</mo>
    <mn>0</mn>
  </mrow>
</math>
```

A 2x2 matrix using `<mtable>`:

```html
<math display="block">
  <mrow>
    <mo>[</mo>
    <mtable>
      <mtr>
        <mtd><mi>a</mi></mtd>
        <mtd><mi>b</mi></mtd>
      </mtr>
      <mtr>
        <mtd><mi>c</mi></mtd>
        <mtd><mi>d</mi></mtd>
      </mtr>
    </mtable>
    <mo>]</mo>
  </mrow>
</math>
```

### SVG with embedded MathML via foreignObject

For diagrams that contain mathematical notation, `<foreignObject>` embeds MathML inside SVG.
This enables node-and-edge diagrams where nodes contain properly typeset equations, which is common in mathematical presentations and scientific documents.

```svg
<svg viewBox="0 0 400 200" xmlns="http://www.w3.org/2000/svg">
  <rect x="10" y="10" width="180" height="80" rx="8"
        fill="var(--color-surface, #f0f0f0)" stroke="var(--color-text, #333)" />
  <foreignObject x="20" y="20" width="160" height="60">
    <math xmlns="http://www.w3.org/1998/Math/MathML" display="block">
      <mfrac>
        <mrow><mo>&#x2202;</mo><mi>u</mi></mrow>
        <mrow><mo>&#x2202;</mo><mi>t</mi></mrow>
      </mfrac>
      <mo>=</mo>
      <mi>&#x03B1;</mi>
      <msup><mo>&#x2207;</mo><mn>2</mn></msup>
      <mi>u</mi>
    </math>
  </foreignObject>
  <text x="100" y="120" text-anchor="middle" fill="currentColor"
        font-size="14">Heat equation node</text>
</svg>
```

### LaTeX to MathML conversion

For migrating existing LaTeX content: temml (JS, pure conversion to MathML), latex2mathml (Python), and KaTeX with `output: "mathml"` all produce standards-compliant MathML.
Conversion can happen at authoring time (static MathML baked into HTML) or display time (via a client-side script).
For no-JS operation, pre-convert at authoring time and ship pure MathML in the HTML source.

### Styling MathML

MathML elements respond to CSS like any other elements:

```css
math {
  font-size: var(--size-fluid-1);
  color: var(--color-text);
}
math[display="block"] {
  margin-block: var(--size-3);
}
```

For high-quality mathematical typography, use STIX Two Math or Latin Modern Math as web fonts.
These fonts provide the full set of mathematical glyphs and OpenType MATH table data that browsers use for proper layout of fractions, radicals, and other constructs.

## Mapping from Typst and Beamer

For users migrating from Typst or LaTeX Beamer, the following table maps source features to their web equivalents.
The "layer" column references the progressive enhancement layers defined in the design system and layer architecture documents.

| Typst/Beamer feature | Web equivalent | Layer |
|---|---|---|
| `= Heading` / `\section` | `<section id="..."><h2>` | 0 |
| `== Slide` / `\begin{frame}` | `<section class="slide">` with scroll-snap | 1 |
| Math mode / `$...$` | `<math>` (MathML) | 0 |
| `#pause` / `\pause` | CSS animation delay + `@starting-style` or intersection observer | 2/5 |
| `#figure` / `\includegraphics` | `<figure><img>` or inline `<svg>` | 0 |
| CeTZ diagrams | Hand-authored SVG | 0 |
| Fletcher node-edge diagrams | SVG with `<g>` groups, `<marker>` arrowheads, `<path>` edges | 0 |
| `#footnote` / `\footnote` | Popover API with anchor positioning | 2 |
| Theorem environments | Semantic HTML with CUBE CSS blocks and `data-*` exceptions | 0/1 |
| `#bibliography` / `\bibliography` | `<footer>` with reference list or inline citations | 0 |
| `#set text(font: ...)` | Open Props typography tokens | 1 |
| Dark/light theme | `light-dark()` with `color-scheme` | 1 |
| `composer: (3fr, 2fr)` | CSS Grid `grid-template-columns: 3fr 2fr` | 1 |
| Focus slides | `data-layout="focus"` CUBE CSS exception | 1 |
| PDF export | `@media print` with `break-after: page` | 1 |
| Touying pause/meanwhile reducers | `@starting-style` + animation-delay staggering | 2/5 |
| Outline slides | `<nav>` with anchor links to section IDs | 0 |
| Progress bar footer | CSS counter or `::scroll-marker` (layer 4) | 1/4 |

The web approach trades Typst's precise typographic control for progressive enhancement, addressability, and platform-native rendering.
Every slide and section is a URL, every element participates in the browser's accessibility tree, and the content degrades gracefully when advanced CSS features are unavailable.

Complex CeTZ and Fletcher diagrams require hand-translation to SVG, which is more verbose than the source DSL but produces human-readable, themeable output that participates in the document cascade.
The SVG authoring patterns described earlier in this document apply directly.

Mathematical notation via MathML covers the vast majority of scientific use cases.
Only advanced LaTeX macro packages lack direct MathML equivalents: tikz-cd commutative diagrams, specialized notation systems like Feynman diagrams, and custom macro-heavy workflows that depend on TeX's macro expansion model.
For those cases, KaTeX or MathJax provide a progressive enhancement bridge while MathML handles the common path.
