---
title: "ADR-0004: Monorepo structure"
---

## Status

Accepted

## Context

When setting up a monorepo, there are two common organizational patterns:
1. Separate `apps/` and `packages/` directories
2. Single `packages/` directory for all code

The choice affects:
- Developer navigation and mental model
- Build tool configuration
- Dependency relationships between packages
- Scalability as the monorepo grows

## Decision

Use a single `packages/` directory rather than separating `apps/` and `packages/`.

## Rationale

- **Simpler structure** appropriate for current scope (2 packages)
- **Follows python-nix-template pattern** for consistency across our templates
- **Equal importance** - both packages are relatively equal in importance
- **Clear package naming** indicates purpose without directory-level categorization (`@vanixiets/docs` is self-explanatory)
- **Refactor-friendly** - can split later if needed without breaking the pattern

## When to use apps/ + packages/

The alternative pattern becomes valuable when:
- Large monorepos with **clear app vs library distinction**
- When you have **5+ packages** needing organizational hierarchy
- When **apps consume packages as dependencies** in a clear consumer/provider relationship

## Consequences

**Positive:**
- Simpler directory structure
- Easier navigation with fewer top-level directories
- Consistent with our other template projects

**Negative:**
- May need refactoring if we grow to 5+ packages with clear app/library split
- Less explicit about which packages are deployable vs reusable libraries

**Neutral:**
- Package names must clearly indicate purpose since directory structure doesn't
