# checks.x86_64-linux.network-target-obligations: the judge of
# flake.lib.networkTargetObligations (modules/lib/network-targets.nix)
# accepts a machine whose every network export logs in as its login user, or
# leaves the user unset for root, and finds exactly one problem in each
# mutant: a darwin peer exported without a user (F36: clan logs in as root), a
# peer exported with another user, and a NixOS peer exported with a non-root
# user.
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
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.network-target-obligations =
        assert lib.assertMsg (
          wrong == { }
        ) "network-target-obligations: the judge misjudges ${toString (lib.attrNames wrong)}";
        pkgs.runCommand "network-target-obligations" { } "touch $out";
    };
}
