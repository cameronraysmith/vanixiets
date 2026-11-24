# perSystem.vmTests, transposed to the flake output vmTests.<system>: the
# on-demand runtime tests, outside the pull-request checks output.
#
# Every test is extended with the NixOS test framework's globalTimeout set to
# the limit of the size class its module declares in testSizes.vmTests
# (modules/checks/test-sizes.nix; openspec/changes/declare-test-size-classes
# design D3). The driver starts that timer just before the test script and,
# when it fires, releases every VM and container and fails the build; the
# driver and node builds are outside it. A test with no testSizes entry fails
# evaluation, naming it. The mapping keeps the key set static: only a test's
# value reads its entry.
{
  lib,
  flake-parts-lib,
  config,
  ...
}:
let
  inherit (config.flake.lib) testSizeLimits;
  type = lib.types.lazyAttrsOf lib.types.package;
in
{
  options = {
    flake.vmTests = lib.mkOption {
      type = lib.types.attrsWith {
        elemType = type;
        lazy = true;
        placeholder = "system";
      };
      default = { };
      description = "See {option}`perSystem.vmTests` for description and examples.";
    };

    perSystem = flake-parts-lib.mkPerSystemOption (
      { config, system, ... }:
      {
        _file = ./default.nix;
        options.vmTests = lib.mkOption {
          inherit type;
          default = { };
          description = "On-demand VM tests, outside the pull-request checks output.";
          apply = lib.mapAttrs (
            name: test:
            let
              entry =
                config.testSizes.vmTests.${name}
                  or (throw "vmTests.${system}.${name} has no testSizes.vmTests entry; declare its size class beside its definition");
            in
            test.extend { modules = [ { globalTimeout = testSizeLimits.${entry.class}; } ]; }
          );
        };
      }
    );
  };

  config.transposition.vmTests = { };
}
