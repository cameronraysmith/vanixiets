# Unified AI agent skills for claude-code, codex, and opencode
# Skills are partitioned: core (shared) and claude (Claude Code-only)
# Third-party skills from flake inputs are flattened and merged
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      lib,
      flake,
      ...
    }:
    let
      # Scan a directory for skill subdirectories (one level deep)
      readSkillsFrom =
        dir:
        lib.mapAttrs (name: _: dir + "/${name}") (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)
        );

      # Scan two-level directory (category/skill) and flatten to single level
      readSkillsNested =
        dir:
        let
          categories = lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir);
        in
        lib.foldlAttrs (
          acc: catName: _:
          let
            catDir = dir + "/${catName}";
            skills = lib.filterAttrs (_: type: type == "directory") (builtins.readDir catDir);
          in
          acc // lib.mapAttrs (name: _: catDir + "/${name}") skills
        ) { } categories;

      coreSkills = readSkillsFrom ./src/core;
      claudeSkills = readSkillsFrom ./src/claude;
      bioSkills = readSkillsNested flake.inputs.bioSkills;

      allCoreSkills = coreSkills // bioSkills;
    in
    {
      programs.claude-code.skills = allCoreSkills // claudeSkills;
      programs.codex.skills = allCoreSkills;
      programs.opencode.skills = allCoreSkills;
    };
}
