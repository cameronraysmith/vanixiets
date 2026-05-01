{ lib, ... }:
{
  flake.users.christophersmith.identity =
    {
      config,
      pkgs,
      ...
    }:
    {
      home.username = lib.mkDefault "christophersmith";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );
    };
}
