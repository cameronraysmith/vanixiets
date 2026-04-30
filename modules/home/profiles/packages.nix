# Packages profile.
#
# Bundles the home-manager package sets aggregated under
# `flake.modules.homeManager.packages` (bioinformatics, compute,
# database, development, platform, publishing, security, terminal
# packages, plus shared shell aliases). Declared as a typed entry under
# `flake.profiles.homeManager` (registered by `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.packages = {
    description = "Curated home-manager package sets (bioinformatics, compute, database, development, platform, publishing, security, terminal) and shared shell aliases.";
    includes = [ config.flake.modules.homeManager.packages ];
  };
}
