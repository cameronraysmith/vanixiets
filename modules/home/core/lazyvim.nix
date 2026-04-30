# LazyVim home-manager module integration.
# Contributes inputs.lazyvim-nix.homeManagerModules.default to the core
# aggregate via flake-parts native multi-writer merge (same pattern as
# catppuccin.nix).
{ ... }:
{
  flake.modules.homeManager.core =
    { flake, ... }:
    {
      imports = [ flake.inputs.lazyvim-nix.homeManagerModules.default ];
    };
}
