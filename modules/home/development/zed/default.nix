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
          package = null;
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
            # Disable AI features to prevent .git/info/exclude pollution from checkpoints
            # See: zed 38391
            disable_ai = true;

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
            ui_font_family = "Cascadia Code";
            buffer_font_size = 12;
            icon_theme = "Catppuccin Mocha";

            theme = {
              mode = "system";
              light = "Catppuccin Mocha";
              dark = "Catppuccin Mocha";
            };

            git_panel = {
              dock = "right";
              sort_by_path = false;
            };
            agent = {
              dock = "right";
              play_sound_when_agent_done = true;
            };
            outline_panel = {
              dock = "right";
            };
            project_panel = {
              dock = "left";
            };
            tab_bar = {
              show = false;
            };
          };
        };
      };
  };
}
