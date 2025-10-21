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
    # Step 2: Build configuration (auto-detects home-manager vs system)
    echo "Step 2/2: Building configuration (without activation)..."

    # Check for home-manager-only configuration first (matches just activate logic)
    if [ -f ./configurations/home/$USER@$(hostname).nix ]; then
        echo "Detected home-manager-only configuration: $USER@$(hostname)"
        # Use nom (nix output manager) for better build output if available
        if command -v nom &> /dev/null; then
            if nom build '.#homeConfigurations.'"$USER@$(hostname)"'.activationPackage'; then
                echo "✓ Home-manager configuration builds successfully"
            else
                echo "✗ Home-manager build failed"
                FAILED=1
            fi
        else
            if nix build '.#homeConfigurations.'"$USER@$(hostname)"'.activationPackage'; then
                echo "✓ Home-manager configuration builds successfully"
            else
                echo "✗ Home-manager build failed"
                FAILED=1
            fi
        fi
    elif command -v darwin-rebuild &> /dev/null; then
        # Darwin system configuration
        echo "Detected darwin system configuration: $(hostname)"
        # Use nom (nix output manager) for better build output if available
        if command -v nom &> /dev/null; then
            if nom build '.#darwinConfigurations.'"$(hostname)"'.system'; then
                echo "✓ Darwin system builds successfully"
            else
                echo "✗ Darwin build failed"
                FAILED=1
            fi
        else
            if darwin-rebuild build --flake .; then
                echo "✓ Darwin system builds successfully"
            else
                echo "✗ Darwin build failed"
                FAILED=1
            fi
        fi
    elif command -v nixos-rebuild &> /dev/null; then
        # NixOS system configuration
        echo "Detected NixOS system configuration: $(hostname)"
        if nixos-rebuild build --flake .; then
            echo "✓ NixOS system builds successfully"
        else
            echo "✗ NixOS build failed"
            FAILED=1
        fi
    else
        echo "✗ Could not detect configuration type"
        echo "  Expected one of:"
        echo "    - ./configurations/home/$USER@$(hostname).nix (home-manager)"
        echo "    - darwin-rebuild command (nix-darwin)"
        echo "    - nixos-rebuild command (NixOS)"
        FAILED=1
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
    echo "  2. Check incident response guide: docs/notes/nixpkgs-incident-response.md"
    echo "  3. Or use incident response prompt: @modules/home/all/tools/claude-code/commands/nixpkgs/incident-response.md"
    exit 1
fi
