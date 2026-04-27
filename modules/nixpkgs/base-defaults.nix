# Shared nixpkgs defaults applied to every NixOS and nix-darwin machine
#
# Contributes to both flake.modules.darwin.base and flake.modules.nixos.base,
# which every machine imports via the `base` flakeModule in its
# modules/machines/<class>/<host>/default.nix.
#
# Settings:
#   - nixpkgs.config.allowUnfree: required for proprietary packages
#     (copilot-language-server, NVIDIA drivers, casks, etc.)
#   - nixpkgs.overlays: wires the composed flake.overlays.default into nixpkgs
#     construction so machines see the overlay-provided attributes (e.g.
#     openclaw-gateway, beads, mactop, channels).
#
# Out of scope: allowUnfree writes in modules/nixpkgs/per-system.nix,
# modules/nixpkgs/overlays/channels.nix, modules/home/configurations.nix,
# modules/darwin/nix-settings.nix, and modules/nixos/nvidia.nix live in
# different evaluation contexts (perSystem pkgs, child-channel imports,
# home-manager pkgs, darwin-specific nix.settings, NVIDIA-only override).
{ inputs, ... }:
let
  defaults = {
    nixpkgs.config.allowUnfree = true;
    nixpkgs.overlays = [ inputs.self.overlays.default ];
  };
in
{
  flake.modules.darwin.base = defaults;
  flake.modules.nixos.base = defaults;
}
