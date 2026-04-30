# nix-index-database home-manager module integration.
# Contributes inputs.nix-index-database.homeModules.nix-index to the core
# aggregate via flake-parts native multi-writer merge (same pattern as
# lazyvim.nix and catppuccin.nix).
{ ... }:
{
  flake.modules.homeManager.core =
    { flake, ... }:
    {
      imports = [ flake.inputs.nix-index-database.homeModules.nix-index ];
    };
}
