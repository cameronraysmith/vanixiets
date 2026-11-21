{ inputs, ... }:
{
  imports = [
    inputs.flake-parts.flakeModules.modules # Enable flake.modules merging
    # Note: clan-core imported in modules/clan/core.nix
  ];
}
