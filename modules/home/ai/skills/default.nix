# Unified AI agent skills for claude-code, codex, opencode, droid, and hermes-agent
#
# First-party skills (apm packages under ../plugins/<package>/.apm/skills) plus
# additively co-shipped upstream skills (superpowers, later the bridge) are
# composed offline into a single flat marketplace tree by aiSkills.composed (see
# compose.nix). This module re-globs that derivation's .claude/skills/ subtree, so
# each skill deploys under its flat leaf name (the package name never appears in
# the deployed path) and every skill is all-agent: the historical src/core vs
# src/claude split is dissolved, so all harnesses receive the same set uniformly.
# Additional third-party skills (from flake inputs via aiSkills.extraSkillDirs)
# coerce to store path strings (not Nix paths), so modules that check lib.isPath
# need home.file entries instead of skills options.
#
# Agents with programs.*.skills options (claude-code, opencode) use the
# module-native mechanism. Codex, Droid, and hermes-agent lack recursive
# symlink support in their modules, so skills are symlinked directly
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
      pkgs,
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

      # First-party skills plus additively co-shipped upstream skills (superpowers,
      # later the bridge) are composed offline by aiSkills.composed (apm-skills-compose),
      # which emits a flat ${out}/.claude/skills/<skill>/SKILL.md tree. Re-glob ONLY
      # that skills/ subtree back into the { <skill> = path; } shape the sinks expect.
      # We deliberately never reference ${composed}/.claude/settings.json or any hooks/
      # that superpowers contributes (design.md D6 / hooks risk note).
      #
      # readDir over a derivation output is import-from-derivation: evaluating the
      # skills attrset realizes aiSkills.composed.
      allSkills = readSkillsFrom "${config.aiSkills.composed}/.claude/skills";

      # Third-party skill directories supplied via aiSkills.extraSkillDirs.
      # Each entry is a directory (often a nix store path string) holding
      # <name>/SKILL.md subdirs; readSkillsFrom maps it the same way as the packages.
      extraSkills = lib.foldl' (acc: dir: acc // readSkillsFrom dir) { } config.aiSkills.extraSkillDirs;

      # Coerce a skill source to a value home.file.source accepts. Store-path
      # strings (from flake inputs / pkgs.*.src) are valid sources, but the
      # safe, type-stable form is an outPath-bearing path produced by
      # builtins.path, which works uniformly for in-repo Nix paths and for
      # store-path strings.
      toFileSource = path: builtins.path { inherit path; };

      # All first-party skills plus any third-party skills, for the home.file-based agents.
      fileSkills = allSkills // extraSkills;

      # Aggregated real-file skills tree for agents that cannot discover skills
      # behind symlinked SKILL.md leaves. home.file with recursive = true uses
      # lndir, which produces real directories but symlinked file leaves into the
      # nix store; codex (v0.135.0) skips symlinked file leaves in its loader and
      # therefore sees no skills. Materializing the tree as real files via a
      # home.activation copy (below) avoids the symlink leaves. -L dereferences
      # any symlinks so the result is real files; --no-preserve=mode makes the
      # copies writable (store files are read-only).
      agentsSkillsTree = pkgs.runCommandLocal "agents-skills" { } (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: path: ''
            mkdir -p "$out/${name}"
            cp -RL --no-preserve=mode ${toFileSource path}/. "$out/${name}/"
          '') fileSkills
        )
      );
    in
    {
      options.aiSkills.extraSkillDirs = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
        default = [ ];
        description = "Additional directories, each containing `<name>/SKILL.md` subdirs, whose skills are injected into all agent destinations alongside first-party skills. Accepts nix store paths.";
      };

      config = {
        programs.claude-code.skills = allSkills // extraSkills;
        # Bypass programs.codex.skills: upstream codex module omits recursive = true
        # on home.file entries, causing .before-home-manager churn on every generation
        # change. Lock to empty to prevent conflicts if upstream changes the default.
        programs.codex.skills = { };
        programs.opencode.skills = allSkills // extraSkills;

        # ~/.agents/skills delivered as real files via home.activation below
        # (not home.file) because codex skips symlinked SKILL.md leaves.
        #
        # Droid (.factory) and hermes (.hermes): direct home.file with
        # recursive = true for stable symlinks.
        home.file =
          lib.mapAttrs' (
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

        # Deliver ~/.agents/skills as real files (see agentsSkillsTree above).
        # Prune and repopulate for idempotency, taking full ownership of the
        # directory so removed skills don't linger.
        home.activation.agentsSkillsRealFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD rm -rf "$HOME/.agents/skills"
          $DRY_RUN_CMD install -d "$HOME/.agents/skills"
          $DRY_RUN_CMD cp -RL --no-preserve=mode ${agentsSkillsTree}/. "$HOME/.agents/skills/"
        '';
      };
    };
}
