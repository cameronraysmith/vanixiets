# Unified AI agent skills for claude-code, codex, and opencode
#
# Skills are partitioned into core (shared across all agents), claude
# (Claude Code-only), and third-party (from flake inputs). Third-party
# flake inputs coerce to store path strings (not Nix paths), so modules
# that check lib.isPath need home.file entries instead of skills options.
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      lib,
      flake,
      ...
    }:
    let
      # Scan a directory for skill subdirectories (one level deep).
      readSkillsFrom =
        dir:
        lib.mapAttrs (name: _: dir + "/${name}") (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)
        );

      coreSkills = readSkillsFrom ./src/core;
      claudeSkills = readSkillsFrom ./src/claude;

    in
    {
      programs.claude-code.skills = coreSkills // claudeSkills;
      programs.codex.skills = coreSkills;
      programs.opencode.skills = coreSkills;
    };
}
