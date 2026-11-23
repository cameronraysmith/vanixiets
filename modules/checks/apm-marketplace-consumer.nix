# checks.x86_64-linux.apm-marketplace-consumer: apm, offline and with an
# isolated HOME, registers this repository's marketplace the way an apm
# consumer does and installs every group that declares no dependencies.
#
# The marketplace is a bare git repository built from the committed files and
# reached at https://git.vanixiets.test/cameronraysmith/vanixiets through a
# url.insteadOf rewrite, so apm takes its git route for a remote marketplace.
# The check fails when apm does not register exactly the groups that
# marketplace.packages publishes, when a group does not install (a misspelled
# source), when a skills group deploys no flat skill tree (apm deploying it
# whole, under .agents/plugins), when an installed skill or instructions
# fragment differs from its source byte for byte, and when the number of
# groups installed is not the source tree's number of groups without
# dependencies, or is zero. Groups with remote dependencies need the network;
# `just agents-marketplace-remote` installs them from GitHub.
#
# One system: the marketplace and plugin trees do not depend on the platform.
{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
      marketplace = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../apm.yml
          ../../.claude-plugin/marketplace.json
          ../../.github/plugin/marketplace.json
          ../home/ai/plugins
        ];
      };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        apm-marketplace-consumer =
          pkgs.runCommand "apm-marketplace-consumer"
            {
              nativeBuildInputs = [
                pkgs.apm
                pkgs.git
                pkgs.yq-go
              ];
              passthru.meta.description = "apm registers the marketplace from git and installs every dependency-free group byte for byte";
            }
            ''
              export HOME="$TMPDIR/home"
              export APM_CACHE_DIR="$TMPDIR/apm-cache"
              export APM_E2E_TESTS=1
              mkdir -p "$HOME" "$APM_CACHE_DIR"
              url=https://git.vanixiets.test/cameronraysmith/vanixiets

              cp -R ${marketplace} src
              chmod -R u+w src
              git -C src init -q -b main
              git -C src add -A
              git -C src -c user.name=check -c user.email=check@localhost commit -q -m marketplace
              git clone -q --bare src "$TMPDIR/vanixiets.git"
              git config --global url."file://$TMPDIR/vanixiets.git".insteadOf "$url"
              plugins=src/modules/home/ai/plugins

              mkdir proj
              cd proj
              apm marketplace add "$url" --ref main
              apm marketplace browse vanixiets > browse.log
              sed -n 's/^  \([^ ]*\)@vanixiets\( .*\)\{0,1\}$/\1/p' browse.log | LC_ALL=C sort > registered
              yq -r '.marketplace.packages[].name' ../src/apm.yml | LC_ALL=C sort > published
              if ! diff -u --label published --label "registered by apm" published registered; then
                echo "FAIL: apm registers a different group set than marketplace.packages" >&2
                exit 1
              fi
              cd ..

              status=0
              installed=0
              for group in $(cat proj/registered); do
                [ "$(yq -r '.dependencies // {} | length' "$plugins/$group/apm.yml")" -eq 0 ] || continue
                root="$TMPDIR/root/$group"
                mkdir -p "proj/$group"
                if ! (cd "proj/$group" && apm install "$group@vanixiets" --root "$root" -t agent-skills,claude) > install.log 2>&1; then
                  cat install.log
                  echo "FAIL: $group does not install" >&2
                  status=1
                  continue
                fi
                if [ -d "$plugins/$group/.apm/skills" ]; then
                  for tree in .agents/skills .claude/skills; do
                    if [ ! -d "$root/$tree" ]; then
                      echo "FAIL: $group deploys no $tree; apm deployed under .agents and .claude:" >&2
                      (cd "$root" && find .agents .claude -mindepth 1 -maxdepth 2 2>/dev/null | LC_ALL=C sort) >&2 || true
                      status=1
                      continue
                    fi
                    ls "$root/$tree" | LC_ALL=C sort > got
                    ls "$plugins/$group/.apm/skills" | LC_ALL=C sort > want
                    if ! diff -u --label "$group source" --label "$group $tree" want got; then
                      echo "FAIL: $group deploys other skills than its .apm/skills into $tree" >&2
                      status=1
                      continue
                    fi
                    for skill in $(cat want); do
                      diff -r "$plugins/$group/.apm/skills/$skill" "$root/$tree/$skill" \
                        || { echo "FAIL: $group: $tree/$skill differs from its source" >&2; status=1; }
                    done
                  done
                  echo "$group skills $(wc -l < want)"
                else
                  staged="$root/apm_modules/cameronraysmith/vanixiets/modules/home/ai/plugins/$group/.apm/instructions"
                  diff -r "$plugins/$group/.apm/instructions" "$staged" \
                    || { echo "FAIL: $group: staged instructions differ from their source" >&2; status=1; }
                  echo "$group instructions $(ls "$plugins/$group/.apm/instructions" | wc -l)"
                fi
                installed=$((installed + 1))
              done
              [ "$status" -eq 0 ] || exit 1
              # Counted from the source tree, not from what apm registered, so a
              # skipped group, or no group left to install offline, fails.
              offline=0
              for manifest in "$plugins"/*/apm.yml; do
                if [ "$(yq -r '.dependencies // {} | length' "$manifest")" -eq 0 ]; then
                  offline=$((offline + 1))
                fi
              done
              if [ "$offline" -eq 0 ] || [ "$installed" -ne "$offline" ]; then
                echo "FAIL: installed $installed groups; the source tree has $offline without dependencies, and at least one must install offline" >&2
                exit 1
              fi
              echo "installed $installed of $(wc -l < proj/registered) registered groups" | tee "$out"
            '';
      };
    };
}
