---
title: Contents
description: Technical reference documentation for the infra repository
sidebar:
  order: 1
---

This section provides comprehensive reference documentation for the infra repository's CLI tooling, automation, and structure.

## Repository structure

- [Repository Structure](/reference/repository-structure/) - Directory layout for deferred module composition + clan architecture

## CLI tooling

Reference documentation for command-line tools and automation:

- [Flake Apps](/reference/flake-apps/) - Reference for nix flake apps (`darwin`, `os`, `home`) that wrap configuration activation
- [Justfile Recipes](/reference/justfile-recipes/) - Complete reference for all ~100 justfile recipes organized by functional group, with CI-tested indicators
- [CI Jobs](/reference/ci-jobs/) - GitHub Actions CI job reference with local equivalents and troubleshooting

## Quick start

Common operations using the CLI tooling:

```bash
# Activate current machine (auto-detects platform)
just activate

# Preview changes before applying
just activate --dry

# Run all tests
just check

# Fast checks (skip VM tests)
just check-fast

# Build documentation
just docs-build

# View available recipes
just --list
```

## Related documentation

For conceptual understanding and guides:

- [Getting Started](/guides/getting-started/) - Initial setup and onboarding
- [Architecture overview](/concepts/architecture-overview/) - How the nix configuration is structured
- [Clan Integration](/concepts/clan-integration/) - Understanding clan integration
- [CI Philosophy](/development/traceability/ci-philosophy/) - Design principles behind the CI system
