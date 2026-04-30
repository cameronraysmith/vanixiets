# Core home environment profile.
#
# Bundles the home-manager modules shared by every user (bitwarden,
# catppuccin, fonts, session-variables, ssh, xdg) along with the
# LazyVim Neovim distribution from `lazyvim-nix` and the prebuilt
# nix-index database integration from `nix-index-database` (provides
# `nix-locate` and the `comma` command-not-found wrapper). Declared as
# a typed entry under `flake.profiles.homeManager` (registered by
# `modules/lib/profiles.nix`).
{
  inputs,
  config,
  lib,
  ...
}:
{
  flake.profiles.homeManager.core = {
    description = "Core home environment shared by all users (bitwarden, catppuccin, fonts, session-variables, ssh, xdg) plus lazyvim editor and nix-index database.";
    includes = [
      config.flake.modules.homeManager.core
      inputs.lazyvim-nix.homeManagerModules.default
      inputs.nix-index-database.homeModules.nix-index
    ];
  };
}
