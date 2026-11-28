# Zed editor with vim mode and Catppuccin theme
# Reference: https://github.com/nix-community/home-manager/blob/master/modules/programs/zed-editor.nix
{ ... }:
{
  flake.modules = {
    homeManager.development =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.zed-editor = {
          enable = true;
          # Null by default because every Mac's binary comes from the `zed` Homebrew cask and
          # headless homes need no editor binary; the linux-workstation module installs the
          # Nix-built Zed, keeping this file the single source of the settings, keymaps and extensions.
          package = lib.mkDefault null;
          # When true (default), home-manager merges Nix settings with existing
          # settings.json via activation script. When false, creates a read-only
          # symlink to Nix store (pure but prevents Zed UI edits).
          mutableUserSettings = true;

          # https://github.com/zed-industries/extensions/tree/main/extensions
          extensions = [
            "catppuccin"
            "catppuccin-icons"
            "just"
            "nix"
            "rainbow-csv"
            "toml"
            "xml"
          ];

          # userKeymaps = {
          #   context = "Workspace";
          #   bindings = {
          #     ctrl-tab = "tab_switcher::ToggleAll";
          #   };
          # };
          #
          # [
          #   {
          #     "context": "Workspace",
          #     "bindings": {
          #       "ctrl-tab": "tab_switcher::ToggleAll"
          #     }
          #   }
          # ]

          userSettings = {
            # Written out because the settings merge never deletes a key and any `true` layer wins.
            disable_ai = false;
            edit_predictions.provider = "none";

            vim_mode = true;
            base_keymap = "VSCode";
            soft_wrap = "editor_width";
            tab_size = 2;
            file_types = {
              Markdown = [ "qmd" ];
            };

            load_direnv = "shell_hook";
            languages.Nix.language_servers = [
              "nixd"
              "!nil"
            ];

            ui_font_size = 14;
            ui_font_family = "Zed Plex Sans";
            buffer_font_size = 15;
            buffer_font_family = "JetBrains Mono";
            buffer_font_weight = 500;
            icon_theme = "Catppuccin Mocha";

            terminal = {
              font_family = "JetBrainsMono Nerd Font Mono";
              font_weight = 500;
            };

            theme = {
              mode = "system";
              light = "Catppuccin Mocha";
              dark = "Catppuccin Mocha";
            };

            git_panel = {
              dock = "right";
            };
            agent = {
              dock = "right";
              play_sound_when_agent_done = "always";
            };
            # Setting CLAUDE_CODE_EXECUTABLE would put MCP servers' `env` and `headers` on the adapter's command line.
            agent_servers = lib.mkIf config.programs.claude-code.enable {
              claude-acp.type = "registry";
            };
            outline_panel = {
              dock = "right";
            };
            project_panel = {
              dock = "left";
            };
            tab_bar = {
              show = true;
            };
          };
        };
      };
  };
}
