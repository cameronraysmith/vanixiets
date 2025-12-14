# macOS custom user preferences for specific applications
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
          # Disabled: blocks remote deployment via `clan machines update`
          # - com.apple.Music: domain doesn't exist if app never opened
          # "com.apple.Music" = {
          #   userWantsPlaybackNotifications = false;
          # };
          # - com.apple.TextEdit: sandboxed app, can't write via sudo
          # "com.apple.TextEdit" = {
          #   SmartQuotes = false;
          #   RichText = false;
          # };
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
