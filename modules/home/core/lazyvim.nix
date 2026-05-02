# LazyVim home-manager module integration.
{ ... }:
{
  flake.modules.homeManager.core =
    { flake, ... }:
    {
      imports = [ flake.inputs.lazyvim-nix.homeManagerModules.default ];
    };
}
