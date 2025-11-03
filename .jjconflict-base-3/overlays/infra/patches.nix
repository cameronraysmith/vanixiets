# List of patches to apply to nixpkgs via applyPatches
#
# Format: Each entry should be compatible with fetchpatch:
# {
#   url = "https://github.com/NixOS/nixpkgs/pull/XXXXX.patch";
#   hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
# }
#
# Usage: Applied in overlays/inputs.nix to create final.patched nixpkgs (Phase 2)
#
# Example (when needed):
# [
#   {
#     url = "https://github.com/NixOS/nixpkgs/pull/123456.patch";
#     hash = "sha256-base64hash...=";
#   }
# ]
#
# Phase 1: Empty list (infrastructure only)
[ ]
