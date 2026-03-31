# Design system layer

Standalone hypermedia documents use Open Props as their design token vocabulary, CUBE CSS as the organizational methodology, and CSS cascade layers as the composition mechanism.
Together these three layers provide a deterministic, framework-agnostic styling architecture that works in any HTML document without a build step.

## Cascade layer ordering

Documents use CSS cascade layers to establish a deterministic specificity order.
The layer declaration goes at the top of the main stylesheet, before any other rules:

```css
@layer openprops, normalize, theme, compositions, utilities, blocks, exceptions;
```

Each layer serves a distinct role in the cascade.

The `openprops` layer contains design token definitions imported from Open Props.
These are the raw custom property primitives that all other layers reference.

The `normalize` layer applies browser normalization.
This may be the Open Props normalize stylesheet or a custom reset, ensuring consistent cross-browser defaults.

The `theme` layer maps Open Props primitives to document-specific semantic tokens using `light-dark()`.
Semantic tokens like `--color-text` and `--color-surface` are defined here, decoupling document styles from raw color or spacing values.

The `compositions` layer holds layout primitives following the Every Layout patterns.
These are structural skeletons that control spatial arrangement without opinions about decoration.

The `utilities` layer provides single-property utility classes bound to Open Props tokens.
Each utility applies exactly one property.

The `blocks` layer styles semantic content types, the meaningful "things" in a document such as slides, code blocks, diagrams, and callouts.

The `exceptions` layer handles per-context overrides via `data-*` attributes.
These are state-specific or variant-specific adjustments that need the highest layer priority.

This layer ordering mirrors the CSS architecture used by Ironstar (`~/projects/rust-workspace/ironstar`), ensuring consistency between standalone documents and server-connected applications.

## Open Props design tokens

Open Props provides CSS custom properties organized by category.
These tokens are the primitive vocabulary from which all document styles are composed.

The typography scale uses `--size-1` through `--size-fluid-3` for responsive font sizes.
Font stacks are available via `--font-sans` and `--font-mono`.

Colors use the OKLch color space.
Each hue provides a 13-step ramp from `--blue-0` (lightest) through `--blue-12` (darkest), with equivalent ramps for all named hues.
Raw color tokens should not appear directly in document styles; instead the theme layer maps them to semantic tokens like `--color-text`, `--color-surface`, and `--color-accent`.

Spacing tokens `--size-1` through `--size-15` provide a consistent scale for margins, padding, and gaps.

Shadow tokens `--shadow-1` through `--shadow-6` provide elevation levels for layered surfaces.

Easing tokens include `--ease-1` through `--ease-5`, directional variants like `--ease-in-1` through `--ease-in-5`, and spring easings for physics-based motion.

Animation tokens such as `--animation-fade-in` and `--animation-slide-in-up` provide reusable keyframe animations.

Open Props tokens are framework-agnostic CSS custom properties.
Import via CDN link for zero-setup usage:

```html
<link rel="stylesheet" href="https://unpkg.com/open-props">
```

Or for a local or bundled approach, import into the cascade layer directly:

```css
@import "open-props/open-props.min.css" layer(openprops);
```

## Theming with light-dark()

The `light-dark()` CSS function provides automatic color scheme support without JavaScript.
Set `color-scheme` on the root element to declare support for both modes:

```css
:root {
  color-scheme: light dark;
}

@layer theme {
  :root {
    --color-text: light-dark(var(--gray-9), var(--gray-2));
    --color-surface: light-dark(var(--gray-0), var(--gray-9));
    --color-accent: light-dark(var(--blue-7), var(--blue-4));
    --color-muted: light-dark(var(--gray-5), var(--gray-6));
  }
}
```

This respects the user's `prefers-color-scheme` preference automatically.
The `light-dark()` function accepts two values: the first for light mode, the second for dark mode.
It is baseline as of 2024 and supported in all modern browsers.

All document styles reference the semantic tokens defined in the theme layer rather than raw Open Props color primitives.
This ensures a single point of change when adjusting the color scheme.

## CUBE CSS methodology

CUBE CSS organizes styles into four categories that work with the cascade rather than against it: Composition, Utility, Block, and Exception.

### Composition

Compositions define layout skeletons that control how child elements are arranged in space.
They have no opinions about decoration such as color, font, or border.
The Every Layout primitives form the composition vocabulary:

- **Stack** applies vertical rhythm via lobotomized owl selector
- **Box** provides a padding and border container
- **Center** constrains max-width with intrinsic gutters
- **Cluster** arranges items horizontally with wrapping and gap
- **Sidebar** creates a two-panel layout where one side has a fixed measure
- **Switcher** flips from horizontal to vertical layout at a threshold width
- **Cover** vertically centers a principal element within a minimum height
- **Grid** produces an auto-fit responsive grid

The Stack composition illustrates the pattern:

```css
@layer compositions {
  .stack {
    display: flex;
    flex-direction: column;
  }
  .stack > * + * {
    margin-block-start: var(--stack-space, var(--size-3));
  }
}
```

The `--stack-space` custom property allows per-instance spacing override while defaulting to a sensible token value.

### Utility

Utility classes apply a single CSS property bound to a design token.
They bridge Open Props tokens to HTML attributes:

```css
@layer utilities {
  .text-1 { font-size: var(--size-1); }
  .text-2 { font-size: var(--size-2); }
  .gap-3 { gap: var(--size-3); }
  .color-accent { color: var(--color-accent); }
}
```

Utilities are deliberately narrow in scope.
Each class does exactly one thing, making its effect predictable and composable.

### Block

Block classes style semantic content types, the meaningful "things" in a document.
Each block should remain small, under roughly 80 to 100 lines.
In a document context, blocks include `.slide`, `.code-block`, `.diagram`, `.equation`, and `.callout`:

```css
@layer blocks {
  .slide {
    min-block-size: 100dvh;
    display: grid;
    place-content: center;
    padding: var(--size-5);
  }
}
```

Blocks reference semantic tokens from the theme layer and spatial tokens from Open Props, keeping them decoupled from raw values.

### Exception

Exception classes handle state-specific or variant-specific overrides via `data-*` attributes.
Exceptions are the CUBE equivalent of BEM modifiers but use the data attribute selector for specificity control:

```css
@layer exceptions {
  .slide[data-layout="title"] {
    text-align: center;
    font-size: var(--size-fluid-3);
  }
  .slide[data-layout="two-column"] {
    grid-template-columns: 1fr 1fr;
  }
}
```

Using `data-*` attributes rather than class-based modifiers keeps the exception mechanism syntactically distinct from blocks and utilities.
The `data-*` attribute also provides a natural hook for JavaScript behavior when needed.

## Composition nesting

Compositions are designed to nest.
A Stack can contain a Sidebar, which itself contains Stacks.
The key constraint is that compositions never set decorative properties, so nesting never produces style conflicts.

A typical document layout combines several compositions:

```html
<div class="center stack">
  <header class="cluster">...</header>
  <main class="stack">
    <article class="sidebar">
      <div class="stack">...</div>
      <aside class="stack">...</aside>
    </article>
  </main>
</div>
```

Each composition class contributes only spatial behavior.
Visual styling comes from block and utility classes applied to the same or child elements.

## Light DOM requirement

Web components used within hypermedia documents should use Light DOM, not Shadow DOM.
Light DOM allows CSS custom properties, cascade layers, and CUBE methodology to flow through web component boundaries without obstruction.
Shadow DOM blocks the cascade, requiring duplicated or pierced styles that defeat the purpose of a unified design system.

Lit components can opt into Light DOM via `createRenderRoot() { return this; }`.
This renders the component's template directly into the document's DOM, participating fully in the cascade layer system.

When a web component wraps a composition or block, the component's host element participates in the parent composition's layout algorithm.
For example, a `<slide-deck>` component rendered in Light DOM can be a direct child of a Stack without breaking the `> * + *` selector chain.

This requirement is consistent with the web component patterns described in `preferences-hypermedia-development/05-web-components.md`.
