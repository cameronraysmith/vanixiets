{
  clan.inventory.instances.beads-ui = {
    module = {
      name = "beads-ui";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        port = 3009;
      };
    };
  };
}
