# Unified AI agent skills for claude-code, codex, opencode, droid, and hermes-agent
#
# First-party skills (apm packages under ../plugins/<package>/.apm/skills, e.g. the
# openspec-* skills shipped inside planning-and-development) plus superpowers — a
# regular remote apm dependency resolved offline via the git-cache pre-warm (D11) —
# are composed offline into a single flat marketplace tree by aiSkills.composed (see
# compose.nix). Skills are enumerated from the compose's committed name index
# (aiSkills.composed.skillNames, drift-guarded inside its build) and point into its
# .claude/skills/ subtree, so each skill deploys under its flat leaf name (the
# package name never appears in the deployed path) and every skill is all-agent: the
# historical src/core vs src/claude split is dissolved, so all harnesses receive the
# same set uniformly. Additional third-party skills arrive via aiSkills.extraSkills
# as name -> skill directory (usually a store path string, not a Nix path), so
# modules that check lib.isPath need home.file entries instead of skills options.
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
let
  content =
    {
      config,
      lib,
      pkgs,
      flake,
      ...
    }:
    let
      # First-party skills plus superpowers (a regular remote apm dependency resolved
      # offline via the git-cache pre-warm, D11) are composed offline by aiSkills.composed (apm-skills-compose),
      # which emits a flat ${out}/.claude/skills/<skill>/SKILL.md tree. The names come
      # from the compose's committed index, and each value is a string interpolation
      # into that subtree, so evaluation never reads the build output (no
      # import-from-derivation). We deliberately never reference
      # ${composed}/.claude/settings.json or any hooks/ that superpowers contributes
      # (design.md D6 / hooks risk note).
      #
      # mattpocock/skills is adopted whole-plugin, and two of its bare-named skills
      # shadow first-party ecosystems at model-selection time, so they are withheld
      # from delivery here. The compose still builds them; only the harness symlink
      # is dropped. Remove a name to re-include it.
      #
      # `tdd` shadows our atdd-outer-loop -> test-driven-development ecosystem and
      # would bypass ATDD routing.
      #
      # `writing-for-agents` arrived in v1.2.3 as a rename of `writing-great-skills`
      # that both dropped `disable-model-invocation: true` and broadened its scope to
      # editing AGENTS.md and CLAUDE.md, so it became model-invocable in territory
      # meta-skill-creator, preferences-documentation and preferences-prose-clarity
      # already own. Same routing-bypass class as `tdd`, no name collision.
      #
      # `linear-cli` is declared in planning-and-development/apm.yml for marketplace
      # consumers (openspec-linear-sync drives it). Nix users receive it from
      # `flake.lib.linearSkills` (pkgs.linear-cli.src/skills/linear-cli) only where the
      # linear module or the user opts in, so it is withheld from the unconditional
      # compose delivery. Both paths ship the same pin (pkgs.linear-cli.src.rev).
      excludedUpstreamSkills = [
        "tdd"
        "writing-for-agents"
        "linear-cli"
      ];

      allSkills =
        lib.genAttrs (lib.subtractLists excludedUpstreamSkills config.aiSkills.composed.skillNames)
          (name: "${config.aiSkills.composed}/.claude/skills/${name}");

      # All first-party skills plus any third-party skills, for the home.file-based agents.
      fileSkills = allSkills // config.aiSkills.extraSkills;

      # Aggregated real-file skills tree for agents that cannot discover skills
      # behind symlinked SKILL.md leaves. home.file with recursive = true uses
      # lndir, which produces real directories but symlinked file leaves into the
      # nix store; codex (v0.135.0) skips symlinked file leaves in its loader and
      # therefore sees no skills. Materializing the tree as real files via a
      # home.activation copy (below) avoids the symlink leaves. -L dereferences
      # any symlinks so the result is real files while preserving whether each
      # source file is executable. The activation copy below adds user write permission.
      agentsSkillsTree = pkgs.runCommandLocal "agents-skills" { } (
        lib.concatStringsSep "\n" (
          lib.mapAttrsToList (name: path: ''
            mkdir -p "$out/${name}"
            cp -RL ${path}/. "$out/${name}/"
          '') fileSkills
        )
      );
    in
    {
      options.aiSkills.extraSkills = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = { };
        description = "Third-party skills injected into all agent destinations alongside first-party skills, keyed by deployed name; each value is a skill directory containing SKILL.md, typically a store path string such as \"\${pkg.src}/skills/<name>\".";
      };

      config = {
        programs.claude-code.skills = fileSkills;
        # Bypass programs.codex.skills: upstream codex module omits recursive = true
        # on home.file entries, causing .before-home-manager churn on every generation
        # change. Lock to empty to prevent conflicts if upstream changes the default.
        programs.codex.skills = { };
        programs.opencode.skills = fileSkills;

        # ~/.agents/skills delivered as real files via home.activation below
        # (not home.file) because codex skips symlinked SKILL.md leaves.
        #
        # Droid (.factory) and hermes (.hermes): direct home.file with
        # recursive = true for stable symlinks.
        home.file =
          lib.mapAttrs' (
            name: path:
            lib.nameValuePair ".factory/skills/${name}" {
              source = path;
              recursive = true;
            }
          ) fileSkills
          // lib.mapAttrs' (
            name: path:
            lib.nameValuePair ".hermes/skills/${name}" {
              source = path;
              recursive = true;
            }
          ) fileSkills;

        # Deliver ~/.agents/skills as real files (see agentsSkillsTree above).
        # Prune and repopulate for idempotency, taking full ownership of the
        # directory so removed skills don't linger.
        home.activation.agentsSkillsRealFiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD rm -rf "$HOME/.agents/skills"
          $DRY_RUN_CMD install -d "$HOME/.agents/skills"
          $DRY_RUN_CMD cp -RL ${agentsSkillsTree}/. "$HOME/.agents/skills/"
          $DRY_RUN_CMD chmod -R u+w "$HOME/.agents/skills"
        '';
      };
    };
in
{
  flake.modules.homeManager.ai-skills = content;
}
