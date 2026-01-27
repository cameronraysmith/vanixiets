# Clawdbot Matrix gateway on cinnabar
{
  clan.inventory.instances.clawdbot = {
    module = {
      name = "clawdbot";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        homeserver = "http://localhost:8008";
        botUserId = "@clawd:matrix.zt";
        port = 18789;
      };
    };
  };
}
