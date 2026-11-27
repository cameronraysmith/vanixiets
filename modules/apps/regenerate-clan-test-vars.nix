# Regenerate the committed clan vars of the runtime tests that use
# flake.lib.clanTestVarsFixture (modules/vm-tests/clan-test-vars-fixture.nix):
# builds the test's `generatedClanVars`, clan-core's generator executor run on
# the test's nodes, and replaces modules/vm-tests/<test>/clan-vars with it.
# With no arguments it regenerates every existing
# modules/vm-tests/*/clan-vars. The generators run on x86_64-linux, locally or
# on a remote builder.
#
# nix run .#regenerate-clan-test-vars -- [<test>...]
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.regenerate-clan-test-vars = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "regenerate-clan-test-vars";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.git
            ];
            text = ''
              repo_root=$(git rev-parse --show-toplevel)
              cd "$repo_root"
              tests=("$@")
              if [ ''${#tests[@]} -eq 0 ]; then
                for dir in modules/vm-tests/*/clan-vars; do
                  [ -d "$dir" ] && tests+=("$(basename "$(dirname "$dir")")")
                done
              fi
              if [ ''${#tests[@]} -eq 0 ]; then
                echo "no modules/vm-tests/*/clan-vars found; name the tests to generate" >&2
                exit 1
              fi
              for test in "''${tests[@]}"; do
                echo "generating the clan vars of vmTests.x86_64-linux.$test"
                generated=$(nix build --no-link --print-out-paths ".#vmTests.x86_64-linux.$test.generatedClanVars")
                dir="modules/vm-tests/$test/clan-vars"
                rm -rf "$dir"
                mkdir -p "$dir"
                cp -r "$generated/vars" "$generated/secrets" "$dir/"
                chmod -R u+w "$dir"
                find "$dir" -type f | sort
              done
            '';
          }
        );
        meta.description = "Regenerate the committed clan vars of the runtime tests built on clanTest";
      };
    };
}
