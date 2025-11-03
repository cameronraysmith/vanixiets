---
title: "ADR-0006: Monorepo tag strategy"
---

## Status

Accepted

## Context

In monorepos with multiple packages, git tags can follow different strategies:
1. Single version for entire monorepo (e.g., `v1.0.0` applies to all packages)
2. Package-specific tags only (e.g., `docs-v1.0.0`, `api-v2.3.1`)
3. Hybrid: both root-level and package-specific tags

The choice affects:
- Release clarity (which package version changed?)
- Deployment workflows (which package to deploy at tag X?)
- Version discovery for package consumers
- Tag namespace collision potential

## Decision

Use hybrid scoped tags with both root-level and package-specific tags.

Following python-nix-template pattern:

**Root-level tags:**
- `v1.0.0`, `v1.0`, `v1` (from semantic-release-major-tag)

**Package-specific tags:**
- `docs-v1.0.0`, `docs-v1.0`, `docs-v1`
- Future packages: `{package-name}-v1.0.0`, etc.

## Rationale

- **Root tags** track overall template versioning
- **Package tags** track individual package versions
- **Clear separation** in multi-package repositories - no ambiguity about which package a version refers to
- **All tags created automatically** by semantic-release (no manual tagging)
- **Consistent with python-nix-template** - reusable pattern across our templates

## Implementation

Uses `semantic-release-major-tag` plugin to create major/minor version tags alongside semantic version tags.

Example after `feat(docs):` commit:
- `v1.2.3` (full version)
- `v1.2` (major.minor)
- `v1` (major only)
- `docs-v1.2.3` (package-scoped full)
- `docs-v1.2` (package-scoped major.minor)
- `docs-v1` (package-scoped major)

## Consequences

**Positive:**
- Clear which package each version refers to
- Root tags provide overall template versioning
- Multiple tag formats support different consumer needs (some want `v1`, others want `v1.2.3`)
- Automatic tag creation prevents manual tagging errors

**Negative:**
- More tags in repository (6 per release per package)
- Tag namespace must avoid collisions (can't have package named `v1`)

**Neutral:**
- Git tag list becomes longer but organized by prefix
