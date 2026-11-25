# checks.x86_64-linux.darwin-resolver-reload: the judge of
# flake.lib.resolverReloadObligations (modules/darwin/resolver-reload.nix)
# accepts an activation script that touches each managed /etc/resolver file
# after nix-darwin's /etc link loop, and rejects the mutants that drop one
# file's touch, move it before the loop, or lack the loop. resolverTargets
# keeps enabled entries under resolver/ by target and nothing else.
#
# Per-host facts are asserted by modules/checks/machines.nix on every
# checks.aarch64-darwin.darwin-<host>, whose toplevel already forces
# system.activationScripts.script.text, so the obligation adds little
# evaluation there (stibnite's drvPath: 3.0915 GB against 3.0865 GB for its
# toplevel alone). A failure is an evaluation error of that attribute, not a
# build failure: nixbot evaluates checks.aarch64-darwin on every pull request,
# and an evaluation error fails the build without a builder, so a Mac being
# asleep does not hide it.
# Judging the real scripts here instead was measured at 4.08 GiB and 15.5 s
# of evaluation for the drvPath (darwin-mesh-resolver-flags: 0.45 GiB, 1.2 s),
# because rendering a darwin activation script on x86_64-linux evaluates most
# of that host. No host is evaluated here; the fixtures are literals, so the
# check runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.resolverReloadObligations;
      loop = ''
        while IFS= read -r -d "" etcStaticFile; do
          ln -s "$etcStaticFile" "$etcFile"
        done < <(find -H /etc/static -type l -print0)
      '';
      targets = [
        "resolver/vanixiets.internal"
        "resolver/zt"
      ];
      script = lines: lib.concatStringsSep "\n" lines;
      cases = {
        accepted = {
          script = script [
            loop
            "  touch -h /etc/resolver/vanixiets.internal"
            "touch -h /etc/resolver/zt"
          ];
          problems = 0;
        };
        dropped = {
          script = script [
            loop
            "touch -h /etc/resolver/zt"
          ];
          problems = 1;
        };
        moved = {
          script = script [
            "touch -h /etc/resolver/vanixiets.internal"
            loop
            "touch -h /etc/resolver/zt"
          ];
          problems = 1;
        };
        unlinked = {
          script = script [
            "touch -h /etc/resolver/vanixiets.internal"
            "touch -h /etc/resolver/zt"
          ];
          problems = 1;
        };
      };
      wrong = lib.filterAttrs (
        _: case:
        lib.length (
          o.missingReloads {
            inherit targets;
            inherit (case) script;
          }
        ) != case.problems
      ) cases;
      etc = {
        "resolver/vanixiets.internal" = {
          enable = true;
          target = "resolver/vanixiets.internal";
        };
        renamed = {
          enable = true;
          target = "resolver/zt";
        };
        "resolver/disabled" = {
          enable = false;
          target = "resolver/disabled";
        };
        hosts = {
          enable = true;
          target = "hosts";
        };
      };
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        darwin-resolver-reload = {
          class = "medium";
          measured = false;
        };
      };
      checks.darwin-resolver-reload =
        assert lib.assertMsg (
          wrong == { }
        ) "darwin-resolver-reload: the judge misjudges ${toString (lib.attrNames wrong)}";
        assert lib.assertMsg (
          lib.sort lib.lessThan (o.resolverTargets etc) == targets
        ) "darwin-resolver-reload: resolverTargets returns ${toString (o.resolverTargets etc)}";
        pkgs.runCommand "darwin-resolver-reload" { } "touch $out";
    };
}
