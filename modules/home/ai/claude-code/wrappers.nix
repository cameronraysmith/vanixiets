# GLM (zhipu.ai) alternative LLM backend wrapper for Claude Code
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
        home = config.home.homeDirectory;
      in
      {
        # GLM wrapper using sops-nix for API key
        # Pattern A + sops-nix enables secrets via config.sops.secrets
        # crs58/cameron only (raquel doesn't have ai aggregate)

        # GLM wrapper script - ENABLED via sops-nix
        home.packages = [
          (pkgs.writeShellApplication {
            name = "claude-glm";
            runtimeInputs = [ config.programs.claude-code.finalPackage ];
            text = ''
              export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-glm"
              mkdir -p "$CLAUDE_CONFIG_DIR"

              # Use sops secret path at runtime (available after activation)
              GLM_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
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
  };
}
