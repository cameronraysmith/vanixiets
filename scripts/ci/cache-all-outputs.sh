#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Cache All CI Outputs Script
# ============================================================================
# Build and cache all CI outputs (packages, devShells, checks, configurations)
# for a system. Orchestrates ci-build-local.sh for building and collects
# store paths for cachix push.
#
# Usage:
#   cache-all-outputs.sh [--dry-run] [system]
#
# Arguments:
#   system      Target system (x86_64-linux, aarch64-linux, aarch64-darwin)
#               Defaults to current system
#
# Options:
#   --help, -h      Show this help message
#   --dry-run       Show what would be done without executing
#
# Examples:
#   cache-all-outputs.sh x86_64-linux
#   cache-all-outputs.sh --dry-run aarch64-darwin
# ============================================================================

# Working directory normalization
cd "$(git rev-parse --show-toplevel)"

# Help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Usage: $0 [--dry-run] [system]

Build and cache all CI outputs (packages, devShells, checks, configurations)
for a system.

Options:
    --help, -h      Show this help message
    --dry-run       Show what would be done without executing

Arguments:
    system          Target system (x86_64-linux, aarch64-linux, aarch64-darwin)
                    Defaults to current system

Workflow:
    1. Build all flake outputs using ci-build-local.sh
    2. Collect all store paths
    3. Push all paths to cachix

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

# Determine target system (default to current system if not specified)
if [ -z "${1:-}" ]; then
    TARGET_SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
else
    TARGET_SYSTEM="$1"
fi

# Validate system is one of the three supported platforms
case "$TARGET_SYSTEM" in
    x86_64-linux|aarch64-linux|aarch64-darwin)
        echo "Building all CI outputs for $TARGET_SYSTEM..."
        ;;
    *)
        echo "error: unsupported system '$TARGET_SYSTEM'"
        echo "supported systems:"
        echo "  - x86_64-linux   (Intel/AMD Linux)"
        echo "  - aarch64-linux  (ARM Linux)"
        echo "  - aarch64-darwin (Apple Silicon macOS)"
        exit 1
        ;;
esac

CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
echo "cache: https://app.cachix.org/cache/$CACHE_NAME"
echo ""
echo "This will:"
echo "  1. Build all flake outputs for $TARGET_SYSTEM"
echo "  2. Push all build outputs and dependencies to cachix"
echo ""
echo "Starting build + push (this may take 10-30 minutes)..."
echo ""

# ============================================================================
# Phase 1: Build all outputs
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "phase 1: building all outputs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would execute: ./scripts/ci/ci-build-local.sh \"\" \"$TARGET_SYSTEM\""
else
    ./scripts/ci/ci-build-local.sh "" "$TARGET_SYSTEM"
fi

# ============================================================================
# Phase 2: Collect store paths and push to cachix
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "phase 2: pushing to cachix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would collect store paths from:"
    echo "  - packages.$TARGET_SYSTEM.*"
    echo "  - devShells.$TARGET_SYSTEM.*"
    echo "  - checks.$TARGET_SYSTEM.*"
    if [[ "$TARGET_SYSTEM" == *-darwin ]]; then
        echo "  - darwinConfigurations.*"
    fi
    if [[ "$TARGET_SYSTEM" == *-linux ]]; then
        echo "  - nixosConfigurations.*"
    fi
    echo "[DRY RUN] Would push all store paths to cachix"
else
    # Collect all store paths from built outputs
    STORE_PATHS=""

    # Packages
    for pkg in $(nix eval ".#packages.$TARGET_SYSTEM" --apply 'x: builtins.attrNames x' --json 2>/dev/null | jq -r '.[]'); do
        path=$(nix build ".#packages.$TARGET_SYSTEM.$pkg" --no-link --print-out-paths 2>/dev/null || true)
        [ -n "$path" ] && STORE_PATHS="$STORE_PATHS $path"
    done

    # DevShells
    for shell in $(nix eval ".#devShells.$TARGET_SYSTEM" --apply 'x: builtins.attrNames x' --json 2>/dev/null | jq -r '.[]'); do
        path=$(nix build ".#devShells.$TARGET_SYSTEM.$shell" --no-link --print-out-paths 2>/dev/null || true)
        [ -n "$path" ] && STORE_PATHS="$STORE_PATHS $path"
    done

    # Checks
    for check in $(nix eval ".#checks.$TARGET_SYSTEM" --apply 'x: builtins.attrNames x' --json 2>/dev/null | jq -r '.[]'); do
        path=$(nix build ".#checks.$TARGET_SYSTEM.$check" --no-link --print-out-paths 2>/dev/null || true)
        [ -n "$path" ] && STORE_PATHS="$STORE_PATHS $path"
    done

    # Darwin configurations (only on darwin)
    if [[ "$TARGET_SYSTEM" == *-darwin ]]; then
        for cfg in $(nix eval ".#darwinConfigurations" --apply 'x: builtins.attrNames x' --json 2>/dev/null | jq -r '.[]'); do
            path=$(nix build ".#darwinConfigurations.$cfg.system" --no-link --print-out-paths 2>/dev/null || true)
            [ -n "$path" ] && STORE_PATHS="$STORE_PATHS $path"
        done
    fi

    # NixOS configurations (only on linux)
    if [[ "$TARGET_SYSTEM" == *-linux ]]; then
        for cfg in $(nix eval ".#nixosConfigurations" --apply 'x: builtins.attrNames x' --json 2>/dev/null | jq -r '.[]'); do
            path=$(nix build ".#nixosConfigurations.$cfg.config.system.build.toplevel" --no-link --print-out-paths 2>/dev/null || true)
            [ -n "$path" ] && STORE_PATHS="$STORE_PATHS $path"
        done
    fi

    # Push all paths to cachix
    if [ -n "$STORE_PATHS" ]; then
        path_count=$(echo $STORE_PATHS | wc -w | tr -d ' ')
        echo "pushing $path_count store paths to cachix..."
        echo $STORE_PATHS | tr ' ' '\n' | grep -v '^$' | \
            sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME"
    else
        echo "no store paths to push"
    fi
fi

echo ""
echo "successfully built and cached all CI outputs for $TARGET_SYSTEM"
echo "  cache: https://app.cachix.org/cache/$CACHE_NAME"
echo ""
echo "Other machines can now pull from cachix instead of rebuilding."
