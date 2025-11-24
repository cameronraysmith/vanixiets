# Neovim with LazyVim configuration
# Pattern A: Directory module importing lazyvim.nix
{ ... }:
{
  imports = [
    ./lazyvim.nix
  ];
}
