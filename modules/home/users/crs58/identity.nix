{ lib, ... }:
{
  flake.users.crs58.identityOverride =
    {
      config,
      pkgs,
      ...
    }:
    {
      home.username = lib.mkDefault "crs58";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );
    };
}
