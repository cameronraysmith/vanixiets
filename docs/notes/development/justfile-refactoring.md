# Justfile Refactoring Plan

## Overview

This plan refactors 8 verbose justfile recipes (totaling ~470 lines) into modular scripts using the **Wrapper Pattern** architecture.
The pattern emphasizes separation of concerns: specialized wrapper scripts orchestrate user-facing workflows while general-purpose scripts remain focused and simple.
This approach reduces complexity, improves maintainability, and enables better testing isolation.

The recipes to refactor and their current line counts are:
- `cache-linux-package`: 192 lines
- `cache-ci-outputs`: 100 lines
- `cache-overlay-packages`: 65 lines
- `docs-deploy-production`: 87 lines
- `ratchet-pin`, `ratchet-unpin`, `ratchet-update`, `ratchet-upgrade`: 26 lines combined

## Architecture Decision: Option C - Wrapper Pattern

**Rationale**: The wrapper pattern preserves the simplicity of existing general-purpose scripts (like `ci-cache-category.sh`) while enabling specialized orchestration logic to live in separate, focused wrappers.

**Key Principles**:
- **Separation of concerns**: Orchestration logic (workflow steps, interactive prompts, multi-stage coordination) lives in wrappers; execution logic (build, cache, deploy) lives in general-purpose scripts
- **Lower regression risk**: Existing scripts remain unchanged, reducing chance of breaking working functionality
- **Testability**: Wrappers and general scripts can be tested independently
- **Composability**: General scripts are reusable building blocks; wrappers compose them for specific workflows
- **User-facing vs. internal**: Interactive prompts belong in wrappers, not in general-purpose scripts

**Example**: Instead of extending `ci-cache-category.sh` with flags like `--package`, `--check-redundant`, `--pin`, we create `cache-linux-package.sh` that:
1. Handles redundancy detection with interactive prompts
2. Calls `ci-cache-category.sh` twice (once per architecture)
3. Handles pinning as a separate post-build step
4. Orchestrates the complete workflow without modifying the general-purpose script

## Prerequisites

Before implementation, the developer should understand:

1. The existing `scripts/ci/ci-cache-category.sh` (418 lines) which handles category-based caching with cachix push for categories: packages, checks-devshells, home, nixos, darwin
2. The existing `scripts/ci/ci-build-local.sh` (364 lines) which discovers and builds all flake outputs
3. The justfile variable definitions at lines 877-881 for `ratchet_base` and `gha_workflows`

## Script Standards

All new scripts MUST include:

1. **Shebang and strict mode**:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   ```

2. **Working directory normalization**:
   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```
   This ensures scripts work when called from any directory.

3. **Usage documentation**:
   Include clear usage/help documentation at the top of the script after the shebang.

4. **Help flag**:
   ```bash
   if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
       cat <<EOF
   Usage: $0 [options] <args>

   Description of what this script does.

   Options:
       --help, -h          Show this help message
       --dry-run           Show what would be done without executing
   EOF
       exit 0
   fi
   ```

5. **Dry-run flag** (where destructive operations occur):
   ```bash
   DRY_RUN=false
   if [[ "${1:-}" == "--dry-run" ]]; then
       DRY_RUN=true
       shift
   fi

   if [[ "$DRY_RUN" == "true" ]]; then
       echo "[DRY RUN] Would execute: <command>"
   else
       <actual command>
   fi
   ```

6. **sops exec-env testing**:
   Before accessing secrets, verify sops exec-env context:
   ```bash
   if ! command -v sops &> /dev/null; then
       echo "Error: sops not found"
       exit 1
   fi
   ```

## Phase 1: Create Wrapper Scripts

### 1.1 scripts/ci/cache-linux-package.sh

Purpose: Wrapper script for building a single package for Linux architectures with redundancy detection and pinning.

**This is the canonical example of the wrapper pattern.**

Interface:
```bash
./scripts/ci/cache-linux-package.sh [--dry-run] <package>
# package: name of the overlay package to build
```

Implementation outline:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 [--dry-run] <package>

Build a single overlay package for both Linux architectures (aarch64-linux, x86_64-linux)
and push to cachix. Includes redundancy detection and cachix pinning.

Options:
    --help, -h      Show this help message
    --dry-run       Show what would be done without executing

Arguments:
    package         Name of the overlay package to build

Example:
    $0 hello
    $0 --dry-run my-package
EOF
    exit 0
fi

# Dry-run flag
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

PACKAGE="${1:-}"
if [[ -z "$PACKAGE" ]]; then
    echo "Error: package name required"
    echo "Run with --help for usage"
    exit 1
fi

# Phase 1: Redundancy detection (extracted from justfile lines 1013-1064)
# Interactive prompts belong here in the wrapper, not in general scripts
echo "Checking if $PACKAGE is redundant with nixpkgs..."

# Build local overlay version
LOCAL_PATH=$(nix build ".#packages.x86_64-linux.$PACKAGE" --print-out-paths --no-link 2>/dev/null || true)

# Build nixpkgs version
NIXPKGS_PATH=$(nix build "nixpkgs#$PACKAGE" --print-out-paths --no-link 2>/dev/null || true)

if [[ -n "$LOCAL_PATH" && "$LOCAL_PATH" == "$NIXPKGS_PATH" ]]; then
    echo "WARNING: Package $PACKAGE is identical to nixpkgs version"
    echo "Consider removing from overlay"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Phase 2: Build and cache for both architectures
# Calls general-purpose script twice, once per architecture
for SYSTEM in aarch64-linux x86_64-linux; do
    echo "Building $PACKAGE for $SYSTEM..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: ./scripts/ci/ci-cache-category.sh $SYSTEM packages"
    else
        ./scripts/ci/ci-cache-category.sh "$SYSTEM" packages
    fi
done

# Phase 3: Pin cached paths to prevent GC (extracted from justfile lines 1126-1134, 1169-1177)
# Orchestration logic: pinning happens after both builds complete
echo "Pinning cached paths..."

for SYSTEM in aarch64-linux x86_64-linux; do
    STORE_PATH=$(nix build ".#packages.$SYSTEM.$PACKAGE" --print-out-paths --no-link 2>/dev/null || true)
    if [[ -n "$STORE_PATH" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[DRY RUN] Would pin: $STORE_PATH"
        else
            # Pin operation requires retry logic with verification
            MAX_RETRIES=3
            RETRY_COUNT=0
            while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
                if sops exec-env secrets/shared.yaml \
                    "cachix pin \$CACHIX_CACHE_NAME $PACKAGE-$SYSTEM $STORE_PATH"; then
                    echo "Successfully pinned $STORE_PATH"
                    break
                else
                    RETRY_COUNT=$((RETRY_COUNT + 1))
                    echo "Pin failed, retry $RETRY_COUNT/$MAX_RETRIES..."
                    sleep 2
                fi
            done

            if [[ $RETRY_COUNT -eq $MAX_RETRIES ]]; then
                echo "Error: Failed to pin after $MAX_RETRIES attempts"
                exit 1
            fi
        fi
    fi
done

echo "Successfully cached $PACKAGE for both Linux architectures"
```

**Key architectural points**:
- **Does NOT extend ci-cache-category.sh** - that script stays focused on its single responsibility
- **Interactive prompts** (redundancy warning) belong in this user-facing wrapper
- **Orchestration logic** (two architecture builds, post-build pinning) lives here
- **Retry logic** for pin operations ensures reliability
- **Working directory normalized** at entry point
- **Dry-run support** for safe testing

Migration steps:
1. Create the wrapper script
2. Test with known overlay package using `--dry-run`
3. Test actual execution with non-critical package
4. Replace justfile recipe
5. Verify with `just cache-linux-package hello`

## Phase 2: Create Additional Scripts

### 2.1 scripts/ci/cache-all-outputs.sh

Purpose: Orchestrate bulk caching of all CI outputs for a system, replacing the 100-line `cache-ci-outputs` recipe.

Interface:
```bash
./scripts/ci/cache-all-outputs.sh [--dry-run] [--help] [system]
# system: x86_64-linux, aarch64-linux, aarch64-darwin (defaults to current)
```

Implementation outline:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 [--dry-run] [system]

Build and cache all CI outputs (packages, devShells, checks, configurations) for a system.

Options:
    --help, -h      Show this help message
    --dry-run       Show what would be done without executing

Arguments:
    system          Target system (x86_64-linux, aarch64-linux, aarch64-darwin)
                    Defaults to current system

Example:
    $0 x86_64-linux
    $0 --dry-run aarch64-darwin
EOF
    exit 0
fi

# Dry-run flag
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

TARGET_SYSTEM="${1:-$(nix eval --raw --impure --expr 'builtins.currentSystem')}"

# Phase 1: Build all outputs using ci-build-local.sh
# Reuse existing discovery and build logic
echo "Building all outputs for $TARGET_SYSTEM..."
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would execute: ./scripts/ci/ci-build-local.sh \"\" \"$TARGET_SYSTEM\""
else
    ./scripts/ci/ci-build-local.sh "" "$TARGET_SYSTEM"
fi

# Phase 2: Collect store paths and push to cachix
# Source discovery functions from ci-build-local.sh where possible
# to avoid code duplication

# Categories to cache based on system type
if [[ "$TARGET_SYSTEM" == *"darwin"* ]]; then
    CATEGORIES="packages devShells checks darwinConfigurations"
else
    CATEGORIES="packages devShells checks nixosConfigurations"
fi

# Iterate through categories and cache
for CATEGORY in $CATEGORIES; do
    echo "Caching $CATEGORY for $TARGET_SYSTEM..."
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: ./scripts/ci/ci-cache-category.sh \"$TARGET_SYSTEM\" \"$CATEGORY\""
    else
        ./scripts/ci/ci-cache-category.sh "$TARGET_SYSTEM" "$CATEGORY"
    fi
done

echo "Successfully cached all outputs for $TARGET_SYSTEM"
```

**Key points**:
- Working directory normalization ensures script works from anywhere
- `--dry-run` flag for testing
- `--help` flag with usage documentation
- Should source/reuse discovery functions from `ci-build-local.sh` to avoid code duplication
- Clear separation: build logic in `ci-build-local.sh`, cache logic in `ci-cache-category.sh`

Dependencies:
- `scripts/ci/ci-build-local.sh` for building
- `scripts/ci/ci-cache-category.sh` for caching
- `sops exec-env` for cachix authentication
- `jq` for JSON parsing

### 2.2 scripts/docs/deploy-production.sh

Purpose: Handle Cloudflare Workers production deployment with version promotion.

Interface:
```bash
./scripts/docs/deploy-production.sh [--dry-run] [--help]
```

Implementation outline (extracted from justfile lines 464-549):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 [--dry-run]

Deploy documentation to Cloudflare Workers production environment.
Attempts version promotion if CI build exists, falls back to direct deploy.

Options:
    --help, -h      Show this help message
    --dry-run       Show what would be done without executing

Example:
    $0
    $0 --dry-run
EOF
    exit 0
fi

# Dry-run flag
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

# Change to docs package directory
cd packages/docs

# Get commit metadata
CURRENT_TAG=$(git rev-parse --short=12 HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
IS_CI="${CI:-false}"

# Build deployment message (CI vs local)
if [[ "$IS_CI" == "true" ]]; then
    DEPLOY_MSG="CI deployment from $GIT_BRANCH@$CURRENT_TAG"
else
    DEPLOY_MSG="Local deployment from $GIT_BRANCH@$CURRENT_TAG"
fi

echo "Deployment: $DEPLOY_MSG"

# Query existing version with matching tag
echo "Checking for existing CI build with tag $CURRENT_TAG..."
EXISTING_VERSION=$(wrangler versions list --json | \
    jq -r ".[] | select(.annotations.\"workers/triggered_by\" | contains(\"$CURRENT_TAG\")) | .id" | \
    head -n1)

if [[ -n "$EXISTING_VERSION" ]]; then
    echo "Found existing version: $EXISTING_VERSION"
    echo "Promoting to 100% production..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: wrangler versions deploy --version $EXISTING_VERSION --percentage 100"
    else
        wrangler versions deploy --version "$EXISTING_VERSION" --percentage 100
    fi
else
    echo "No existing CI build found, falling back to direct deploy..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: wrangler deploy --message \"$DEPLOY_MSG\""
    else
        wrangler deploy --message "$DEPLOY_MSG"
    fi
fi

echo "Successfully deployed documentation to production"
```

**Key features preserved**:
- Git metadata capture (SHA, tag, branch)
- CI vs local detection
- Version query and promotion workflow
- Fallback direct deploy path
- Working directory normalization
- `--dry-run` and `--help` flags

### 2.3 scripts/ci/ratchet-workflow.sh

Purpose: Consolidate 4 ratchet recipes into a single parameterized script.

Interface:
```bash
./scripts/ci/ratchet-workflow.sh [--help] <action> [workflow...]
# action: pin, unpin, update, upgrade
# workflow: defaults to GHA_WORKFLOWS environment variable or ./.github/workflows/flake.yaml
```

Implementation outline:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 <action> [workflow...]

Run ratchet action on GitHub Actions workflow files.

Arguments:
    action          Action to perform: pin, unpin, update, upgrade
    workflow        Workflow files to process (default: \$GHA_WORKFLOWS or ./.github/workflows/flake.yaml)

Environment Variables:
    GHA_WORKFLOWS   Space-separated list of workflow files to process
    RATCHET_BASE    Base ratchet command (default: ratchet)

Examples:
    $0 pin
    $0 update ./.github/workflows/flake.yaml ./.github/workflows/docs.yaml
    GHA_WORKFLOWS="./.github/workflows/*.yaml" $0 upgrade
EOF
    exit 0
fi

ACTION="${1:-}"
shift

# Use environment variable for workflows, with fallback to default
WORKFLOWS="${*:-${GHA_WORKFLOWS:-./.github/workflows/flake.yaml}}"
RATCHET_BASE="${RATCHET_BASE:-ratchet}"

if [[ -z "$ACTION" ]]; then
    echo "Error: action required"
    echo "Run with --help for usage"
    exit 1
fi

case "$ACTION" in
  pin|unpin|update|upgrade)
    for workflow in $WORKFLOWS; do
        echo "Running ratchet $ACTION on $workflow..."
        eval "$RATCHET_BASE $ACTION $workflow"
    done
    ;;
  *)
    echo "Error: Unknown action '$ACTION'"
    echo "Valid actions: pin, unpin, update, upgrade"
    echo "Run with --help for usage"
    exit 1
    ;;
esac

echo "Successfully completed ratchet $ACTION on all workflows"
```

**Key points**:
- Uses environment variable `GHA_WORKFLOWS` for workflow list (allows justfile integration)
- `--help` flag with usage documentation
- Working directory normalization
- Clear error messages

## Phase 3: Refactor Justfile Recipes

### 3.1 cache-linux-package refactoring

Before: 192 lines of embedded bash (lines 1004-1195)
After: ~5 lines calling wrapper script

```just
# Build a package for Linux architectures and push to cachix
[group('CI/CD')]
cache-linux-package package:
    @./scripts/ci/cache-linux-package.sh {{package}}
```

Migration steps:
1. Create cache-linux-package.sh wrapper
2. Test wrapper matches existing behavior with `--dry-run`
3. Test actual execution with known package
4. Replace justfile recipe
5. Verify with `just cache-linux-package hello`

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

**Migration**: This is already directly supported by the existing general-purpose `ci-cache-category.sh`, no wrapper needed.
Just update the recipe to call the script directly.

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
1. Create scripts/docs/ directory if needed
2. Create deploy-production.sh script
3. Test deployment workflow with `--dry-run`
4. Replace recipe

### 3.5 ratchet-* consolidation

Before: 4 recipes, 26 lines total (lines 885-909)
After: 4 recipes, ~20 lines total (keep individual recipes for discoverability)

```just
# Pin GitHub Actions workflow versions
[group('CI/CD')]
ratchet-pin:
    @./scripts/ci/ratchet-workflow.sh pin

# Unpin GitHub Actions workflow versions
[group('CI/CD')]
ratchet-unpin:
    @./scripts/ci/ratchet-workflow.sh unpin

# Update GitHub Actions workflow versions
[group('CI/CD')]
ratchet-update:
    @./scripts/ci/ratchet-workflow.sh update

# Upgrade (update + pin) GitHub Actions workflow versions
[group('CI/CD')]
ratchet-upgrade:
    @./scripts/ci/ratchet-workflow.sh upgrade
```

**Rationale**: Keep individual recipes for user discoverability (`just --list` shows all actions), but implementation lives in script.

## Phase 4: Validation

Testing approach for each refactoring:

1. **cache-linux-package**:
   - Test `--help` flag displays usage
   - Test `--dry-run` shows expected operations without executing
   - Test with known overlay package (non-redundant)
   - Verify redundancy detection with package that matches nixpkgs
   - Verify cachix push operations succeed
   - Verify cachix pin operations succeed with retry logic
   - Verify script works when called from different directories

2. **cache-ci-outputs**:
   - Test `--help` flag displays usage
   - Test `--dry-run` shows expected operations
   - Run for each supported system (x86_64-linux, aarch64-linux, aarch64-darwin)
   - Verify all categories cached
   - Compare output counts with original recipe
   - Verify script works from any directory

3. **cache-overlay-packages**:
   - Already covered by ci-cache-category.sh tests
   - Verify just recipe invocation works
   - Verify from any directory

4. **docs-deploy-production**:
   - Test `--help` flag displays usage
   - Test `--dry-run` shows expected operations
   - Test on non-main branch first
   - Verify version query logic (existing CI build)
   - Test fallback deploy path (no existing build)
   - Verify git metadata captured correctly
   - Verify script works from any directory

5. **ratchet-\***:
   - Test `--help` flag displays usage
   - Test each action: pin, unpin, update, upgrade
   - Verify workflow files modified correctly
   - Test with custom GHA_WORKFLOWS environment variable
   - Verify script works from any directory

6. **sops exec-env context**:
   - Verify secrets accessible in all script contexts
   - Test CACHIX_CACHE_NAME available in cache scripts
   - Test from different working directories

Rollback approach:
- Keep original recipes commented out until validation complete
- Git revert if issues found
- Scripts can be deleted without breaking justfile (just revert recipe)

## Execution Order

Ordered to build from simple to complex, with atomic commits:

1. Create `scripts/ci/ratchet-workflow.sh` (simplest, no dependencies)
2. Refactor ratchet-* recipes in justfile
3. Commit: "refactor(justfile): consolidate ratchet recipes into script"
4. Create `scripts/docs/deploy-production.sh`
5. Refactor docs-deploy-production recipe
6. Commit: "refactor(justfile): extract docs-deploy-production to script"
7. Simplify cache-overlay-packages recipe (one-liner, no new script needed)
8. Commit: "refactor(justfile): simplify cache-overlay-packages to call ci-cache-category.sh directly"
9. Create `scripts/ci/cache-linux-package.sh` (wrapper pattern)
10. Refactor cache-linux-package recipe
11. Commit: "refactor(justfile): extract cache-linux-package to wrapper script"
12. Create `scripts/ci/cache-all-outputs.sh`
13. Refactor cache-ci-outputs recipe
14. Commit: "refactor(justfile): extract cache-ci-outputs to script"
15. Final validation pass (all tests from Phase 4)
16. Commit: "docs: update justfile documentation comments"

## Risk Assessment

Potential issues and mitigations:

1. **sops exec-env context differences**:
   - **Risk**: Scripts vs inline bash may handle environment differently
   - **Impact**: Secrets might not be accessible, breaking cachix operations
   - **Mitigation**: Test secrets availability in scripts independently before migration; include sops exec-env context testing in Phase 4 validation

2. **Working directory assumptions**:
   - **Risk**: Scripts assume specific working directory, break when called from elsewhere
   - **Impact**: Build/cache operations fail with confusing path errors
   - **Mitigation**: All scripts use `cd "$(git rev-parse --show-toplevel)"` at entry point; test from multiple directories in Phase 4

3. **Pin operations reliability**:
   - **Risk**: Cachix pin operations may fail intermittently (network, rate limits)
   - **Impact**: Cached artifacts not permanently stored, potential GC loss
   - **Mitigation**: Implement retry logic with verification in wrapper scripts; cache-linux-package.sh includes 3-retry pattern with exponential backoff

4. **Wrapper complexity**:
   - **Risk**: Wrappers become complex, defeating simplicity goal
   - **Impact**: Maintenance burden shifts from justfile to scripts without net reduction
   - **Mitigation**: Keep wrappers focused on orchestration only; resist temptation to add features; code review enforces single responsibility

5. **Interactive prompt context**:
   - **Risk**: Interactive prompts in wrappers break CI/automation contexts
   - **Impact**: CI builds hang waiting for user input
   - **Mitigation**: Document that wrapper scripts are for local development use; CI should call general-purpose scripts directly or use non-interactive flags

6. **Discovery function duplication**:
   - **Risk**: cache-all-outputs.sh duplicates discovery logic from ci-build-local.sh
   - **Impact**: Code duplication increases maintenance burden
   - **Mitigation**: Source/reuse discovery functions from ci-build-local.sh where possible; refactor common logic into shared library if duplication becomes significant

## Estimated Effort

Adjusted for wrapper pattern approach:

- Phase 1 (cache-linux-package.sh wrapper): 2 hours
- Phase 2.1 (cache-all-outputs.sh): 1.5 hours
- Phase 2.2 (deploy-production.sh): 1.5 hours
- Phase 2.3 (ratchet-workflow.sh): 30 minutes
- Phase 3 (justfile refactoring): 1.5 hours
- Phase 4 (validation): 2 hours

Total: 7-9 hours

## Success Criteria

- Justfile reduced by ~400 lines
- All existing functionality preserved
- No manual intervention required for common operations
- Scripts are individually testable in isolation
- Clear separation between orchestration (wrappers) and execution (general scripts)
- Atomic commits for each refactoring step
- All new scripts support `--help` flag
- All new scripts with destructive operations support `--dry-run` flag
- All scripts work when called from any directory (working directory normalization)
- sops exec-env secrets accessible in all script contexts
- No interactive prompts in general-purpose scripts (only in user-facing wrappers)
- Pin operations include retry logic with verification
- Wrapper scripts demonstrate composability of general-purpose scripts

## Critical Files for Implementation

- `justfile` - Primary file to refactor (1611 lines, target recipes at lines 464, 885-909, 1004, 1218, 1371)
- `scripts/ci/ci-cache-category.sh` - General-purpose script, **remains unchanged** (418 lines, core caching logic)
- `scripts/ci/ci-build-local.sh` - Pattern to follow for discovery/build orchestration (364 lines); source discovery functions from here
- `scripts/ci/ci-build-category.sh` - Reference for consistent script interface design (370 lines)
- `secrets/shared.yaml` - Secrets file used by sops exec-env for CACHIX_CACHE_NAME

## Wrapper Pattern Examples

For reference, the key wrapper pattern examples in this plan:

1. **cache-linux-package.sh**: Wrapper that orchestrates redundancy detection, dual-architecture builds, and pinning by calling `ci-cache-category.sh` multiple times
2. **cache-all-outputs.sh**: Wrapper that orchestrates full CI caching by calling `ci-build-local.sh` then `ci-cache-category.sh` for each category
3. **deploy-production.sh**: Wrapper that orchestrates version promotion workflow with fallback to direct deploy

Each wrapper demonstrates:
- Single responsibility for a user-facing workflow
- Composition of general-purpose scripts
- Interactive prompts (where appropriate)
- Orchestration logic separate from execution
- Standard flags (--help, --dry-run)
- Working directory normalization
