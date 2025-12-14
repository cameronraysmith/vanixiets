# Nix configuration for darwin systems
# Note: overlays handled separately in modules/nixpkgs/
{ ... }:
{
  flake.modules = {
    darwin.base =
      {
        config,
        inputs,
        pkgs,
        lib,
        ...
      }:
      {
        # Allow unfree packages (copilot, etc.)
        nixpkgs.config = {
          allowBroken = true;
          allowUnsupportedSystem = true;
          allowUnfree = true;
        };

        nix = {
          # Enables use of `nix-shell -p ...` etc with pinned nixpkgs
          nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

          # Make `nix shell` etc use pinned nixpkgs
          registry.nixpkgs.flake = inputs.nixpkgs;

          # Automatic garbage collection
          gc = {
            automatic = true;
            options = "--delete-older-than 14d";
            # Darwin-specific: use launchd interval
            interval = {
              Weekday = 5; # Friday
              Hour = 21; # 9pm
              Minute = 0;
            };
          };

          # Automatic store optimization via hardlinking
          optimise.automatic = true;

          settings = {
            accept-flake-config = true;
            build-users-group = lib.mkDefault "nixbld";

            # Merge with base.nix experimental-features
            experimental-features = [
              "nix-command"
              "flakes"
              "auto-allocate-uids"
            ];

            # Enable Rosetta builds on Apple Silicon
            extra-platforms = "aarch64-darwin x86_64-darwin";

            # Empty flake registry (use pinned inputs only)
            flake-registry = builtins.toFile "empty-flake-registry.json" ''{"flakes":[],"version":2}'';

            max-jobs = "auto";

            # Space-based automatic GC handled by clan-core nix-settings
            # clan-core sets: min-free = 1GB, max-free = 3GB
            # Override per-machine if needed with lib.mkForce
          };
        };
      };
  };
}
