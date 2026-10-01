{
  self,
  inputs,
  lib,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      package = self'.packages.playwright-cli;
      fixturePkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };
      home =
        aggregate:
        (inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = fixturePkgs;
          extraSpecialArgs = {
            flake = self // {
              inputs = inputs // {
                contentPrivate = throw "Playwright aggregate fixture imported private content";
              };
              users = throw "Playwright aggregate fixture imported a user";
            };
            osConfig = null;
          };
          modules = [
            # Option providers shared by the aggregates, without personal modules.
            inputs.sops-nix.homeManagerModules.sops
            self.modules.homeManager.agents-md
            self.modules.homeManager.${aggregate}
            {
              home.username = "playwright-fixture";
              home.homeDirectory =
                if pkgs.stdenv.hostPlatform.isDarwin then
                  "/Users/playwright-fixture"
                else
                  "/home/playwright-fixture";
              home.stateVersion = "25.11";
              programs.agents-md.settings.body = "Playwright consumer fixture";
            }
          ];
        }).config;
      ai = home "ai";
      agents = home "agents";
      cases = {
        aiAggregate = lib.elem package ai.home.packages;
        lighterAgentsAggregate = !lib.elem package agents.home.packages;
        matchingSkill =
          toString ai.programs.claude-code.skills.playwright-cli
          == "${ai.aiSkills.composed}/.claude/skills/playwright-cli"
          && !lib.elem package.skills ai.aiSkills.extraSkillDirs;
        devshell = lib.elem package self'.devShells.default.nativeBuildInputs;
      };
      failed = lib.attrNames (lib.filterAttrs (_: passed: !passed) cases);
    in
    {
      checks.playwright-cli-consumers =
        assert lib.assertMsg (
          failed == [ ]
        ) "Playwright consumer failures: ${lib.concatStringsSep ", " failed}";
        pkgs.runCommand "playwright-cli-consumers"
          {
            passthru = {
              inherit cases;
              meta.description = "Playwright CLI reaches the devshell and AI aggregate without broadening the lighter agents aggregate";
            };
          }
          ''
            for target in .claude .agents; do
              diff -r ${package.src}/skills/playwright-cli \
                ${ai.aiSkills.composed}/"$target"/skills/playwright-cli
            done
            touch "$out"
          '';
    };
}
