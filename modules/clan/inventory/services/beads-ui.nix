{
  clan.inventory.instances.beads-ui = {
    module = {
      name = "beads-ui";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        enable = false;
        port = 3009;
      };
    };
  };
}
