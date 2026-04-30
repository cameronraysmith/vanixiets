# AI agent documentation profile.
#
# Bundles the `programs.agents-md` option module aggregated under
# `flake.modules.homeManager.agents-md`, which generates unified
# CLAUDE.md / AGENTS.md / GEMINI.md / CRUSH.md / OPENCODE.md files
# from shared configuration. Declared as a typed entry under
# `flake.profiles.homeManager` (registered by
# `modules/lib/profiles.nix`).
{ config, lib, ... }:
{
  flake.profiles.homeManager.agents-md = {
    description = "AI agent documentation generation (programs.agents-md option producing CLAUDE.md, AGENTS.md, GEMINI.md, CRUSH.md, OPENCODE.md).";
    includes = [ config.flake.modules.homeManager.agents-md ];
  };
}
