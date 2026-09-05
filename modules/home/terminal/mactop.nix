{ ... }:
{
  flake.modules.homeManager.terminal =
    { pkgs, lib, ... }:
    {
      home.packages = lib.optionals pkgs.stdenv.isDarwin [ pkgs.mactop ];
    };
}
