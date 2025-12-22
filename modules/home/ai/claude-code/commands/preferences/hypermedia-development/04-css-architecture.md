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
@layer openprops, normalize, theme, components, utilities, app;
```

Layer semantics:
- `openprops`: Design token definitions (lowest precedence)
- `normalize`: Reset/normalization styles (overrides browser defaults)
- `theme`: Semantic token mappings and theme-specific overrides
- `components`: Reusable component styles
- `utilities`: Single-purpose utility classes
- `app`: Application-specific overrides (highest precedence)

Layer declarations must occur before any layered styles.

Example layered architecture:

```css
/* Layer definition */
@layer openprops, normalize, theme, components, utilities, app;

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
    components/
      card.css
      button.css
      dialog.css
    utilities.css          # Utility classes
  app.css                  # App-specific overrides
  main.css                 # Entry point, layer definitions
```

Entry point imports in layer order:

```css
/* main.css */
@layer openprops, normalize, theme, components, utilities, app;

@import "./tokens/openprops.css" layer(openprops);
@import "./layers/normalize.css" layer(normalize);
@import "./tokens/theme.css" layer(theme);
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
