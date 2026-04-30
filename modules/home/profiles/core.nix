# Core home environment profile.
#
# Bundles the home-manager modules shared by every user (bitwarden,
# catppuccin, fonts, session-variables, ssh, xdg). Declared as a typed
# entry under `flake.profiles.homeManager` (registered by
# `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.core = {
    description = "Core home environment shared by all users (bitwarden, catppuccin, fonts, session-variables, ssh, xdg).";
    includes = [ config.flake.modules.homeManager.core ];
  };
}
