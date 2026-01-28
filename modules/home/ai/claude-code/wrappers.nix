# Alternative LLM backend wrappers for Claude Code
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
      let
        mkClaudeWrapper =
          {
            name,
            apiBase,
            apiKeySecret,
            models,
          }:
          let
            wrapperName = "claude-${name}";
            configDir = "${config.xdg.configHome}/${wrapperName}";
            envVarPrefix = lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name);
          in
          {
            package = pkgs.writeShellApplication {
              name = wrapperName;
              runtimeInputs = [ config.programs.claude-code.finalPackage ];
              text = ''
                export CLAUDE_CONFIG_DIR="${configDir}"
                mkdir -p "$CLAUDE_CONFIG_DIR"

                # Use sops secret path at runtime (available after activation)
                API_KEY="$(cat ${config.sops.secrets.${apiKeySecret}.path})"
                export ${envVarPrefix}_API_KEY="$API_KEY"
                export ANTHROPIC_BASE_URL="${apiBase}"
                export ANTHROPIC_AUTH_TOKEN="$API_KEY"
                export ANTHROPIC_DEFAULT_OPUS_MODEL="${models.opus}"
                export ANTHROPIC_DEFAULT_SONNET_MODEL="${models.sonnet}"
                export ANTHROPIC_DEFAULT_HAIKU_MODEL="${models.haiku}"

                export DISABLE_COST_WARNINGS=1

                exec claude "$@"
              '';
            };

            configFiles = {
              # Share settings from default profile
              "${wrapperName}/settings.json" = {
                source = config.home.file.".claude/settings.json".source;
              };

              # Share commands directory
              "${wrapperName}/commands" = lib.mkIf (config.programs.claude-code.commandsDir != null) {
                source = config.programs.claude-code.commandsDir;
                recursive = true;
              };

              # Share agents directory
              "${wrapperName}/agents" = lib.mkIf (config.programs.claude-code.agentsDir != null) {
                source = config.programs.claude-code.agentsDir;
                recursive = true;
              };
            };
          };

        glmWrapper = mkClaudeWrapper {
          name = "glm";
          apiBase = "https://api.z.ai/api/anthropic";
          apiKeySecret = "glm-api-key";
          models = {
            opus = "glm-4.7";
            sonnet = "glm-4.7";
            haiku = "glm-4.5-air";
          };
        };

        cerebrasWrapper = mkClaudeWrapper {
          name = "cerebras";
          apiBase = "https://api.cerebras.ai/v1";
          apiKeySecret = "cerebras-api-key";
          models = {
            opus = "zai-glm-4.7";
            sonnet = "zai-glm-4.7";
            haiku = "llama3.1-8b";
          };
        };
      in
      {
        home.packages = [
          glmWrapper.package
          cerebrasWrapper.package
        ];

        xdg.configFile = glmWrapper.configFiles // cerebrasWrapper.configFiles;
      };
  };
}
