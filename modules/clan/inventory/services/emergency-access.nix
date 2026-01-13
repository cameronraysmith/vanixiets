# Emergency access via root SSH keys for recovery scenarios
{
  clan.inventory.instances.emergency-access = {
    module = {
      name = "emergency-access";
      input = "clan-core";
    };
    roles.default.tags."all" = { };
    roles.default.settings.allowedKeys = {
      "admin-key-1" =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+ camrn86@gmail.com";
    };
  };
}
