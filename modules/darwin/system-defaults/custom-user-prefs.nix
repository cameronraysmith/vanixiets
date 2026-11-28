# macOS custom user preferences for specific applications
{ ... }:
{
  flake.modules.darwin.base-system-defaults =
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
          # Sparkle auto-install (SUAutomaticallyUpdate) replaces an app's own bundle
          # mid-session, forcing a full Gatekeeper re-assessment; a Sparkle auto-install
          # on 2026-09-03 compounded a Logi Options+ lockup. Update *checks*
          # (SUEnableAutomaticChecks) stay on for all of these; only unattended
          # installation is disabled.
          "net.imput.helium" = {
            SUAutomaticallyUpdate = false;
          };
          "com.openai.codex" = {
            SUAutomaticallyUpdate = false;
          };
          "com.steipete.codexbar" = {
            SUAutomaticallyUpdate = false;
          };
          # Modes, prompts, hotkeys and vocabulary are in ./voiceink-settings.json,
          # imported by hand (VoiceInk → Settings → Import); its export omits the
          # recording sounds, so they are set here.
          "com.prakashjoshipax.VoiceInk" = {
            SUAutomaticallyUpdate = false;
            selectedStartSoundSelection = "none";
            selectedStopSoundSelection = "none";
          };
        };
      };
    };
}
