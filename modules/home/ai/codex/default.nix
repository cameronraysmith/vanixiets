{ ... }:
{
  flake.modules.homeManager.ai =
    {
      pkgs,
      config,
      flake,
      ...
    }:
    {
      programs.codex = {
        enable = true;
        package = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;

        # https://developers.openai.com/codex/config-reference
        # https://github.com/openai/codex/blob/main/codex-rs/config.md
        settings = {
          # Model configuration
          model = "gpt-5.2-codex";
          # model_reasoning_effort = "high";
          # model_reasoning_summary = "auto";

          # Approval and interaction
          approval_policy = "on-request";
          file_opener = "none";
          preferred_auth_method = "chatgpt";
          check_for_update_on_startup = false;

          # Sandbox configuration
          sandbox_mode = "workspace-write";
          sandbox_workspace_write = {
            network_access = true;
            writable_roots = [
              config.xdg.cacheHome
              "${config.home.homeDirectory}/.npm"
            ];
          };

          # UI
          tui.notifications = true;

          # Shell environment
          shell_environment_policy = {
            set = {
              UV_NO_SYNC = "1";
            };
          };

          # Experimental features
          # https://github.com/openai/codex/blob/main/codex-rs/core/src/features.rs
          features = {
            apply_patch_freeform = true;
            collaboration_modes = true;
            shell_snapshot = true;
            steer = true;
            unified_exec = true;
            web_search_cached = true;
          };
        };

        # NOTE: Do NOT set custom-instructions here.
        # Memory file (~/.codex/AGENTS.md) is managed by programs.agents-md
        # to maintain unified instructions across all AI agents.
      };
    };
}
