{ flake, pkgs, ... }:

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

  # Bootstrap step 1: Enable linux-builder to build nix-rosetta-builder VM
  # See: docs/notes/containers/multi-arch-container-builds.md
  nix.linux-builder = {
    enable = true;
    # Explicit defaults (from nixpkgs#darwin.linux-builder.nixosConfig.virtualisation):
    config.virtualisation = {
      cores = 4; # default: 4 (increase if builds are slow)
      memorySize = 6144; # default: 6144 (6GB)
      diskSize = 40960; # default: 40960 (40GB)
    };
  };

  # Bootstrap step 2: Enable nix-rosetta-builder after first darwin-rebuild
  # Then disable linux-builder above and rebuild again
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
