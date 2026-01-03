#!/usr/bin/env bash
# ============================================================================
# CI Shared Infrastructure
# ============================================================================
# Common functions and utilities sourced by ci-build-category.sh and
# ci-cache-category.sh for GitHub Actions matrix jobs.
#
# This file is intended to be sourced, not executed directly.
# ============================================================================

# ============================================================================
# Argument Parsing
# ============================================================================

parse_arguments() {
    if [ $# -lt 2 ]; then
        echo "usage: $(basename "$0") <system> <category> [config]"
        echo ""
        echo "system: x86_64-linux, aarch64-linux, aarch64-darwin"
        echo "category: packages, checks-devshells, home, nixos, darwin"
        echo "config: required for nixos/darwin categories"
        exit 1
    fi

    SYSTEM="$1"
    CATEGORY="$2"
    CONFIG="${3:-}"
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_system() {
    case "$SYSTEM" in
        x86_64-linux|aarch64-linux|aarch64-darwin)
            ;;
        *)
            echo "error: unsupported system '$SYSTEM'"
            echo "supported: x86_64-linux, aarch64-linux, aarch64-darwin"
            exit 1
            ;;
    esac
}

validate_category() {
    case "$CATEGORY" in
        packages|checks-devshells|home|nixos|darwin)
            ;;
        *)
            echo "error: unknown category '$CATEGORY'"
            echo "valid: packages, checks-devshells, home, nixos, darwin"
            exit 1
            ;;
    esac
}

validate_config_requirement() {
    if [ "$CATEGORY" = "nixos" ] || [ "$CATEGORY" = "darwin" ]; then
        if [ -z "$CONFIG" ]; then
            echo "error: category '$CATEGORY' requires config argument"
            echo "example: $(basename "$0") $SYSTEM $CATEGORY blackphos"
            exit 1
        fi
    fi
}

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

print_ci_header() {
    local script_type="$1"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║              CI Category $script_type                              ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "system: $SYSTEM"
    echo "category: $CATEGORY"
    if [ -n "$CONFIG" ]; then
        echo "config: $CONFIG"
    fi
}

# ============================================================================
# Discovery Functions
# ============================================================================

discover_packages() {
    local system="$1"
    # Filter packages by meta.hydraPlatforms (nixpkgs convention for CI platform control)
    # - hydraPlatforms unset: include package (default behavior)
    # - hydraPlatforms = []: exclude from all CI builds
    # - hydraPlatforms = ["x86_64-linux"]: include only for that system
    nix eval ".#packages.$system" --apply '
      pkgs: builtins.filter (name:
        let
          pkg = pkgs.${name};
          hydraPlatforms = pkg.meta.hydraPlatforms or null;
        in
          hydraPlatforms == null || builtins.elem "'"$system"'" hydraPlatforms
      ) (builtins.attrNames pkgs)
    ' --json 2>/dev/null | jq -r '.[]' || echo ""
}

discover_checks() {
    local system="$1"
    nix eval ".#checks.$system" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo ""
}

discover_devshells() {
    local system="$1"
    nix eval ".#devShells.$system" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo ""
}

discover_homes() {
    local system="$1"
    nix eval ".#legacyPackages.$system.homeConfigurations" --apply 'builtins.attrNames' --json 2>/dev/null | jq -r '.[]' || echo ""
}
