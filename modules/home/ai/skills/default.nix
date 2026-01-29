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

      # Scan two-level directory (category/skill) and flatten with prefix
      # Produces keys like "${prefix}-${category}-${skill}" to preserve
      # semantic context from the nested directory hierarchy
      readSkillsNested =
        prefix: dir:
        let
          categories = lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir);
        in
        lib.foldlAttrs (
          acc: catName: _:
          let
            catDir = dir + "/${catName}";
            skills = lib.filterAttrs (_: type: type == "directory") (builtins.readDir catDir);
          in
          acc
          // lib.mapAttrs' (
            name: _: lib.nameValuePair "${prefix}-${catName}-${name}" (catDir + "/${name}")
          ) skills
        ) { } categories;

      coreSkills = readSkillsFrom ./src/core;
      claudeSkills = readSkillsFrom ./src/claude;

      # Convert flake input to Nix path type so upstream modules recognize
      # directory values via lib.isPath (flake inputs coerce to store path
      # strings which fail the lib.isPath check in claude-code and codex modules)
      bioSkillsSrc = /. + "${flake.inputs.bioSkills}";
      bioSkills = readSkillsNested "bio" bioSkillsSrc;

      allCoreSkills = coreSkills // bioSkills;
    in
    {
      programs.claude-code.skills = allCoreSkills // claudeSkills;
      programs.codex.skills = allCoreSkills;
      programs.opencode.skills = allCoreSkills;
    };
}
