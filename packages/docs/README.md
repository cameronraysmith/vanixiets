# @typescript-nix-template/docs

[![Built with Starlight](https://astro.badg.es/v2/built-with-starlight/tiny.svg)](https://starlight.astro.build)

Documentation site built with Astro Starlight and deployed to Cloudflare Workers.

## Features

- Built with [Astro](https://astro.build) and [Starlight](https://starlight.astro.build)
- TypeScript support with strict type checking
- Unit testing with [Vitest](https://vitest.dev)
- E2E testing with [Playwright](https://playwright.dev)
- Code quality with [Biome](https://biomejs.dev)
- Deployed to [Cloudflare Workers](https://workers.cloudflare.com)

## Project structure

```
packages/docs/
├── src/
│   ├── assets/              # Images and static assets
│   ├── content/
│   │   └── docs/            # Markdown documentation files
│   ├── components/          # Astro components
│   └── utils/               # Utility functions
├── public/                  # Static assets (favicon, etc.)
├── e2e/                     # End-to-end tests
├── tests/                   # Unit tests and fixtures
├── astro.config.ts          # Astro configuration
├── wrangler.jsonc           # Cloudflare Workers configuration
├── tsconfig.json            # TypeScript configuration
├── vitest.config.ts         # Vitest configuration
├── playwright.config.ts     # Playwright configuration
└── package.json             # Package dependencies and scripts
```

## Development

### From workspace root

```bash
# Start dev server
just dev
# or
bun run --filter '@typescript-nix-template/docs' dev

# Build
just build
# or
bun run --filter '@typescript-nix-template/docs' build
```

### From package directory

```bash
cd packages/docs

# Start dev server
bun run dev

# Build
bun run build

# Preview
bun run preview
```

## Testing

```bash
# Run all tests
bun run test

# Run unit tests
bun run test:unit

# Run E2E tests
bun run test:e2e

# Run in watch mode
bun run test:watch

# Run Playwright UI
bun run test:ui

# Generate coverage
bun run test:coverage
```

## Code quality

```bash
# Format code
bun run format

# Lint code
bun run lint

# Check and fix
bun run check:fix
```

## Deployment

### Cloudflare Workers

```bash
# Preview locally
bun run preview

# Deploy
bun run deploy

# Or use justfile from root
just cf-deploy-production
```

## Adding content

Starlight looks for `.md` or `.mdx` files in the `src/content/docs/` directory.
Each file is exposed as a route based on its file name.

### Example

Create `src/content/docs/guides/my-guide.md`:

```markdown
---
title: My Guide
description: A guide for using this feature
---

# My Guide

Content goes here...
```

This will be available at `/guides/my-guide`.

## Adding components

Create Astro components in `src/components/` and use them in your markdown:

```astro
---
// src/components/MyComponent.astro
const { title } = Astro.props;
---

<div class="my-component">
  <h2>{title}</h2>
  <slot />
</div>
```

Import in markdown:

```mdx
---
title: Page with Component
---

import MyComponent from '../../components/MyComponent.astro';

<MyComponent title="Hello">
  Content here
</MyComponent>
```

## Learn more

- [Starlight documentation](https://starlight.astro.build/)
- [Astro documentation](https://docs.astro.build)
- [Cloudflare Workers docs](https://developers.cloudflare.com/workers/)
