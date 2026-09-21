{ ... }:
{
  flake.modules.homeManager.herdr =
    {
      pkgs,
      lib,
      config,
      flake,
      ...
    }:
    let
      herdr = lib.getExe config.programs.herdr.package;
      # Open a new focused herdr tab and run the given command in it, labelled
      # after the command unless `--label NAME` overrides it. herdr has no
      # single-shot "new tab running X", so this creates the tab then runs the
      # command in its root pane over the socket.
      htab = pkgs.writeShellApplication {
        name = "htab";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          if [ "''${1:-}" = "--label" ]; then
            label="$2"
            shift 2
          else
            label="$1"
          fi
          pane_id="$(${herdr} tab create --label "$label" --focus | jq -r '.result.root_pane.pane_id')"
          exec ${herdr} pane run "$pane_id" "$*"
        '';
      };
    in
    {
      home.packages = [ htab ];
      programs.herdr = {
        enable = true;
        package = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
        # https://herdr.dev/docs/configuration/ — ported from modules/home/shell/tmux.nix
        settings = {
          # herdr persists onboarding dismissal by rewriting config.toml
          # (src/config/write.rs: upsert_top_level_bool "onboarding"), which
          # EACCESes against this store symlink and re-toasts every launch.
          # Declaring it is what both Mic92/dotfiles and mirkolenz/infra do.
          onboarding = false;
          # The binary comes from the flake input, so the self-updater has
          # nothing to update and its writes would fail the same way.
          update.version_check = false;
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
          # The two recovery paths are disjoint per pane, not alternatives:
          # persist/restore.rs:785 gives native resume precedence and suppresses
          # replay for that pane only, so history covers shells, logs and any
          # agent pane without a usable session ref. Resume relaunches agent
          # CLIs unattended on server start, which is the risk being accepted.
          # Cost of history: session-history.json holds every pane's full
          # scrollback in plaintext, bounded only by scrollback_limit_bytes.
          session.resume_agents_on_restore = true;
          experimental.pane_history = true;
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
            # herdr's default swap family; prefix+x is tmux's `bind x swap-pane -D`
            # kept as an alias for the down direction.
            swap_pane_left = "prefix+shift+h";
            swap_pane_down = [
              "prefix+shift+j"
              "prefix+x"
            ];
            swap_pane_up = "prefix+shift+k";
            swap_pane_right = "prefix+shift+l";
            resize_mode = "prefix+r";
            copy_mode = "prefix+[";
            reload_config = "prefix+shift+r";
            detach = [
              "prefix+ctrl+d"
              "prefix+q"
            ];
            new_tab = "prefix+ctrl+c";
            # tmux's `bind H`/`bind L` window nav is deliberately not ported here:
            # binding prefix+shift+{h,l} to tab nav wins conflict resolution and
            # silently disables swap_pane_{left,right} above.
            previous_tab = "prefix+p";
            next_tab = "prefix+n";
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
              {
                key = "prefix+!";
                type = "shell";
                command = ''"$HERDR_BIN_PATH" pane move "$HERDR_ACTIVE_PANE_ID" --new-tab --focus'';
                description = "break pane out to new tab";
              }
            ];
          };
        };
      };
    };
}
