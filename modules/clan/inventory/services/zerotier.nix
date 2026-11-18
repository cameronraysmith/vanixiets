# Zerotier VPN with cinnabar as controller, NixOS peers, and external darwin members
{ config, ... }:
{
  flake.clan.inventory.instances.zerotier = {
    module = {
      name = "zerotier";
      input = "clan-core";
    };
    # Replace with the name (string) of your machine that you will use as zerotier-controller
    # See: https://docs.zerotier.com/controller/
    # Deploy this machine first to create the network secrets
    roles.controller.extraModules = [ config.flake.modules.nixos.zerotier-mss-clamp ];
    roles.controller.machines."cinnabar" = {
      settings = {
        # External members (darwin machines and phones not managed by the clan
        # zerotier service); addresses and member ids live in flake.lib.hosts.
        allowedIps = map (name: config.flake.lib.hosts.${name}.zerotier.address) [
          "blackphos"
          "stibnite"
          "argentum"
          "rosegold"
          "pixel7"
          "pixel11"
        ];
      };
    };
    # Peers of the network (NixOS machines only - darwin uses external zerotier-one)
    roles.peer.extraModules = [ config.flake.modules.nixos.zerotier-mss-clamp ];
    roles.peer.tags."peer" = { };
  };
}
