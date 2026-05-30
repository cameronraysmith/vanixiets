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
      config,
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

      # Third-party skill directories supplied via aiSkills.extraSkillDirs.
      # Each entry is a directory (often a nix store path string) holding
      # <name>/SKILL.md subdirs; readSkillsFrom maps it the same way as core.
      extraSkills = lib.foldl' (acc: dir: acc // readSkillsFrom dir) { } config.aiSkills.extraSkillDirs;

      # Coerce a skill source to a value home.file.source accepts. Store-path
      # strings (from flake inputs / pkgs.*.src) are valid sources, but the
      # safe, type-stable form is an outPath-bearing path produced by
      # builtins.path, which works uniformly for in-repo Nix paths and for
      # store-path strings.
      toFileSource = path: builtins.path { inherit path; };

      # Core skills plus any third-party skills, for the home.file-based agents.
      fileSkills = coreSkills // extraSkills;
    in
    {
      options.aiSkills.extraSkillDirs = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
        default = [ ];
        description = "Additional directories, each containing `<name>/SKILL.md` subdirs, whose skills are injected into all agent destinations alongside core skills. Accepts nix store paths.";
      };

      config = {
        programs.claude-code.skills = coreSkills // extraSkills // claudeSkills;
        # Bypass programs.codex.skills: upstream codex module omits recursive = true
        # on home.file entries, causing .before-home-manager churn on every generation
        # change. Lock to empty to prevent conflicts if upstream changes the default.
        programs.codex.skills = { };
        programs.opencode.skills = coreSkills // extraSkills;

        # Codex and Droid: direct home.file with recursive = true for stable symlinks
        home.file =
          lib.mapAttrs' (
            name: path:
            lib.nameValuePair ".agents/skills/${name}" {
              source = toFileSource path;
              recursive = true;
            }
          ) fileSkills
          // lib.mapAttrs' (
            name: path:
            lib.nameValuePair ".factory/skills/${name}" {
              source = toFileSource path;
              recursive = true;
            }
          ) fileSkills
          // lib.mapAttrs' (
            name: path:
            lib.nameValuePair ".hermes/skills/${name}" {
              source = toFileSource path;
              recursive = true;
            }
          ) fileSkills;
      };
    };
}
