---
title: Architecture decisions
description: Key architectural decisions and rationale for typescript-nix-template
---

This document explains the key architectural decisions made in this template and the rationale behind them.

## Monorepo structure

### Why packages/ not apps/ + packages/

This template uses a single `packages/` directory rather than separating `apps/` and `packages/`.

**Rationale:**
- Simpler structure appropriate for current scope
- Follows python-nix-template pattern for consistency
- Both packages are relatively equal in importance
- Clear package naming indicates purpose without directory-level categorization
- Can refactor later if needed without breaking the pattern

**When to use apps/ + packages/:**
- Large monorepos with clear app vs library distinction
- When you have 5+ packages needing organizational hierarchy
- When apps consume packages as dependencies

## Release configuration

### Semantic versioning with semantic-release

This template uses [semantic-release](https://semantic-release.gitbook.io/) for automated versioning based on conventional commits.

**Key decisions:**

#### Disabled by default
- All semantic-release configuration is in place
- GitHub Actions workflow exists but triggers are commented out
- Releases are disabled initially to allow template customization
- Enable later by uncommenting workflow triggers

**Rationale:** Template users need time to customize before public releases.

#### Changelog and git plugins
- Includes `@semantic-release/changelog` plugin - generates CHANGELOG.md
- Includes `@semantic-release/git` plugin - commits CHANGELOG.md back with `[skip ci]`
- Package.json version remains `"0.0.0-development"`
- Semantic-release determines actual version from commits
- No npm publishing (`npmPublish: false`)
- Git plugin commits only CHANGELOG.md (no package.json version updates)

**Rationale:**
- Provides complete audit trail in repository
- Automated commits are minimal and skip CI to prevent loops
- Version in package.json stays as development placeholder
- Actual version comes from git tags

#### Monorepo scoping
- Uses `semantic-release-monorepo` plugin
- Automatically scopes analysis to commits affecting each package
- No manual path filtering needed in CI

**Rationale:**
- Plugin handles per-package change detection automatically
- Scales to multiple packages without workflow complexity

#### Main branch only
- Single `main` branch (no beta branch initially)
- Initial version: `0.1.0` (when releases enabled)

**Rationale:**
- Simpler for template users starting out
- Can add beta/next branches later if needed

## Tag strategy

### Scoped tags for monorepo packages

Following python-nix-template pattern with scoped tags:

**Root-level tags:**
- `v1.0.0`, `v1.0`, `v1` (from semantic-release-major-tag)

**Package-specific tags:**
- `docs-v1.0.0`, `docs-v1.0`, `docs-v1`
- Future packages: `{package-name}-v1.0.0`, etc.

**Rationale:**
- Root tags track overall template versioning
- Package tags track individual package versions
- Clear separation in multi-package repositories
- All tags created automatically by semantic-release

## Commit message conventions

### Conventional commits enforced via PR review

This template relies on PR review process rather than pre-commit hooks for commit message validation.

**Required format:**
```
<type>(<scope>): <subject>
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `build`

**Scopes:** Package names (e.g., `docs`, `sqlrooms-hf-ducklake`)

**Breaking changes:**
- Include `BREAKING CHANGE:` in footer, or
- Use `!` after type: `feat(api)!: remove deprecated endpoint`

**Examples:**
```bash
feat(docs): add dark mode toggle
fix(docs): handle null values in query results
docs: update installation guide
```

**Rationale:**
- PR review catches malformed commits before merge
- No pre-commit friction during local development
- Clear documentation in CONTRIBUTING.md
- Semantic-release requires proper format for version bumps

See [CONTRIBUTING.md](/CONTRIBUTING.md) for detailed conventional commit guidelines.

## Workspace configuration

### Bun workspaces

This template uses Bun workspaces for monorepo package management.

**Configuration:**
```json
{
  "workspaces": ["packages/*"]
}
```

**Benefits:**
- Fast package installation and linking
- Shared dependencies hoisted to root
- Simple workspace filtering with `--filter`
- Native TypeScript support

**Usage:**
```bash
# Run command in specific package
bun run --filter '@typescript-nix-template/docs' dev

# Run command in all packages
bun run --filter '@typescript-nix-template/*' test
```

## TypeScript configuration

### Shared base tsconfig

Root `tsconfig.json` provides shared base configuration:

```json
{
  "compilerOptions": {
    "strict": true,
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler"
  }
}
```

Package-specific configs extend the base:

```json
{
  "extends": "../../tsconfig.json",
  "include": ["src/**/*", "tests/**/*"]
}
```

**Rationale:**
- Consistent TypeScript settings across packages
- Package-specific overrides when needed
- Single source of truth for shared compiler options

## Nix development environment

### Flake-based development shell

This template uses Nix flakes for reproducible development environments.

**Key components:**
- `flake.nix` - Flake configuration and inputs
- `nix/modules/` - Modular Nix configuration
- `.envrc` - direnv integration for automatic shell activation

**Provided tools:**
- Bun (package manager and runtime)
- Node.js (for compatibility)
- Playwright browsers (for E2E testing)
- Development tools (just, gh, sops, etc.)

**Rationale:**
- Reproducible environments across machines
- Declarative dependency management
- Automatic environment activation with direnv
- No manual tool installation needed

## Testing architecture

### Comprehensive testing stack

**Unit and component testing:** Vitest
- Fast test execution
- Astro Container API for component testing
- Built-in coverage reporting

**E2E testing:** Playwright
- Multi-browser testing (Chromium, Firefox, WebKit)
- Type-safe APIs
- Managed by Nix for reproducibility

**Test co-location:**
- Unit tests next to source files: `foo.test.ts` next to `foo.ts`
- Component tests next to components: `Card.test.ts` next to `Card.astro`
- E2E tests in separate `e2e/` directory

**Rationale:**
- Co-location makes tests easy to find and maintain
- Vitest is fast and has excellent TypeScript support
- Playwright provides reliable cross-browser testing
- Nix ensures consistent Playwright browser versions

See [Testing guide](/guides/testing) for comprehensive documentation.

## Secrets management

### SOPS with age encryption

This template uses SOPS (Secrets OPerationS) with age encryption for managing secrets.

**Key architecture:**
- Developer keys for local decryption
- CI key stored in GitHub Secrets
- Encrypted `vars/shared.yaml` committed to repository
- `.sops.yaml` contains public keys only

**Design decisions:**

#### Why store CI_AGE_KEY in vars/shared.yaml?
- Allows rotating SOPS_AGE_KEY GitHub secret from dev workstation
- Still requires dev key to decrypt
- Bitwarden serves as offline backup

#### Why separate sops-upload-github-key from ghsecrets?
- Avoids chicken-and-egg: can't use SOPS to get key needed to use SOPS
- During rotation, new key may not be in vars/shared.yaml yet
- Supports pasting from Bitwarden during initial bootstrap

See [Secrets management guide](/guides/secrets-management) for workflows and setup.

## CI/CD pipeline

### GitHub Actions workflows

This template includes three main workflows:

**ci.yaml:**
- Runs on PRs and pushes to main
- GitGuardian secret scanning
- Nix flake checks
- Unit and E2E tests across packages
- Build artifacts uploaded for deployment

**release.yaml:**
- Disabled by default (triggers commented out)
- Runs semantic-release for each package
- Creates GitHub releases and tags
- Commits CHANGELOG.md back to repository

**deploy-docs.yaml:**
- Deploys docs package to Cloudflare Workers
- Manual trigger or on successful CI completion

**Design decisions:**

#### Test job uses matrix for packages
- Each package tested independently
- Parallel execution when possible
- Artifacts uploaded per package

#### Build job reuses test artifacts
- Avoids redundant builds
- Faster CI execution
- Build happens during test job

**Rationale:**
- Modular workflows are easier to understand and modify
- Matrix strategy scales to multiple packages
- Reusing artifacts reduces CI time and cost

See [CI/CD setup guide](/guides/ci-cd-setup) for detailed configuration.

## Deployment architecture

### Cloudflare Workers

The docs package deploys as a Cloudflare Worker using the Astro Cloudflare adapter.

**Build process:**
1. Astro builds static site and SSR components
2. Cloudflare adapter creates Worker bundle
3. Wrangler deploys to Cloudflare Workers

**Configuration:**
- `wrangler.jsonc` - Worker name, routes, and settings
- `astro.config.ts` - Cloudflare adapter configuration
- Environment variables from SOPS

**Rationale:**
- Cloudflare Workers provide global edge deployment
- SSR capabilities for dynamic content
- Cost-effective for documentation sites
- Wrangler provides excellent deployment experience

## Design principles

### Framework independence

The template avoids framework-specific naming:
- Package name is `@typescript-nix-template/docs` not `@typescript-nix-template/starlight`
- Rationale: Astro/Starlight are implementation details that may change

### Template duality

This repository serves two purposes:
1. Working deployment for sciexp demonstrating semantic-release
2. Forkable template for TypeScript monorepo projects

**Design approach:**
- Use generic, purpose-based naming
- Package structure works for both uses
- Documentation explains both template usage and customization

### Type safety and functional patterns

Following user preferences from global CLAUDE.md:
- Type-safe patterns throughout
- Functional programming where feasible
- No `any` types
- Explicit side effects in type signatures

### Bias toward removal

Documentation and code should:
- Serve current needs, not future maybes
- Be removed when no longer valuable
- Preserve historical content in git history only

**Rationale:**
- Reduces maintenance burden
- Keeps codebase focused
- Git history preserves complete audit trail

## References

- [python-nix-template](https://github.com/scientistexperience/python-nix-template) - Inspiration for patterns
- [semantic-release](https://semantic-release.gitbook.io/) - Automated versioning
- [Conventional Commits](https://www.conventionalcommits.org/) - Commit message format
- [Bun workspaces](https://bun.sh/docs/install/workspaces) - Monorepo package management
