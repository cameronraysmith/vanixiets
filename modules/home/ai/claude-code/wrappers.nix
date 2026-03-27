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
        jsonFormat = pkgs.formats.json { };

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

            # Derive wrapper settings from base profile, overriding model env vars
            # for the alternative backend. All other settings are inherited.
            baseSettings = config.programs.claude-code.settings;
            wrapperSettings = baseSettings // {
              env = (baseSettings.env or { }) // {
                ANTHROPIC_DEFAULT_OPUS_MODEL = models.opus;
                ANTHROPIC_DEFAULT_SONNET_MODEL = models.sonnet;
                ANTHROPIC_DEFAULT_HAIKU_MODEL = models.haiku;
                CLAUDE_CODE_SUBAGENT_MODEL = models.opus;
              };
            };
            settingsFile = jsonFormat.generate "${wrapperName}-settings.json" (
              wrapperSettings
              // {
                "$schema" = "https://json.schemastore.org/claude-code-settings.json";
              }
            );
          in
          {
            package = pkgs.writeShellApplication {
              name = wrapperName;
              runtimeInputs = [ config.programs.claude-code.finalPackage ];
              text = ''
                export CLAUDE_CONFIG_DIR="${configDir}"
                mkdir -p "$CLAUDE_CONFIG_DIR"

                # Runtime secrets (read from sops at invocation time)
                API_KEY="$(cat ${config.sops.secrets.${apiKeySecret}.path})"
                export ${envVarPrefix}_API_KEY="$API_KEY"
                export ANTHROPIC_BASE_URL="${apiBase}"
                export ANTHROPIC_AUTH_TOKEN="$API_KEY"

                export DISABLE_COST_WARNINGS=1

                exec claude "$@"
              '';
            };

            configFiles = {
              "${wrapperName}/settings.json" =
                if config.programs.claude-code.mutableSettings then
                  { enable = false; }
                else
                  { source = settingsFile; };

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
          }
          // lib.optionalAttrs config.programs.claude-code.mutableSettings {
            activation = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              $DRY_RUN_CMD install -Dm644 ${settingsFile} ${configDir}/settings.json
            '';
          };

        glmWrapper = mkClaudeWrapper {
          name = "glm";
          apiBase = "https://api.z.ai/api/anthropic";
          apiKeySecret = "glm-api-key";
          models = {
            opus = "glm-5.1";
            sonnet = "glm-5.1";
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

        home.activation = lib.mkIf config.programs.claude-code.mutableSettings {
          claudeGlmMutableSettings = glmWrapper.activation;
          claudeCerebrasMutableSettings = cerebrasWrapper.activation;
        };
      };
  };
}
