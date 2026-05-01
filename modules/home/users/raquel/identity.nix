{ lib, ... }:
{
  flake.users.raquel.identity =
    {
      config,
      pkgs,
      ...
    }:
    {
      home.username = lib.mkDefault "raquel";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );
    };
}
