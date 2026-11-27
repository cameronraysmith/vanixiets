# Zerotier VPN with cinnabar as controller, NixOS peers, and external darwin
# and phone members
{ config, lib, ... }:
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
        # External members: every darwin host and phone, which do not run the
        # clan zerotier service, in registry name order; addresses and member
        # ids live in flake.fleet.hosts.
        allowedIps = map (h: h.zerotier.address) (
          lib.attrValues (
            lib.filterAttrs (
              _: h:
              lib.elem h.class [
                "darwin"
                "android"
              ]
            ) config.flake.fleet.hosts
          )
        );
      };
    };
    # Peers of the network (NixOS machines only - darwin uses external zerotier-one)
    roles.peer.extraModules = [ config.flake.modules.nixos.zerotier-mss-clamp ];
    roles.peer.tags."peer" = { };
  };
}
