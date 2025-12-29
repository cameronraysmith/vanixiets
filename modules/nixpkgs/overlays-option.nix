# Declare flake.nixpkgsOverlays as a mergeable list option
#
# This enables list concatenation where multiple modules can append to
# the same list, which is then composed into overlays.
#
# Without this declaration, flake-parts treats multiple assignments to
# flake.nixpkgsOverlays as conflicts rather than mergeable list items.
{ lib, flake-parts-lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (flake-parts-lib) mkSubmoduleOptions;
in
{
  options = {
    flake = mkSubmoduleOptions {
      nixpkgsOverlays = mkOption {
        type = types.listOf types.unspecified;
        default = [ ];
        description = ''
          List of nixpkgs overlays to be composed together.
          Each overlay should be a function: final -> prev -> attrset

          Multiple modules can append to this list for overlay
          composition. The overlays are composed using
          lib.composeManyExtensions in compose.nix.
        '';
      };
    };
  };
}
