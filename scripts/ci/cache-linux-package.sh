#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Cache Linux Package Wrapper Script
# ============================================================================
# Build a single overlay package for both Linux architectures and push to
# cachix. Includes redundancy detection against nixpkgs and cachix pinning.
#
# This is the canonical example of the wrapper pattern:
# - Handles redundancy detection with interactive prompts
# - Orchestrates dual-architecture builds
# - Handles pinning as a separate post-build step
# - Does NOT modify general-purpose scripts
#
# Usage:
#   cache-linux-package.sh [--dry-run] <package>
#
# Arguments:
#   package     Name of the overlay package to build
#
# Options:
#   --help, -h      Show this help message
#   --dry-run       Show what would be done without executing
#
# Examples:
#   cache-linux-package.sh hello
#   cache-linux-package.sh --dry-run my-package
# ============================================================================

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 [--dry-run] <package>

Build a single overlay package for both Linux architectures (aarch64-linux,
x86_64-linux) and push to cachix. Includes redundancy detection and pinning.

Options:
    --help, -h      Show this help message
    --dry-run       Show what would be done without executing

Arguments:
    package         Name of the overlay package to build

Workflow:
    1. Check if package is redundant with nixpkgs
    2. Check if already cached for each architecture
    3. Build and push for each architecture using cachix watch-exec
    4. Pin cached paths to prevent garbage collection

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
    echo "error: package name required"
    echo "run with --help for usage"
    exit 1
fi

echo "Building $PACKAGE for Linux architectures using rosetta-builder..."
CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
echo "Cache: https://app.cachix.org/cache/$CACHE_NAME"
echo ""

# ============================================================================
# Phase 1: Redundancy Detection
# ============================================================================
# Interactive prompts belong here in the wrapper, not in general scripts

echo "Checking if package is redundant with nixpkgs..."
OUR_DRV=$(nix eval --raw ".#packages.aarch64-linux.$PACKAGE.drvPath" 2>/dev/null || echo "none")
NIXPKGS_DRV=$(nix eval --raw "nixpkgs#$PACKAGE.drvPath" --system aarch64-linux 2>/dev/null || echo "none")

REDUNDANT_OVERLAY=false
if [[ "$OUR_DRV" != "none" && "$NIXPKGS_DRV" != "none" && "$OUR_DRV" == "$NIXPKGS_DRV" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "warning: redundant overlay detected"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Your overlay package is IDENTICAL to nixpkgs:"
    echo "  package: $PACKAGE"
    echo "  derivation: $OUR_DRV"
    echo ""
    echo "This typically happens when:"
    echo "  1. You copied a nixpkgs derivation to your overlay for upgrades"
    echo "  2. Then updated your nixpkgs lockfile"
    echo "  3. Now both are at the same version"
    echo ""
    echo "Implications:"
    echo "  - Your overlay provides zero value (byte-for-byte identical)"
    echo "  - Package is already available from cache.nixos.org"
    echo "  - CI will fetch from cache.nixos.org automatically"
    echo "  - Caching in personal cachix will likely fail (already exists elsewhere)"
    echo ""
    echo "Recommended action:"
    echo "  rm -rf overlays/packages/$PACKAGE/"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would prompt: skip caching and exit? (Y/n)"
        echo "[DRY RUN] Assuming 'n' to continue dry run..."
        REDUNDANT_OVERLAY=true
    else
        echo "Skip caching and exit? (Y/n): "
        read -r response
        if [[ ! "$response" =~ ^[Nn]$ ]]; then
            echo ""
            echo "skipped caching - package available from cache.nixos.org"
            echo ""
            echo "Next steps:"
            echo "  1. Remove the redundant overlay: rm -rf overlays/packages/$PACKAGE/"
            echo "  2. Update any explicit references to use nixpkgs directly"
            echo "  3. Commit the cleanup"
            echo ""
            exit 0
        fi
        echo ""
        echo "warning: continuing anyway - expect push/pin failures..."
        echo ""
        REDUNDANT_OVERLAY=true
    fi
else
    echo "package differs from nixpkgs (custom overlay)"
fi
echo ""

# ============================================================================
# Phase 2: Cache Status Check
# ============================================================================

echo "Checking cache status..."
AARCH64_CACHED=false
X86_64_CACHED=false

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would check: nix path-info --store https://$CACHE_NAME.cachix.org .#packages.aarch64-linux.$PACKAGE"
    echo "[DRY RUN] Would check: nix path-info --store https://$CACHE_NAME.cachix.org .#packages.x86_64-linux.$PACKAGE"
else
    if nix path-info --store "https://$CACHE_NAME.cachix.org" ".#packages.aarch64-linux.$PACKAGE" &>/dev/null; then
        echo "aarch64-linux: already in cache"
        AARCH64_CACHED=true
    else
        echo "aarch64-linux: need to build"
    fi

    if nix path-info --store "https://$CACHE_NAME.cachix.org" ".#packages.x86_64-linux.$PACKAGE" &>/dev/null; then
        echo "x86_64-linux: already in cache"
        X86_64_CACHED=true
    else
        echo "x86_64-linux: need to build"
    fi

    if [[ "$AARCH64_CACHED" == true && "$X86_64_CACHED" == true ]]; then
        echo ""
        echo "both architectures already cached - nothing to do"
        exit 0
    fi
fi

echo ""
echo "Building and pushing to cachix (this may take 15-30 minutes for large packages)..."
echo "Using cachix watch-exec to push store paths as they're built..."
echo ""

# ============================================================================
# Phase 3: Build and Cache
# ============================================================================
# Orchestration logic: build each architecture, push, verify, then pin

build_and_cache_arch() {
    local system="$1"
    local cached="$2"

    if [[ "$cached" == true ]]; then
        return 0
    fi

    echo "Building for $system..."

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY RUN] Would execute: cachix watch-exec \$CACHIX_CACHE_NAME --jobs 8 -- nom build .#packages.$system.$PACKAGE --no-link --print-out-paths --max-jobs 0"
        echo "[DRY RUN] Would push and pin result"
        return 0
    fi

    local store_path
    store_path=$(sops exec-env secrets/shared.yaml \
        "cachix watch-exec \$CACHIX_CACHE_NAME --jobs 8 -- nom build .#packages.$system.$PACKAGE --no-link --print-out-paths --max-jobs 0" | tail -1)

    echo "Pushing $store_path to cachix..."

    if [[ "$REDUNDANT_OVERLAY" == "true" ]]; then
        # Try to push but expect failure (package already in cache.nixos.org)
        if sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $store_path" 2>&1 | tee /tmp/cachix_push.log | grep -q "Nothing to push"; then
            echo "warning: as expected, package already available (likely in cache.nixos.org)"
            echo "  skipping pin - remove overlay to avoid this workflow"
        else
            echo "push succeeded (unexpected for redundant overlay)"
        fi
    else
        # Normal cachix push for custom packages
        sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $store_path"

        # Verify it's actually in our cachix before pinning
        echo "Verifying path is in cache..."
        sleep 3  # Allow CDN propagation
        if ! nix path-info --store "https://$CACHE_NAME.cachix.org" "$store_path" &>/dev/null; then
            echo "warning: path not in cache after push, retrying..."
            sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME $store_path"
            sleep 3
        fi

        # Pin the path to prevent garbage collection with retry logic
        local pin_name="${PACKAGE}-${system}"
        echo "Pinning $store_path as '$pin_name'..."

        local max_retries=3
        local retry_count=0
        while [[ $retry_count -lt $max_retries ]]; do
            if sops exec-env secrets/shared.yaml "cachix pin \$CACHIX_CACHE_NAME $pin_name $store_path"; then
                echo "pinned and verified: $store_path"
                break
            else
                retry_count=$((retry_count + 1))
                echo "pin failed, retry $retry_count/$max_retries..."
                sleep 2
            fi
        done

        if [[ $retry_count -eq $max_retries ]]; then
            echo "error: failed to pin after $max_retries attempts"
            exit 1
        fi
    fi
    echo ""
}

# Build for aarch64-linux
build_and_cache_arch "aarch64-linux" "$AARCH64_CACHED"

# Build for x86_64-linux
build_and_cache_arch "x86_64-linux" "$X86_64_CACHED"

# ============================================================================
# Phase 4: Summary
# ============================================================================

echo ""
if [[ "$REDUNDANT_OVERLAY" == "true" ]]; then
    echo "warning: build completed (but caching skipped - package redundant with nixpkgs)"
    echo ""
    echo "IMPORTANT: Remove the redundant overlay to avoid this issue:"
    echo "  rm -rf overlays/packages/$PACKAGE/"
    echo ""
    echo "Your CI will fetch from cache.nixos.org automatically."
else
    echo "successfully built and cached $PACKAGE for Linux architectures"
    echo "  cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""
    echo "CI will now fetch from cachix instead of building, avoiding disk space issues."
fi
