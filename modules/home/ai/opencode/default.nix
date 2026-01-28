# opencode CLI configuration with Z.ai and Cerebras provider support
{ ... }:
{
  flake.modules = {
    homeManager.ai =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        home.packages =
          let
            opencodePackage = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
          in
          [
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

        xdg.configFile."opencode/opencode.jsonc".text = builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          model = "cerebras/zai-glm-4.7";
          disabled_providers = [
            "anthropic"
            "openai"
            "google"
            "github-copilot"
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
  };
}
