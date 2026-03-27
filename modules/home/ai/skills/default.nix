# Unified AI agent skills for claude-code, codex, opencode, and droid
#
# Skills are partitioned into core (shared across all agents), claude
# (Claude Code-only), and third-party (from flake inputs). Third-party
# flake inputs coerce to store path strings (not Nix paths), so modules
# that check lib.isPath need home.file entries instead of skills options.
#
# Agents with programs.*.skills options (claude-code, opencode) use the
# module-native mechanism. Codex and Droid lack recursive symlink support
# in their modules, so core skills are symlinked directly via home.file.
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
      # Bypass programs.codex.skills: upstream codex module omits recursive = true
      # on home.file entries, causing .before-home-manager churn on every generation
      # change. Lock to empty to prevent conflicts if upstream changes the default.
      programs.codex.skills = { };
      programs.opencode.skills = coreSkills;

      # Codex and Droid: direct home.file with recursive = true for stable symlinks
      home.file =
        lib.mapAttrs' (
          name: path:
          lib.nameValuePair ".agents/skills/${name}" {
            source = path;
            recursive = true;
          }
        ) coreSkills
        // lib.mapAttrs' (
          name: path:
          lib.nameValuePair ".factory/skills/${name}" {
            source = path;
            recursive = true;
          }
        ) coreSkills;
    };
}
