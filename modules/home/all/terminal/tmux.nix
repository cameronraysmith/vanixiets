{ pkgs, ... }:
let
  tmux-sessionx = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-sessionx";
    version = "unstable-2025-01-30";
    src = pkgs.fetchFromGitHub {
      owner = "omerxx";
      repo = "tmux-sessionx";
      rev = "fe704934f8cec16f07fcb9e722ed868fd769c647";
      sha256 = "0yfxinx6bdddila3svszpky9776afjprn26c8agj6sqh8glhiz3b";
    };
  };
in
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
      tmuxPlugins.better-mouse-mode
      tmuxPlugins.catppuccin
      tmuxPlugins.fzf-tmux-url
      tmuxPlugins.yank
      tmuxPlugins.prefix-highlight
      tmuxPlugins.tmux-fzf
      tmuxPlugins.tmux-thumbs
      tmuxPlugins.resurrect
      tmuxPlugins.continuum
      tmuxPlugins.tmux-floax
      tmux-sessionx
      tmuxPlugins.session-wizard
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
      bind ^R send-keys "clear"\; send-keys "Enter"

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

      # Plugin: tmux-floax (floating window)
      set -g @floax-width '80%'
      set -g @floax-height '80%'
      set -g @floax-border-color 'magenta'
      set -g @floax-text-color 'blue'
      set -g @floax-bind 'p'
      set -g @floax-change-path 'true'

      # Plugin: session-wizard (session management)
      set -g @session-wizard 't'
      set -g @session-wizard-height 80
      set -g @session-wizard-width 80

      # Plugin: sessionx (advanced session/path management with zoxide)
      set -g @sessionx-bind 'o'
      set -g @sessionx-zoxide-mode 'on'
      set -g @sessionx-window-height '85%'
      set -g @sessionx-window-width '75%'
      set -g @sessionx-filter-current 'false'
      set -g @sessionx-preview-location 'right'
      set -g @sessionx-preview-ratio '55%'

      # Plugin: resurrect + continuum (session persistence)
      set -g @resurrect-strategy-nvim 'session'
      set -g @resurrect-capture-pane-contents 'on'
      set -g @continuum-restore 'on'
      set -g @continuum-boot 'on'
      set -g @continuum-save-interval '15'

      # Plugin: catppuccin (theme)
      # Custom separators using shell printf to preserve UTF-8 encoding
      # Left: U+E0B6 (nf-ple-left_half_circle_thick) = \xee\x82\xb6
      # Right: U+E0B4 (nf-ple-right_half_circle_thick) = \xee\x82\xb4
      # Block: U+2588 (█) = \xe2\x96\x88
      # Zoom: U+F531 (nf-oct-zoom_in) = \xef\x94\xb1
      set -g @catppuccin_window_status_style 'custom'
      set -g @catppuccin_window_left_separator "$(printf '\xee\x82\xb6')"
      set -g @catppuccin_window_right_separator "$(printf '\xee\x82\xb4 ')"
      set -g @catppuccin_window_middle_separator " $(printf '\xe2\x96\x88')"
      set -g @catppuccin_window_number_position 'right'
      set -g @catppuccin_window_default_fill 'number'
      set -g @catppuccin_window_default_text '#W'
      set -g @catppuccin_window_current_fill 'number'
      set -g @catppuccin_window_current_text "#W#{?window_zoomed_flag,$(printf '\xef\x94\xb1'),}"

      set -g @catppuccin_status_modules_right 'directory date_time'
      set -g @catppuccin_status_modules_left 'session'
      set -g @catppuccin_status_left_separator "$(printf '\xee\x82\xb6 ')"
      set -g @catppuccin_status_right_separator "$(printf '\xee\x82\xb4')"
      set -g @catppuccin_status_right_separator_inverse 'no'
      set -g @catppuccin_status_fill 'icon'
      set -g @catppuccin_status_connect_separator 'no'
      set -g @catppuccin_directory_text '#{b:pane_current_path}'
      set -g @catppuccin_date_time_text '%H:%M'
    '';
  };

  programs.tmate = {
    enable = true;
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
