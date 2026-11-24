# Behavioural check for the seed-json-defaults activation program
# (modules/home/night-light/seed-json-defaults.sh) against fixture files.
#
# The rows follow one session.json through its life: created when missing,
# merged into an existing file whose user-changed value and unrelated keys
# must survive, left alone on later runs, and left alone after the user turns
# the feature off, which DMS records by deleting the key. A new marker
# re-seeds; a failing settle command and a malformed file withhold the marker.
#
# The mutant lets the defaults win over the existing file, the plausible
# slip that would overwrite the user's choices; it must change the user's
# value.
#
# x86_64-linux only: the program runs nixpkgs' bash, jq and coreutils on every
# platform, so its behaviour does not depend on the system.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      program = self.lib.seedJsonDefaultsProgram pkgs;
      source = builtins.readFile ../home/night-light/seed-json-defaults.sh;
      merge = "'$defaults[0] + .'";
      mutantSource = builtins.replaceStrings [ merge ] [ "'. + $defaults[0]'" ] source;
      mutantProgram =
        assert lib.assertMsg (
          mutantSource != source
        ) "seed-json-defaults: the overwriting mutant no longer applies";
        pkgs.writeShellApplication {
          name = "seed-json-defaults-overwrite-mutant";
          runtimeInputs = [
            pkgs.jq
            pkgs.coreutils
          ];
          text = mutantSource;
        };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        seed-json-defaults-rehearsal = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        seed-json-defaults-rehearsal =
          pkgs.runCommand "seed-json-defaults-rehearsal"
            {
              nativeBuildInputs = [
                pkgs.coreutils
                pkgs.jq
              ];
              meta.description = "behavioural check: seed-json-defaults activation program";
            }
            ''
              fail() { echo "FAIL: $*" >&2; exit 1; }
              same() {
                [ "$(jq -S . "$1")" = "$(jq -S . <<< "$2")" ] || fail "$1: $(jq -c . "$1"), expected $2"
              }

              seed=${lib.getExe program}
              printf '{"enabled": true, "temperature": 1000}\n' > defaults.json
              settle=$TMPDIR/settle
              printf '#!%s\necho settled >> "%s/settled"\n' "${pkgs.runtimeShell}" "$TMPDIR" > "$settle"
              chmod +x "$settle"
              settled() { [ "$(cat "$TMPDIR/settled" 2> /dev/null | wc -l)" = "$1" ] || fail "settle ran $(cat "$TMPDIR/settled" 2> /dev/null | wc -l) times, expected $1"; }

              echo "--- a missing file is created holding the defaults"
              $seed state/new.json state/new.v1 defaults.json "$settle"
              same state/new.json '{"enabled": true, "temperature": 1000}'
              [ -e state/new.v1 ] || fail "marker not written"
              settled 1

              echo "--- an existing file gains the absent keys and keeps its own"
              rm -f "$TMPDIR/settled"
              printf '{"temperature": 3000, "launcherLastQuery": "zen"}\n' > session.json
              chmod 600 session.json
              $seed session.json v1 defaults.json "$settle"
              same session.json '{"enabled": true, "temperature": 3000, "launcherLastQuery": "zen"}'
              [ "$(stat -c %a session.json)" = 600 ] || fail "mode not kept"
              settled 1

              echo "--- a second run changes nothing and does not settle"
              cp session.json before.json
              $seed session.json v1 defaults.json "$settle"
              cmp -s before.json session.json || fail "second run rewrote the file"
              settled 1

              echo "--- turned off after seeding (DMS deletes the default-valued key), it stays off"
              jq 'del(.enabled)' session.json > t && mv t session.json
              $seed session.json v1 defaults.json "$settle"
              same session.json '{"temperature": 3000, "launcherLastQuery": "zen"}'

              echo "--- a new marker version seeds again"
              $seed session.json v2 defaults.json "$settle"
              same session.json '{"enabled": true, "temperature": 3000, "launcherLastQuery": "zen"}'
              [ -e v2 ] || fail "v2 marker not written"
              settled 2

              echo "--- a failing settle withholds the marker until a run that settles"
              printf '{}\n' > retry.json
              $seed retry.json retry.v1 defaults.json false 2> err
              grep -q "will retry" err || fail "failure not logged: $(cat err)"
              [ ! -e retry.v1 ] || fail "marker written although settle failed"
              same retry.json '{"enabled": true, "temperature": 1000}'
              $seed retry.json retry.v1 defaults.json "$settle"
              [ -e retry.v1 ] || fail "marker not written on retry"

              echo "--- a file that is not a JSON object is left unchanged without a marker"
              printf '[1, 2]\n' > broken.json
              $seed broken.json broken.v1 defaults.json "$settle" 2> err
              [ "$(cat broken.json)" = "[1, 2]" ] || fail "broken file changed"
              [ ! -e broken.v1 ] || fail "marker written for a broken file"

              echo "--- mutant: defaults winning overwrite the user's value"
              printf '{"temperature": 3000}\n' > mutant.json
              ${lib.getExe mutantProgram} mutant.json mutant.v1 defaults.json true > /dev/null
              [ "$(jq .temperature mutant.json)" != 3000 ] \
                || fail "the overwriting mutant kept the user's value; the rehearsal cannot tell merge order"

              touch $out
            '';
      };
    };
}
