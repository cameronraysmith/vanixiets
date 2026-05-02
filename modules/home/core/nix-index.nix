# nix-index-database home-manager module integration.
{ ... }:
{
  flake.modules.homeManager.core =
    { flake, ... }:
    {
      imports = [ flake.inputs.nix-index-database.homeModules.nix-index ];
    };
}
