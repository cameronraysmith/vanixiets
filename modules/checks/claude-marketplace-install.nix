# checks.x86_64-linux.claude-marketplace-install: Claude Code, offline and with
# an isolated configuration directory, validates the committed
# .claude-plugin/marketplace.json, adds the repository as a directory
# marketplace, installs every entry, and compares each installed plugin's skill
# names with the children of its group's .apm/skills.
#
# It fails when validation fails (a skills path without "./"), when an entry
# does not install (a source naming a missing directory, which validation
# passes), when a plugin's skills differ from its group's (an entry without
# `skills` installs with none), and when the skills installed are fewer or more
# than the source tree's first-party skill directories (an entry missing from
# the manifest). The entry shape is undocumented (world assumption A217,
# observed with Claude Code 2.1.330), so a claude-code bump that changes it
# fails here.
#
# One system: the marketplace and plugin trees do not depend on the platform.
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
      marketplace = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../.claude-plugin/marketplace.json
          ../home/ai/plugins
        ];
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 17 s, slowest 34 s, 12 runs in 30 days
        claude-marketplace-install.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        claude-marketplace-install =
          pkgs.runCommand "claude-marketplace-install"
            {
              nativeBuildInputs = [
                self'.packages.claude-code
                pkgs.jq
              ];
              passthru.meta.description = "Claude Code installs every Claude marketplace entry with exactly its group's skills";
            }
            ''
              export HOME="$TMPDIR/home"
              export CLAUDE_CONFIG_DIR="$HOME/.claude"
              export DISABLE_AUTOUPDATER=1
              export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
              mkdir -p "$CLAUDE_CONFIG_DIR"
              cp -R ${marketplace} repo
              chmod -R u+w repo
              manifest=repo/.claude-plugin/marketplace.json

              claude plugin validate repo
              claude plugin marketplace add "$PWD/repo"
              name=$(jq -r '.name' "$manifest")

              status=0
              total=0
              for group in $(jq -r '.plugins[].name' "$manifest"); do
                if ! claude plugin install "$group@$name" > install.log 2>&1; then
                  cat install.log
                  echo "FAIL: $group does not install" >&2
                  status=1
                  continue
                fi
                claude plugin details "$group@$name" \
                  | sed -n 's/^  Skills ([0-9]*)//p' | tr ',' '\n' | tr -d ' ' | sed '/^$/d' | LC_ALL=C sort > got
                ls "repo/modules/home/ai/plugins/$group/.apm/skills" | LC_ALL=C sort > want
                if ! diff -u --label "$group source" --label "$group installed" want got; then
                  echo "FAIL: $group installs skills that differ from its .apm/skills" >&2
                  status=1
                fi
                echo "$group $(wc -l < got)"
                total=$((total + $(wc -l < got)))
              done
              [ "$status" -eq 0 ] || exit 1
              skills=$(find repo/modules/home/ai/plugins/*/.apm/skills -mindepth 1 -maxdepth 1 -type d | wc -l)
              if [ "$skills" -eq 0 ] || [ "$total" -ne "$skills" ]; then
                echo "FAIL: installed $total skills; the source tree has $skills first-party skills" >&2
                exit 1
              fi
              echo "total $total" | tee "$out"
            '';
      };
    };
}
