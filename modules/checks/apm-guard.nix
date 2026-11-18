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
