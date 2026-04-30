# Terminal profile.
#
# Bundles the home-manager interactive terminal helpers aggregated
# under `flake.modules.homeManager.terminal` (autojump, bat, btop,
# direnv, fzf, htop, jq, lsd, nix-index, nnn, zoxide). Declared as a
# typed entry under `flake.profiles.homeManager` (registered by
# `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.terminal = {
    description = "Interactive terminal helpers (autojump, bat, btop, direnv, fzf, htop, jq, lsd, nix-index, nnn, zoxide).";
    includes = [ config.flake.modules.homeManager.terminal ];
  };
}
