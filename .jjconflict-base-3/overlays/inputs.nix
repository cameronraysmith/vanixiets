# Multi-channel nixpkgs access layer
#
# Exports:
#   - inputs: Raw flake inputs reference
#   - nixpkgs: Main nixpkgs (unstable) - for reference
#   - patched: nixpkgs with patches from infra/patches.nix applied
#   - stable: OS-specific stable nixpkgs (darwin-stable or linux-stable)
#   - unstable: Explicit unstable nixpkgs (same as nixpkgs, for clarity)
#
# Usage in other overlays or configurations:
#   pkgs.stable.packageName       # Get package from stable channel
#   pkgs.patched.packageName      # Get package from patched nixpkgs
#   pkgs.unstable.packageName     # Explicit unstable reference
#
{ flake, ... }:
final: prev:
let
  inherit (flake) inputs;
  # Access lib through inputs.self since nixos-unified's specialArgsFor.common doesn't include lib directly
  lib' = inputs.self.lib;
  os = lib'.systemOs prev.stdenv.hostPlatform.system;

  # Shared nixpkgs configuration
  # Must match configuration in flake.nix perSystem
  nixpkgsConfig = {
    system = prev.stdenv.hostPlatform.system;
    config = {
      allowUnfree = true;
    };
  };
in
{
  # Raw inputs access
  inherit inputs;

  # Main nixpkgs (unstable) - imported for reference
  # Note: prev is already from nixpkgs, this is explicit
  nixpkgs = import inputs.nixpkgs nixpkgsConfig;

  # Patched nixpkgs (with patches from infra/patches.nix applied via applyPatches)
  # NOTE: infra/ subdirectory is intentional (Phase 1 architectural decision)
  patched = import (prev.applyPatches {
    name = "nixpkgs-patched";
    src = inputs.nixpkgs.outPath;
    patches = map prev.fetchpatch (import ./infra/patches.nix);
  }) nixpkgsConfig;

  # Stable channel (OS-specific: darwin-stable or linux-stable)
  # Uses lib'.systemInput to select appropriate input
  stable = import (lib'.systemInput {
    inherit os;
    name = "nixpkgs";
    channel = "stable";
  }) nixpkgsConfig;

  # Explicit unstable (for clarity when pulling from unstable)
  unstable = import inputs.nixpkgs nixpkgsConfig;
}
