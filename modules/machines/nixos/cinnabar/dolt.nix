{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" = {
    services.dolt-sql-server.enable = true;
  };
}
