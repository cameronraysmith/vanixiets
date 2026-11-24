# perSystem.testSizes: each check's and runtime test's declared size class
# (openspec/changes/declare-test-size-classes, design D1 and D2), defined as
# literal data in the module that defines the check or test, keyed by its
# attribute name. `class` is the class of one cold run as the
# preferences-nix-checks-architecture skill's references/test-sizes.md defines
# it; `measured = false` marks a class no run backs yet (design D4); `reason`
# records why a check is large, or why a class is what it is.
#
# Entries are literal or depend only on `system`: reading them must force no
# derivation and no nixpkgs. The option is not transposed into a flake output.
#
# flake.lib.testSizeLimits holds each class's limit in seconds, the timeouts
# Bazel implies for its test sizes; modules/vm-tests/default.nix gives every
# runtime test its class limit as the driver's globalTimeout (design D3).
# flake.lib.enormousTests lists the x86_64-linux runtime tests declared
# enormous. flake.lib.checkSizes maps every check of the two gated systems,
# by the attribute path nixbot records (`checks.<system>.<name>`), to its
# `class` and `measured`; fleet-alert's CheckOutgrewItsClass renders its
# per-check limits from it (design D10).
{
  lib,
  flake-parts-lib,
  withSystem,
  ...
}:
let
  entry = lib.types.submodule {
    options = {
      class = lib.mkOption {
        type = lib.types.enum [
          "small"
          "medium"
          "large"
          "enormous"
        ];
        description = "The size class of one cold run.";
      };
      reason = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Why the test has this class; required for a large check.";
      };
      measured = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether a measured run backs the class.";
      };
    };
  };
  entries =
    kind:
    lib.mkOption {
      type = lib.types.attrsOf entry;
      default = { };
      description = "Declared size classes of this system's ${kind}, keyed by attribute name.";
    };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption {
    _file = ./test-sizes.nix;
    options.testSizes = {
      checks = entries "checks";
      vmTests = entries "vmTests";
    };
  };

  config.flake.lib = {
    testSizeLimits = {
      small = 60;
      medium = 300;
      large = 900;
      enormous = 3600;
    };
    enormousTests = withSystem "x86_64-linux" (
      { config, ... }:
      lib.attrNames (lib.filterAttrs (_: e: e.class == "enormous") config.testSizes.vmTests)
    );
    # The two systems nixbot's gate builds; only the entries are read, so
    # no check is evaluated.
    checkSizes = lib.listToAttrs (
      lib.concatMap
        (
          system:
          withSystem system (
            { config, ... }:
            lib.mapAttrsToList (
              name: e: lib.nameValuePair "checks.${system}.${name}" { inherit (e) class measured; }
            ) config.testSizes.checks
          )
        )
        [
          "x86_64-linux"
          "aarch64-darwin"
        ]
    );
  };
}
