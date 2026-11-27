# checks.x86_64-linux.matrix-server-name-reset: the one-shot reset run before
# cinnabar's tuwunel starts (flake.lib.tuwunelServerNameGuard, defined in
# modules/machines/nixos/cinnabar/matrix.nix). A homeserver's server name
# cannot change on an existing database, so the guard moves the database
# aside when the marker in the state directory names another server, or is
# absent while the directory holds data (a database made before the marker
# existed), and then writes the configured name into the marker.
#
# The fixture mimics DynamicUser's layout: the guard is given the real
# directory private/tuwunel, and a retired database must land beside it.
# Each case starts from a fresh fixture; `cases` selects which run, so a mutant
# can be judged on the one case it must fail. The guard is platform-independent
# shell, so the check runs on x86_64-linux only; the units around it, sandbox
# included, are judged by vmTests.x86_64-linux.tuwunel-server-name-guard.
{ config, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = {
        # nixbot: 0 runs, too few to class (design D4)
        matrix-server-name-reset = {
          class = "medium";
          measured = false;
        };
      };
      checks.matrix-server-name-reset =
        pkgs.runCommand "matrix-server-name-reset"
          {
            nativeBuildInputs = [
              (config.flake.lib.tuwunelServerNameGuard pkgs { serverName = "matrix.new.internal"; })
            ];
            cases = "unmarked current other empty absent";
          }
          ''
            set -uo pipefail
            cd "$TMPDIR"
            fail() { echo "FAIL ($case): $*"; exit 1; }
            new=matrix.new.internal
            real=$TMPDIR/lib/private/tuwunel

            fresh() {
              rm -rf lib
              mkdir -p "$real"
            }
            guard() { tuwunel-server-name-guard "$real"; }
            retired() { find lib/private -mindepth 1 -maxdepth 1 -name "tuwunel.retired-$1-*" | sort; }
            onlyMarker() {
              [ "$(ls -A "$real")" = .server-name ] || fail "state directory holds more than the marker: $(ls -A "$real")"
              [ "$(cat "$real/.server-name")" = "$new" ] || fail "marker does not name $new: $(cat "$real/.server-name")"
            }
            noRetired() {
              [ -z "$(retired '*')" ] || fail "a database was retired: $(retired '*')"
            }

            case_unmarked() {
              echo db > "$real/CURRENT"; echo hidden > "$real/.lock"; mkdir "$real/media"; echo m > "$real/media/x"
              guard || fail "guard exited non-zero"
              onlyMarker
              dest=$(retired unmarked)
              [ "$(echo "$dest" | wc -l)" = 1 ] && [ -n "$dest" ] || fail "expected one retired-unmarked directory, found: $dest"
              [ -f "$dest/CURRENT" ] && [ -f "$dest/.lock" ] && [ -f "$dest/media/x" ] || fail "retired directory lacks the old data: $(ls -A "$dest")"
              guard || fail "second run exited non-zero"
              [ "$(retired '*' | wc -l)" = 1 ] || fail "second run retired again"
              onlyMarker
            }

            case_current() {
              echo "$new" > "$real/.server-name"; echo db > "$real/CURRENT"
              guard || fail "guard exited non-zero"
              [ -f "$real/CURRENT" ] || fail "database of the configured server was moved"
              noRetired
            }

            case_other() {
              echo matrix.old > "$real/.server-name"; echo db > "$real/CURRENT"
              guard || fail "guard exited non-zero"
              onlyMarker
              dest=$(retired matrix.old)
              [ -n "$dest" ] && [ -f "$dest/CURRENT" ] || fail "database of matrix.old was not retired"
              [ "$(cat "$dest/.server-name")" = matrix.old ] || fail "retired directory lost its marker"
            }

            case_empty() {
              guard || fail "guard exited non-zero"
              onlyMarker
              noRetired
            }

            case_absent() {
              rm -rf lib
              guard || fail "guard exited non-zero"
              [ "$(stat -c %a lib/private)" = 700 ] || fail "created private/ with mode $(stat -c %a lib/private)"
              onlyMarker
              noRetired
            }

            for case in $cases; do
              fresh
              "case_$case"
              echo "case $case: passes"
            done
            touch "$out"
          '';
    };
}
