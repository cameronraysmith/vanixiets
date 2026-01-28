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
        home.packages = [
          (pkgs.writeShellApplication {
            name = "opencode";
            runtimeInputs = [
              flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
            ];
            text = ''
              ZHIPU_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
              export ZHIPU_API_KEY
              CEREBRAS_API_KEY="$(cat ${config.sops.secrets.cerebras-api-key.path})"
              export CEREBRAS_API_KEY

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
        };
      };
  };
}
