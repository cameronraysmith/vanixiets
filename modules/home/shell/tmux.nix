# Tmux terminal multiplexer with extensive plugins and catppuccin theme
{ ... }:
{
  flake.modules = {
    homeManager.shell =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      let
        # Tmux plugin for kubernetes context display (required by catppuccin kube module)
        # Provides #{kubectx_context} and #{kubectx_namespace} variables
        # Patched to use yq-go (mikefarah/yq) instead of python-yq for correct YAML parsing
        tmux-kubectx = pkgs.tmuxPlugins.mkTmuxPlugin {
          pluginName = "tmux-kubectx";
          version = "unstable-2024-12-28";
          src = pkgs.fetchFromGitHub {
            owner = "tony-sol";
            repo = "tmux-kubectx";
            rev = "7913d57d72d7162f6b0e6050d4c9364b129d7215";
            sha256 = "0lymdzd5a8ycs6rqahn4yl2hyi5fy60w0jsg38wlxqa5ysa2mdqs";
          };

          # Patch to use full paths to yq-go and kubectl, and fix tilde expansion bug
          postPatch = ''
            substituteInPlace scripts/utils/kube.sh \
              --replace-fail 'command -v yq' 'command -v ${pkgs.lib.getExe pkgs.yq-go}' \
              --replace-fail 'command yq' '${pkgs.lib.getExe pkgs.yq-go}' \
              --replace-fail 'command kubectl' '${pkgs.lib.getExe pkgs.kubectl}' \
              --replace-fail '~/.kube/config' '$HOME/.kube/config'
          '';
        };
      in
      {
        # Integrated catppuccin-nix module for tmux theme
        # Pattern 6 (flake.inputs module import): catppuccin home-manager module
        imports = [ flake.inputs.catppuccin.homeModules.catppuccin ];

        catppuccin.tmux = {
          enable = true;
          extraConfig = ''
            # Window tab styling
            set -g @catppuccin_window_status_style 'rounded'
            set -g @catppuccin_window_number_position 'right'
            set -g @catppuccin_window_flags 'icon'

            # Use basename of current path for window names
            set -g @catppuccin_window_text ' #{b:pane_current_path}'
            set -g @catppuccin_window_current_text ' #{b:pane_current_path}'

            # Status bar separators
            set -g @catppuccin_status_left_separator ""
            set -g @catppuccin_status_right_separator ""
            set -g @catppuccin_status_right_separator_inverse "no"
            set -g @catppuccin_status_fill "icon"
            set -g @catppuccin_status_connect_separator "no"
            set -g @catppuccin_status_middle_separator " "

            # Module customizations
            set -g @catppuccin_host_text ' @#H'
            set -g @catppuccin_date_time_text '%H:%M %d-%b-%y'

            # Kubernetes module customizations (set BEFORE loading catppuccin)
            set -gF @catppuccin_kube_context_color "#{E:@thm_sky}"
            set -g @catppuccin_kube_text " #{l:#[fg=#{@catppuccin_kube_context_color}]#{kubectx_context}#[fg=default]:#[fg=#{@catppuccin_kube_namespace_color}]#{kubectx_namespace}}"
          '';
        };

        programs.tmux = {
          enable = true;
          shell = "${pkgs.zsh}/bin/zsh";
          terminal = "tmux-256color";
          shortcut = "a";
          keyMode = "vi";
          baseIndex = 1;
          historyLimit = 1000000;
          newSession = true;
          escapeTime = 10;
          secureSocket = false;
          disableConfirmationPrompt = true;

          plugins = with pkgs; [
            # Mouse support improvements
            tmuxPlugins.better-mouse-mode

            # URL selection and opening
            tmuxPlugins.fzf-tmux-url

            # Copy to system clipboard
            tmuxPlugins.yank

            # Highlight when prefix is active
            tmuxPlugins.prefix-highlight

            # Fuzzy finder integration
            tmuxPlugins.tmux-fzf

            # Hint-based text copying (vimium-style)
            tmuxPlugins.tmux-thumbs

            # Session persistence
            {
              plugin = tmuxPlugins.resurrect;
              extraConfig = ''
                # Restore nvim sessions
                set -g @resurrect-strategy-nvim 'session'
                # Capture and restore pane contents
                set -g @resurrect-capture-pane-contents 'on'
              '';
            }

            # Automatic session save/restore
            {
              plugin = tmuxPlugins.continuum;
              extraConfig = ''
                # Manual restore for explicit control
                set -g @continuum-restore 'off'
                set -g @continuum-boot 'off'
                # Auto-save every 3 minutes
                set -g @continuum-save-interval '3'
              '';
            }

            # Floating window support
            {
              plugin = tmuxPlugins.tmux-floax;
              extraConfig = ''
                set -g @floax-width '80%'
                set -g @floax-height '80%'
                set -g @floax-border-color 'magenta'
                set -g @floax-text-color 'blue'
                # Bind to prefix + p
                set -g @floax-bind 'p'
                set -g @floax-change-path 'true'
              '';
            }

            # Advanced session/window selector with zoxide integration
            # https://github.com/omerxx/tmux-sessionx
            #
            # Fuzzy session manager with preview, creation, deletion, and navigation.
            # Bound to prefix+o for quick access.
            #
            # Default keybindings (within sessionx popup):
            # - enter               : Switch to selected session (or create new if name doesn't exist)
            # - alt-backspace       : Delete selected session
            # - ctrl-r              : Rename selected session
            # - ctrl-w              : Window mode - show all windows across all sessions
            # - ctrl-x              : Browse ~/.config (or custom path) to create session from directory
            # - ctrl-e              : Expand PWD - search local subdirectories to create sessions
            # - ctrl-b              : Back - return to initial session list view
            # - ctrl-t              : Tree mode - hierarchical view of sessions+windows
            # - ctrl-/              : Tmuxinator - list tmuxinator project templates (if enabled)
            # - ctrl-g              : fzf-marks - show bookmarked directories (if enabled)
            # - ctrl-u / ctrl-d     : Scroll preview up/down
            # - ctrl-n / ctrl-p     : Navigate selection up/down
            # - ?                   : Toggle preview pane visibility
            #
            # With zoxide integration enabled, non-matching input queries zoxide for smart path matching.
            {
              plugin = tmuxPlugins.tmux-sessionx;
              extraConfig = ''
                # Bind to prefix + o
                set -g @sessionx-bind 'o'
                set -g @sessionx-zoxide-mode 'on'
                set -g @sessionx-window-height '85%'
                set -g @sessionx-window-width '75%'
                set -g @sessionx-filter-current 'false'
                set -g @sessionx-preview-location 'right'
                set -g @sessionx-preview-ratio '55%'
              '';
            }

            # Session creation wizard
            {
              plugin = tmuxPlugins.session-wizard;
              extraConfig = ''
                # Bind to prefix + t
                set -g @session-wizard 't'
                set -g @session-wizard-height 80
                set -g @session-wizard-width 80
              '';
            }

            # Kubernetes context/namespace display - manually loaded in extraConfig due to nixpkgs naming issue
            # (nixpkgs generates tmux_kubectx.tmux but the actual file is kubectx.tmux)

            # Command palette and keybinding discovery (must load last to override Space)
            {
              plugin = tmuxPlugins.tmux-which-key;
              extraConfig = ''
                # Enable XDG-compliant configuration
                set -g @tmux-which-key-xdg-enable 1

                # Explicitly source the XDG init file to ensure it loads
                run-shell "[ -f ${config.xdg.dataHome}/tmux/plugins/tmux-which-key/init.tmux ] && tmux source-file ${config.xdg.dataHome}/tmux/plugins/tmux-which-key/init.tmux"
              '';
            }
          ];

          extraConfig = ''
            # Build status bar using catppuccin's recommended pattern (see README.md:160-164):
            # - Use -ag for modules with dynamic tmux vars (#S, #H, time formats)
            # - Use -agF for modules with plugin-populated variables or shell commands
            # - Gitmux uses #{@...} without E: per catppuccin docs (line 177)
            set -g status-left-length 100
            set -g status-left ""
            set -ag status-left "#{E:@catppuccin_status_session}"

            set -g status-right-length 200
            set -g status-right ""
            set -agF status-right "#{E:@catppuccin_status_kube}"
            set -agF status-right "#{@catppuccin_status_gitmux}"
            set -ag status-right "#{E:@catppuccin_status_host}"
            set -ag status-right "#{E:@catppuccin_status_date_time}"

            # Initialize tmux-kubectx plugin AFTER setting status-right so it can interpolate #{kubectx_*} placeholders
            run-shell ${tmux-kubectx}/share/tmux-plugins/tmux-kubectx/kubectx.tmux

            # Session and client management
            bind ^X lock-server
            bind ^C new-window -c "#{pane_current_path}"
            bind ^D detach
            bind S choose-session

            # Window navigation
            bind H previous-window
            bind L next-window
            bind ^A last-window
            bind ^W list-windows
            bind w list-windows
            bind M move-window -t 0
            bind ^T clock-mode

            # Window management
            bind r command-prompt "rename-window %%"
            bind R source-file ~/.config/tmux/tmux.conf
            bind C-l send-keys "clear"\; send-keys "Enter"

            # Pane splitting (keep current path)
            bind | split-window -h -c "#{pane_current_path}"
            bind s split-window -v -c "#{pane_current_path}"
            bind v split-window -h -c "#{pane_current_path}"

            # Pane navigation (vim-style)
            bind h select-pane -L
            bind j select-pane -D
            bind k select-pane -U
            bind l select-pane -R

            # Pane management
            bind z resize-pane -Z
            bind x swap-pane -D
            bind @ choose-tree 'join-pane -h -t "%%"'
            bind c kill-pane
            bind * setw synchronize-panes
            bind P set pane-border-status

            # Display toggles
            bind b set-option -g status

            # Pane resizing (repeatable)
            bind -r -T prefix , resize-pane -L 20
            bind -r -T prefix . resize-pane -R 20
            bind -r -T prefix - resize-pane -D 7
            bind -r -T prefix = resize-pane -U 7

            # Command and navigation helpers
            bind : command-prompt
            bind ^L refresh-client
            bind -n M-\' choose-window
            bind-key "K" display-popup -E -w 80% -h 80% "sesh connect \"$(sesh list -i | gum filter --limit 1 --placeholder 'Pick a sesh' --prompt='⚡')\""
            bind-key -T copy-mode-vi v send-keys -X begin-selection

            # Terminal capabilities for truecolor and cursor shapes
            set -ga terminal-overrides ",*256col*:RGB"
            set -ga terminal-overrides ",*:Ss=\\E[%p1%d q:Se=\\E[0 q"
            set-environment -g COLORTERM "truecolor"

            # Modern tmux features
            set -g focus-events off
            setw -g aggressive-resize on

            # User experience settings
            set-option -g mouse on
            set -g detach-on-destroy off
            set -g renumber-windows on
            set -g set-clipboard on
            set -g status-position top

            # Visual styling
            set -g pane-active-border-style 'fg=magenta,bg=default'
            set -g pane-border-style 'fg=brightblack,bg=default'
          '';
        };

        programs.tmate = {
          enable = true;
        };

        # Fix tmux-which-key XDG file permissions
        # The plugin copies files from Nix store (read-only) to XDG dirs, breaking auto-rebuild
        home.activation.fixTmuxWhichKeyPermissions = {
          after = [ "writeBoundary" ];
          before = [ ];
          data = ''
            if [ -f "${config.xdg.dataHome}/tmux/plugins/tmux-which-key/init.tmux" ]; then
              chmod u+w "${config.xdg.dataHome}/tmux/plugins/tmux-which-key/init.tmux"
            fi
            if [ -f "${config.xdg.configHome}/tmux/plugins/tmux-which-key/config.yaml" ]; then
              chmod u+w "${config.xdg.configHome}/tmux/plugins/tmux-which-key/config.yaml"
            fi
          '';
        };

        home.packages = [
          (pkgs.writeShellApplication {
            name = "pux";
            runtimeInputs = [ pkgs.tmux ];
            text = ''
              PRJ="''$(zoxide query -i)"
              echo "Launching tmux for ''$PRJ"
              set -x
              cd "''$PRJ" && \
                exec tmux -S "''$PRJ".tmux attach
            '';
          })
        ];

        # Configure gitmux with catppuccin colors and concise layout for git status in tmux
        home.file.".gitmux.conf".text = ''
          tmux:
            styles:
              clear: "#[fg=#{@thm_fg}]"
              state: "#[fg=#{@thm_red},bold]"
              branch: "#[fg=#{@thm_fg},bold]"
              remote: "#[fg=#{@thm_teal}]"
              divergence: "#[fg=#{@thm_fg}]"
              staged: "#[fg=#{@thm_green},bold]"
              conflict: "#[fg=#{@thm_red},bold]"
              modified: "#[fg=#{@thm_yellow},bold]"
              untracked: "#[fg=#{@thm_mauve},bold]"
              stashed: "#[fg=#{@thm_blue},bold]"
              clean: "#[fg=#{@thm_rosewater},bold]"
              insertions: "#[fg=#{@thm_green}]"
              deletions: "#[fg=#{@thm_red}]"
            layout: [branch, " ", flags]
            options:
              branch_max_len: 15
              branch_trim: right
              ellipsis: …
              hide_clean: true
        '';
      };
  };
}
