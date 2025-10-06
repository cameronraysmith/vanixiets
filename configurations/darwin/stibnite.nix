{
  flake,
  pkgs,
  lib,
  ...
}:

let
  inherit (flake) config inputs;
  inherit (inputs) self;
  adminUser = config.crs58; # explicit admin user for stibnite
in
{
  imports = [
    self.darwinModules.default
    inputs.nix-rosetta-builder.darwinModules.default
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  system.primaryUser = adminUser.username;

  # Bootstrap step 1 complete: linux-builder was used to build nix-rosetta-builder VM
  # Now disabled in favor of nix-rosetta-builder
  # See: docs/notes/containers/multi-arch-container-builds.md
  nix.linux-builder.enable = false;

  # Bootstrap step 2: nix-rosetta-builder is now the primary Linux builder
  nix-rosetta-builder = {
    enable = true;
    onDemand = true; # VM powers off when idle to save resources
    permitNonRootSshAccess = true; # Allow nix-daemon to read SSH key (safe for localhost-only VM)
    cores = 8;
    memory = "6GiB";
    diskSize = "100GiB";
  };

  custom.homebrew = {
    enable = true;
    additionalCasks = [
      "codelayer-nightly"
      "dbeaver-community"
      "docker-desktop"
      "gpg-suite"
      "inkscape"
      "keycastr"
      "meld"
      "postgres-unofficial"
    ];
    additionalMasApps = {
      save-to-raindrop-io = 1549370672;
    };
    manageFonts = false;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
}
