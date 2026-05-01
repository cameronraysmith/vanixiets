{ lib, ... }:
{
  flake.users.janettesmith.identity =
    {
      config,
      pkgs,
      ...
    }:
    {
      home.username = lib.mkDefault "janettesmith";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );
    };
}
