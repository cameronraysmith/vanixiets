# Tor relay service for NixOS machines
{
  clan.inventory.instances.tor = {
    module = {
      name = "tor";
      input = "clan-core";
    };
    roles.server.tags."nixos" = { };
  };
}
