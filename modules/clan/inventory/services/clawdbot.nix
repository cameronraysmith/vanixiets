# Clawdbot Matrix gateway on cinnabar
{
  clan.inventory.instances.clawdbot = {
    module = {
      name = "clawdbot";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        homeserver = "https://matrix.zt";
        botUserId = "@clawd:matrix.zt";
        port = 18789;
      };
    };
  };
}
