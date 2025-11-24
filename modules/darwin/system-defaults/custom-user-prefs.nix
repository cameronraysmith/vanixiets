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
          "com.apple.Music" = {
            userWantsPlaybackNotifications = false;
          };
          "com.apple.ActivityMonitor" = {
            UpdatePeriod = 1;
          };
          "com.apple.TextEdit" = {
            SmartQuotes = false;
            RichText = false;
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
