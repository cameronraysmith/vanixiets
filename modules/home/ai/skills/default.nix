# Unified AI agent skills for claude-code, codex, opencode, droid, and hermes-agent
#
# Skills are partitioned into core (shared across all agents), claude
# (Claude Code-only), and third-party (from flake inputs). Third-party
# flake inputs coerce to store path strings (not Nix paths), so modules
# that check lib.isPath need home.file entries instead of skills options.
#
# Agents with programs.*.skills options (claude-code, opencode) use the
# module-native mechanism. Codex, Droid, and hermes-agent lack recursive
# symlink support in their modules, so core skills are symlinked directly
# via home.file. For hermes-agent, skills are delivered into
# ~/.hermes/skills/ (SKILLS_DIR) directly rather than ~/.hermes/external-skills/
# to work around an upstream bug in agent/skill_commands.py:_load_skill_payload
# where the normalize at line 65 fails for paths outside SKILLS_DIR, causing
# slash-command invocation of external skills to fail with "Failed to load
# skill" while discovery (via bare names) still works.
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
        ) coreSkills
        // lib.mapAttrs' (
          name: path:
          lib.nameValuePair ".hermes/skills/${name}" {
            source = path;
            recursive = true;
          }
        ) coreSkills;
    };
}
