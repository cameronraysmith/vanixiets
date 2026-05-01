{ lib, ... }:
{
  flake.users.tara.identity =
    {
      config,
      pkgs,
      ...
    }:
    {
      home.username = lib.mkDefault "tara";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );
    };
}
