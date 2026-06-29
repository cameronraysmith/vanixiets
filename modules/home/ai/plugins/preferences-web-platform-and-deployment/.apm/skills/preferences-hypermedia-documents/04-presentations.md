# Presentations

Slide presentations are a specific parameterization of the hypermedia document pattern described in this skill set.
A presentation is a document whose sections serve as slides, navigated via scroll-snap, styled via CUBE CSS with slide-specific blocks and exceptions, and progressively enhanced with modern CSS and minimal JavaScript.

The approach produces a standards-aligned HTML document that is addressable (each slide has a URL fragment), inspectable (View Source works), media-independent (printable), and progressively enhanced (functional at every layer).
Presentations activate layers 0-5 (HTML, scroll-snap, modern CSS, view transitions, native carousel, minimal JS) from `02-progressive-layers.md`, with optional layer 6 (web components for charts or diagrams).

This replaces reveal.js for standards-aligned needs, Typst/Beamer for web-native delivery, and custom single-file generators (like the ericmjl html-presentations pattern) with a principled, composable foundation.

## Document structure

A presentation is an HTML document with `<section>` elements as slides inside a scroll-snap container.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <title>Presentation title</title>
  <link rel="stylesheet" href="./styles/main.css">
</head>
<body>
  <main>
    <section class="slide" id="title" data-layout="title">
      <h1>Presentation title</h1>
      <p>Author name</p>
      <p><time datetime="2026-03-31">March 2026</time></p>
    </section>

    <section class="slide" id="motivation" data-layout="content">
      <h2>Motivation</h2>
      <p>Content here.</p>
    </section>

    <section class="slide" id="diagram" data-layout="two-column">
      <div>
        <h2>Architecture</h2>
        <p>Explanation.</p>
      </div>
      <figure>
        <svg class="icon"><use href="./assets/arch-diagram.svg#overview"></use></svg>
        <figcaption>System architecture overview</figcaption>
      </figure>
    </section>

    <section class="slide" id="math-example" data-layout="content">
      <h2>The heat equation</h2>
      <math display="block">
        <mfrac>
          <mrow><mo>&part;</mo><mi>u</mi></mrow>
          <mrow><mo>&part;</mo><mi>t</mi></mrow>
        </mfrac>
        <mo>=</mo>
        <mi>&alpha;</mi>
        <msup><mo>&nabla;</mo><mn>2</mn></msup>
        <mi>u</mi>
      </math>
    </section>

    <section class="slide" id="thanks" data-layout="title">
      <h2>Thank you</h2>
    </section>

    <section class="slide" id="supp-details" data-supplementary data-layout="content">
      <h2>Supplementary: detailed derivation</h2>
      <!-- supplementary material -->
    </section>
  </main>
  <script type="module" src="./scripts/navigation.js"></script>
</body>
</html>
```

Key structural decisions:

- `<main>` is the scroll-snap container
- Each `<section class="slide">` is a snap target
- `data-layout` attributes select CUBE CSS exceptions for layout variants
- `data-supplementary` marks slides that appear after the main deck (referenced via internal links)
- `id` attributes on every section enable URL-fragment addressing

## Slide layouts

Slide layouts are CUBE CSS exceptions applied via `data-layout` attributes on `<section>` elements.

```css
@layer blocks {
  .slide {
    min-inline-size: 100vw;
    min-block-size: 100dvh;
    scroll-snap-align: start;
    display: grid;
    place-content: center;
    padding: var(--size-5);
    gap: var(--size-3);
  }
}

@layer exceptions {
  .slide[data-layout="title"] {
    text-align: center;
    justify-content: center;
  }

  .slide[data-layout="content"] {
    align-content: start;
    padding-block-start: var(--size-8);
  }

  .slide[data-layout="two-column"] {
    grid-template-columns: 1fr 1fr;
    align-items: center;
  }

  .slide[data-layout="focus"] {
    background: var(--color-accent);
    color: var(--color-surface);
    font-size: var(--size-fluid-3);
    text-align: center;
  }

  .slide[data-layout="code"] {
    font-family: var(--font-mono);
    align-content: start;
  }

  .slide[data-layout="diagram"] {
    padding: var(--size-3);
  }
  .slide[data-layout="diagram"] svg {
    max-inline-size: 100%;
    max-block-size: 80dvh;
  }
}
```

Additional layouts can be added as project-specific exceptions without modifying the core blocks.

## Navigation

Navigation progresses through three enhancement layers.

### CSS-only (layer 1)

Scroll, touch, and swipe navigation via scroll-snap.
Tab and Shift+Tab move focus between interactive elements.
`:target` enables direct jump to any slide via URL fragment.

### Native carousel (layer 4, Chrome 142+)

```css
main::scroll-button(previous) { content: "\2190"; }
main::scroll-button(next) { content: "\2192"; }

.slide::scroll-marker {
  content: "";
  inline-size: 0.5rem;
  block-size: 0.5rem;
  border-radius: var(--radius-round);
  background: var(--color-muted);
}
.slide::scroll-marker:target-current {
  background: var(--color-accent);
}
```

### JavaScript enhancement (layer 5)

```js
const slides = document.querySelectorAll('.slide');
let current = 0;

function show(index) {
  current = Math.max(0, Math.min(index, slides.length - 1));
  slides[current].scrollIntoView({ behavior: 'smooth' });
  history.replaceState(null, '', `#${slides[current].id}`);
}

document.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowRight' || e.key === ' ') { e.preventDefault(); show(current + 1); }
  if (e.key === 'ArrowLeft') { e.preventDefault(); show(current - 1); }
});

// Restore position from URL hash on load
const hash = location.hash.slice(1);
if (hash) {
  const target = document.getElementById(hash);
  if (target) show([...slides].indexOf(target));
}
```

This JS is approximately 20 lines, substantially smaller than the ericmjl pattern's navigation IIFE because modern CSS (layers 2-4) handles active-slide styling, progress indicators, and basic navigation.

## Active slide styling

Three approaches, in order of preference.

### `@container scroll-state()` (Chrome 133+)

```css
main { container-type: scroll-state; }

@container scroll-state(snapped: inline) {
  .slide { opacity: 1; transform: scale(1); }
}
.slide { opacity: 0.3; transform: scale(0.95); transition: all 0.3s var(--ease-2); }
```

### Intersection Observer fallback (all browsers)

```js
const observer = new IntersectionObserver((entries) => {
  entries.forEach(e => e.target.classList.toggle('active', e.isIntersecting));
}, { threshold: 0.5 });
slides.forEach(s => observer.observe(s));
```

### JS scroll event fallback (most compatible, least performant)

Only use this approach if the above two are insufficient for the target browser matrix.

## Incremental reveal

Progressive reveal of content within a slide replaces Typst's `#pause` and Beamer's `\pause`.

### CSS-only approach using `@starting-style` and animation delays

```css
.slide.active .reveal {
  opacity: 1;
  transform: translateY(0);
  transition: opacity 0.4s var(--ease-2), transform 0.4s var(--ease-2);
  transition-delay: calc(var(--reveal-order, 0) * 0.15s);

  @starting-style {
    opacity: 0;
    transform: translateY(1rem);
  }
}
```

```html
<section class="slide" id="steps">
  <h2>Three steps</h2>
  <p class="reveal" style="--reveal-order: 0">First</p>
  <p class="reveal" style="--reveal-order: 1">Second</p>
  <p class="reveal" style="--reveal-order: 2">Third</p>
</section>
```

This reveals items automatically when the slide becomes active via the `.active` class.
No click interaction is required.
For click-to-advance reveal, a small JS handler that toggles visibility per step is needed (layer 5).

## Speaker notes

Speaker notes use the popover API (baseline).

```html
<section class="slide" id="example">
  <h2>Topic</h2>
  <p>Visible content.</p>
  <button popovertarget="notes-example" class="notes-toggle">Notes</button>
  <div id="notes-example" popover>
    <p>Speaker notes visible only when toggled.</p>
  </div>
</section>
```

For a separate presenter window:

```js
function openPresenterView() {
  const win = window.open('', 'presenter', 'width=800,height=600');
  // Sync slide state and display notes in the secondary window
}
```

Speaker notes are invisible by default and do not affect the document's layout or print output.

## Print and export

```css
@media print {
  main {
    overflow: visible;
    scroll-snap-type: none;
    display: block;
  }
  .slide {
    break-after: page;
    min-block-size: auto;
    page-break-inside: avoid;
  }
  .slide[data-supplementary] {
    /* optionally exclude supplementary slides from print */
  }
  nav, .notes-toggle, [popover] {
    display: none;
  }
}
```

This produces one slide per page when printing to PDF via the browser's native Print dialog.
No external tool is needed.

## Supplementary slides

Slides after the main deck are marked with `data-supplementary`.
They are linked from the main deck via standard anchor elements.

```html
<!-- In a main slide -->
<a href="#supp-details">See detailed derivation</a>

<!-- The supplementary slide -->
<section class="slide" id="supp-details" data-supplementary>
  ...
</section>
```

A visual separator (CSS border or counter reset) distinguishes main from supplementary content.
Progress indicators (if present) can exclude supplementary slides:

```css
.slide[data-supplementary]::scroll-marker {
  display: none;
}
```

## What this approach replaces

| Tool | What it does | What the web approach trades | What it gains |
|---|---|---|---|
| reveal.js | Full-featured JS presentation framework (~250KB) | Plugin ecosystem, multiplexing, PDF export via puppeteer | No framework dependency, progressive enhancement, full platform property compliance |
| Slidev | Vue + Vite markdown presentations | Markdown authoring, Monaco live coding, NPM theme ecosystem | No build step, no Node.js, no Vue runtime |
| Typst/Beamer | PDF presentations via typesetting | Precise typographic control, equation rendering parity with LaTeX | Addressability, linkability, interactivity, live CSS theming, web component integration |
| ericmjl html-presentations | Single-file AI-generated HTML slides | Established templates, catppuccin/nord themes | Open Props tokens, CUBE CSS methodology, progressive enhancement, modern CSS features, modular structure |
