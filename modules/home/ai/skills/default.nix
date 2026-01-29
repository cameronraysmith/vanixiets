# Unified AI agent skills for claude-code, codex, and opencode
#
# Skills are partitioned into core (shared across all agents), claude
# (Claude Code-only), and third-party (e.g. bioSkills from flake inputs).
#
# Core and claude skills are Nix path values (from relative path literals)
# and pass through programs.X.skills where upstream modules handle them via
# lib.isPath. Third-party skills from flake inputs coerce to store path
# strings via outPath, which the claude-code and codex modules do not
# recognize as directories (they check lib.isPath, not store path strings).
# The opencode module already handles both. We create home.file and
# xdg.configFile entries directly for third-party skills on claude-code
# and codex, bypassing their skills option for store path values.
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
      # When dir is a Nix path literal (e.g. ./src/core), values are
      # Nix path types suitable for upstream module skills options.
      readSkillsFrom =
        dir:
        lib.mapAttrs (name: _: dir + "/${name}") (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)
        );

      # Scan two-level directory (category/skill) and flatten with prefix.
      # Produces keys like "${prefix}-${category}-${skill}" to preserve
      # semantic context from the nested directory hierarchy.
      # When dir is a flake input, values are store path strings via outPath.
      readSkillsNested =
        prefix: dir:
        let
          categories = lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir);
        in
        lib.foldlAttrs (
          acc: catName: _:
          let
            catDir = "${dir}/${catName}";
            skills = lib.filterAttrs (_: type: type == "directory") (builtins.readDir catDir);
          in
          acc
          // lib.mapAttrs' (
            name: _: lib.nameValuePair "${prefix}-${catName}-${name}" "${catDir}/${name}"
          ) skills
        ) { } categories;

      coreSkills = readSkillsFrom ./src/core;
      claudeSkills = readSkillsFrom ./src/claude;
      bioSkills = readSkillsNested "bio" flake.inputs.bioSkills;

      # Generate home.file or xdg.configFile entries for store path skills
      storePathSkillFiles =
        prefix:
        lib.mapAttrs' (
          name: source:
          lib.nameValuePair "${prefix}/${name}" {
            inherit source;
            recursive = true;
          }
        );
    in
    {
      # Core and claude skills: Nix path values, upstream modules handle via lib.isPath
      programs.claude-code.skills = coreSkills // claudeSkills;
      programs.codex.skills = coreSkills;

      # opencode module handles both Nix paths and store path strings
      # programs.opencode.skills = coreSkills // bioSkills;
      programs.opencode.skills = coreSkills;

      # Third-party skills: store path strings bypass upstream skills options
      # and go directly to home.file / xdg.configFile with recursive symlinks
      # home.file =
      #   storePathSkillFiles ".claude/skills" bioSkills // storePathSkillFiles ".codex/skills" bioSkills;
    };
}
