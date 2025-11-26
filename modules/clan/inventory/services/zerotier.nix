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
        ];
      };
    };
    # Peers of the network
    # tags.all means 'all machines' will joined
    roles.peer.tags."all" = { };
  };
}
