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

  # Bootstrap: enable linux-builder for first build, then disable
  # See: docs/notes/containers/multi-arch-container-builds.md
  nix.linux-builder.enable = true; # TODO: disable after first successful darwin-rebuild

  nix-rosetta-builder = {
    enable = true;
    onDemand = true;
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
