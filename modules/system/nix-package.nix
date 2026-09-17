let
  nixPackage =
    { lib, pkgs, ... }:
    {
      nix.package = lib.mkDefault pkgs.nixVersions.nix_2_35;
    };
in
{
  flake.modules.nixos.base = nixPackage;
  flake.modules.darwin.base = nixPackage;
}
