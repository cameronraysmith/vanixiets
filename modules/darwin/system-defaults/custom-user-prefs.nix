# macOS custom user preferences for specific applications
# Merged into darwin.base via dendritic auto-discovery
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
        # Custom User Preferences for specific applications
        CustomUserPreferences = {
          NSGlobalDomain = {
            NSCloseAlwaysConfirmsChanges = false;
            AppleSpacesSwitchOnActivate = true;
          };
          # Note: Removed sandboxed/problematic app preferences that block remote deployment:
          # - com.apple.Music: domain doesn't exist if app never opened
          # - com.apple.TextEdit: sandboxed, can't write via sudo
          "com.apple.ActivityMonitor" = {
            UpdatePeriod = 1;
          };
          "com.apple.spaces" = {
            "spans-displays" = false;
          };
          "com.apple.menuextra.clock" = {
            DateFormat = "EEE d MMM HH:mm:ss";
            FlashDateSeparators = false;
          };
        };
      };
    };
}
