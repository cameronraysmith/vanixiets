{ ... }:
{
  flake.modules.homeManager.ai =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      herdr = lib.getExe config.programs.herdr.package;
      # Open a new focused herdr tab and run the given command in it, labelled
      # after the command. herdr has no single-shot "new tab running X", so this
      # creates the tab then runs the command in its root pane over the socket.
      htab = pkgs.writeShellApplication {
        name = "htab";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          pane_id="$(${herdr} tab create --label "$1" --focus | jq -r '.result.root_pane.pane_id')"
          exec ${herdr} pane run "$pane_id" "$*"
        '';
      };
    in
    {
      home.packages = [ htab ];
      programs.herdr = {
        enable = true;
        package = pkgs.herdr-bin;
        # https://herdr.dev/docs/configuration/ — ported from modules/home/shell/tmux.nix
        settings = {
          theme = {
            name = "catppuccin";
            auto_switch = true;
            dark_name = "catppuccin";
            light_name = "catppuccin-latte";
          };
          terminal = {
            default_shell = "fish";
            new_cwd = "follow";
          };
          session.resume_agents_on_restore = false;
          ui = {
            confirm_close = false;
            prompt_new_tab_name = false;
            sound.enabled = false;
          };
          advanced.scrollback_limit_bytes = 100000000;
          keys = {
            prefix = "ctrl+a";
            # herdr's vertical/horizontal name the resulting pane arrangement,
            # the opposite axis from tmux's -h/-v flags; mapped by visual result:
            # tmux v/| (side-by-side) -> split_vertical; tmux s (stacked) -> split_horizontal.
            split_vertical = "prefix+v";
            split_horizontal = "prefix+s";
            focus_pane_left = "prefix+h";
            focus_pane_down = "prefix+j";
            focus_pane_up = "prefix+k";
            focus_pane_right = "prefix+l";
            zoom = "prefix+z";
            close_pane = "prefix+c";
            swap_pane_down = "prefix+x";
            # Unbind herdr's default prefix+shift+{h,l} swaps; reused for tab nav below.
            swap_pane_up = "";
            swap_pane_left = "";
            swap_pane_right = "";
            resize_mode = "prefix+r";
            copy_mode = "prefix+[";
            reload_config = "prefix+shift+r";
            detach = [
              "prefix+ctrl+d"
              "prefix+q"
            ];
            new_tab = "prefix+ctrl+c";
            previous_tab = [
              "prefix+shift+h"
              "prefix+p"
            ];
            next_tab = [
              "prefix+shift+l"
              "prefix+n"
            ];
            switch_tab = "prefix+1..9";
            rename_tab = "prefix+shift+t";
            close_tab = "prefix+shift+x";
            workspace_picker = "prefix+shift+s";
            toggle_sidebar = "prefix+b";
            settings = "prefix+comma";
            command = [
              {
                key = "prefix+alt+g";
                type = "shell";
                command = "htab lazygit";
                description = "lazygit in a new tab";
              }
              {
                key = "prefix+alt+e";
                type = "shell";
                command = "htab nvim";
                description = "nvim in a new tab";
              }
            ];
          };
        };
      };
    };
}
