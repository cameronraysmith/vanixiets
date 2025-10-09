{ pkgs, config, ... }:
{
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

      # Theme configuration
      {
        plugin = tmuxPlugins.catppuccin;
        extraConfig = ''
          # Window tab styling
          set -g @catppuccin_window_status_style 'rounded'
          set -g @catppuccin_window_number_position 'right'
          set -g @catppuccin_window_default_fill 'number'
          set -g @catppuccin_window_current_fill 'number'

          # Use basename of current path for window names
          set -g @catppuccin_window_default_text '#{b:pane_current_path}'
          set -g @catppuccin_window_current_text '#{b:pane_current_path}'

          # Status bar modules - only show time/date on right
          set -g @catppuccin_status_modules_right 'date_time'
          set -g @catppuccin_status_modules_left 'session'
          set -g @catppuccin_status_left_separator ' '
          set -g @catppuccin_status_right_separator ' '
          set -g @catppuccin_status_right_separator_inverse 'no'
          set -g @catppuccin_status_fill 'icon'
          set -g @catppuccin_status_connect_separator 'no'

          # Date/time format: HH:MM DD-Mon-YY
          set -g @catppuccin_date_time_text '%H:%M %d-%b-%y'
        '';
      }

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
      bind c kill-pane
      bind * setw synchronize-panes
      bind P set pane-border-status

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
      set -ga terminal-overrides ",*:Ss=\E[%p1%d q:Se=\E[ q"
      set-environment -g COLORTERM "truecolor"

      # Modern tmux features
      set -g focus-events on
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
      if [ -f "$HOME/.local/share/tmux/plugins/tmux-which-key/init.tmux" ]; then
        chmod u+w "$HOME/.local/share/tmux/plugins/tmux-which-key/init.tmux"
      fi
      if [ -f "$HOME/.config/tmux/plugins/tmux-which-key/config.yaml" ]; then
        chmod u+w "$HOME/.config/tmux/plugins/tmux-which-key/config.yaml"
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
}
