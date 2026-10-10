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

            # Backstop only: harmonia-gc (modules/system/harmonia-gc.nix) is the
            # primary reclaimer and runs daily to 15% free. These values exist so a
            # single large build cannot wedge the machine between daily runs. On
            # 2026-10-07 argentum (8 GiB RAM, 250 GB disk) reached 235 MB free under
            # clan-core's 512 MiB / ~3 GiB defaults, macOS had no room for swap, and
            # the session beachballed. 5 GiB min-free covers swap growth on an 8 GiB
            # host plus an in-flight build; 10 GiB max-free stops the daemon's GC
            # early so it does not stall the build that triggered it.
            min-free = 5 * 1024 * 1024 * 1024;
            max-free = 10 * 1024 * 1024 * 1024;
          };
        };
      };
  };
}
