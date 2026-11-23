# checks.x86_64-linux.skills-marketplace-drift: the committed
# .claude-plugin/marketplace.json and .github/plugin/marketplace.json equal the
# skills-marketplace build, printing the difference when they do not. The build
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
        ];
      };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        skills-marketplace-drift =
          pkgs.runCommand "skills-marketplace-drift"
            {
              passthru.meta.description = "The committed marketplace files equal the files generated from the apm.yml manifests";
            }
            ''
              status=0
              for file in .claude-plugin/marketplace.json .github/plugin/marketplace.json; do
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
