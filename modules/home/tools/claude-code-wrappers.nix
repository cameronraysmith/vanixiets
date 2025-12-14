{ ... }:
{
  # TODO: Previously used flake.config user lookup pattern from nixos-unified
  # This module references flake.config.${config.home.username} which is a pattern
  # that was in place when this config was based on nixos-unified and needs adaptation
  # for deferred module composition pattern. Temporarily disabled.
  /*
    flake.modules.homeManager.tools =
      {
        config,
        pkgs,
        lib,
        flake,
        ...
      }:
      let
        home = config.home.homeDirectory;
        # Look up user config based on home.username (set by each home configuration)
        user = flake.config.${config.home.username};
        # User-specific LLM API keys (separate from MCP server keys)
        llmSecretsFile = flake.inputs.self + "/secrets/users/${user.sopsIdentifier}/llm-api-keys.yaml";
      in
      {
        # Define sops secret for GLM API key (following mcp-servers.nix pattern)
        sops.secrets."glm-api-key" = {
          sopsFile = llmSecretsFile;
          key = "glm-api-key";
        };

        # GLM wrapper script
        home.packages = [
          (pkgs.writeShellApplication {
            name = "claude-glm";
            runtimeInputs = [ config.programs.claude-code.finalPackage ];
            text = ''
              export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-glm"
              mkdir -p "$CLAUDE_CONFIG_DIR"

              GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"
              export GLM_API_KEY
              export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
              export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
              export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
              export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
              export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"

              exec claude "$@"
            '';
          })
        ];

        # Share settings from default profile
        xdg.configFile."claude-glm/settings.json" = {
          source = config.home.file.".claude/settings.json".source;
        };

        # Share commands directory
        xdg.configFile."claude-glm/commands" = lib.mkIf (config.programs.claude-code.commandsDir != null) {
          source = config.programs.claude-code.commandsDir;
          recursive = true;
        };

        # Share agents directory
        xdg.configFile."claude-glm/agents" = lib.mkIf (config.programs.claude-code.agentsDir != null) {
          source = config.programs.claude-code.agentsDir;
          recursive = true;
        };
      };
  */
}
