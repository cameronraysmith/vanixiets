{ ... }:
{
  flake.modules.homeManager.ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.aiSkills = {
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = lib.attrNames (
            lib.filterAttrs (n: t: t == "directory" && builtins.pathExists (../plugins + "/${n}/.apm/skills")) (
              builtins.readDir ../plugins
            )
          );
          description = "First-party apm package directory names under modules/home/ai/plugins/ to compose into the marketplace tree. Defaults to every directory containing an .apm/skills subtree, so new packages are auto-included.";
        };

        upstreamDeps = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Local dependency directory name written into the consumer apm.yml.";
                };
                src = lib.mkOption {
                  type = lib.types.package;
                  description = "Store path of the upstream apm/marketplace plugin co-shipped additively.";
                };
              };
            }
          );
          default = [ ];
          description = "Upstream apm dependencies additively co-shipped alongside first-party skills. Empty now that superpowers is a regular remote apm dep resolved offline via the compose's git-cache pre-warm (design D11); retained for a future additive co-ship. Same-name collisions resolve by apm precedence (design D6).";
        };

        superpowersSrc = lib.mkOption {
          type = lib.types.package;
          default = pkgs.agent-plugins-superpowers;
          description = "Flake-pinned superpowers tree feeding apm's git checkout cache so the regular remote superpowers dep resolves offline (design D11).";
        };

        superpowersRev = lib.mkOption {
          type = lib.types.str;
          default = pkgs.agent-plugins-superpowers.rev;
          description = "Full 40-char superpowers commit SHA; the single source of truth reconciled against the planning-and-development/apm.yml pin by the compose drift guard (design D11).";
        };

        apmTargets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "agent-skills"
            "claude"
          ];
          description = "apm install target harnesses. Only the skills/ subtree of the resulting tree is consumed downstream; codex/hermes/opencode/droid are fanned out nix-side, not by apm.";
        };

        composed = lib.mkOption {
          type = lib.types.package;
          internal = true;
          description = "Wired apm-skills-compose derivation; its .claude/skills/ subtree is re-globbed by skills/default.nix. Never reference its .claude/settings.json or hooks/ (superpowers side-effect).";
        };
      };

      config.aiSkills.composed = pkgs.apm-skills-compose.override {
        firstPartyPackages = config.aiSkills.packages;
        upstreamDeps = config.aiSkills.upstreamDeps;
        superpowersSrc = config.aiSkills.superpowersSrc;
        superpowersRev = config.aiSkills.superpowersRev;
        targets = config.aiSkills.apmTargets;
      };
    };
}
