# Development tooling profile.
#
# Bundles the home-manager modules used by developer-focused users
# (ghostty, gui-apps, helix, incus, radicle). Declared as a typed
# entry under `flake.profiles.homeManager` (registered by
# `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.development = {
    description = "Development tooling profile (ghostty, gui-apps, helix, incus, radicle).";
    includes = [
      config.flake.modules.homeManager.development
    ];
  };
}
