{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, ... }:
    {
      services.dolt-sql-server = {
        enable = false;
        user = config.users.users.cameron.name;
        group = "users";
      };
    };
}
