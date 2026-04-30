# Shell environment profile.
#
# Bundles the home-manager modules covering shell tooling (atuin, bash,
# fish, nushell, tmux, yazi, zellij). Declared as a typed entry under
# `flake.profiles.homeManager` (registered by `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.shell = {
    description = "Shell environment profile (atuin, bash, fish, nushell, tmux, yazi, zellij).";
    includes = [ config.flake.modules.homeManager.shell ];
  };
}
