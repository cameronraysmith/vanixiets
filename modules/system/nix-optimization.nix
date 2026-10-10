{
  # Advanced nix settings: store optimization, platforms
  # Auto-merges into base namespace
  # Garbage collection lives in modules/system/harmonia-gc.nix
  flake.modules.darwin.base =
    { pkgs, lib, ... }:
    {
      # Additional nix settings
      nix.settings = {
        # Fleet is aarch64-only; no x86_64-darwin in extra-platforms
        extra-platforms = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin "aarch64-darwin";

        # min-free/max-free: set in modules/darwin/nix-settings.nix as a small
        # backstop to harmonia-gc, overriding clan-core's 512 MiB / ~3 GiB defaults.
      };
    };

  flake.modules.nixos.base =
    { pkgs, lib, ... }:
    {
      # Automatic store optimization via hardlinking
      nix.optimise.automatic = true;

      # Note: min-free/max-free omitted - clan-core already sets conservative defaults
      # (3GB max-free / 512MB min-free via clan.core.enableRecommendedDefaults)
    };
}
