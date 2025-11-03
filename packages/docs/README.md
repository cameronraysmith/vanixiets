# infra/docs

[![Built with Starlight](https://astro.badg.es/v2/built-with-starlight/tiny.svg)](https://starlight.astro.build)

Documentation site built with Astro Starlight and deployed to Cloudflare Workers.

## Features

- Built with [Astro](https://astro.build) and [Starlight](https://starlight.astro.build)
- TypeScript support with strict type checking
- Unit testing with [Vitest](https://vitest.dev)
- E2E testing with [Playwright](https://playwright.dev)
- Code quality with [Biome](https://biomejs.dev)
- Deployed to [Cloudflare Workers](https://workers.cloudflare.com)
- Documentation structure following [Diataxis](https://diataxis.fr/) framework

## Project structure

```
packages/docs/
├── src/
│   ├── assets/              # Images and static assets
│   ├── content/
│   │   └── docs/            # Markdown documentation files
│   │       ├── guides/      # Task-oriented how-tos (12 files, ordered)
│   │       ├── reference/   # Information-oriented docs
│   │       ├── development/ # Development documentation (AMDiRE)
│   │       │   ├── decisions/      # Architecture Decision Records
│   │       │   ├── operations/     # Operational procedures
│   │       │   ├── traceability/   # CI philosophy and testing
│   │       │   ├── work-items/     # Implementation tracking
│   │       │   └── workflows/      # Development workflows
│   │       └── notes/       # Working notes (excluded from sidebar)
│   │           ├── clan/           # Clan integration planning
│   │           ├── mcp/            # MCP integration notes
│   │           ├── nix-rosetta/    # Cross-arch build planning
│   │           ├── nixpkgs/        # Nixpkgs troubleshooting
│   │           ├── prompts/        # LLM session templates
│   │           └── work-items/     # Meta-documentation
│   ├── components/          # Astro components
│   ├── grammars/            # Syntax highlighting (Justfile)
│   └── utils/               # Utility functions
├── public/                  # Static assets (favicon, etc.)
├── e2e/                     # End-to-end tests
├── tests/                   # Unit tests and fixtures
├── astro.config.ts          # Astro configuration with sidebar config
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

## Documentation structure

This site follows the [Diataxis](https://diataxis.fr/) framework for user-facing documentation and AMDiRE methodology for development documentation.

### User-facing documentation

- **guides/** - Task-oriented how-tos for accomplishing specific goals
  - Files use `sidebar.order` frontmatter for explicit ordering (1-12)
  - Each guide should be action-oriented and practical

- **reference/** - Information-oriented API docs and reference material

### Development documentation

Located in `development/` with capitalized subsections via hybrid sidebar config:

- **Decisions** - Architecture Decision Records (ADRs)
- **Operations** - Operational procedures and incident response
- **Traceability** - Requirements traceability and testing philosophy
- **Work Items** - Implementation tracking (active/completed/backlog)
- **Workflows** - Development workflows and processes

### Working notes (excluded from main site)

The `notes/` directory contains LLM-centric planning documents and working notes, organized by topic:
- **clan/** - Clan integration migration planning
- **mcp/** - Model Context Protocol integration
- **nix-rosetta/** - Cross-architecture build infrastructure
- **nixpkgs/** - Nixpkgs troubleshooting procedures
- **prompts/** - LLM session templates

These are intentionally excluded from the sidebar but remain in the repository for context.

## Adding content

### Adding a guide

Create `src/content/docs/guides/my-guide.md`:

```markdown
---
title: My Guide
description: A guide for using this feature
sidebar:
  order: 13  # Explicit ordering
---

Content goes here (no duplicate H1 needed, title becomes H1)...
```

### Adding a development document

Create `src/content/docs/development/operations/my-procedure.md`:

```markdown
---
title: My Procedure
---

Operational procedure content...
```

The file will be auto-discovered and added to the Operations section.

### Adding to notes (working documents)

Create `src/content/docs/notes/topic/my-note.md`:

```markdown
---
title: My Planning Document
---

LLM-centric planning content...
```

Update the relevant `notes/topic/index.md` to link to your new document.

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

## Sidebar configuration

The sidebar uses a hybrid manual/autogenerate approach in `astro.config.ts`:

- **Guides** - Fully autogenerated from `guides/` directory, ordered by `sidebar.order` frontmatter
- **Development** - Manual structure with capitalized labels, autogenerate within each subdirectory
- **Reference** - Fully autogenerated from `reference/` directory

This approach provides:
- Capitalized section labels (Decisions, Operations, etc.) without renaming directories
- Autogenerate benefits within each section (automatic file discovery)
- Fine-grained control over section ordering and structure

### Index files

Each directory with an `index.md` uses `title: Contents` since Starlight automatically uses the directory name for the sidebar label.

## Frontmatter conventions

### Required fields
```yaml
---
title: Page Title  # Always required
---
```

### Optional fields
```yaml
---
title: Page Title
description: SEO description  # Recommended for guides
sidebar:
  order: 1         # Explicit ordering (guides only)
  label: Custom    # Override sidebar display (rarely needed)
---
```

### Markdown conventions

- One sentence per line in markdown files
- Use `title` frontmatter; Starlight renders it as H1
- No duplicate `# H1` headings in content
- Start content with prose or `## H2` headings
- Avoid emojis in documentation

## Learn more

- [Starlight documentation](https://starlight.astro.build/)
- [Astro documentation](https://docs.astro.build)
- [Cloudflare Workers docs](https://developers.cloudflare.com/workers/)
- [Diataxis framework](https://diataxis.fr/)
