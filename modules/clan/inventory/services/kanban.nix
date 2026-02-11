{
  clan.inventory.instances.kanban = {
    module = {
      name = "kanban";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        port = 3008;
      };
    };
  };
}
