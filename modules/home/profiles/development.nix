# Development tooling profile.
#
# Bundles the home-manager modules used by developer-focused users
# (ghostty, gui-apps, helix, incus, radicle) along with the LazyVim
# Neovim distribution from the `lazyvim-nix` flake input. Declared as a
# typed entry under `flake.profiles.homeManager` (registered by
# `modules/lib/profiles.nix`).
{
  inputs,
  config,
  lib,
  ...
}:
{
  flake.profiles.homeManager.development = {
    description = "Development tooling profile (ghostty, gui-apps, helix, incus, radicle, lazyvim).";
    includes = [
      config.flake.modules.homeManager.development
      inputs.lazyvim-nix.homeManagerModules.default
    ];
  };
}
