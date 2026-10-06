# Nix configuration for darwin systems
# Note: nixpkgs instance (allowUnfree, overlays) comes from
# modules/nixpkgs/base-defaults.nix via nixpkgs.pkgs
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

          # No scheduled `nix-store --optimise` on darwin. Hardlinking an existing
          # store file into /nix/store/.links bumps its inode ctime, which discards
          # syspolicyd's cached malware-scan verdict for any binary already run.
          # The next exec rescans the whole file, and concurrent execs each rescan
          # independently. On 2026-09-27 the 03:45 run relinked the 178 MB omp
          # binary; after the next wake, a burst of omp execs saturated syspolicyd,
          # authd and then WindowServer blocked, and the watchdog ended the session.
          # Run `nix store optimise` by hand (ngc) when disk space matters more.
          optimise.automatic = false;

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

            # Fleet is aarch64-only; no x86_64-darwin in extra-platforms
            extra-platforms = "aarch64-darwin";

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
