{ inputs, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules # Enable flake.modules merging
    inputs.nix-unit.modules.flake.default
    # Note: clan-core imported in modules/clan/core.nix
  ];
}
