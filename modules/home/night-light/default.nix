# Scheduled night light through DankMaterialShell's own Night Mode, the
# counterpart of macOS Night Shift. DMS is the only wlr-gamma-control client
# on the output; a second one, such as gammastep, would be refused.
#
# DMS keeps Night Mode in ~/.local/state/dms/session.json, which its Settings
# window (Display > Gamma Control) and Control Center tile rewrite, and it
# drops every key equal to its built-in default when saving. The schedule is
# therefore seeded once (seed-json-defaults.sh) behind a versioned marker:
# keys the file lacks are added, the user's own values win, and nothing is
# written again, so turning Night Mode off in the GUI sticks. Bump the marker
# version to re-seed after changing the values below.
#
# A running DMS never rereads session.json and saves its in-memory state over
# it, so seeding restarts dms.service when it is active, once; the marker is
# written only when DMS was not running or came back after the restart.
#
# DMS's manual schedule (core/internal/server/wayland/manager.go) is reddest
# from start + transition until end - transition, in the host's local time
# zone: 17:00 to 06:00 here, fading over the half hour on either side.
{ ... }:
let
  program =
    pkgs:
    pkgs.writeShellApplication {
      name = "seed-json-defaults";
      runtimeInputs = [
        pkgs.jq
        pkgs.coreutils
      ];
      text = builtins.readFile ./seed-json-defaults.sh;
    };
in
{
  flake.lib.seedJsonDefaultsProgram = program;

  flake.modules.homeManager.night-light =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      stateDir = "${config.xdg.stateHome}/dms";
      defaults = (pkgs.formats.json { }).generate "dms-night-mode-defaults.json" {
        nightModeEnabled = true;
        nightModeAutoEnabled = true;
        nightModeAutoMode = "time";
        nightModeStartHour = 16;
        nightModeStartMinute = 30;
        nightModeEndHour = 6;
        nightModeEndMinute = 30;
        nightModeTransitionMinutes = 30;
        # The lowest temperature both the settings slider and the gamma backend accept.
        nightModeTemperature = 1000;
        nightModeHighTemperature = 6500;
        nightModeUseIPLocation = false;
      };
      # Activation under the NixOS module runs from home-manager-<user>.service
      # without XDG_RUNTIME_DIR unless the user is logged in; this falls back
      # the way home-manager's own reloadSystemd step does. Without a user
      # manager no DMS is running, so the file alone is effective.
      settle = pkgs.writeShellApplication {
        name = "dms-night-mode-settle";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
          systemctl=${lib.escapeShellArg config.systemd.user.systemctlPath}
          if [ ! -S "$XDG_RUNTIME_DIR/systemd/private" ]; then
            exit 0
          fi
          # show fails when the manager cannot be reached; is-active would report that as inactive.
          state=$("$systemctl" --user show --property=ActiveState --value dms.service)
          case $state in
            inactive | failed) exit 0 ;;
          esac
          "$systemctl" --user try-restart dms.service
          "$systemctl" --user --quiet is-active dms.service
        '';
      };
    in
    {
      assertions = [
        {
          assertion = config.programs.dank-material-shell.session == { };
          message = "night-light seeds DMS's session.json, which programs.dank-material-shell.session would make a read-only store link.";
        }
      ];

      home.activation.dmsNightModeDefaults =
        lib.hm.dag.entryAfter
          [
            "writeBoundary"
            "reloadSystemd"
          ]
          ''
            run ${lib.getExe (program pkgs)} \
              ${lib.escapeShellArg "${stateDir}/session.json"} \
              ${lib.escapeShellArg "${stateDir}/.vanixiets-night-mode-seeded-v1"} \
              ${defaults} \
              ${lib.getExe settle}
          '';
    };
}
