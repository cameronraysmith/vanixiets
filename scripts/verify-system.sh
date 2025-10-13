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
    # Step 2: Build system configuration
    echo "Step 2/2: Building system configuration (without activation)..."

    if command -v darwin-rebuild &> /dev/null; then
        if darwin-rebuild build --flake .; then
            echo "✓ Darwin system builds successfully"
        else
            echo "✗ Darwin build failed"
            FAILED=1
        fi
    elif command -v nixos-rebuild &> /dev/null; then
        if nixos-rebuild build --flake .; then
            echo "✓ NixOS system builds successfully"
        else
            echo "✗ NixOS build failed"
            FAILED=1
        fi
    else
        echo "⚠ Could not detect darwin-rebuild or nixos-rebuild"
        echo "  For home-manager only, run:"
        echo "    nix build '.#homeConfigurations.\$USER@\$(hostname).activationPackage'"
        echo "  Skipping system build verification"
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
