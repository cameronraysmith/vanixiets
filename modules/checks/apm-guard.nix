# nix-unit cases for the apm-deps evaluation-time guard
# (pkgs/by-name/apm-skills-compose/guard.nix, design D2 and D3 rules 1-4).
{ config, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      src = builtins.path {
        name = "apm-guard-src";
        path = ../../pkgs/by-name/apm-skills-compose;
        filter =
          path: _:
          lib.elem (baseNameOf path) [
            "guard.nix"
            "guard.test.nix"
          ];
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        eval-apm-guard = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        eval-apm-guard = config.flake.lib.mkEvalCheck pkgs {
          name = "apm-guard";
          testFile = pkgs.writeText "apm-guard.tests.nix" ''
            import ${src}/guard.test.nix {
              lib = import ${pkgs.path}/lib;
            }
          '';
        };
      };
    };
}
