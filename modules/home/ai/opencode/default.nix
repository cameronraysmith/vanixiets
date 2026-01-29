# opencode CLI configuration with Z.AI Coding Plan and Cerebras provider support
# Wrapper scripts inject API secrets at runtime; the upstream programs.opencode
# module handles settings, skills, and other xdg.configFile entries.
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      pkgs,
      config,
      flake,
      ...
    }:
    let
      opencodePackage = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
    in
    {
      programs.opencode = {
        enable = true;
        # Null package: wrapper scripts below provide the entry point
        # with secret injection; setting a package here would conflict
        package = null;
        settings = {
          model = "zai-coding-plan/glm-4.7";
          share = "disabled";
          autoupdate = false;
          disabled_providers = [
            "anthropic"
            "openai"
            "google"
            "github-copilot"
            "zai" # Use zai-coding-plan instead of basic zai
            "zhipuai" # Use zai-coding-plan instead of zhipuai
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
          name = "opencode";
          runtimeInputs = [ opencodePackage ];
          text = ''
            ZHIPU_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
            export ZHIPU_API_KEY
            CEREBRAS_API_KEY="$(cat ${config.sops.secrets.cerebras-api-key.path})"
            export CEREBRAS_API_KEY

            exec opencode "$@"
          '';
        })
        (pkgs.writeShellApplication {
          name = "ocd";
          runtimeInputs = [ opencodePackage ];
          text = ''
            ZHIPU_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
            export ZHIPU_API_KEY
            CEREBRAS_API_KEY="$(cat ${config.sops.secrets.cerebras-api-key.path})"
            export CEREBRAS_API_KEY
            export OPENCODE_PERMISSION='{"*":"allow"}'

            exec opencode "$@"
          '';
        })
      ];
    };
}
