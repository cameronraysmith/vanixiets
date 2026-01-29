# CSS architecture

Modern CSS architecture for hypermedia applications built on design tokens, cascade layers, and component-scoped styles.
This document prioritizes server-rendered HTML patterns where CSS provides styling and progressive enhancement without requiring JavaScript for core presentation.

## Design token philosophy

Design tokens are named CSS custom properties that represent design decisions as reusable values throughout an application.
Primitive tokens encode raw values (colors, sizes, durations) while semantic tokens derive meaning from primitives (primary color, surface background, text color).

Token-based architecture provides:
- Single source of truth for design values
- Theming via custom property reassignment
- Type safety through naming conventions
- Easy maintenance when design systems evolve

CSS custom properties cascade through the DOM, making them ideal for design tokens in hypermedia applications where server-rendered HTML needs consistent styling without bundling token values into every style declaration.

Contrast with utility-first approaches (Tailwind) where design values are embedded in class names, requiring build-time processing and lacking runtime flexibility.

## CUBE CSS methodology

CUBE CSS is a methodology developed by Andy Bell that works *with* the cascade rather than against it.
The acronym stands for **Composition**, **Utility**, **Block**, **Exception**—representing four conceptual layers organized by cascade priority.
Unlike methodologies like BEM that fight CSS's grain, CUBE extends CSS's natural capabilities.

For authoritative reference, see [cube.fyi](https://cube.fyi) and [Andy Bell's original article](https://piccalil.li/blog/cube-css/).

### Core philosophy

CUBE CSS embraces two fundamental principles.

*Work with the cascade*: Style as much as possible at a high level using cascade and inheritance.
By the time you reach the Block layer, blocks become small because previous layers have done most of the work.
Pages should render acceptably with only global styles loaded—blocks refine rather than define.

*Progressive enhancement*: Create a minimum viable experience that works in older browsers, then enhance with modern features like flexbox and grid.
CSS's forgiving nature allows extending functionality without polyfills or hacks, resulting in significantly less CSS code.

### The four layers

**Composition** provides high-level, flexible layouts that determine how elements interact spatially.
Composition creates consistent flow and rhythm, accommodating any content type without visual treatment (colors, shadows).
This layer is the macro view—even when applied in component-level contexts.

**Utility** classes do one job well.
Each utility applies a single CSS property or small group of related properties.
Utilities extend design tokens as reusable helpers, abstracting repeatability to HTML rather than CSS.
Open Props tokens integrate naturally here—utility classes generated from token values.

**Block** styles apply specific rules for component contexts.
Blocks arrive late in the cascade; most work is done by global styles, composition, and utilities.
This makes blocks tiny compared to BEM-style component CSS.
Block internals should employ composition patterns for flexible content support.

**Exception** handles deviations from block rules, typically state changes.
Exceptions use data attributes rather than CSS classes:

```html
<article class="card" data-state="reversed"></article>
```

```css
.card[data-state='reversed'] {
  flex-direction: column-reverse;
}
```

Data attributes provide dual hooks for CSS and JavaScript, aligning with finite state machine concepts.
Exceptions should be concise variations—if a variation is extreme enough to be unrecognizable, create a new block instead.

### Class grouping convention

CUBE recommends grouping classes for readability:

```html
<article
  class="[ card ] [ section box ] [ bg-base color-primary ]"
  data-state="reversed"
>
```

Groups separate: primary block class, additional blocks/compositions, utility classes.
Square brackets or pipes (`|`) work as delimiters—consistency matters more than specific syntax.

## Open Props integration

Open Props is a design token library delivered as CSS custom properties, not utility classes.
Install via npm (`open-props`) or CDN, then import token categories as needed.

Primary token categories:
- Colors: `--red-0` through `--red-12`, `--blue-0` through `--blue-12`, etc (OKLch-based)
- Sizes: `--size-000` through `--size-15` (fluid scale from 0.125rem to 15rem)
- Typography: `--font-sans`, `--font-serif`, `--font-mono`, `--font-size-0` through `--font-size-8`
- Shadows: `--shadow-1` through `--shadow-6` (elevation scale)
- Borders: `--border-size-1` through `--border-size-5`, `--radius-1` through `--radius-6`
- Easings: `--ease-1` through `--ease-5`, `--ease-spring-1` through `--ease-spring-5`
- Gradients: `--gradient-1` through `--gradient-30` (pre-designed gradient combinations)

Example usage:

```css
.card {
  padding: var(--size-4);
  background: var(--gray-1);
  border-radius: var(--radius-3);
  box-shadow: var(--shadow-2);
  color: var(--gray-9);
}
```

Token names are semantic within their category (`--size-4` is medium size, `--shadow-2` is subtle elevation) but primitive in absolute terms (not named "card-padding" or "subtle-shadow").
This balances reusability with semantic meaning.

### Import strategy

Import only needed token categories to minimize CSS payload:

```css
@import "open-props/colors";
@import "open-props/sizes";
@import "open-props/shadows";
@import "open-props/borders";
```

For comprehensive coverage, use the aggregate import:

```css
@import "open-props/style";
```

Imports must occur before any styles that reference the tokens.

### OKLch color space

Open Props colors use OKLch (Lightness, Chroma, Hue) for perceptual uniformity.
OKLch ensures equal visual weight across hues at the same lightness level, unlike HSL where blue-5 and yellow-5 appear drastically different in brightness.

Browser compatibility:
- Chrome 111+
- Firefox 113+
- Safari 15.4+

For wider browser support, use PostCSS with `postcss-preset-env` to transpile OKLch to fallback color spaces.

## Open Props UI component ownership model

Open Props UI provides copy-paste components where you own the CSS after copying, not an npm dependency with locked implementation.

Component workflow:
1. Browse components at [open-props.style](https://open-props.style)
2. Copy component CSS into your project
3. Customize freely without version lock-in
4. No build-time dependency or class name conflicts

This contrasts with utility-first frameworks (Tailwind) where you don't own the utility classes and must accept framework conventions.
It also contrasts with component libraries (Bootstrap) where customization requires overriding existing styles with specificity battles.

Example copied component (button):

```css
.button {
  padding: var(--size-2) var(--size-4);
  border-radius: var(--radius-2);
  background: var(--primary);
  color: var(--text-on-primary);
  border: none;
  font-weight: var(--font-weight-6);
  cursor: pointer;
  transition: background 0.2s var(--ease-3);
}

.button:hover {
  background: var(--primary-hover);
}
```

After copying, rename classes, adjust token references, or rewrite entirely to match your design system.

## CSS cascade layers

Cascade layers (`@layer`) provide explicit control over style precedence independent of specificity.
Layers eliminate specificity wars and `!important` hacks by defining a global ordering where later layers override earlier layers regardless of selector specificity.

Recommended layer order for hypermedia applications:

```css
@layer openprops, normalize, theme, compositions, components, utilities, app;
```

Layer semantics:
- `openprops`: Design token definitions (lowest precedence)
- `normalize`: Reset/normalization styles (overrides browser defaults)
- `theme`: Semantic token mappings and theme-specific overrides
- `compositions`: Layout primitives for spatial relationships (see "Composition primitives" section)
- `components`: Reusable component styles (CUBE "blocks")
- `utilities`: Single-purpose utility classes
- `app`: Application-specific overrides (highest precedence)

The `compositions` layer sits between theme (design decisions) and components (styled blocks) because compositions use theme tokens but don't define them, and components may contain compositions but compositions remain layout-agnostic.

Layer declarations must occur before any layered styles.

Example layered architecture:

```css
/* Layer definition */
@layer openprops, normalize, theme, compositions, components, utilities, app;

/* Open Props tokens */
@layer openprops {
  @import "open-props/style";
}

/* Normalize */
@layer normalize {
  *, *::before, *::after {
    box-sizing: border-box;
  }
  body {
    margin: 0;
    line-height: 1.5;
  }
}

/* Theme layer */
@layer theme {
  :root {
    --primary: var(--blue-7);
    --primary-hover: var(--blue-8);
    --surface-default: light-dark(var(--gray-0), var(--gray-9));
    --text-primary: light-dark(var(--gray-9), var(--gray-1));
  }
}

/* Compositions layer - layout primitives */
@layer compositions {
  .stack > * + * {
    margin-block-start: var(--stack-space, var(--size-3));
  }

  .cluster {
    display: flex;
    flex-wrap: wrap;
    gap: var(--cluster-space, var(--size-3));
  }
}

/* Component layer */
@layer components {
  .card {
    background: var(--surface-default);
    color: var(--text-primary);
    padding: var(--size-4);
  }
}

/* App layer */
@layer app {
  .homepage-hero {
    padding: var(--size-8);
  }
}
```

Specificity within a layer still matters, but layer order takes precedence.
A simple selector in the `app` layer beats a complex selector in the `components` layer.

## Theme switching with light-dark()

The `light-dark()` CSS function selects values based on color scheme preference without JavaScript.

Syntax:

```css
color: light-dark(var(--gray-9), var(--gray-1));
```

Resolves to first argument (light mode) when `color-scheme: light` is active, second argument (dark mode) when `color-scheme: dark` is active.

Enable color scheme detection:

```css
:root {
  color-scheme: light dark;
}
```

This respects user's system preference via `prefers-color-scheme` media query.

For manual theme toggle, use `data-theme` attribute with fallback:

```html
<html data-theme="dark">
```

```css
:root {
  color-scheme: light dark;
}

[data-theme="light"] {
  color-scheme: light;
}

[data-theme="dark"] {
  color-scheme: dark;
}
```

Toggle via server-rendered attribute or minimal JavaScript:

```js
document.documentElement.dataset.theme = newTheme;
```

Browser compatibility:
- Chrome 123+
- Firefox 120+
- Safari 17.5+

For wider support, use PostCSS transpilation or CSS variable fallback:

```css
:root {
  --text-primary: var(--gray-9);
}

@media (prefers-color-scheme: dark) {
  :root {
    --text-primary: var(--gray-1);
  }
}
```

## Semantic token mapping

Map primitive tokens to semantic tokens in the `theme` layer to enable design changes without touching component styles.

Example semantic mapping:

```css
@layer theme {
  :root {
    /* Color semantics */
    --primary: var(--blue-7);
    --primary-hover: var(--blue-8);
    --danger: var(--red-7);
    --success: var(--green-7);

    /* Surface semantics */
    --surface-default: light-dark(var(--gray-0), var(--gray-9));
    --surface-raised: light-dark(var(--gray-1), var(--gray-8));
    --surface-overlay: light-dark(var(--gray-2), var(--gray-7));

    /* Text semantics */
    --text-primary: light-dark(var(--gray-9), var(--gray-1));
    --text-secondary: light-dark(var(--gray-7), var(--gray-3));
    --text-on-primary: var(--gray-0);

    /* Interactive semantics */
    --link: var(--primary);
    --link-visited: var(--purple-7);
    --focus-ring: var(--primary);

    /* Spacing semantics (optional, primitive sizes often sufficient) */
    --space-component: var(--size-4);
    --space-section: var(--size-8);
  }
}
```

Component styles reference semantic tokens:

```css
@layer components {
  .card {
    background: var(--surface-raised);
    color: var(--text-primary);
    padding: var(--space-component);
  }

  .button-primary {
    background: var(--primary);
    color: var(--text-on-primary);
  }

  .button-primary:hover {
    background: var(--primary-hover);
  }
}
```

When design system changes (rebrand from blue to purple), update only theme layer:

```css
@layer theme {
  :root {
    --primary: var(--purple-7);
    --primary-hover: var(--purple-8);
  }
}
```

All components using `--primary` update automatically.

## Container queries

Container queries enable component-level responsive design based on container size, not viewport size.

Define container context:

```css
.card-grid {
  container-type: inline-size;
  container-name: card-grid;
}
```

Query container dimensions:

```css
.card {
  padding: var(--size-2);
}

@container card-grid (min-width: 40rem) {
  .card {
    padding: var(--size-4);
    display: grid;
    grid-template-columns: auto 1fr;
  }
}
```

Container queries provide true component encapsulation where a component adapts to its container regardless of viewport size.
This eliminates the need for JavaScript-based resize observers or viewport media queries that couple components to page layout.

Use container query units for fluid sizing within containers:

```css
.card-title {
  font-size: clamp(1rem, 5cqi, 2rem);
}
```

Container query units (`cqi`, `cqb`, `cqw`, `cqh`) are relative to container dimensions, not viewport.

Browser compatibility:
- Chrome 105+
- Firefox 110+
- Safari 16.0+

For older browsers, provide viewport media query fallback or accept single-column layout.

## Composition primitives

Composition primitives are reusable layout patterns that respond to their content and container rather than viewport breakpoints.
This approach is called *intrinsic design*—layouts that figure themselves out algorithmically without media query intervention.

For authoritative reference, see [Every Layout](https://every-layout.dev) by Heydon Pickering and Andy Bell.

### Design principles

Composition primitives embody three key principles.

*Singular responsibility*: Each primitive does one layout job.
Stack handles vertical spacing; Cluster handles horizontal wrapping; Sidebar handles two-element main/sidebar relationships.
Complex layouts emerge from composition of simple primitives.

*Intrinsic responsiveness*: Primitives reconfigure based on available space, not viewport width.
A Switcher switches from row to column when its container becomes too narrow—no media query needed.
This produces context-independent components usable anywhere.

*Composability*: Primitives nest within each other.
A Stack inside a Sidebar inside a Center all compose correctly.
This compositional property resembles algebraic closure—layout operations preserve the layout type.

### The eight primitives

Each primitive exposes custom properties for configuration, using Open Props tokens as defaults.

#### Stack

Manages vertical spacing between siblings via the "owl selector" pattern:

```css
.stack {
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
}

.stack > * + * {
  margin-block-start: var(--stack-space, var(--size-3));
}
```

The `> * + *` selector applies margin only where an element is preceded by another, avoiding extra margin on first/last elements.
Configure spacing via custom property:

```html
<div class="stack" style="--stack-space: var(--size-5)">
  <h1>Title</h1>
  <p>First paragraph</p>
  <p>Second paragraph</p>
</div>
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--stack-space` | `var(--size-3)` | Vertical gap between siblings |

#### Box

A padded container with optional border and background inheritance:

```css
.box {
  padding: var(--box-padding, var(--size-3));
  border: var(--box-border, 0) solid;
  background-color: inherit;
}
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--box-padding` | `var(--size-3)` | Internal padding |
| `--box-border` | `0` | Border width |

#### Center

Horizontally centers content within a maximum width:

```css
.center {
  box-sizing: content-box;
  max-inline-size: var(--center-max, var(--size-content-3));
  margin-inline: auto;
  padding-inline: var(--center-gutters, var(--size-3));
}
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--center-max` | `var(--size-content-3)` | Maximum width |
| `--center-gutters` | `var(--size-3)` | Horizontal padding |

#### Cluster

A wrapping horizontal group with consistent gap spacing:

```css
.cluster {
  display: flex;
  flex-wrap: wrap;
  gap: var(--cluster-space, var(--size-3));
  justify-content: var(--cluster-justify, flex-start);
  align-items: var(--cluster-align, center);
}
```

Ideal for tag collections, button groups, or icon sets that should flow horizontally and wrap naturally:

```html
<div class="cluster">
  <button>Save</button>
  <button>Cancel</button>
  <button>Delete</button>
</div>
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--cluster-space` | `var(--size-3)` | Gap between items |
| `--cluster-justify` | `flex-start` | Horizontal alignment |
| `--cluster-align` | `center` | Vertical alignment |

#### Sidebar

Two elements where one maintains fixed width while the other fills remaining space:

```css
.sidebar {
  display: flex;
  flex-wrap: wrap;
  gap: var(--sidebar-gap, var(--size-3));
}

.sidebar > :first-child {
  flex-basis: var(--sidebar-width, 20rem);
  flex-grow: 1;
}

.sidebar > :last-child {
  flex-basis: 0;
  flex-grow: 999;
  min-inline-size: var(--sidebar-content-min, 50%);
}
```

The `min-inline-size: 50%` triggers wrapping when content area would become too narrow.
No media query—behavior emerges from flex properties:

```html
<div class="sidebar">
  <nav>Sidebar content</nav>
  <main>Main content expands to fill space</main>
</div>
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--sidebar-width` | `20rem` | Sidebar target width |
| `--sidebar-gap` | `var(--size-3)` | Gap between elements |
| `--sidebar-content-min` | `50%` | Min width before wrapping |

#### Switcher

Switches between horizontal and vertical layout based on container width threshold:

```css
.switcher {
  display: flex;
  flex-wrap: wrap;
  gap: var(--switcher-gap, var(--size-3));
}

.switcher > * {
  flex-grow: 1;
  flex-basis: calc((var(--switcher-threshold, 30rem) - 100%) * 999);
}
```

The calculation produces either a large positive (forces 100% width, vertical stacking) or negative (horizontal distribution) value based on container width.
All children get equal width—no awkward intermediate states:

```html
<div class="switcher">
  <div>Equal width</div>
  <div>Equal width</div>
  <div>Equal width</div>
</div>
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--switcher-threshold` | `30rem` | Width at which layout switches |
| `--switcher-gap` | `var(--size-3)` | Gap between items |

#### Cover

Full-height container with centered principal element:

```css
.cover {
  display: flex;
  flex-direction: column;
  min-block-size: var(--cover-min-height, 100vh);
  padding: var(--cover-padding, var(--size-3));
}

.cover > * {
  margin-block: var(--cover-space, var(--size-3));
}

.cover > :first-child:not(.cover-centered) {
  margin-block-start: 0;
}

.cover > :last-child:not(.cover-centered) {
  margin-block-end: 0;
}

.cover > .cover-centered {
  margin-block: auto;
}
```

Ideal for hero sections where a heading should be vertically centered with header/footer content at edges:

```html
<div class="cover">
  <header>Top</header>
  <h1 class="cover-centered">Vertically centered hero</h1>
  <footer>Bottom</footer>
</div>
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--cover-min-height` | `100vh` | Minimum container height |
| `--cover-padding` | `var(--size-3)` | Internal padding |
| `--cover-space` | `var(--size-3)` | Margin around children |

#### Grid

Responsive auto-filling grid that adapts column count to available space:

```css
.grid {
  display: grid;
  grid-template-columns: repeat(
    auto-fill,
    minmax(min(var(--grid-min, 250px), 100%), 1fr)
  );
  gap: var(--grid-gap, var(--size-3));
}
```

Items never become narrower than `--grid-min`, and columns are added/removed automatically:

```html
<div class="grid" style="--grid-min: 300px">
  <div>Card 1</div>
  <div>Card 2</div>
  <div>Card 3</div>
  <div>Card 4</div>
</div>
```

| Property | Default | Purpose |
|----------|---------|---------|
| `--grid-min` | `250px` | Minimum item width |
| `--grid-gap` | `var(--size-3)` | Gap between items |

### Composition examples

Complex layouts emerge from combining primitives:

```html
<!-- Dialog: Center > Box > Stack > Cluster -->
<div class="center">
  <div class="box">
    <div class="stack">
      <h2>Confirm Action</h2>
      <p>Are you sure you want to proceed?</p>
      <div class="cluster" style="--cluster-justify: flex-end">
        <button>Cancel</button>
        <button>Confirm</button>
      </div>
    </div>
  </div>
</div>

<!-- Article layout: Center > Stack > Sidebar -->
<article class="center">
  <div class="stack" style="--stack-space: var(--size-5)">
    <h1>Article Title</h1>
    <div class="sidebar">
      <aside>Table of contents</aside>
      <div class="stack">
        <p>Main content...</p>
        <p>More content...</p>
      </div>
    </div>
  </div>
</article>
```

### Algebraic properties

Composition primitives exhibit properties analogous to algebraic structures.

*Closure*: Composing primitives yields valid layouts.
A Stack containing a Grid containing Clusters remains well-formed.

*Local reasoning*: A Stack behaves identically regardless of parent context.
Like pure functions that produce the same output for the same input, primitives produce consistent layout behavior regardless of where they're used.

*Identity*: An empty composition (a div with no layout class) acts as identity—it doesn't transform the layout of its children.

These properties emerge from the CSS techniques used (flexbox/grid intrinsic sizing) rather than being explicitly enforced, but they're reliable enough to treat compositions as a layout algebra.

See `theoretical-foundations.md` for formal algebraic foundations including signals as comonads and web components as coalgebras.

## PostCSS configuration

PostCSS transpiles modern CSS features for broader browser support.

Recommended plugins for hypermedia applications:

```js
// postcss.config.js
export default {
  plugins: {
    'postcss-import': {},
    'postcss-preset-env': {
      stage: 0,
      features: {
        'oklab-function': true,
        'light-dark-function': true,
        'custom-media-queries': true,
        'nesting-rules': true,
      },
    },
  },
};
```

Plugin purposes:
- `postcss-import`: Process `@import` statements, required for Open Props imports
- `postcss-preset-env`: Transpile modern features to fallback syntax

Stage 0 enables experimental features (OKLch, `light-dark()`).
Specify features explicitly to avoid unexpected transpilation of stable features.

Custom media queries for design token-based breakpoints:

```css
@custom-media --viewport-sm (min-width: 40rem);
@custom-media --viewport-md (min-width: 60rem);
@custom-media --viewport-lg (min-width: 80rem);

@media (--viewport-md) {
  .container {
    max-width: 60rem;
  }
}
```

Transpiles to standard media queries for browser compatibility.

## Light DOM requirement for web components

Shadow DOM encapsulation blocks CSS custom property inheritance from document scope.
Web components using Open Props tokens must render in Light DOM to inherit `--size-*`, `--color-*`, etc.

For Lit components, override `createRenderRoot()`:

```ts
import { LitElement, html } from 'lit';

class MyCard extends LitElement {
  createRenderRoot() {
    return this;
  }

  render() {
    return html`
      <div class="card" style="padding: var(--size-4)">
        <slot></slot>
      </div>
    `;
  }
}
```

Without `createRenderRoot()` override, Lit creates Shadow DOM and `var(--size-4)` fails to resolve.

Light DOM trade-offs:
- Enables token inheritance
- Loses style encapsulation
- Requires unique class names or scoping strategy

See `05-web-components.md` for Lit Light DOM patterns and scoping strategies.

## File organization

Organize CSS by layer and feature:

```
styles/
  tokens/
    openprops.css          # Open Props imports
    theme.css              # Semantic token mappings
  layers/
    normalize.css          # Reset styles
    compositions/          # Layout primitives
      stack.css
      box.css
      center.css
      cluster.css
      sidebar.css
      switcher.css
      cover.css
      grid.css
    components/            # CUBE "blocks"
      card.css
      button.css
      dialog.css
    utilities.css          # Single-purpose utilities
  app.css                  # App-specific overrides
  main.css                 # Entry point, layer definitions
```

Entry point imports in layer order:

```css
/* main.css */
@layer openprops, normalize, theme, compositions, components, utilities, app;

@import "./tokens/openprops.css" layer(openprops);
@import "./layers/normalize.css" layer(normalize);
@import "./tokens/theme.css" layer(theme);
@import "./layers/compositions/stack.css" layer(compositions);
@import "./layers/compositions/box.css" layer(compositions);
@import "./layers/compositions/center.css" layer(compositions);
@import "./layers/compositions/cluster.css" layer(compositions);
@import "./layers/compositions/sidebar.css" layer(compositions);
@import "./layers/compositions/switcher.css" layer(compositions);
@import "./layers/compositions/cover.css" layer(compositions);
@import "./layers/compositions/grid.css" layer(compositions);
@import "./layers/components/card.css" layer(components);
@import "./layers/components/button.css" layer(components);
@import "./layers/utilities.css" layer(utilities);
@import "./app.css" layer(app);
```

Component CSS files contain only component styles:

```css
/* layers/components/card.css */
.card {
  background: var(--surface-raised);
  padding: var(--size-4);
  border-radius: var(--radius-3);
  box-shadow: var(--shadow-2);
}

.card-title {
  font-size: var(--font-size-4);
  font-weight: var(--font-weight-7);
  margin-block-end: var(--size-2);
}
```

No layer declarations in component files; layer assignment happens at import.

## Browser compatibility strategy

Modern CSS features require recent browsers.
Accept this constraint for greenfield projects targeting current browsers, or provide graceful degradation for wider support.

Critical features and minimum versions:
- Cascade layers: Chrome 99+, Firefox 97+, Safari 15.4+
- Container queries: Chrome 105+, Firefox 110+, Safari 16.0+
- `light-dark()`: Chrome 123+, Firefox 120+, Safari 17.5+
- OKLch colors: Chrome 111+, Firefox 113+, Safari 15.4+

Graceful degradation patterns:

For cascade layers, provide fallback without layers (specificity-based):

```css
/* Modern browsers */
@supports (color: light-dark(red, blue)) {
  @layer theme {
    :root {
      --text: light-dark(var(--gray-9), var(--gray-1));
    }
  }
}

/* Fallback */
@supports not (color: light-dark(red, blue)) {
  :root {
    --text: var(--gray-9);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --text: var(--gray-1);
    }
  }
}
```

For OKLch, PostCSS transpilation converts to RGB/HSL automatically.

For container queries, accept single-column layout or use viewport media queries as fallback.

Document minimum browser versions in project README and communicate to stakeholders.

## Comparison with utility-first approaches

Utility-first frameworks (Tailwind) embed design decisions in HTML class names.
Token-based approaches (Open Props) embed design decisions in CSS custom properties.

Utility-first example:

```html
<div class="p-4 bg-gray-100 rounded-lg shadow-md text-gray-900">
  <h2 class="text-xl font-bold mb-2">Card Title</h2>
</div>
```

Token-based example:

```html
<div class="card">
  <h2 class="card-title">Card Title</h2>
</div>
```

```css
.card {
  padding: var(--size-4);
  background: var(--surface-raised);
  border-radius: var(--radius-3);
  box-shadow: var(--shadow-2);
  color: var(--text-primary);
}

.card-title {
  font-size: var(--font-size-4);
  font-weight: var(--font-weight-7);
  margin-block-end: var(--size-2);
}
```

Trade-offs:

Utility-first:
- Rapid development for common patterns
- Requires build step for purging unused utilities
- Design changes require HTML edits
- No runtime theming without JavaScript

Token-based:
- Semantic HTML class names
- Runtime theming via custom property reassignment
- Design changes isolated to CSS
- Requires writing custom CSS

Choose utility-first when development speed and consistency matter more than semantic HTML.
Choose token-based when semantic HTML, runtime theming, and server-rendered hypermedia matter more than build-time optimization.

For hypermedia applications where HTML is server-rendered and CSS provides styling without JavaScript, token-based architecture aligns better with progressive enhancement and the principle of least power.
