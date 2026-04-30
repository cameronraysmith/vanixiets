# Terminal profile.
#
# Bundles the home-manager interactive terminal helpers aggregated
# under `flake.modules.homeManager.terminal` (autojump, bat, btop,
# direnv, fzf, htop, jq, lsd, nix-index, nnn, zoxide) along with the
# prebuilt nix-index database integration from the `nix-index-database`
# flake input (provides `nix-locate` and the `comma` command-not-found
# wrapper). Declared as a typed entry under `flake.profiles.homeManager`
# (registered by `modules/lib/profiles.nix`).
{
  inputs,
  config,
  lib,
  ...
}:
{
  flake.profiles.homeManager.terminal = {
    description = "Interactive terminal helpers (autojump, bat, btop, direnv, fzf, htop, jq, lsd, nix-index, nnn, zoxide) plus prebuilt nix-index database.";
    includes = [
      config.flake.modules.homeManager.terminal
      inputs.nix-index-database.homeModules.nix-index
    ];
  };
}
