{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, lib, ... }:
    {
      home.packages = [ ] ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.mactop ];
    };
}
