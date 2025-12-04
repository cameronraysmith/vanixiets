# Justfile Refactoring Plan

## Overview

This plan refactors 8 verbose justfile recipes (totaling ~470 lines) into modular scripts, reducing justfile complexity while maintaining functionality.
The refactoring targets release-critical developer orientation by eliminating redundancy and improving maintainability.

The recipes to refactor and their current line counts are:
- `cache-linux-package`: 192 lines
- `cache-ci-outputs`: 100 lines
- `cache-overlay-packages`: 65 lines
- `docs-deploy-production`: 87 lines
- `ratchet-pin`, `ratchet-unpin`, `ratchet-update`, `ratchet-upgrade`: 26 lines combined

## Prerequisites

Before implementation, the developer should understand:

1. The existing `scripts/ci/ci-cache-category.sh` (418 lines) which handles category-based caching with cachix push for categories: packages, checks-devshells, home, nixos, darwin
2. The existing `scripts/ci/ci-build-local.sh` (364 lines) which discovers and builds all flake outputs
3. The justfile variable definitions at lines 877-881 for `ratchet_base` and `gha_workflows`

## Phase 1: Extend Existing Scripts

### 1.1 Extend ci-cache-category.sh with single-package mode

The current `ci-cache-category.sh` handles category-based caching but lacks:
- Single package mode (for `cache-linux-package` use case)
- Redundant overlay detection (checking if package matches nixpkgs)
- Cross-architecture building (aarch64-linux + x86_64-linux simultaneously)
- Cachix pinning for permanent storage

New flags to add:
- `--package <name>`: Enable single-package mode
- `--check-redundant`: Check if package is identical to nixpkgs
- `--pin`: Pin cached paths to prevent GC
- `--cross-linux`: Build for both Linux architectures

Implementation details:
- Add new `cache_single_package()` function after line 348
- Reuse existing `push_to_cachix()` helper (lines 111-125)
- Add redundancy check logic from justfile lines 1013-1064
- Add pinning logic from justfile lines 1126-1134, 1169-1177

Testing approach:
```bash
# Test single package mode
./scripts/ci/ci-cache-category.sh aarch64-linux packages --package hello
# Test redundant detection
./scripts/ci/ci-cache-category.sh aarch64-linux packages --package <overlay-pkg> --check-redundant
```

## Phase 2: Create New Scripts

### 2.1 scripts/ci/cache-all-outputs.sh

Purpose: Orchestrate bulk caching of all CI outputs for a system, replacing the 100-line `cache-ci-outputs` recipe.

Interface:
```bash
./scripts/ci/cache-all-outputs.sh [system]
# system: x86_64-linux, aarch64-linux, aarch64-darwin (defaults to current)
```

Implementation outline:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Source: justfile lines 1218-1317

# Phase 1: Build all outputs using ci-build-local.sh
./scripts/ci/ci-build-local.sh "" "$TARGET_SYSTEM"

# Phase 2: Collect store paths and push
# - Iterate packages, devShells, checks
# - For darwin: darwinConfigurations
# - For linux: nixosConfigurations
# - Push all paths to cachix
```

Dependencies:
- `scripts/ci/ci-build-local.sh` for building
- `sops exec-env` for cachix authentication
- `jq` for JSON parsing

### 2.2 scripts/docs/deploy-production.sh

Purpose: Handle Cloudflare Workers production deployment with version promotion.

Interface:
```bash
./scripts/docs/deploy-production.sh
```

Implementation outline (extracted from justfile lines 464-549):
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../packages/docs"

# Get commit metadata
CURRENT_TAG=$(git rev-parse --short=12 HEAD)

# Build deployment message (CI vs local)
# Query existing version with matching tag
# If found: promote to 100% production
# If not: fallback to direct build and deploy
```

Key features to preserve:
- Git metadata capture (SHA, tag, branch)
- CI vs local detection
- Version query and promotion workflow
- Fallback direct deploy path

### 2.3 scripts/ci/ratchet-workflow.sh

Purpose: Consolidate 4 ratchet recipes into a single parameterized script.

Interface:
```bash
./scripts/ci/ratchet-workflow.sh <action> [workflow...]
# action: pin, unpin, update, upgrade
# workflow: defaults to gha_workflows variable content
```

Implementation outline:
```bash
#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
shift
WORKFLOWS="${@:-./.github/workflows/flake.yaml}"

RATCHET_BASE="${RATCHET_BASE:-ratchet}"

case "$ACTION" in
  pin|unpin|update|upgrade)
    for workflow in $WORKFLOWS; do
      eval "$RATCHET_BASE $ACTION $workflow"
    done
    ;;
  *)
    echo "Usage: $0 <pin|unpin|update|upgrade> [workflow...]"
    exit 1
    ;;
esac
```

## Phase 3: Refactor Justfile Recipes

### 3.1 cache-linux-package refactoring

Before: 192 lines of embedded bash (lines 1004-1195)
After: ~10 lines calling extended ci-cache-category.sh

```just
# Build a package for Linux architectures and push to cachix
[group('CI/CD')]
cache-linux-package package:
    @./scripts/ci/ci-cache-category.sh aarch64-linux packages --package {{package}} --cross-linux --check-redundant --pin
```

Migration steps:
1. First extend ci-cache-category.sh with new functionality
2. Test new script matches existing behavior
3. Replace justfile recipe
4. Verify with `just cache-linux-package hello`

### 3.2 cache-ci-outputs refactoring

Before: 100 lines (lines 1218-1317)
After: ~5 lines

```just
# Build all CI outputs for a system and push to cachix
[group('CI/CD')]
cache-ci-outputs system="":
    @./scripts/ci/cache-all-outputs.sh "{{system}}"
```

Migration steps:
1. Create cache-all-outputs.sh
2. Test output matches existing recipe
3. Replace justfile recipe

### 3.3 cache-overlay-packages simplification

Before: 65 lines (lines 1371-1435)
After: ~5 lines calling existing ci-cache-category.sh

```just
# Build and cache all overlay packages for a specific system
[group('CI/CD')]
cache-overlay-packages system:
    @./scripts/ci/ci-cache-category.sh "{{system}}" packages
```

Migration: This is already directly supported by ci-cache-category.sh, just need to update the recipe.

### 3.4 docs-deploy-production extraction

Before: 87 lines (lines 464-550)
After: ~5 lines

```just
# Deploy documentation to Cloudflare Workers (production)
[group('docs')]
docs-deploy-production:
    @./scripts/docs/deploy-production.sh
```

Migration steps:
1. Create scripts/docs/ directory
2. Extract script
3. Test deployment workflow
4. Replace recipe

### 3.5 ratchet-* consolidation

Before: 4 recipes, 26 lines total (lines 885-909)
After: 1 parameterized recipe, ~5 lines

```just
# Run ratchet workflow action on GitHub Actions workflows
[group('CI/CD')]
ratchet action:
    @./scripts/ci/ratchet-workflow.sh {{action}}
```

Or alternatively, keep as individual recipes but call script:

```just
[group('CI/CD')]
ratchet-pin:
    @./scripts/ci/ratchet-workflow.sh pin

[group('CI/CD')]
ratchet-unpin:
    @./scripts/ci/ratchet-workflow.sh unpin

[group('CI/CD')]
ratchet-update:
    @./scripts/ci/ratchet-workflow.sh update

[group('CI/CD')]
ratchet-upgrade:
    @./scripts/ci/ratchet-workflow.sh upgrade
```

## Phase 4: Validation

Testing approach for each refactoring:

1. **cache-linux-package**:
   - Test with known overlay package
   - Verify redundancy detection works
   - Verify cachix push and pin operations

2. **cache-ci-outputs**:
   - Run for each supported system
   - Verify all categories cached
   - Compare output counts with original

3. **cache-overlay-packages**:
   - Already covered by ci-cache-category.sh tests
   - Verify just recipe invocation works

4. **docs-deploy-production**:
   - Test on non-main branch first
   - Verify version query logic
   - Test fallback deploy path

5. **ratchet-\***:
   - Test each action: pin, unpin, update, upgrade
   - Verify workflow files modified correctly

Rollback approach:
- Keep original recipes commented out until validation complete
- Git revert if issues found
- Scripts can be deleted without breaking justfile (just revert recipe)

## Execution Order

1. Create `scripts/docs/` directory
2. Create `scripts/ci/ratchet-workflow.sh` (simplest, no dependencies)
3. Refactor ratchet-* recipes in justfile
4. Commit: "refactor(justfile): consolidate ratchet recipes into script"
5. Create `scripts/docs/deploy-production.sh`
6. Refactor docs-deploy-production recipe
7. Commit: "refactor(justfile): extract docs-deploy-production to script"
8. Extend `scripts/ci/ci-cache-category.sh` with single-package mode
9. Refactor cache-linux-package recipe
10. Commit: "refactor(justfile): cache-linux-package uses extended ci-cache-category.sh"
11. Simplify cache-overlay-packages recipe (one-liner)
12. Commit: "refactor(justfile): simplify cache-overlay-packages"
13. Create `scripts/ci/cache-all-outputs.sh`
14. Refactor cache-ci-outputs recipe
15. Commit: "refactor(justfile): extract cache-ci-outputs to script"
16. Final validation pass
17. Commit: "docs: update justfile documentation comments"

## Risk Assessment

Potential issues:

1. **ci-cache-category.sh extension complexity**: Adding single-package mode requires careful integration with existing category logic
   - Mitigation: Add as separate function, don't modify existing paths

2. **sops exec-env context differences**: Scripts vs inline bash may handle environment differently
   - Mitigation: Test secrets availability in scripts before migration

3. **Working directory assumptions**: Scripts need absolute paths or explicit cd
   - Mitigation: Use `$(dirname "$0")` pattern consistently

4. **Ratchet variable scope**: justfile variables not available in scripts
   - Mitigation: Use environment variables or hardcode defaults with override

## Estimated Effort

- Phase 1 (extend ci-cache-category.sh): 2-3 hours
- Phase 2.1 (cache-all-outputs.sh): 1-2 hours
- Phase 2.2 (deploy-production.sh): 1 hour
- Phase 2.3 (ratchet-workflow.sh): 30 minutes
- Phase 3 (justfile refactoring): 1-2 hours
- Phase 4 (validation): 2-3 hours

Total: 8-12 hours

## Success Criteria

- Justfile reduced by ~400 lines
- All existing functionality preserved
- No manual intervention required for common operations
- Scripts are individually testable
- Clear separation between orchestration (justfile) and implementation (scripts)
- Atomic commits for each refactoring step

## Critical Files for Implementation

- `justfile` - Primary file to refactor (1611 lines, target recipes at lines 464, 885-909, 1004, 1218, 1371)
- `scripts/ci/ci-cache-category.sh` - Extend with single-package mode (418 lines, core caching logic)
- `scripts/ci/ci-build-local.sh` - Pattern to follow for discovery/build orchestration (364 lines)
- `scripts/ci/ci-build-category.sh` - Reference for consistent script interface design (370 lines)
- `secrets/shared.yaml` - Secrets file used by sops exec-env for CACHIX_CACHE_NAME
