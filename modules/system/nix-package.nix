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
  flake.modules.nixos.base-nix-package = nixPackage;
  flake.modules.darwin.base-nix-package = nixPackage;
}
