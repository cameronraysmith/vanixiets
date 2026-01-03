#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# CI Category Cacher
# ============================================================================
# Build specific categories of flake outputs and push to cachix with all
# dependencies. Designed for local testing of CI matrix jobs on aarch64
# with nix-rosetta-builder for aarch64-linux builds.
#
# Usage:
#   ci-cache-category.sh <system> <category> [config]
#
# Arguments:
#   system    - Target system (x86_64-linux, aarch64-linux, aarch64-darwin)
#   category  - Output category to build and cache:
#               - packages: all packages for system
#               - checks-devshells: checks and devshells (combined)
#               - home: all home configurations for system
#               - nixos: NixOS configuration (requires config argument)
#               - darwin: Darwin configuration (requires config argument)
#   config    - Specific configuration name (required for nixos/darwin)
#
# Examples:
#   ci-cache-category.sh aarch64-linux packages
#   ci-cache-category.sh aarch64-linux nixos blackphos-nixos
#   ci-cache-category.sh x86_64-linux checks-devshells
#
# Environment:
#   Requires secrets/shared.yaml with CACHIX_CACHE_NAME variable
# ============================================================================

# ============================================================================
# Argument Parsing
# ============================================================================

if [ $# -lt 2 ]; then
    echo "usage: $0 <system> <category> [config]"
    echo ""
    echo "system: x86_64-linux, aarch64-linux, aarch64-darwin"
    echo "category: packages, checks-devshells, home, nixos, darwin"
    echo "config: required for nixos/darwin categories"
    exit 1
fi

SYSTEM="$1"
CATEGORY="$2"
CONFIG="${3:-}"

# ============================================================================
# Validation
# ============================================================================

# Validate system
case "$SYSTEM" in
    x86_64-linux|aarch64-linux|aarch64-darwin)
        ;;
    *)
        echo "error: unsupported system '$SYSTEM'"
        echo "supported: x86_64-linux, aarch64-linux, aarch64-darwin"
        exit 1
        ;;
esac

# Validate category
case "$CATEGORY" in
    packages|checks-devshells|home|nixos|darwin)
        ;;
    *)
        echo "error: unknown category '$CATEGORY'"
        echo "valid: packages, checks-devshells, home, nixos, darwin"
        exit 1
        ;;
esac

# Validate config requirement
if [ "$CATEGORY" = "nixos" ] || [ "$CATEGORY" = "darwin" ]; then
    if [ -z "$CONFIG" ]; then
        echo "error: category '$CATEGORY' requires config argument"
        echo "example: $0 $SYSTEM $CATEGORY blackphos"
        exit 1
    fi
fi

# Get cachix cache name
CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    local title="$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$title"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_step() {
    local step="$1"
    echo ""
    echo "step: $step"
}

report_disk_usage() {
    echo ""
    echo "disk usage:"
    df -h / | tail -1
}

push_to_cachix() {
    local store_paths="$1"

    print_step "querying dependencies and pushing to cachix"
    echo "cache: https://app.cachix.org/cache/$CACHE_NAME"
    echo ""

    # Query all requisites (runtime dependencies and build outputs)
    # Sort and deduplicate, then push to cachix
    echo "$store_paths" | while read -r path; do
        if [ -n "$path" ]; then
            nix-store --query --requisites --include-outputs "$path"
        fi
    done | sort -u | sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME"
}

# ============================================================================
# Category Caching Functions
# ============================================================================

cache_packages() {
    local system="$1"

    print_header "caching packages for $system"

    print_step "discovering packages"
    # Filter packages by meta.hydraPlatforms (nixpkgs convention for CI platform control)
    # - hydraPlatforms unset: include package (default behavior)
    # - hydraPlatforms = []: exclude from all CI builds
    # - hydraPlatforms = ["x86_64-linux"]: include only for that system
    local packages
    packages=$(nix eval ".#packages.$system" --apply '
      pkgs: builtins.filter (name:
        let
          pkg = pkgs.${name};
          hydraPlatforms = pkg.meta.hydraPlatforms or null;
        in
          hydraPlatforms == null || builtins.elem "'"$system"'" hydraPlatforms
      ) (builtins.attrNames pkgs)
    ' --json 2>/dev/null | jq -r '.[]' || echo "")

    if [ -z "$packages" ]; then
        echo "no packages found for $system"
        return 0
    fi

    local count
    count=$(echo "$packages" | wc -l | tr -d ' ')
    echo "found $count packages"

    print_step "building packages"
    local package_targets=""
    while read -r pkg; do
        if [ -n "$pkg" ]; then
            package_targets="$package_targets .#packages.$system.$pkg"
        fi
    done <<< "$packages"

    echo "building all packages with captured paths..."
    local store_paths
    store_paths=$(nix build $package_targets -L --print-out-paths --no-link 2>&1 | grep "^/nix/store/" || echo "")

    if [ -z "$store_paths" ]; then
        echo "error: no store paths captured from build"
        return 1
    fi

    local paths_count
    paths_count=$(echo "$store_paths" | wc -l | tr -d ' ')
    echo "captured $paths_count store paths"

    push_to_cachix "$store_paths"

    echo ""
    echo "successfully cached $count packages"
}

cache_checks_devshells() {
    local system="$1"

    print_header "caching checks and devshells for $system"

    local store_paths=""

    print_step "discovering and building checks"
    local checks
    checks=$(nix eval ".#checks.$system" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo "")

    if [ -n "$checks" ]; then
        local check_targets=""
        while read -r check; do
            if [ -n "$check" ]; then
                check_targets="$check_targets .#checks.$system.$check"
            fi
        done <<< "$checks"

        echo "building checks..."
        local check_paths
        check_paths=$(nix build $check_targets -L --print-out-paths --no-link 2>&1 | grep "^/nix/store/" || echo "")
        store_paths="$store_paths"$'\n'"$check_paths"
    else
        echo "no checks found"
    fi

    print_step "discovering and building devshells"
    local devshells
    devshells=$(nix eval ".#devShells.$system" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo "")

    if [ -n "$devshells" ]; then
        local shell_targets=""
        while read -r shell; do
            if [ -n "$shell" ]; then
                shell_targets="$shell_targets .#devShells.$system.$shell"
            fi
        done <<< "$devshells"

        echo "building devshells..."
        local shell_paths
        shell_paths=$(nix build $shell_targets -L --print-out-paths --no-link 2>&1 | grep "^/nix/store/" || echo "")
        store_paths="$store_paths"$'\n'"$shell_paths"
    else
        echo "no devshells found"
    fi

    # Clean up empty lines
    store_paths=$(echo "$store_paths" | grep -v "^$" || echo "")

    if [ -z "$store_paths" ]; then
        echo "error: no store paths captured"
        return 1
    fi

    push_to_cachix "$store_paths"

    echo ""
    echo "successfully cached checks and devshells"
}

cache_home() {
    local system="$1"

    print_header "caching home configurations for $system"

    print_step "discovering home configurations"
    local homes
    homes=$(nix eval ".#legacyPackages.$system.homeConfigurations" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo "")

    if [ -z "$homes" ]; then
        echo "no home configurations found for $system"
        return 0
    fi

    local count
    count=$(echo "$homes" | wc -l | tr -d ' ')
    echo "found $count home configurations"

    print_step "building home configurations"
    local home_targets=""
    while read -r home; do
        if [ -n "$home" ]; then
            home_targets="$home_targets .#legacyPackages.$system.homeConfigurations.\"$home\".activationPackage"
        fi
    done <<< "$homes"

    echo "building all home configurations..."
    local store_paths
    store_paths=$(nix build $home_targets -L --print-out-paths --no-link 2>&1 | grep "^/nix/store/" || echo "")

    if [ -z "$store_paths" ]; then
        echo "error: no store paths captured from build"
        return 1
    fi

    local paths_count
    paths_count=$(echo "$store_paths" | wc -l | tr -d ' ')
    echo "captured $paths_count store paths"

    push_to_cachix "$store_paths"

    echo ""
    echo "successfully cached $count home configurations"
}

cache_nixos() {
    local config="$1"

    print_header "caching nixos configuration: $config"

    print_step "validating configuration exists"
    if ! nix eval ".#nixosConfigurations.$config" --apply 'x: true' 2>/dev/null; then
        echo "error: nixosConfigurations.$config does not exist"
        return 1
    fi

    local config_system
    config_system=$(nix eval ".#nixosConfigurations.$config.config.nixpkgs.system" --raw 2>/dev/null || echo "unknown")
    echo "configuration system: $config_system"

    print_step "building system"
    echo "building nixosConfigurations.$config.config.system.build.toplevel"

    local store_path
    store_path=$(nix build ".#nixosConfigurations.$config.config.system.build.toplevel" -L --print-out-paths --no-link 2>&1 | grep "^/nix/store/" || echo "")

    if [ -z "$store_path" ]; then
        echo "error: no store path captured from build"
        return 1
    fi

    echo "captured store path: $store_path"

    push_to_cachix "$store_path"

    echo ""
    echo "successfully cached nixos configuration: $config"
}

cache_darwin() {
    local config="$1"

    print_header "caching darwin configuration: $config"

    print_step "validating configuration exists"
    if ! nix eval ".#darwinConfigurations.$config" --apply 'x: true' 2>/dev/null; then
        echo "error: darwinConfigurations.$config does not exist"
        return 1
    fi

    local config_system
    config_system=$(nix eval ".#darwinConfigurations.$config.pkgs.stdenv.hostPlatform.system" --raw 2>/dev/null || echo "unknown")
    echo "configuration system: $config_system"

    print_step "building system"
    echo "building darwinConfigurations.$config.system"

    local store_path
    store_path=$(nix build ".#darwinConfigurations.$config.system" -L --print-out-paths --no-link 2>&1 | grep "^/nix/store/" || echo "")

    if [ -z "$store_path" ]; then
        echo "error: no store path captured from build"
        return 1
    fi

    echo "captured store path: $store_path"

    push_to_cachix "$store_path"

    echo ""
    echo "successfully cached darwin configuration: $config"
}

# ============================================================================
# Main Execution
# ============================================================================

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              CI Category Cacher                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "system: $SYSTEM"
echo "category: $CATEGORY"
if [ -n "$CONFIG" ]; then
    echo "config: $CONFIG"
fi
echo "cache: https://app.cachix.org/cache/$CACHE_NAME"
echo ""

# Record start time and disk usage
START_TIME=$(date +%s)
echo "start time: $(date)"
report_disk_usage

# Execute appropriate caching function
case "$CATEGORY" in
    packages)
        cache_packages "$SYSTEM"
        ;;
    checks-devshells)
        cache_checks_devshells "$SYSTEM"
        ;;
    home)
        cache_home "$SYSTEM"
        ;;
    nixos)
        cache_nixos "$CONFIG"
        ;;
    darwin)
        cache_darwin "$CONFIG"
        ;;
esac

CACHE_STATUS=$?

# Report completion
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
print_header "caching summary"
echo ""
echo "category: $CATEGORY"
if [ -n "$CONFIG" ]; then
    echo "config: $CONFIG"
fi
echo "duration: ${DURATION}s"
echo "cache: https://app.cachix.org/cache/$CACHE_NAME"
report_disk_usage
echo ""

if [ $CACHE_STATUS -eq 0 ]; then
    echo "status: success"
    echo ""
    echo "all store paths and dependencies pushed to cachix"
    echo "ci jobs will now fetch from cache instead of rebuilding"
    exit 0
else
    echo "status: failed"
    exit 1
fi
