# checks.x86_64-linux.mesh-hosts-obligations: the judge of
# flake.lib.meshHostsObligations (modules/system/mesh-hosts.nix) accepts
# hosts entries that map every mesh name to exactly the records' addresses,
# ignores names outside the fleet domain and `.zt` and the host's own name,
# and finds exactly one problem in each mutant: a second address for a name
# (the conflicting-address case), a missing name, a moved address, a stray
# name, and a `.zt` name that lost its IPv4 address.
#
# Per-host facts are asserted by modules/checks/machines.nix on every
# nixos-<host> and darwin-<host> check, which already evaluates the
# configuration; nixbot evaluates checks.aarch64-darwin on every pull request,
# so a darwin failure is an evaluation error there whether or not a Mac is
# awake. No host is evaluated
# here; the fixtures are literals, so the check runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.meshHostsObligations;
      inherit (self.lib.fleet) domain;
      a = "a.${domain}";
      svc = "svc.${domain}";
      b = "b.${domain}";
      records = [
        {
          name = a;
          address = "fd09::1";
        }
        {
          name = svc;
          address = "fd09::1";
        }
        {
          name = b;
          address = "fd09::2";
        }
        {
          name = "a.zt";
          address = "fddb::1";
        }
        {
          name = "a.zt";
          address = "10.147.17.1";
        }
      ];
      exact = {
        "fd09::1" = [
          a
          svc
        ];
        "fd09::2" = [ b ];
        "fddb::1" = [ "a.zt" ];
        "10.147.17.1" = [ "a.zt" ];
      };
      cases = {
        accepted = {
          hosts = exact // {
            "127.0.0.1" = [ "localhost" ];
          };
          problems = 0;
        };
        ownNameExempt = {
          hosts = exact // {
            "127.0.0.2" = [ b ];
          };
          own = b;
          problems = 0;
        };
        conflictingAddress = {
          hosts = exact // {
            "fd00::9" = [ a ];
          };
          problems = 1;
        };
        nameMissing = {
          hosts = removeAttrs exact [ "fd09::2" ];
          problems = 1;
        };
        addressMoved = {
          hosts = removeAttrs exact [ "fd09::2" ] // {
            "fd09::3" = [ b ];
          };
          problems = 1;
        };
        strayName = {
          hosts = exact // {
            "fd09::4" = [ "ghost.${domain}" ];
          };
          problems = 1;
        };
        ztIpv4Dropped = {
          hosts = removeAttrs exact [ "10.147.17.1" ];
          problems = 1;
        };
      };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = {
        # nixbot: 0 runs, too few to class (design D4)
        mesh-hosts-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.mesh-hosts-obligations = self.lib.mkJudgeCheck pkgs {
        name = "mesh-hosts-obligations";
        judge =
          case:
          o.mismatches {
            inherit records;
            inherit (case) hosts;
            own = case.own or null;
          };
        inherit cases;
      };
    };
}
