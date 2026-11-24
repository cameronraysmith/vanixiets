# nix-unit invariants for the `flake.users.<u>.systems` field declared in
# modules/home/users/lib.nix.
#
# Evaluates the submodule against a stub two-system flake and asserts both
# the default (every system the flake builds for) and the narrowing case,
# including the `<user>@<system>` key set that `configurations.nix` and
# `modules/checks/home.nix` derive from it. Catches a regression where the
# field stops being honoured and every user is emitted for every system.
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
      check = config.flake.lib.mkEvalCheck pkgs {
        name = "users-lib";
        testFile = pkgs.writeText "users-lib.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;

            usersOption =
              (import ${./lib.nix} {
                inherit lib;
                config.systems = [
                  "aarch64-darwin"
                  "x86_64-linux"
                ];
              }).options.flake.users;

            meta = {
              username = "stub";
              fullname = "Stub User";
              email = "stub@example.com";
            };

            users =
              (lib.evalModules {
                modules = [
                  { options.users = usersOption; }
                  {
                    users.unrestricted.meta = meta;
                    users.restricted = {
                      inherit meta;
                      systems = [ "x86_64-linux" ];
                    };
                  }
                ];
              }).config.users;
          in
          {
            testDefaultIsEveryFlakeSystem = {
              expr = users.unrestricted.systems;
              expected = [
                "aarch64-darwin"
                "x86_64-linux"
              ];
            };

            testExplicitListNarrowsSystems = {
              expr = users.restricted.systems;
              expected = [ "x86_64-linux" ];
            };

            testEmissionKeysOmitUnlistedSystem = {
              expr = lib.naturalSort (
                lib.concatMap (u: map (s: "''${u}@''${s}") users.''${u}.systems) (lib.attrNames users)
              );
              expected = [
                "restricted@x86_64-linux"
                "unrestricted@aarch64-darwin"
                "unrestricted@x86_64-linux"
              ];
            };
          }
        '';
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 3.1 s, slowest 24 s, 12 runs in 30 days
        eval-users-lib.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") { eval-users-lib = check; };
    };
}
