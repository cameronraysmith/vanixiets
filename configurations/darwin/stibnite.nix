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
    # Bootstrap step 1: Comment out nix-rosetta-builder import (requires Linux builder)
    # inputs.nix-rosetta-builder.darwinModules.default
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  system.primaryUser = adminUser.username;

  # Bootstrap step 1: Enable linux-builder to build nix-rosetta-builder VM
  # See: docs/notes/containers/multi-arch-container-builds.md
  nix.linux-builder = {
    enable = true;
    # Override defaults (nix-builder-vm.nix sets: cores=1, memorySize=3072, diskSize=20480)
    config.virtualisation = {
      cores = lib.mkForce 4; # override default 1 core
      memorySize = lib.mkForce 6144; # override default 3GB → 6GB
      diskSize = lib.mkForce 40960; # override default 20GB → 40GB
    };
  };

  # Bootstrap step 2: After first darwin-rebuild succeeds:
  # 1. Uncomment the nix-rosetta-builder import at the top
  # 2. Uncomment the config below
  # 3. Set nix.linux-builder.enable = false
  # 4. Run darwin-rebuild switch again
  # nix-rosetta-builder = {
  #   enable = true;
  #   onDemand = true;
  #   cores = 8;
  #   memory = "6GiB";
  #   diskSize = "100GiB";
  # };

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
