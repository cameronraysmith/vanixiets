---
title: "ADR-0008: TypeScript configuration strategy"
---

## Status

Accepted

## Context

TypeScript configuration in monorepos can be organized in several ways:
1. **Independent configs** - each package has complete tsconfig.json
2. **Shared base** - root tsconfig.json extended by packages
3. **Composite projects** - TypeScript project references with dependencies
4. **Shared config package** - `@company/tsconfig` npm package

The choice affects:
- Configuration maintenance (DRY vs explicit)
- Type checking across package boundaries
- Build performance with project references
- IDE experience

## Decision

Use shared base tsconfig with package-specific extensions.

## Implementation

**Root `tsconfig.json`** provides shared base configuration:

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

**Package-specific configs** extend the base:

```json
{
  "extends": "../../tsconfig.json",
  "include": ["src/**/*", "tests/**/*"]
}
```

## Rationale

- **Consistent TypeScript settings** across all packages
- **Single source of truth** for shared compiler options
- **Package-specific overrides** when needed (e.g., different `include` paths)
- **Simple mental model** - look at root for baseline, package for specifics
- **No additional dependencies** - doesn't require publishing config package

## Trade-offs

**Positive:**
- Easy to update TypeScript settings globally
- Consistent type checking across packages
- Package configs remain minimal and focused
- Clear inheritance hierarchy

**Negative:**
- Not using TypeScript project references (potential performance benefit lost)
- Changes to root config affect all packages (less isolation)
- Can't version different TypeScript compiler options per package

**Neutral:**
- Relative path to extend (`../../tsconfig.json`) - must maintain correct nesting

## Future considerations

If we need cross-package type checking or build performance optimization, consider migrating to TypeScript project references with `composite: true`.
