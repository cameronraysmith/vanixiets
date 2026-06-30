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
          default = [
            {
              name = "superpowers-src";
              src = pkgs.agent-plugins-superpowers;
            }
          ];
          description = "Upstream apm dependencies (e.g. superpowers; later the agentic-planning bridge fork) additively co-shipped alongside first-party skills. Same-name collisions resolve by apm precedence (design D6).";
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
        targets = config.aiSkills.apmTargets;
      };
    };
}
