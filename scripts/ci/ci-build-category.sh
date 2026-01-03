#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# CI Category Builder
# ============================================================================
# Build specific categories of flake outputs for GitHub Actions matrix jobs.
# Designed to minimize disk space usage per job by building subsets of outputs.
#
# Usage:
#   ci-build-category.sh <system> <category> [config]
#
# Arguments:
#   system    - Target system (x86_64-linux, aarch64-linux, aarch64-darwin)
#   category  - Output category to build:
#               - packages: all packages for system
#               - checks-devshells: checks and devshells (combined for efficiency)
#               - home: all home configurations for system
#               - nixos: NixOS configuration (requires config argument)
#               - darwin: Darwin configuration (requires config argument)
#   config    - Specific configuration name (required for nixos/darwin)
#
# Examples:
#   ci-build-category.sh x86_64-linux packages
#   ci-build-category.sh x86_64-linux nixos blackphos-nixos
#   ci-build-category.sh aarch64-darwin darwin stibnite
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

# ============================================================================
# Category Build Functions
# ============================================================================

build_packages() {
    local system="$1"

    print_header "building packages for $system"

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
    local failed=0
    echo "$packages" | while read -r pkg; do
        if [ -n "$pkg" ]; then
            echo ""
            echo "building packages.$system.$pkg"
            if ! nix build ".#packages.$system.$pkg" -L --no-link; then
                echo "failed to build packages.$system.$pkg"
                failed=$((failed + 1))
            fi
        fi
    done

    if [ $failed -gt 0 ]; then
        echo ""
        echo "failed to build $failed packages"
        return 1
    fi

    echo ""
    echo "successfully built $count packages"
}

build_checks_devshells() {
    local system="$1"

    print_header "building checks and devshells for $system"

    local failed=0

    print_step "discovering checks"
    local checks
    checks=$(nix eval ".#checks.$system" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo "")

    if [ -n "$checks" ]; then
        local check_count
        check_count=$(echo "$checks" | wc -l | tr -d ' ')
        echo "found $check_count checks"

        echo "$checks" | while read -r check; do
            if [ -n "$check" ]; then
                echo ""
                echo "building checks.$system.$check"
                if ! nix build ".#checks.$system.$check" -L --no-link; then
                    echo "failed to build checks.$system.$check"
                    failed=$((failed + 1))
                fi
            fi
        done
    else
        echo "no checks found"
    fi

    print_step "discovering devshells"
    local devshells
    devshells=$(nix eval ".#devShells.$system" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo "")

    if [ -n "$devshells" ]; then
        local shell_count
        shell_count=$(echo "$devshells" | wc -l | tr -d ' ')
        echo "found $shell_count devshells"

        echo "$devshells" | while read -r shell; do
            if [ -n "$shell" ]; then
                echo ""
                echo "building devShells.$system.$shell"
                if ! nix build ".#devShells.$system.$shell" -L --no-link; then
                    echo "failed to build devShells.$system.$shell"
                    failed=$((failed + 1))
                fi
            fi
        done
    else
        echo "no devshells found"
    fi

    if [ $failed -gt 0 ]; then
        echo ""
        echo "failed to build $failed items"
        return 1
    fi

    echo ""
    echo "successfully built checks and devshells"
}

build_home() {
    local system="$1"

    print_header "building home configurations for $system"

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
    local failed=0
    echo "$homes" | while read -r home; do
        if [ -n "$home" ]; then
            echo ""
            echo "building legacyPackages.$system.homeConfigurations.$home"
            if ! nix build ".#legacyPackages.$system.homeConfigurations.\"$home\".activationPackage" -L --no-link; then
                echo "failed to build home configuration: $home"
                failed=$((failed + 1))
            fi
        fi
    done

    if [ $failed -gt 0 ]; then
        echo ""
        echo "failed to build $failed home configurations"
        return 1
    fi

    echo ""
    echo "successfully built $count home configurations"
}

build_nixos() {
    local config="$1"

    print_header "building nixos configuration: $config"

    print_step "validating configuration exists"
    if ! nix eval ".#nixosConfigurations.$config" --apply 'x: true' 2>/dev/null; then
        echo "error: nixosConfigurations.$config does not exist"
        return 1
    fi

    local config_system
    config_system=$(nix eval ".#nixosConfigurations.$config.config.nixpkgs.system" --raw 2>/dev/null || echo "unknown")
    echo "configuration system: $config_system"

    print_step "building system"
    echo ""
    echo "building nixosConfigurations.$config.config.system.build.toplevel"
    if ! nix build ".#nixosConfigurations.$config.config.system.build.toplevel" -L --no-link; then
        echo "failed to build nixos configuration: $config"
        return 1
    fi

    echo ""
    echo "successfully built nixos configuration: $config"
}

build_darwin() {
    local config="$1"

    print_header "building darwin configuration: $config"

    print_step "validating configuration exists"
    if ! nix eval ".#darwinConfigurations.$config" --apply 'x: true' 2>/dev/null; then
        echo "error: darwinConfigurations.$config does not exist"
        return 1
    fi

    local config_system
    config_system=$(nix eval ".#darwinConfigurations.$config.pkgs.stdenv.hostPlatform.system" --raw 2>/dev/null || echo "unknown")
    echo "configuration system: $config_system"

    print_step "building system"
    echo ""
    echo "building darwinConfigurations.$config.system"
    if ! nix build ".#darwinConfigurations.$config.system" -L --no-link; then
        echo "failed to build darwin configuration: $config"
        return 1
    fi

    echo ""
    echo "successfully built darwin configuration: $config"
}

# ============================================================================
# Main Execution
# ============================================================================

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              CI Category Builder                              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "system: $SYSTEM"
echo "category: $CATEGORY"
if [ -n "$CONFIG" ]; then
    echo "config: $CONFIG"
fi
echo ""

# Record start time and disk usage
START_TIME=$(date +%s)
echo "start time: $(date)"
report_disk_usage

# Execute appropriate build function
case "$CATEGORY" in
    packages)
        build_packages "$SYSTEM"
        ;;
    checks-devshells)
        build_checks_devshells "$SYSTEM"
        ;;
    home)
        build_home "$SYSTEM"
        ;;
    nixos)
        build_nixos "$CONFIG"
        ;;
    darwin)
        build_darwin "$CONFIG"
        ;;
esac

BUILD_STATUS=$?

# Report completion
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
print_header "build summary"
echo ""
echo "category: $CATEGORY"
if [ -n "$CONFIG" ]; then
    echo "config: $CONFIG"
fi
echo "duration: ${DURATION}s"
report_disk_usage
echo ""

if [ $BUILD_STATUS -eq 0 ]; then
    echo "status: success"
    exit 0
else
    echo "status: failed"
    exit 1
fi
