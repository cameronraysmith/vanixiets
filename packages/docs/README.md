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
│   │       │   └── workflows/      # Development workflows
│   │       └── notes/       # Working notes (excluded from sidebar)
│   │           ├── clan/           # Clan integration planning
│   │           ├── mcp/            # MCP integration notes
│   │           ├── nix-rosetta/    # Cross-arch build planning
│   │           ├── nixpkgs/        # Nixpkgs troubleshooting
│   │           └── prompts/        # LLM session templates
│   ├── components/          # Astro components
│   ├── grammars/            # Syntax highlighting (Justfile)
│   ├── pages/               # Endpoints outside the docs collection (robots.txt)
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
bun run --filter '@vanixiets/docs' dev

# Build
just build
# or
bun run --filter '@vanixiets/docs' build
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

When an AI coding agent runs these, Astro 7 detects it and starts `astro preview` in the background, so Playwright's `webServer` (under `CI`) reports that the process exited early.
Unset the detection variables for the run, for example `env -u AGENT -u CLAUDECODE bun run test:e2e`.

## Agent-facing outputs

The build emits three things for crawlers and LLM agents besides the HTML pages.
`src/pages/robots.txt.ts` serves `/robots.txt`: it allows every crawler, names the sitemap and points at `/llms.txt` and the Agent Skills discovery index.
[starlight-llms-txt](https://github.com/delucis/starlight-llms-txt) serves `/llms.txt` with the entry points configured in `astro.config.ts`, plus `/llms-full.txt` (every page) and `/llms-small.txt` (every page outside `development/`).
It runs with `rawContent: true`, so both bundles carry each page's Markdown source: its HTML-to-Markdown round trip flattens KaTeX formulas and drops their TeX, and the source keeps them.
[starlight-md-txt](https://github.com/max-ostapenko/starlight-md-txt) serves each page's source at its path with `.md` in place of the trailing slash (`/index.md` for the home page), with absolute links, and adds `<link rel="alternate" type="text/markdown">` to every page's head.
Being source, neither output renders MDX components, so the fleet table that `concepts/fleet-topology.mdx` imports is absent from both.
None of these appears in the sitemap, which lists HTML pages only.
`e2e/agent-affordances.spec.ts` checks all three against the built site.

The Agent Skills discovery index at `/.well-known/agent-skills/` (`index.json`, one `SKILL.md` or zip per first-party skill, each with its sha256 digest) is not part of this build.
`pkgs/by-name/vanixiets-docs-payload` generates it from `modules/home/ai/plugins/*/.apm/skills/` and adds it to the nix-built site that `deploy-docs` deploys, so a skill edit rebuilds the index and that copy but neither `astro build` nor the e2e suite.
`bun run build` and `bun run preview` therefore serve no index; `checks.x86_64-linux.agent-skills-index` checks it, and the skills CLI installing from it, against the deploy payload.

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

# From the repository root: deploy HEAD as the Cloudflare Preview named after the current branch
# (runs `deploy-docs preview --rev <HEAD> --name <branch>`)
just docs-deploy-preview

# From the repository root: deploy the nix-built site to production
# (runs `deploy-docs production --rev <HEAD>`; exits 0 without deploying unless HEAD is main's head on GitHub)
just docs-deploy-production
```

Deploys normally run in CI through the `docs` effect, whose three triggers all run `deploy-docs`.
Each push to `main` runs `deploy-docs production --rev <commit>`.
Each pull request gets the Cloudflare Preview `pr-<number>`, reported as a `docs-preview` GitHub check run whose details link is the Preview URL, and the Preview is deleted when the pull request closes or merges.
See `src/content/docs/about/contributing/ci-cd-setup.md`.

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
