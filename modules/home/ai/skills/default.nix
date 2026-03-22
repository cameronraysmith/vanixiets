# Unified AI agent skills for claude-code, codex, opencode, and droid
#
# Skills are partitioned into core (shared across all agents), claude
# (Claude Code-only), and third-party (from flake inputs). Third-party
# flake inputs coerce to store path strings (not Nix paths), so modules
# that check lib.isPath need home.file entries instead of skills options.
#
# Agents with programs.*.skills options (claude-code, codex, opencode) use
# the module-native mechanism. Droid lacks a home-manager module, so core
# skills are symlinked directly via home.file into ~/.factory/skills/.
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

      # Droid: no programs.droid.skills option exists, symlink directly
      home.file = lib.mapAttrs' (
        name: path:
        lib.nameValuePair ".factory/skills/${name}" {
          source = path;
          recursive = true;
        }
      ) coreSkills;
    };
}
