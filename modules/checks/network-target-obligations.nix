# checks.x86_64-linux.network-target-obligations: the judge of
# flake.lib.networkTargetObligations (modules/lib/network-targets.nix)
# accepts a machine whose every network export logs in as its login user, or
# leaves the user unset for root, and finds exactly one problem in each
# mutant: a darwin peer exported without a user (F36: clan logs in as root), a
# peer exported with another user, and a NixOS peer exported with a non-root
# user. Its targetProblems accepts a machine whose clan targetHost is
# flake.lib.hosts.<name>.targetHost and finds one problem each for a darwin
# machine with another targetHost or with an inventory deploy.targetHost
# (F83).
#
# Per-host facts are asserted by modules/checks/machines.nix on every
# nixos-<host> and darwin-<host> check against the flake's real exports. No
# host is evaluated here; the fixtures are literals, so the check runs on
# x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.networkTargetObligations;
      darwin = peers: {
        deployUser = "cameron";
        inherit peers;
      };
      nixos = peers: {
        deployUser = "root";
        inherit peers;
      };
      cases = {
        darwinAccepted =
          darwin {
            "tincr:vanixiets".user = "cameron";
          }
          // {
            problems = 0;
          };
        nixosUnsetAccepted =
          nixos {
            "tincr:vanixiets".user = null;
            "clan-core/zerotier:zerotier".user = null;
          }
          // {
            problems = 0;
          };
        darwinUserUnset = darwin { "tincr:vanixiets".user = null; } // {
          problems = 1;
        };
        darwinOtherUser =
          darwin {
            "tincr:vanixiets".user = "cameron";
            "clan-core/zerotier:zerotier".user = "crs58";
          }
          // {
            problems = 1;
          };
        nixosNonRoot = nixos { "tincr:vanixiets".user = "cameron"; } // {
          problems = 1;
        };
      };
      wrong = lib.filterAttrs (
        _: case:
        lib.length (
          o.problems {
            name = "m";
            inherit (case) deployUser peers;
          }
        ) != case.problems
      ) cases;
      # targetProblems: the deploy address has one source (F83).
      target = {
        name = "m";
        class = "darwin";
        targetHost = "cameron@m.zt";
        configTargetHost = "cameron@m.zt";
        inventoryTargetHost = null;
      };
      targetCases = {
        darwinFromHosts = target // {
          problems = 0;
        };
        nixosInventoryFromHosts = target // {
          class = "nixos";
          targetHost = "root@m.zt";
          configTargetHost = "root@m.zt";
          inventoryTargetHost = "root@m.zt";
          problems = 0;
        };
        darwinLiteralElsewhere = target // {
          configTargetHost = "cameron@m.vanixiets.internal";
          problems = 1;
        };
        darwinInventoryTarget = target // {
          inventoryTargetHost = "cameron@m.zt";
          problems = 1;
        };
      };
      wrongTarget = lib.filterAttrs (
        _: case: lib.length (o.targetProblems (removeAttrs case [ "problems" ])) != case.problems
      ) targetCases;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        network-target-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.network-target-obligations =
        assert lib.assertMsg (wrong == { } && wrongTarget == { })
          "network-target-obligations: the judge misjudges ${
            toString (lib.attrNames wrong ++ lib.attrNames wrongTarget)
          }";
        pkgs.runCommand "network-target-obligations" { } "touch $out";
    };
}
