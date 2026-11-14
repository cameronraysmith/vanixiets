{ inputs, ... }:
{
  flake.modules.homeManager.niri =
    { config, lib, ... }:
    {
      imports = [ inputs.niri-flake.homeModules.config ];

      programs.niri.settings = {
        layout.focus-ring.enable = false;

        input = {
          # logind also ignores this key on pyrite; neither handler may suspend it.
          power-key-handling.enable = false;
          touchpad = {
            tap = true;
            natural-scroll = true;
          };
        };

        binds =
          (
            with config.lib.niri.actions;
            let
              # One bind holds one action; chained steps go through niri's own IPC.
              act =
                steps:
                spawn-sh (
                  lib.concatMapStringsSep " && " (
                    step: "${lib.getExe config.programs.niri.package} msg action ${step}"
                  ) steps
                );
              floatHalf =
                x:
                act [
                  "move-window-to-floating"
                  "set-window-width 50%"
                  "set-window-height 100%"
                  "move-floating-window -x ${x} -y 0%"
                ];
            in
            {
              "Mod+Return".action = spawn (lib.getExe config.programs.ghostty.package);
              "Mod+Q".action = close-window;
              "Mod+Left".action = focus-column-left;
              "Mod+Right".action = focus-column-right;
              "Mod+Up".action = focus-window-up;
              "Mod+Down".action = focus-window-down;
              "Mod+Shift+Left".action = move-column-left;
              "Mod+Shift+Right".action = move-column-right;
              "Mod+Shift+Up".action = move-window-up;
              "Mod+Shift+Down".action = move-window-down;
              "Mod+Page_Up".action = focus-workspace-up;
              "Mod+Page_Down".action = focus-workspace-down;
              "Mod+Shift+Page_Up".action = move-window-to-workspace-up;
              "Mod+Shift+Page_Down".action = move-window-to-workspace-down;
              "Mod+Shift+E".action = quit;
              # Mirrors stibnite's Raycast Cmd+Alt hotkeys; Mod is Super, the Mac keyboard's Cmd.
              "Mod+Alt+F".action = maximize-window-to-edges;
              # Halves experiment: O1 keeps the window tiled in niri's scrolling strip, O2 floats it onto an exact half of the working area.
              # The operator tries both on pyrite and the losing variant is removed.
              "Mod+Alt+Left".action = act [
                "set-column-width 50%"
                "move-column-to-first"
              ];
              "Mod+Alt+Right".action = act [
                "set-column-width 50%"
                "move-column-to-last"
              ];
              "Mod+Alt+Shift+Left".action = floatHalf "0%";
              "Mod+Alt+Shift+Right".action = floatHalf "50%";
            }
          )
          // lib.optionalAttrs (config.programs.dank-material-shell.enable or false) (
            let
              ipc =
                config.lib.niri.actions.spawn (lib.getExe config.programs.dank-material-shell.package) "ipc"
                  "call";
            in
            {
              "Mod+Space" = {
                action = ipc "spotlight" "toggle";
                hotkey-overlay.title = "Application launcher";
              };
              "Mod+N" = {
                action = ipc "notifications" "toggle";
                hotkey-overlay.title = "Notifications";
              };
              "Mod+Comma" = {
                action = ipc "settings" "toggle";
                hotkey-overlay.title = "Shell settings";
              };
              "Super+Alt+L" = {
                action = ipc "lock" "lock";
                hotkey-overlay.title = "Lock screen";
              };
              "Mod+V" = {
                action = ipc "clipboard" "toggle";
                hotkey-overlay.title = "Clipboard";
              };
              "Mod+X" = {
                action = ipc "powermenu" "toggle";
                hotkey-overlay.title = "Power menu";
              };
              "XF86AudioRaiseVolume" = {
                allow-when-locked = true;
                action = ipc "audio" "increment" "3";
              };
              "XF86AudioLowerVolume" = {
                allow-when-locked = true;
                action = ipc "audio" "decrement" "3";
              };
              "XF86AudioMute" = {
                allow-when-locked = true;
                action = ipc "audio" "mute";
              };
              "XF86AudioMicMute" = {
                allow-when-locked = true;
                action = ipc "audio" "micmute";
              };
              "XF86MonBrightnessUp" = {
                allow-when-locked = true;
                action = ipc "brightness" "increment" "5" "";
              };
              "XF86MonBrightnessDown" = {
                allow-when-locked = true;
                action = ipc "brightness" "decrement" "5" "";
              };
              "XF86KbdBrightnessUp" = {
                allow-when-locked = true;
                action = ipc "brightness" "increment" "5" "leds:spi::kbd_backlight";
              };
              "XF86KbdBrightnessDown" = {
                allow-when-locked = true;
                action = ipc "brightness" "decrement" "5" "leds:spi::kbd_backlight";
              };
              "XF86AudioPlay" = {
                allow-when-locked = true;
                action = ipc "mpris" "playPause";
              };
              "XF86AudioNext" = {
                allow-when-locked = true;
                action = ipc "mpris" "next";
              };
              "XF86AudioPrev" = {
                allow-when-locked = true;
                action = ipc "mpris" "previous";
              };
            }
          );
      };
    };
}
