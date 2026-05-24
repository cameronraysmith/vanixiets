{
  # Advanced nix settings: garbage collection, store optimization
  # Auto-merges into base namespace
  # Platform-aware: darwin launchd interval vs nixos systemd dates
  flake.modules.darwin.base =
    { pkgs, lib, ... }:
    {
      # Automatic garbage collection (darwin uses launchd interval)
      nix.gc = {
        automatic = true;
        options = "--delete-older-than 14d";
        interval = {
          Weekday = 5; # Friday
          Hour = 21; # 9pm
          Minute = 0;
        };
      };

      # Automatic store optimization via hardlinking
      nix.optimise.automatic = true;

      # Additional nix settings
      nix.settings = {
        # Fleet is aarch64-only; no x86_64-darwin in extra-platforms
        extra-platforms = lib.mkIf pkgs.stdenv.isDarwin "aarch64-darwin";

        # Note: min-free/max-free omitted - clan-core already sets conservative defaults
        # (3GB max-free / 512MB min-free via clan.core.enableRecommendedDefaults)
      };
    };

  flake.modules.nixos.base =
    { pkgs, lib, ... }:
    {
      # Automatic garbage collection (nixos uses systemd dates)
      # Pin to 4am America/New_York year-round (timezone-aware OnCalendar);
      # bounded 5-minute jitter avoids default ~45min randomized delay.
      nix.gc = {
        automatic = true;
        options = "--delete-older-than 14d";
        dates = "*-*-* 04:00:00 America/New_York";
        randomizedDelaySec = "5min";
      };

      # Automatic store optimization via hardlinking
      nix.optimise.automatic = true;

      # Note: min-free/max-free omitted - clan-core already sets conservative defaults
      # (3GB max-free / 512MB min-free via clan.core.enableRecommendedDefaults)
    };
}
