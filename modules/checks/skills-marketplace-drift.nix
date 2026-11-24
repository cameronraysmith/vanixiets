# checks.x86_64-linux.skills-marketplace-drift: the committed
# .claude-plugin/marketplace.json, .github/plugin/marketplace.json and
# skills.sh.json equal the skills-marketplace build, printing the difference
# when they do not. The build
# itself fails when marketplace.packages and the group directories disagree.
# Fix: `just agents-marketplace`, review the diff, commit it.
#
# One system: the generated files do not depend on the platform.
{ lib, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      system,
      ...
    }:
    let
      committed = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../.claude-plugin/marketplace.json
          ../../.github/plugin/marketplace.json
          ../../skills.sh.json
        ];
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        skills-marketplace-drift = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        skills-marketplace-drift =
          pkgs.runCommand "skills-marketplace-drift"
            {
              passthru.meta.description = "The committed marketplace files equal the files generated from the apm.yml manifests";
            }
            ''
              status=0
              for file in .claude-plugin/marketplace.json .github/plugin/marketplace.json skills.sh.json; do
                if ! diff -u --label "committed $file" --label "generated $file" \
                  ${committed}/$file ${self'.packages.skills-marketplace}/$file; then
                  echo "FAIL: $file differs from the generated file; run just agents-marketplace" >&2
                  status=1
                fi
              done
              [ "$status" -eq 0 ] || exit 1
              touch "$out"
            '';
      };
    };
}
