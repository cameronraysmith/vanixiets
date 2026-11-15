{ inputs, ... }:
{
  flake.modules.homeManager.niri =
    { config, lib, ... }:
    {
      imports = [ inputs.niri-flake.homeModules.config ];

      programs.niri.settings = {
        layout.focus-ring.enable = false;
        # stibnite's com.apple.screencapture location; the DMS screenshot binds below use the same directory.
        screenshot-path = "~/Downloads/Screenshot from %Y-%m-%d %H-%M-%S.png";

        input = {
          # logind also ignores this key on pyrite; neither handler may suspend it.
          power-key-handling.enable = false;
          # Matches stibnite, where natural scrolling is off: content moves the way the fingers do.
          touchpad = {
            tap = true;
            natural-scroll = false;
          };
          # Matches stibnite, where Caps Lock sends Escape.
          keyboard.xkb.options = "caps:escape";
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
              tiledHalf =
                direction:
                act [
                  "set-column-width 50%"
                  "move-column-${direction}"
                ];
            in
            {
              # A spawn bind without a title is listed by its store path in the DMS shortcuts window.
              "Mod+Return" = {
                action = spawn (lib.getExe config.programs.ghostty.package);
                hotkey-overlay.title = "Terminal";
              };
              "Mod+Q".action = close-window;
              # Focus loops past either end of the strip; niri's layout itself has two ends,
              # so the view scrolls across, and column moves still stop at the ends.
              "Mod+Left".action = focus-column-left-or-last;
              "Mod+Right".action = focus-column-right-or-first;
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
              # Mirrors stibnite's Mission Control; niri's own default for the overview is Mod+O.
              "Ctrl+Up".action = toggle-overview;
              # Mirrors stibnite's Raycast Cmd+Alt hotkeys; Mod is Super, the Mac keyboard's Cmd.
              "Mod+Alt+F".action = maximize-window-to-edges;
              # niri can place a tiled column on half of the view only relative to its neighbour, so a
              # half is 50% width moved one column along; floating halves overlapped filled windows.
              "Mod+Alt+Left" = {
                action = tiledHalf "left";
                hotkey-overlay.title = "Tile window as left half";
              };
              "Mod+Alt+Right" = {
                action = tiledHalf "right";
                hotkey-overlay.title = "Tile window as right half";
              };
              "Mod+Alt+Shift+Left".action = move-column-to-first;
              "Mod+Alt+Shift+Right".action = move-column-to-last;
              "Mod+Alt+Down".action = move-window-to-tiling;
              "Mod+Alt+Up".action = switch-focus-between-floating-and-tiling;
            }
          )
          // lib.optionalAttrs (config.programs.dank-material-shell.enable or false) (
            let
              ipc =
                config.lib.niri.actions.spawn (lib.getExe config.programs.dank-material-shell.package) "ipc"
                  "call";
              # macOS sends Cmd+Shift captures to a file and their Ctrl variants to the clipboard only,
              # and a region is taken on mouse release.
              shot =
                mode: target:
                config.lib.niri.actions.spawn (
                  [
                    (lib.getExe config.programs.dank-material-shell.package)
                    "screenshot"
                    mode
                  ]
                  ++ lib.optional (mode == "region") "--no-confirm"
                  ++ (
                    if target == "file" then
                      [
                        "--no-clipboard"
                        "--dir"
                        "${config.home.homeDirectory}/Downloads"
                      ]
                    else
                      [ "--no-file" ]
                  )
                );
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
              # niri's own default here is its hotkey overlay; the DMS window is searchable and lists every bind.
              "Mod+Shift+Slash" = {
                action = ipc "keybinds" "toggle" "niri";
                hotkey-overlay.title = "Keyboard shortcuts";
              };
              "Mod+Shift+3" = {
                action = shot "full" "file";
                hotkey-overlay.title = "Screenshot of the screen to ~/Downloads";
              };
              "Mod+Ctrl+Shift+3" = {
                action = shot "full" "clipboard";
                hotkey-overlay.title = "Screenshot of the screen to the clipboard";
              };
              "Mod+Shift+4" = {
                action = shot "region" "file";
                hotkey-overlay.title = "Screenshot of a region to ~/Downloads";
              };
              "Mod+Ctrl+Shift+4" = {
                action = shot "region" "clipboard";
                hotkey-overlay.title = "Screenshot of a region to the clipboard";
              };
              "Mod+Shift+5" = {
                action = shot "window" "file";
                hotkey-overlay.title = "Screenshot of the focused window to ~/Downloads";
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
                hotkey-overlay.title = "Volume up";
              };
              "XF86AudioLowerVolume" = {
                allow-when-locked = true;
                action = ipc "audio" "decrement" "3";
                hotkey-overlay.title = "Volume down";
              };
              "XF86AudioMute" = {
                allow-when-locked = true;
                action = ipc "audio" "mute";
                hotkey-overlay.title = "Mute audio";
              };
              "XF86AudioMicMute" = {
                allow-when-locked = true;
                action = ipc "audio" "micmute";
                hotkey-overlay.title = "Mute microphone";
              };
              "XF86MonBrightnessUp" = {
                allow-when-locked = true;
                action = ipc "brightness" "increment" "5" "";
                hotkey-overlay.title = "Display brightness up";
              };
              "XF86MonBrightnessDown" = {
                allow-when-locked = true;
                action = ipc "brightness" "decrement" "5" "";
                hotkey-overlay.title = "Display brightness down";
              };
              "XF86KbdBrightnessUp" = {
                allow-when-locked = true;
                action = ipc "brightness" "increment" "5" "leds:spi::kbd_backlight";
                hotkey-overlay.title = "Keyboard backlight up";
              };
              "XF86KbdBrightnessDown" = {
                allow-when-locked = true;
                action = ipc "brightness" "decrement" "5" "leds:spi::kbd_backlight";
                hotkey-overlay.title = "Keyboard backlight down";
              };
              "XF86AudioPlay" = {
                allow-when-locked = true;
                action = ipc "mpris" "playPause";
                hotkey-overlay.title = "Play or pause media";
              };
              "XF86AudioNext" = {
                allow-when-locked = true;
                action = ipc "mpris" "next";
                hotkey-overlay.title = "Next track";
              };
              "XF86AudioPrev" = {
                allow-when-locked = true;
                action = ipc "mpris" "previous";
                hotkey-overlay.title = "Previous track";
              };
            }
          );
      };
    };
}
