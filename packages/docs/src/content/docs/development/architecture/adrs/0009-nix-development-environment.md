---
title: "ADR-0009: Nix flake-based development environment"
---

## Status

Accepted

## Context

Development environment setup can use various approaches:
1. **Manual installation** - README with tool versions, team installs manually
2. **Docker Dev Containers** - containerized development environment
3. **asdf/mise** - version manager for multiple tools
4. **Nix** - declarative, reproducible environment management
5. **direnv + tool version managers** - automatic environment activation

The choice affects:
- Reproducibility across machines and developers
- Onboarding friction for new contributors
- Tool version consistency
- Cross-platform support

## Decision

Use Nix flakes for reproducible development environments with direnv integration.

## Implementation

**Key components:**
- `flake.nix` - Flake configuration and inputs
- `modules/` - Modular Nix configuration (including `modules/dev-shell.nix`)
- `.envrc` - direnv integration for automatic shell activation

**Provided tools:**
- Bun (package manager and runtime)
- Node.js (for compatibility)
- Playwright browsers (for E2E testing)
- Development tools (just, gh, sops, etc.)

## Rationale

- **Reproducible environments** - exact same tool versions across all machines
- **Declarative dependency management** - tools and versions in version control
- **Automatic environment activation** with direnv - no manual `nix develop`
- **No manual tool installation** - new developers run `nix develop` once
- **Cross-platform support** - works on Linux, macOS (including Apple Silicon), and NixOS
- **Transitive dependency management** - Nix handles system libraries automatically

## Trade-offs

**Positive:**
- Zero-configuration onboarding (after Nix installed)
- Impossible to have wrong tool versions
- No global pollution of developer machine
- Can have different versions per project
- Works with Nix-based CI/CD

**Negative:**
- Requires Nix installation (one-time setup)
- Nix learning curve for contributors unfamiliar with it
- Binary cache rebuilds can be slow without cachix
- Some tools have limited macOS support

**Neutral:**
- Nix flakes are experimental (but stable in practice)
- Need to maintain `flake.lock` for pinned dependencies

## Consequences

**For developers:**
- Must install Nix and direnv (documented in README)
- Automatic environment activation when entering project directory
- Can use `nix develop` for manual activation

**For CI/CD:**
- Can use same flake in GitHub Actions
- Ensures dev/CI parity
- Cachix can speed up builds

**For contributors:**
- Lower barrier if they already use Nix
- Higher barrier if completely new to Nix
- Can still use manual installation if they prefer
