# checks.x86_64-linux.user-slice-guard-obligations: the judge of
# flake.lib.userSliceGuard (modules/nixos/magnetite-user-slice-guard.nix)
# accepts a user.slice with MemoryHigh and no MemoryMax, and finds exactly one
# problem in each mutant: no MemoryHigh, MemoryHigh infinity, and a MemoryMax
# beside the MemoryHigh.
#
# magnetite's own slice is judged by the module's assertion, which the
# nixos-magnetite check evaluates. No host is evaluated here; the fixtures are
# literals, so the check runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.userSliceGuard;
      ok = {
        MemoryHigh = o.memoryHigh;
      };
      cases = {
        accepted = {
          slice = ok;
          problems = 0;
        };
        noMemoryHigh = {
          slice = { };
          problems = 1;
        };
        memoryHighInfinity = {
          slice = {
            MemoryHigh = "infinity";
          };
          problems = 1;
        };
        memoryMaxPresent = {
          slice = ok // {
            MemoryMax = "12G";
          };
          problems = 1;
        };
      };
      wrong = lib.filterAttrs (_: case: lib.length (o.problems case.slice) != case.problems) cases;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        user-slice-guard-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.user-slice-guard-obligations =
        assert lib.assertMsg (
          wrong == { }
        ) "user-slice-guard-obligations: the judge misjudges ${toString (lib.attrNames wrong)}";
        pkgs.runCommand "user-slice-guard-obligations" { } "touch $out";
    };
}
