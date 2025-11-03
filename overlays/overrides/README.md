# Package overrides

This directory contains per-package build modifications for packages that need adjustments but are still usable from the unstable channel.

## When to use overrides vs hotfixes vs patches

### Use `overrides/*` when:
- Package builds but needs modification (disable tests, change flags, apply patches)
- Issue is build-time or runtime behavior, not package version
- You're enhancing or fixing the nixpkgs package definition
- Example: Disable tests that fail with specific compiler version

### Use `infra/hotfixes.nix` when:
- Package is completely broken in unstable
- Need to use stable channel version temporarily
- Package should be disabled entirely on certain platforms
- Example: Package fails to compile in unstable, use stable version

### Use `infra/patches.nix` when:
- Upstream nixpkgs fix exists but hasn't made it to your channel yet
- You have a patch that applies to the entire nixpkgs tree
- Fixing issues in nixpkgs infrastructure (not individual packages)
- Example: Apply PR patch before it merges

## Current overrides

### ghc_filesystem.nix
- **Issue**: Test failures with clang 21.x on darwin
- **Solution**: Disable test suite via `doCheck = false`
- **Tracking**: https://github.com/gulrak/filesystem/issues
- **Date added**: 2025-10-13
- **Affects**: aarch64-darwin, x86_64-darwin
- **Remove when**: Upstream fixes test suite or clang version changes

## Adding new overrides

Create a file `packageName.nix` with this structure:

```nix
# packageName: brief description of issue
#
# Issue: Detailed description
# Reference: Links to upstream issues/PRs
# TODO: Removal criteria
# Date added: YYYY-MM-DD
#
{ ... }:
final: prev: {
  packageName = prev.packageName.overrideAttrs (oldAttrs: {
    # modifications here
  });
}
```

The override will be automatically imported by default.nix.

## Removing overrides

When upstream fixes land:

1. Delete the override file
2. Test build: `nix build .#legacyPackages.SYSTEM.packageName`
3. Commit: `fix(overlays): remove packageName override after upstream fix`
