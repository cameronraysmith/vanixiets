# Each machine's tags and description are written here; its machineClass is
# flake.fleet.hosts.<name>.class, and a NixOS machine's deploy.targetHost is
# flake.fleet.hosts.<name>.targetHost (modules/lib/hosts.nix). Darwin
# machines carry none: with it set, `clan machines update` would skip the
# network peers (tincr) for the darwin login user (F36,
# flake.lib.networkTargetObligations).
{ config, lib, ... }:
let
  inherit (config.flake.lib) hosts;
in
{
  flake.clan.inventory.machines =
    lib.mapAttrs
      (
        name: machine:
        machine
        // {
          machineClass = hosts.${name}.class;
        }
        // lib.optionalAttrs (hosts.${name}.class == "nixos") {
          deploy.targetHost = hosts.${name}.targetHost;
        }
      )
      {
        cinnabar = {
          tags = [
            "nixos"
            "cloud"
            "hetzner"
            "controller"
          ];
          description = "Primary VPS, zerotier controller";
        };

        electrum = {
          tags = [
            "nixos"
            "cloud"
            "hetzner"
            "peer"
          ];
          description = "Secondary test VM, zerotier peer";
        };

        galena = {
          tags = [
            "nixos"
            "cloud"
            "gcp"
            "peer"
          ];
          description = "GCP CPU node (e2-standard-8), zerotier peer";
        };

        scheelite = {
          tags = [
            "nixos"
            "cloud"
            "gcp"
            "gpu"
            "peer"
          ];
          description = "GCP GPU node (n1-standard-8, T4), zerotier peer";
        };

        magnetite = {
          tags = [
            "nixos"
            "cloud"
            "hetzner"
            "peer"
          ];
          description = "Build infrastructure server (niks3, nixbot, Gitea)";
        };

        pyrite = {
          tags = [
            "nixos"
            "laptop"
            "peer"
          ];
          description = "Apple MacBookPro14,1 bare-metal NixOS laptop, zerotier peer";
        };

        blackphos = {
          tags = [
            "darwin"
            "workstation"
            "laptop"
            "fleet"
          ];
          description = "raquel's laptop (primary user), crs58 admin";
        };

        stibnite = {
          tags = [
            "darwin"
            "workstation"
            "laptop"
            "deployer-workstation"
          ];
          description = "crs58's primary workstation, deployment controller";
        };

        rosegold = {
          tags = [
            "darwin"
            "workstation"
            "laptop"
            "fleet"
          ];
          description = "janettesmith's laptop (primary user), cameron admin";
        };

        argentum = {
          tags = [
            "darwin"
            "workstation"
            "laptop"
            "fleet"
          ];
          description = "christophersmith's laptop (primary user), cameron admin";
        };
      };
}
