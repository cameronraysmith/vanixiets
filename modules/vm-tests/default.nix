{ lib, flake-parts-lib, ... }:
flake-parts-lib.mkTransposedPerSystemModule {
  name = "vmTests";
  option = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.package;
    default = { };
    description = "On-demand VM tests, outside the pull-request checks output.";
  };
  file = ./default.nix;
}
