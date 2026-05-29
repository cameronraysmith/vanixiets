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
      # Upstream programs.codex (home-manager modules/programs/codex.nix:185-188)
      # picks .codex vs xdg.configHome/codex based on home.preferXdgDirectories
      # and the codex package version (TOML for >=0.2.0). We're on codex 0.130
      # without XDG preference, so .codex/config.toml is the live key. If either
      # condition flips, the override key and install destination both need to
      # follow.
      configDir = ".codex";
      configFileName = "config.toml";
      settingsKey = "${configDir}/${configFileName}";
      tomlFormat = pkgs.formats.toml { };
    in
    {
      options.programs.codex.mutableSettings = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use a mutable copy instead of an immutable nix store symlink for ${configFileName}. Allows codex to write to its config at runtime at the cost of nix-declared state being overwritten between activations.";
      };

      config = {
        programs.codex = {
          enable = true;
          mutableSettings = true;
          package = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;

          # https://developers.openai.com/codex/config-reference
          # https://github.com/openai/codex/blob/main/codex-rs/config.md
          settings = {
            # Model configuration
            model = "gpt-5.5";
            # model_reasoning_effort = "high";
            # model_reasoning_summary = "auto";

            # Top-level web_search gates WebSearchMode (disabled | cached | live).
            # Distinct from features.web_search_cached, which is an internal
            # feature flag used for review-session gating.
            web_search = "cached";

            # Approval and interaction
            approval_policy = "on-request";
            file_opener = "none";
            # preferred_auth_method was removed upstream; ConfigToml accepts but
            # silently drops unknown keys (no serde deny_unknown_fields). Auth
            # path is driven by ~/.codex/auth.json after `codex login`.
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
              apps = false;
              apply_patch_freeform = true;
              collaboration_modes = true;
              shell_snapshot = true;
              steer = true;
              unified_exec = true;
            };

            # MCP servers
            mcp_servers.linear.url = "https://mcp.linear.app/mcp";

            # Plugins (linear@openai-curated uses the built-in ChatGPT-auth
            # marketplace — no [marketplaces.*] declaration required; its Skill
            # loads via Feature::Plugins and resolves through mcp_servers.linear)
            plugins."linear@openai-curated".enabled = true;
            plugins."browser@openai-bundled".enabled = true;
          };

          # NOTE: Do NOT set custom-instructions here.
          # Memory file (~/.codex/AGENTS.md) is managed by programs.agents-md
          # to maintain unified instructions across all AI agents.
        };

        # Mutable settings: suppress the upstream symlink-style home.file entry
        # on the absolute-path key upstream actually writes to. Mirrors the
        # claude-code pattern at modules/home/ai/claude-code/default.nix:374-376;
        # targeting a relative key would be a silent no-op (see the
        # homemanager-upstream-key-paths memory entry).
        home.file.${settingsKey}.enable = lib.mkIf config.programs.codex.mutableSettings (
          lib.mkForce false
        );

        home.activation.codexMutableSettings = lib.mkIf config.programs.codex.mutableSettings (
          let
            settingsFile = tomlFormat.generate "codex-config" config.programs.codex.settings;
          in
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            $DRY_RUN_CMD install -Dm644 ${settingsFile} $HOME/${settingsKey}
          ''
        );
      };
    };
}
