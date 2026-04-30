# Tools profile.
#
# Bundles the broader workstation tooling aggregated under
# `flake.modules.homeManager.tools` (atuin format, awscli, beads
# registry, bottom, dolt config, gpg, k9s, macchina, nix, nixpkgs,
# pandoc, tealdeer, texlive, typst, plus claude-code hooks). Declared
# as a typed entry under `flake.profiles.homeManager` (registered by
# `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.tools = {
    description = "Workstation tooling (atuin, awscli, beads, bottom, dolt, gpg, k9s, macchina, nix, nixpkgs, pandoc, tealdeer, texlive, typst, claude-code hooks).";
    includes = [ config.flake.modules.homeManager.tools ];
  };
}
