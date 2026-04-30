# AI agent tooling profile.
#
# Bundles the home-manager modules for AI agent integrations (codex,
# opencode, skills). Declared as a typed entry under
# `flake.profiles.homeManager` (registered by `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.ai = {
    description = "AI agent tooling profile (codex, opencode, skills).";
    includes = [ config.flake.modules.homeManager.ai ];
  };
}
