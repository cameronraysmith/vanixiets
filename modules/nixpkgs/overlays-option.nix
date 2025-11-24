# Declare flake.nixpkgsOverlays as a mergeable list option
#
# This enables dendritic list concatenation pattern where multiple modules
# can append to the same list, which is then composed into overlays.
#
# Without this declaration, flake-parts treats multiple assignments to
# flake.nixpkgsOverlays as conflicts rather than mergeable list items.
#
# Pattern from flake-parts/modules/overlays.nix using mkSubmoduleOptions
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

          Multiple modules can append to this list, enabling dendritic
          overlay composition pattern. The overlays are composed using
          lib.composeManyExtensions in compose.nix.
        '';
      };
    };
  };
}
