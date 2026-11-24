# checks.<system>.etc-hosts-splice: flake.lib.etcHostsSplice, which darwin
# activation runs on /private/etc/hosts (modules/darwin/etc-hosts.nix),
# against fixture files:
#   - a block is appended and every other line kept byte for byte;
#   - a second run with the same block leaves the file (and its inode) alone;
#   - a block in the middle is replaced, and the lines after it are kept;
#   - an empty block removes the block and its markers;
#   - unpaired markers (a BEGIN without END, an END without BEGIN, a BEGIN
#     inside a block) leave the file untouched and exit 2;
#   - a missing file is created with mode 0644, and a file's mode is kept.
# The deployed command is the aarch64-darwin build; x86_64-linux runs the
# same script for nixbot.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-darwin") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: 0 runs, too few to class (design D4)
            etc-hosts-splice = {
              class = "medium";
              measured = false;
            };
          };
          aarch64-darwin = {
            # nixbot: 1 run, too few to class (design D4)
            etc-hosts-splice = {
              class = "medium";
              measured = false;
            };
          };
        }
        .${system} or { };
      checks.etc-hosts-splice =
        pkgs.runCommand "etc-hosts-splice"
          {
            nativeBuildInputs = [
              (self.lib.etcHostsSplice pkgs)
              pkgs.diffutils
            ];
          }
          ''
            set -euo pipefail
            begin='# BEGIN vanixiets hosts (generated on activation; edits inside are replaced)'
            end='# END vanixiets hosts'
            fail() { echo "FAIL: $*"; exit 1; }
            expect() { diff -u "$2" "$1" || fail "$3"; echo "ok: $3"; }
            inode() { stat -c %i "$1"; }

            printf '127.0.0.1 localhost\n# a comment the user wrote\n::1 localhost\n' > user
            printf 'fd09::1 a.vanixiets.internal\nfd09::2 b.vanixiets.internal\n' > block
            printf 'fd09::3 c.vanixiets.internal\n' > block2
            : > empty

            cp user hosts
            chmod 0640 hosts
            etc-hosts-splice hosts block
            { cat user; echo "$begin"; cat block; echo "$end"; } > want
            expect hosts want "block appended, user lines kept"
            [ "$(stat -c %a hosts)" = 640 ] || fail "mode not kept"
            echo "ok: mode kept"

            before=$(inode hosts)
            etc-hosts-splice hosts block
            expect hosts want "second run leaves the content"
            [ "$(inode hosts)" = "$before" ] || fail "second run rewrote the file"
            echo "ok: second run does not rewrite"

            { head -n 1 user; echo "$begin"; cat block; echo "$end"; tail -n +2 user; } > hosts
            etc-hosts-splice hosts block2
            { cat user; echo "$begin"; cat block2; echo "$end"; } > want
            expect hosts want "middle block replaced, lines after it kept"

            etc-hosts-splice hosts empty
            expect hosts user "empty block removes block and markers"

            { cat user; echo "$begin"; cat block; } > hosts
            cp hosts want
            rc=0; etc-hosts-splice hosts block2 || rc=$?
            [ "$rc" = 2 ] || fail "unclosed BEGIN exited $rc, not 2"
            expect hosts want "unclosed BEGIN leaves the file"

            { echo "$end"; cat user; } > hosts
            cp hosts want
            rc=0; etc-hosts-splice hosts block2 || rc=$?
            [ "$rc" = 2 ] || fail "END without BEGIN exited $rc, not 2"
            expect hosts want "END without BEGIN leaves the file"

            { echo "$begin"; cat user; echo "$begin"; cat block; echo "$end"; } > hosts
            cp hosts want
            rc=0; etc-hosts-splice hosts block2 || rc=$?
            [ "$rc" = 2 ] || fail "BEGIN inside a block exited $rc, not 2"
            expect hosts want "BEGIN inside a block leaves the file"

            etc-hosts-splice missing block
            { echo "$begin"; cat block; echo "$end"; } > want
            expect missing want "missing file created"
            [ "$(stat -c %a missing)" = 644 ] || fail "created file is not 0644"
            echo "ok: created file is 0644"

            [ -z "$(ls -A | grep vanixiets || true)" ] || fail "temporary file left behind"
            echo "ok: no temporary file left"
            touch $out
          '';
    };
}
