#!/usr/bin/env bash
# Inspect a nix derivation without building it

set -euo pipefail

NIX_CMD="nix --accept-flake-config"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <flake-ref>"
    echo "Example: $0 .#nvim-treesitter-main"
    exit 1
fi

FLAKE_REF="$1"

echo "=== Basic Info ==="
$NIX_CMD eval "${FLAKE_REF}.name" --raw && echo
$NIX_CMD eval "${FLAKE_REF}.version" --raw 2>/dev/null && echo || true
$NIX_CMD eval "${FLAKE_REF}.pname" --raw 2>/dev/null && echo || true

echo -e "\n=== Source ==="
$NIX_CMD derivation show "${FLAKE_REF}" | jq -r '.[] | .env.src // "unknown"' | head -1

echo -e "\n=== Build Phases ==="
echo "postPatch:"
$NIX_CMD eval "${FLAKE_REF}.postPatch" --raw 2>/dev/null | sed 's/^/  /' || echo "  (default)"
echo "buildPhase:"
$NIX_CMD eval "${FLAKE_REF}.buildPhase" --raw 2>/dev/null | head -c 100 | sed 's/^/  /' || echo "  (default)"

echo -e "\n=== Neovim Plugin Attributes ==="
echo "nvimSkipModules:"
$NIX_CMD eval "${FLAKE_REF}.nvimSkipModules" --json 2>/dev/null | jq -r '.[]' | sed 's/^/  - /' || echo "  (none)"
echo "nvimRequireCheck:"
$NIX_CMD eval "${FLAKE_REF}.nvimRequireCheck" --json 2>/dev/null | jq -r '.[]' | sed 's/^/  - /' || echo "  (auto-discover)"

echo -e "\n=== Passthru Attributes ==="
$NIX_CMD eval "${FLAKE_REF}.passthru" --apply 'x: builtins.attrNames x' 2>/dev/null || echo "No passthru"

echo -e "\n=== Dependencies Count ==="
$NIX_CMD derivation show "${FLAKE_REF}" | jq -r '.[] |
  "Build dependencies: " + (.inputDrvs | length | tostring) + "\n" +
  "Outputs: " + (.outputs | keys | join(", "))'

echo -e "\n=== Would Build ==="
$NIX_CMD build "${FLAKE_REF}" --dry-run 2>&1 | grep -E "will be (built|fetched)" || echo "Nothing new to build"
