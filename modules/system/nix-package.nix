{ config, ... }:
let
  flakeLib = config.flake.lib;
  nixPackage =
    { lib, pkgs, ... }:
    {
      nix.package = lib.mkDefault (flakeLib.fleetNix pkgs);
    };
in
{
  flake.modules.nixos.base = nixPackage;
  flake.modules.darwin.base = nixPackage;
}
