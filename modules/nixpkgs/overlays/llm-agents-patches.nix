# Patches for llm-agents flake packages
#
# llm-agents.inputs.nixpkgs.follows = "nixpkgs" inherits breaking changes from nixpkgs
#
# Current patches:
# - gemini-cli: pin nodejs_22 (mirrors nixpkgs fix 73771abf0a90)
#   Issue: nodejs 24's npm 11 cache handling breaks npmDepsHash validation
#   Upstream: https://github.com/numtide/llm-agents.nix/issues/1644
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      # gemini-cli with nodejs_22 pin
      # Rebuild package from source with nodejs_22 to fix npm 11 cache breakage
      # overrideAttrs doesn't work because nodejs is baked into builder at definition time
      # Must override buildNpmPackage's default nodejs in the callPackage scope
      gemini-cli =
        let
          buildNpmPackage = final.buildNpmPackage.override { nodejs = final.nodejs_22; };
        in
        final.callPackage "${inputs.llm-agents}/packages/gemini-cli/package.nix" {
          inherit buildNpmPackage;
          darwinOpenptyHook = final.callPackage "${inputs.llm-agents}/packages/darwinOpenptyHook/package.nix" { };
        };
    })
  ];
}
