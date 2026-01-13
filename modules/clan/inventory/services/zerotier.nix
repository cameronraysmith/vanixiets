# Zerotier VPN with cinnabar as controller, NixOS peers, and external darwin members
{
  clan.inventory.instances.zerotier = {
    module = {
      name = "zerotier";
      input = "clan-core";
    };
    # Replace with the name (string) of your machine that you will use as zerotier-controller
    # See: https://docs.zerotier.com/controller/
    # Deploy this machine first to create the network secrets
    roles.controller.machines."cinnabar" = {
      settings = {
        # External members (darwin machines not managed by clan zerotier service)
        allowedIps = [
          "fddb:4344:343b:14b9:399:930e:e971:d9e0" # blackphos (darwin, member ID: 0ee971d9e0)
          "fddb:4344:343b:14b9:399:933e:1059:d43a" # stibnite (darwin, member ID: 3e1059d43a)
          "fddb:4344:343b:14b9:399:93f7:54d5:ad7e" # argentum (darwin, member ID: f754d5ad7e)
          "fddb:4344:343b:14b9:399:9315:3431:ee8" # rosegold (darwin, member ID: 1534310ee8)
          "fddb:4344:343b:14b9:399:939f:c45d:577c" # android (member ID: 9fc45d577c)
        ];
      };
    };
    # Peers of the network (NixOS machines only - darwin uses external zerotier-one)
    roles.peer.tags."peer" = { };
  };
}
