# flake.lib.pins: the package pin type and helper of lib/pins.nix. Packages
# under pkgs/by-name import lib/pins.nix directly, since callPackage gives
# them no flake arguments.
{ lib, ... }:
{
  flake.lib.pins = import ../../lib/pins.nix { inherit lib; };
}
