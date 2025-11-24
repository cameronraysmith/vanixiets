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
        # Platform-specific: darwin can build both aarch64 and x86_64
        extra-platforms = lib.mkIf pkgs.stdenv.isDarwin "aarch64-darwin x86_64-darwin";

        # Note: min-free/max-free omitted - clan-core already sets conservative defaults
        # (3GB max-free / 512MB min-free via clan.core.enableRecommendedDefaults)
      };
    };

  flake.modules.nixos.base =
    { pkgs, lib, ... }:
    {
      # Automatic garbage collection (nixos uses systemd dates)
      nix.gc = {
        automatic = true;
        options = "--delete-older-than 14d";
        dates = "weekly";
      };

      # Automatic store optimization via hardlinking
      nix.optimise.automatic = true;

      # Note: min-free/max-free omitted - clan-core already sets conservative defaults
      # (3GB max-free / 512MB min-free via clan.core.enableRecommendedDefaults)
    };
}
