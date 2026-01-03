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

# Source shared infrastructure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ci-shared.sh"

# Parse and validate arguments
parse_arguments "$@"
validate_system
validate_category
validate_config_requirement

# ============================================================================
# Category Build Functions
# ============================================================================

build_packages() {
    local system="$1"

    print_header "building packages for $system"

    print_step "discovering packages"
    local packages
    packages=$(discover_packages "$system")

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
    checks=$(discover_checks "$system")

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
    devshells=$(discover_devshells "$system")

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
    homes=$(discover_homes "$system")

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

print_ci_header "Builder"
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
