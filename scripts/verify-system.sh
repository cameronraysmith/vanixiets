#!/usr/bin/env bash
# Verify system configuration builds after updates (run before activate)
#
# Usage: ./scripts/verify-system.sh
#
# Exit codes:
#   0 - All verification passed
#   1 - Verification failed

set -uo pipefail

FAILED=0

echo "=== Verifying nix-config after updates ==="
echo ""

# Step 1: Flake check
echo "Step 1/2: Running flake check..."
if nix flake check; then
    echo "✓ Flake check passed"
else
    echo "✗ Flake check failed"
    FAILED=1
fi
echo ""

if [ $FAILED -eq 0 ]; then
    # Step 2: Build configuration (auto-detects platform)
    echo "Step 2/2: Building configuration (without activation)..."

    if [[ "$(uname -s)" == "Darwin" ]]; then
        HOSTNAME=$(hostname -s)
        echo "Detected darwin system configuration: $HOSTNAME"
        if command -v nom &> /dev/null; then
            if nom build ".#darwinConfigurations.$HOSTNAME.system"; then
                echo "✓ Darwin system builds successfully"
            else
                echo "✗ Darwin build failed"
                FAILED=1
            fi
        else
            if nix build ".#darwinConfigurations.$HOSTNAME.system"; then
                echo "✓ Darwin system builds successfully"
            else
                echo "✗ Darwin build failed"
                FAILED=1
            fi
        fi
    elif [ -f /etc/NIXOS ]; then
        HOSTNAME=$(hostname)
        echo "Detected NixOS system configuration: $HOSTNAME"
        if command -v nom &> /dev/null; then
            if nom build ".#nixosConfigurations.$HOSTNAME.config.system.build.toplevel"; then
                echo "✓ NixOS system builds successfully"
            else
                echo "✗ NixOS build failed"
                FAILED=1
            fi
        else
            if nix build ".#nixosConfigurations.$HOSTNAME.config.system.build.toplevel"; then
                echo "✓ NixOS system builds successfully"
            else
                echo "✗ NixOS build failed"
                FAILED=1
            fi
        fi
    else
        echo "Detected home-manager-only configuration: $USER"
        SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
        if command -v nom &> /dev/null; then
            if nom build ".#legacyPackages.$SYSTEM.homeConfigurations.$USER.activationPackage"; then
                echo "✓ Home-manager configuration builds successfully"
            else
                echo "✗ Home-manager build failed"
                FAILED=1
            fi
        else
            if nix build ".#legacyPackages.$SYSTEM.homeConfigurations.$USER.activationPackage"; then
                echo "✓ Home-manager configuration builds successfully"
            else
                echo "✗ Home-manager build failed"
                FAILED=1
            fi
        fi
    fi
fi

echo ""
if [ $FAILED -eq 0 ]; then
    echo "=== ✓ All verification passed ==="
    echo "Safe to activate: just activate"
    exit 0
else
    echo "=== ✗ Verification failed ==="
    echo ""
    echo "Next steps:"
    echo "  1. Review error output above"
    echo "  2. Check handling broken packages guide: docs/guides/handling-broken-packages.md"
    echo "  3. Or use broken package prompt: @modules/home/all/tools/claude-code/commands/nixpkgs/broken-package.md"
    exit 1
fi
