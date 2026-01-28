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
              # TODO: Uncomment when upstream bun build issue is resolved
              # flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.opencode
            ];
            text = ''
              # Read API keys from sops secrets at runtime
              ZHIPU_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
              export ZHIPU_API_KEY
              CEREBRAS_API_KEY="$(cat ${config.sops.secrets.cerebras-api-key.path})"
              export CEREBRAS_API_KEY

              # TODO: Replace with opencode binary when package becomes available
              echo "opencode package not yet available - blocked by upstream bun build issue"
              exit 1
              # exec opencode "$@"
            '';
          })
        ];

        xdg.configFile."opencode/opencode.jsonc".text = builtins.toJSON {
          "$schema" = "https://opencode.ai/schema.json";
          default_model = "cerebras/zai-glm-4.7";
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
