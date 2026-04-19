# opencode CLI configuration with Z.AI Coding Plan and Cerebras provider support.
#
# Pattern: wrap the llm-agents opencode derivation so programs.opencode.package
# is a real (non-null) derivation. This:
#   1. Avoids the HM regression where cfg.package = null causes
#      `lib.versionAtLeast null "1.2.15"` to throw (hm commit 1089b2cab).
#   2. Makes lib.getExe cfg.package resolve for launchd.agents / systemd.user.services
#      (currently dormant; future opencode-web mode would use it).
#   3. Injects API keys from sops runtime paths at EXEC time, so secrets never
#      enter the nix store — the wrapper cat's them at invocation.
#
# The `ocd` permissive variant is a separate writeShellApplication in
# home.packages because it is a distinct binary name.
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      pkgs,
      config,
      lib,
      flake,
      ...
    }:
    let
      opencodePackage = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;

      glmKeyPath = config.sops.secrets.glm-api-key.path;
      cerebrasKeyPath = config.sops.secrets.cerebras-api-key.path;

      opencodeWrapped = pkgs.symlinkJoin {
        name = "opencode-wrapped-${lib.getVersion opencodePackage}";
        inherit (opencodePackage) meta;
        paths = [ opencodePackage ];
        preferLocalBuild = true;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/opencode \
            --set-default ZHIPU_API_KEY_FILE ${glmKeyPath} \
            --set-default CEREBRAS_API_KEY_FILE ${cerebrasKeyPath} \
            --run 'export ZHIPU_API_KEY="$(cat "$ZHIPU_API_KEY_FILE")"' \
            --run 'export CEREBRAS_API_KEY="$(cat "$CEREBRAS_API_KEY_FILE")"'
        '';
      };
    in
    {
      programs.opencode = {
        enable = true;
        package = opencodeWrapped;
        settings = {
          model = "zai-coding-plan/glm-5.1";
          share = "disabled";
          autoupdate = false;
          disabled_providers = [
            "anthropic"
            "openai"
            "google"
            "github-copilot"
            "zai"
            "zhipuai"
          ];
          permission = {
            bash = {
              "rm -rf *" = "deny";
              "rm -f *" = "deny";
              "sudo *" = "deny";
              "chmod *" = "deny";
              "chown *" = "deny";
            };
          };
        };
      };

      home.packages = [
        (pkgs.writeShellApplication {
          name = "ocd";
          runtimeInputs = [ opencodeWrapped ];
          text = ''
            export OPENCODE_PERMISSION='{"*":"allow"}'
            exec opencode "$@"
          '';
        })
      ];
    };
}
