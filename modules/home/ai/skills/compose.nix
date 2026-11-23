{ ... }:
let
  content =
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
          default = (import ../../../../lib/plugin-groups.nix).skills;
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
          description = "Upstream source trees composed as additional local packages alongside first-party skills. Empty: remote apm dependencies are declared in the plugin apm.yml files and downloaded by apm-deps; retained for a future additive co-ship. Same-name collisions resolve by apm precedence (design D6).";
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
          description = "Wired apm-skills-compose derivation; skills/default.nix points into its .claude/skills/ subtree using the committed name index in passthru.skillNames. Never reference its .claude/settings.json or hooks/ (upstream hook side effects).";
        };
      };

      config.aiSkills.composed = pkgs.apm-skills-compose.override {
        firstPartyPackages = config.aiSkills.packages;
        upstreamDeps = config.aiSkills.upstreamDeps;
        targets = config.aiSkills.apmTargets;
      };
    };
in
{
  flake.modules.homeManager.ai-skills-compose = content;
}
