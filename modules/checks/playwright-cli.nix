{ self, lib, ... }:
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
      home = user: self.homeConfigurations."${user}@${system}".config;
      installed = user: lib.elem package (home user).home.packages;
      cases = {
        aiUsers = lib.all installed [
          "crs58"
          "cameron"
        ];
        lighterAgentUsers = lib.all (user: !installed user) [
          "raquel"
          "janettesmith"
        ];
        matchingSkill =
          lib.all
            (
              user:
              toString (home user).programs.claude-code.skills.playwright-cli
              == "${(home user).aiSkills.composed}/.claude/skills/playwright-cli"
              && !lib.elem package.skills (home user).aiSkills.extraSkillDirs
            )
            [
              "crs58"
              "cameron"
            ];
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
              meta.description = "Playwright CLI reaches the devshell and AI users without broadening lighter agent profiles";
            };
          }
          ''
            for target in .claude .agents; do
              diff -r ${package.src}/skills/playwright-cli \
                ${(home "cameron").aiSkills.composed}/"$target"/skills/playwright-cli
            done
            touch "$out"
          '';
    };
}
