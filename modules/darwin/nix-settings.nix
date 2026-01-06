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
          # Enable `nix-shell -p ...` etc with pinned nixpkgs via NIX_PATH env var
          # Note: settings.nix-path below also needed for daemon/non-shell contexts
          nixPath = [ "nixpkgs=flake:nixpkgs" ];

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
            # Write nix-path to nix.conf for daemon and non-shell contexts
            # Complements nixPath (env var) above; both needed for full coverage
            # Overrides default behavior of reading /nix/var/nix/profiles/per-user/root/channels
            nix-path = [ "nixpkgs=flake:nixpkgs" ];

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

            # Disable mutable global flake registry (fetched from GitHub by default)
            # Resolution still works via system registry populated by registry.nixpkgs above
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
