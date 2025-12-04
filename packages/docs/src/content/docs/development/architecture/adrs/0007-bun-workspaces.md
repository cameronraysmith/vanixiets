---
title: "ADR-0007: Bun workspaces configuration"
---

## Status

Accepted

## Context

Monorepo package management requires choosing a workspace tool:
- **npm workspaces** - native to npm, widely compatible
- **yarn workspaces** - fast, good tooling, requires yarn
- **pnpm workspaces** - efficient disk usage, strict dependency resolution
- **bun workspaces** - fastest, native TypeScript support, newer ecosystem
- **turborepo** - orchestration layer on top of workspaces
- **nx** - full monorepo tooling with caching and graph analysis

The choice affects:
- Installation speed
- Build performance
- TypeScript support
- Ecosystem compatibility
- Developer experience

## Decision

Use Bun workspaces for monorepo package management.

## Configuration

```json
{
  "workspaces": ["packages/*"]
}
```

## Usage patterns

```bash
# Run command in specific package
bun run --filter '@vanixiets/docs' dev

# Run command in all packages
bun run --filter '@vanixiets/*' test
```

## Rationale

- **Fast package installation** - significantly faster than npm/yarn/pnpm
- **Shared dependencies hoisted** to root automatically
- **Simple workspace filtering** with `--filter` flag
- **Native TypeScript support** - no transpilation needed for scripts
- **Compatible with existing npm ecosystem** - can use any npm package
- **Good developer experience** - fast feedback loops

## Trade-offs

**Positive:**
- Fastest package manager in benchmarks
- Built-in TypeScript execution
- Simple, intuitive CLI
- Active development and improvement

**Negative:**
- Newer ecosystem (less mature than npm/yarn/pnpm)
- Some edge case bugs still being discovered
- Not all npm features supported yet
- May have compatibility issues with some native modules

**Neutral:**
- Requires Bun installation (handled by Nix in this template)
- Different lockfile format (`bun.lockb` binary format)

## Consequences

Team members need Bun installed (handled automatically via `nix develop`).
Lock file format is binary - can't easily review changes to `bun.lockb` in PRs.
Build and test cycles are faster due to Bun's performance.
