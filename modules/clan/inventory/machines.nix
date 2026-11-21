# A NixOS machine's deploy.targetHost is flake.lib.hosts.<name>.targetHost.
# Darwin machines carry none: with it set, `clan machines update` would skip
# the network peers (tincr) for the darwin login user (F36,
# flake.lib.networkTargetObligations).
{ config, ... }:
let
  inherit (config.flake.lib) hosts;
in
{
  flake.lib.machineSystems = {
    argentum = "aarch64-darwin";
    blackphos = "aarch64-darwin";
    cinnabar = "x86_64-linux";
    electrum = "x86_64-linux";
    galena = "x86_64-linux";
    magnetite = "x86_64-linux";
    pyrite = "x86_64-linux";
    rosegold = "aarch64-darwin";
    scheelite = "x86_64-linux";
    stibnite = "aarch64-darwin";
  };

  flake.clan.inventory.machines = {
    cinnabar = {
      tags = [
        "nixos"
        "cloud"
        "hetzner"
        "controller"
      ];
      machineClass = "nixos";
      description = "Primary VPS, zerotier controller";
      deploy.targetHost = hosts.cinnabar.targetHost;
    };

    electrum = {
      tags = [
        "nixos"
        "cloud"
        "hetzner"
        "peer"
      ];
      machineClass = "nixos";
      description = "Secondary test VM, zerotier peer";
      deploy.targetHost = hosts.electrum.targetHost;
    };

    galena = {
      tags = [
        "nixos"
        "cloud"
        "gcp"
        "peer"
      ];
      machineClass = "nixos";
      description = "GCP CPU node (e2-standard-8), zerotier peer";
      deploy.targetHost = hosts.galena.targetHost;
    };

    scheelite = {
      tags = [
        "nixos"
        "cloud"
        "gcp"
        "gpu"
        "peer"
      ];
      machineClass = "nixos";
      description = "GCP GPU node (n1-standard-8, T4), zerotier peer";
      deploy.targetHost = hosts.scheelite.targetHost;
    };

    magnetite = {
      tags = [
        "nixos"
        "cloud"
        "hetzner"
        "peer"
      ];
      machineClass = "nixos";
      description = "Build infrastructure server (niks3, nixbot, Gitea)";
      deploy.targetHost = hosts.magnetite.targetHost;
    };

    pyrite = {
      tags = [
        "nixos"
        "laptop"
        "peer"
      ];
      machineClass = "nixos";
      description = "Apple MacBookPro14,1 bare-metal NixOS laptop, zerotier peer";
      deploy.targetHost = hosts.pyrite.targetHost;
    };

    blackphos = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "fleet"
      ];
      machineClass = "darwin";
      description = "raquel's laptop (primary user), crs58 admin";
    };

    stibnite = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "controller"
      ];
      machineClass = "darwin";
      description = "crs58's primary workstation, deployment controller";
    };

    rosegold = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "fleet"
      ];
      machineClass = "darwin";
      description = "janettesmith's laptop (primary user), cameron admin";
    };

    argentum = {
      tags = [
        "darwin"
        "workstation"
        "laptop"
        "fleet"
      ];
      machineClass = "darwin";
      description = "christophersmith's laptop (primary user), cameron admin";
    };
  };
}
