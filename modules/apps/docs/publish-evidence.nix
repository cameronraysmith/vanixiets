# Publish the docs browser report nixbot built for a finished build.
#
#   nix run .#publish-evidence -- build-finished --out <dir>
#
# The mode reads nixbot's build_finished event environment. No effect runs it
# yet: the storage destination is undecided, so the program ends publication
# at a local directory, the seam an upload backend would consume.
#
# Why: the report and its metadata are untrusted build output, so the
# validator that judges them is this program's own copy of
# packages/docs/tests/report, interpolated as the non-exported shell variable
# `validator` so neither the environment nor the report can substitute it.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.publish-evidence = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "publish-evidence";
            # The effect sandbox PATH is runtimeInputs only: curl reaches
            # nixbot's build API, nix provides nix-store to realise the
            # recorded report, node runs the validator.
            runtimeInputs = [
              pkgs.nodejs_24
              pkgs.curl
              pkgs.jq
              pkgs.nix
              pkgs.coreutils
              pkgs.diffutils
              pkgs.findutils
            ];
            text = ''
              validator=${lib.escapeShellArg "${../../../packages/docs/tests/report}/validate-report.ts"}
              ${builtins.readFile ./publish-evidence.sh}
            '';
          }
        );
      };
    };
}
