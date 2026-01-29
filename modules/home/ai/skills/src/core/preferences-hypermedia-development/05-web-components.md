# Web components for hypermedia applications

## Overview

Web components provide encapsulation for third-party libraries that need to own their DOM subtree while remaining compatible with server-driven hypermedia updates.
This document covers patterns for integrating charting libraries, rich text editors, drag-and-drop, maps, and other stateful JavaScript libraries into hypermedia applications.

## The fundamental tension

Hypermedia frameworks use DOM morphing to apply server updates efficiently.
Morphing algorithms compare incoming HTML with current DOM and apply minimal changes to preserve focus, scroll position, and component state.
Third-party libraries modify DOM in ways the server doesn't know about, creating internal structure the morphing algorithm will destroy.

Example tension points:
- Chart library creates SVG elements, canvas contexts, event listeners
- Server sends updated chart configuration
- Morphing replaces entire subtree, destroying library's internal state
- Library leaks memory from orphaned listeners, loses zoom/pan state

Web components solve this by establishing a morphing boundary with attribute-based communication.

## Solution: thin wrapper pattern

The thin wrapper pattern treats web components as morphisms between the hypermedia signal world and imperative library APIs.

Core principles:
1. Exclude component element from morphing (`data-ignore-morph` in Datastar, `hx-preserve` in htmx)
2. Component receives configuration via attributes
3. Component emits events for user interactions
4. Component lifecycle manages library instantiation and cleanup

Algebraic perspective:
```
Signals ──data-attr:*──▶ Web Component ──library API──▶ Library DOM
                              │
                              ◀──custom events──
                              │
Signals ◀──data-on:*─── Event Dispatch ◀──callbacks──
```

The web component is a functor between hypermedia signals and imperative library state.
Pure in the functional sense: same attributes produce same library configuration.
Side effects are isolated in lifecycle methods with explicit cleanup.

**Theoretical foundation**: Web components are coalgebras (specifically Moore machines) where state determines output and input triggers transitions.
This coalgebraic structure explains why morphing boundaries work: bisimilar states produce equivalent DOM output and transition behavior.
See `theoretical-foundations.md` section "Web components as coalgebras" for the formal model and section "Composing reactive systems" for how comonadic signal extraction feeds into coalgebraic observation.

## Vanilla web component pattern

Use vanilla web components (no framework) when the library wrapper is simple and state is owned by the library.

```javascript
class LibraryWrapper extends HTMLElement {
  static observedAttributes = ['config', 'data-url'];

  connectedCallback() {
    // Initialize library with current configuration
    this.instance = Library.create(this, this.getConfig());

    // Forward library events as custom events
    this.instance.on('select', (value) => {
      this.dispatchEvent(new CustomEvent('select', {
        detail: value,
        bubbles: true,
        composed: true
      }));
    });
  }

  disconnectedCallback() {
    // Critical: cleanup to prevent memory leaks
    this.instance?.destroy();
    this.instance = null;
  }

  attributeChangedCallback(name, oldValue, newValue) {
    if (!this.instance || oldValue === newValue) return;

    // Update library configuration
    if (name === 'config') {
      this.instance.setOption(JSON.parse(newValue));
    } else if (name === 'data-url') {
      this.fetchAndUpdate(newValue);
    }
  }

  getConfig() {
    const config = this.getAttribute('config');
    return config ? JSON.parse(config) : {};
  }

  async fetchAndUpdate(url) {
    const response = await fetch(url);
    const data = await response.json();
    this.instance.setData(data);
  }
}

customElements.define('library-wrapper', LibraryWrapper);
```

Key implementation details:
- `observedAttributes` declares which attributes trigger `attributeChangedCallback`
- `connectedCallback` runs when element is added to DOM
- `disconnectedCallback` is critical for cleanup, always implement
- Custom events must set `bubbles: true` to work with hypermedia event delegation
- `composed: true` allows events to cross shadow DOM boundaries (use if shadow DOM present)

## When to use Lit (pattern 1.5)

Lit adds reactive properties and templating but remains lightweight compared to full frameworks.

Use Lit instead of vanilla when ALL apply:
- Complex internal state (animation timers, computed scales, tracked selections)
- Multiple lifecycle observers (ResizeObserver, MediaQueryList, IntersectionObserver)
- Light DOM acceptable (required for CSS token inheritance)
- Lit's reactivity is internal to component, not competing with hypermedia signals

Do NOT use Lit if:
- Shadow DOM is required (blocks CSS custom property inheritance)
- Component is a simple library wrapper with no internal state
- You need SSR (Lit SSR exists but adds complexity)

Lit pattern:
```javascript
import { LitElement, html, css } from 'lit';
import { customElement, property, state, query } from 'lit/decorators.js';

@customElement('chart-wrapper')
export class ChartWrapper extends LitElement {
  @property({ type: String }) option = '{}';
  @property({ type: String, attribute: 'data-url' }) dataUrl = '';

  @state() private loading = false;
  @query('#container') container;

  private chart;
  private resizeObserver;

  // Light DOM: allow CSS tokens to inherit from :root
  protected createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();

    this.resizeObserver = new ResizeObserver(() => {
      this.chart?.resize();
    });
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    this.resizeObserver?.disconnect();
    this.chart?.dispose();
  }

  firstUpdated() {
    this.chart = Library.init(this.container);
    this.updateChart();
  }

  updated(changedProperties) {
    if (changedProperties.has('option') || changedProperties.has('dataUrl')) {
      this.updateChart();
    }
  }

  async updateChart() {
    if (this.dataUrl) {
      this.loading = true;
      const response = await fetch(this.dataUrl);
      const data = await response.json();
      this.chart.setOption({ ...JSON.parse(this.option), data });
      this.loading = false;
    } else {
      this.chart.setOption(JSON.parse(this.option));
    }
  }

  render() {
    return html`
      <div id="container" style="width: 100%; height: 100%;">
        ${this.loading ? html`<div class="loading">Loading...</div>` : ''}
      </div>
    `;
  }
}
```

Lit-specific considerations:
- `createRenderRoot() { return this }` enables light DOM (see CSS architecture section)
- `@property` creates reactive properties from attributes
- `@state` creates internal reactive state
- `updated(changedProperties)` runs after any reactive property changes
- `firstUpdated()` runs once after initial render

## Light DOM requirement

Shadow DOM encapsulation blocks CSS custom property inheritance.
Design token systems like Open Props define tokens in `:root` which cannot reach shadow DOM.

Always use light DOM when:
- Component needs to inherit CSS custom properties from page
- Component uses design tokens for colors, spacing, typography
- Component needs to participate in page layout (flexbox/grid parent)

Enable light DOM:
```javascript
// Vanilla
class MyComponent extends HTMLElement {
  constructor() {
    super();
    // Don't call this.attachShadow()
    // Render directly to this
  }
}

// Lit
class MyComponent extends LitElement {
  protected createRenderRoot() {
    return this;  // Render to light DOM
  }
}
```

Trade-offs:
- Light DOM: CSS tokens work, styles leak in/out
- Shadow DOM: style encapsulation, CSS tokens blocked

For hypermedia applications with design token systems, light DOM is preferred.

## Integration with hypermedia

Datastar integration:
```html
<library-wrapper
  data-ignore-morph
  data-attr:config="JSON.stringify($chartConfig)"
  data-attr:data-url="$dataEndpoint"
  data-on:select="$selection = evt.detail"
></library-wrapper>
```

htmx integration:
```html
<library-wrapper
  hx-preserve
  config='{"type": "bar", "data": [1, 2, 3]}'
  hx-get="/api/data"
  hx-trigger="load"
  hx-on:select="htmx.trigger('#results', 'refresh')"
></library-wrapper>
```

Key attributes:
- `data-ignore-morph` (Datastar) or `hx-preserve` (htmx): exclude from morphing
- `data-attr:*` (Datastar): bind signal to attribute
- `data-on:*` (Datastar) or `hx-on:*` (htmx): handle custom events

## Memory management and cleanup

Libraries that render to canvas, create event listeners, or spawn workers require explicit cleanup.

Critical cleanup checklist:
- Library instance: call `.destroy()`, `.dispose()`, or equivalent
- Event listeners: call `.off()`, `.removeEventListener()`
- Observers: call `.disconnect()` on ResizeObserver, IntersectionObserver, MutationObserver
- Timers: call `clearInterval()`, `clearTimeout()`
- Workers: call `worker.terminate()`
- Animations: call `cancelAnimationFrame()`

Vanilla pattern:
```javascript
disconnectedCallback() {
  this.chart?.dispose();
  this.resizeObserver?.disconnect();
  this.mediaQuery?.removeEventListener('change', this.handleMediaChange);
  clearInterval(this.pollInterval);
  this.worker?.terminate();
  cancelAnimationFrame(this.animationFrame);
}
```

Lit pattern:
```javascript
disconnectedCallback() {
  super.disconnectedCallback();  // Call super first
  this.chart?.dispose();
  this.resizeObserver?.disconnect();
  // ... other cleanup
}
```

Testing cleanup:
- Manually call `element.remove()` and check browser DevTools memory profiler
- Verify detached DOM nodes count doesn't grow
- Use weak references where possible to avoid forcing retention

## Common use cases

Charts and visualization:
- ECharts, Apache ECharts
- Vega, Vega-Lite
- D3.js (for complex custom visualizations)
- Plotly.js
- Chart.js

Rich text editors:
- ProseMirror
- TipTap (ProseMirror wrapper)
- Quill
- CodeMirror (code editor)

Drag and drop:
- SortableJS
- Pragmatic drag and drop (Atlassian)

Maps:
- Mapbox GL JS
- Leaflet
- OpenLayers

3D graphics:
- Three.js
- Babylon.js

Media:
- Video.js
- Plyr

Each library needs:
- Attribute for configuration object
- Attribute for data source (URL or inline)
- Event emission for user interactions
- Proper cleanup in `disconnectedCallback`

## Attribute design patterns

Attributes are strings, so complex data must be serialized.

JSON for complex configuration:
```html
<chart-wrapper
  config='{"type": "line", "smooth": true, "animation": {"duration": 300}}'
></chart-wrapper>
```

Signal binding in Datastar:
```html
<chart-wrapper
  data-attr:config="JSON.stringify($chartOptions)"
></chart-wrapper>
```

Multiple simple attributes:
```html
<chart-wrapper
  type="line"
  smooth="true"
  duration="300"
></chart-wrapper>
```

Prefer single JSON config attribute when:
- Configuration has nested structure
- Configuration is computed from signals
- Library has existing JSON-based API

Prefer multiple simple attributes when:
- Each attribute is independent
- Attributes are mostly static
- SSR templates benefit from separate attributes

## Event design patterns

Custom events carry data from component to hypermedia signals.

Basic event:
```javascript
this.dispatchEvent(new CustomEvent('select', {
  detail: selectedValue,
  bubbles: true
}));
```

Event with multiple values:
```javascript
this.dispatchEvent(new CustomEvent('zoom', {
  detail: { start: startDate, end: endDate, scale: zoomLevel },
  bubbles: true
}));
```

Datastar handler:
```html
<chart-wrapper
  data-on:select="$selection = evt.detail"
  data-on:zoom="$dateRange = evt.detail; $renderChart()"
></chart-wrapper>
```

Event naming:
- Use present tense verbs: `select`, `change`, `zoom`, `drop`
- Match library event names when possible
- Prefix with component name if generic: `chart-select`, `editor-change`

## SSR considerations

Web components with light DOM work with SSR but require hydration strategy.

Declarative shadow DOM (DSD) is not recommended for hypermedia applications:
- Requires shadow DOM (blocks CSS tokens)
- Adds complexity for minimal benefit
- Hypermedia already handles HTML updates

SSR pattern for hypermedia:
1. Server renders initial HTML inside component tags
2. Component uses existing content in `connectedCallback`
3. Library hydrates existing DOM or replaces it

```javascript
connectedCallback() {
  const existingContent = this.querySelector('.chart-container');

  if (existingContent) {
    // Hydrate existing server-rendered content
    this.chart = Library.init(existingContent, this.getConfig());
  } else {
    // Client-only render
    const container = document.createElement('div');
    container.className = 'chart-container';
    this.appendChild(container);
    this.chart = Library.init(container, this.getConfig());
  }
}
```

Most charting and editor libraries don't support SSR, so progressive enhancement means:
- Server renders loading state or static fallback
- Component replaces with interactive version on client

## Testing web components

Unit testing vanilla components:
```javascript
import { test } from 'vitest';

test('library wrapper emits select event', async () => {
  const wrapper = document.createElement('library-wrapper');
  wrapper.setAttribute('config', '{"data": [1, 2, 3]}');

  const selectPromise = new Promise(resolve => {
    wrapper.addEventListener('select', (e) => resolve(e.detail));
  });

  document.body.appendChild(wrapper);

  // Simulate library interaction
  wrapper.instance.simulateClick(1);

  const selected = await selectPromise;
  expect(selected).toBe(1);

  wrapper.remove();  // Cleanup
});
```

Testing Lit components:
```javascript
import { fixture, html } from '@open-wc/testing';

test('chart wrapper updates on config change', async () => {
  const el = await fixture(html`
    <chart-wrapper config='{"type": "bar"}'></chart-wrapper>
  `);

  expect(el.chart.getOption().type).toBe('bar');

  el.setAttribute('config', '{"type": "line"}');
  await el.updateComplete;  // Wait for Lit to update

  expect(el.chart.getOption().type).toBe('line');
});
```

Integration testing with hypermedia:
- Use Playwright or Cypress for full browser environment
- Test morphing exclusion: update surrounding HTML, verify component state preserved
- Test signal binding: update signal, verify attribute changes
- Test event flow: trigger library interaction, verify signal updates

## Framework-specific notes

Datastar:
- Use `data-ignore-morph` to exclude from morphing
- Use `data-attr:*` for reactive attribute binding
- Use `data-on:*` for event handling
- Access event data via `evt.detail`

htmx:
- Use `hx-preserve` to exclude from swapping (htmx 2.x) or `hx-preserve="true"` (htmx 1.x)
- Use `hx-vals` to include component state in requests
- Use `hx-on:*` for event handling
- Trigger htmx requests from custom events: `htmx.trigger(selector, event)`

Turbo (Hotwire):
- Use `data-turbo-permanent` with matching `id` to preserve across visits
- Component persists across page navigations if `id` matches
- Use `turbo:before-render` event to save component state before navigation

## When NOT to use web components

Avoid web components when:
- Server can fully render the component (use hypermedia fragments instead)
- No third-party library involved (use plain HTML + CSS)
- State is simple enough for URL or hidden inputs (use hypermedia state management)
- Library provides native HTML API (use it directly)

Example of over-engineering:
```html
<!-- Bad: wrapping simple select in web component -->
<select-wrapper options='["a", "b", "c"]'></select-wrapper>

<!-- Good: use native element -->
<select data-model="$selection">
  <option>a</option>
  <option>b</option>
  <option>c</option>
</select>
```

Web components are boundary objects for imperative libraries, not replacements for hypermedia patterns.
