# macOS miscellaneous system defaults (≤7 lines each)
# Larger setting groups extracted to dedicated modules:
# - CustomUserPreferences → custom-user-prefs.nix
# - loginwindow → loginwindow.nix
# - screencapture → screencapture.nix
# - WindowManager → window-manager.nix
{ ... }:
{
  flake.modules.darwin.base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      system.defaults = {
        # SMB settings
        smb = {
          NetBIOSName = null;
          ServerDescription = null;
        };

        # Spaces settings
        spaces = {
          spans-displays = false;
        };

        # Software Update settings
        SoftwareUpdate = {
          AutomaticallyInstallMacOSUpdates = false;
        };

        # Launch Services settings
        LaunchServices = {
          LSQuarantine = true;
        };

        # Global preferences
        ".GlobalPreferences" = {
          "com.apple.mouse.scaling" = null;
          "com.apple.sound.beep.sound" = null;
        };
      };

      # System startup settings
      system.startup = {
        chime = false;
      };
    };
}
