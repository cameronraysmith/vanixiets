# checks.x86_64-linux.darwin-machine-key-guard: the darwin machine-key guard
# (flake.lib.darwinMachineKeyGuard, run by the .#darwin app before activation)
# decides on a key file inside a directory the user cannot traverse, which is
# how clan's upload leaves /var/lib/sops-nix (root-only, 0700).
#
# The build user stands in for the unprivileged operator: the fixture directory
# is chmod 000, so the user cannot see the key file, and a stub `sudo` opens it
# for the duration of the command it runs, standing in for root. The stub logs
# its arguments, so the check also confirms a dry run uses `sudo -n` and a real
# run plain `sudo`. The guard's logic is platform-independent shell, so the
# check runs on x86_64-linux only, where nixbot builds.
{ config, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        darwin-machine-key-guard = {
          class = "medium";
          measured = false;
        };
      };
      checks.darwin-machine-key-guard =
        pkgs.runCommand "darwin-machine-key-guard"
          {
            nativeBuildInputs = [
              (config.flake.lib.darwinMachineKeyGuard pkgs)
              pkgs.age
            ];
          }
          ''
            set -uo pipefail
            cd "$TMPDIR"
            fail() { echo "FAIL: $*"; exit 1; }

            mkdir -p root bin
            age-keygen -o root/key.txt 2>/dev/null
            expected=$(age-keygen -y root/key.txt)
            other=$(age-keygen 2>/dev/null | age-keygen -y)
            chmod 000 root
            export MACHINE_KEY_FILE=$TMPDIR/root/key.txt

            # Control: the fixture really hides the file from the user. The old
            # guard decided existence with this unprivileged test, so it reported
            # "missing" for a present, matching key; that is the mutant this
            # fixture must catch.
            if [ -e "$MACHINE_KEY_FILE" ]; then fail "fixture: the key file is visible to the user"; fi
            echo "mutant (unprivileged existence test) reports missing, as the old guard did"

            # Stub sudo: open the directory for the command, log the arguments.
            cat > bin/sudo <<EOF
            #!${pkgs.runtimeShell}
            echo "\$*" >> $TMPDIR/sudo.log
            [ -n "\''${SUDO_FAIL:-}" ] && exit 1
            [ "\$1" = -n ] && shift
            chmod 700 $TMPDIR/root
            "\$@"; rc=\$?
            chmod 000 $TMPDIR/root
            exit \$rc
            EOF
            chmod +x bin/sudo
            export PATH=$TMPDIR/bin:$PATH

            # 1. Present and matching in a root-only directory: pass.
            : > sudo.log
            machine-key-guard argentum "$expected" 2> out || fail "matching key in a root-only directory was refused: $(cat out)"
            grep -q '^true$' sudo.log || fail "real run did not use plain sudo"
            echo "case matching-root-only: passes"

            # 2. Dry run uses sudo -n.
            : > sudo.log
            machine-key-guard argentum "$expected" --dry 2> out || fail "dry run refused a matching key: $(cat out)"
            grep -q '^-n true$' sudo.log || fail "dry run did not use sudo -n"
            if grep -qx 'true' sudo.log; then fail "dry run used plain sudo"; fi
            echo "case dry-uses-sudo-n: passes"

            # 3. Different key: fails, naming both public keys.
            if machine-key-guard argentum "$other" 2> out; then fail "a different key was accepted"; fi
            grep -q "found:    $expected" out && grep -q "expected: $other" out || fail "mismatch message lacks the keys: $(cat out)"
            echo "case mismatch: fails as expected"

            # 4. Absent in a root-only directory: fails with "missing".
            chmod 700 root; mv root/key.txt root/key.bak; chmod 000 root
            if machine-key-guard argentum "$expected" 2> out; then fail "an absent key was accepted"; fi
            grep -q 'found:    missing' out || fail "absent key not reported missing: $(cat out)"
            grep -q 'clan vars upload argentum' out || fail "remedy not named"
            chmod 700 root; mv root/key.bak root/key.txt; chmod 000 root
            echo "case missing: fails as expected"

            # 5. sudo cannot run: fails closed and says so.
            if SUDO_FAIL=1 machine-key-guard argentum "$expected" --dry 2> out; then fail "unchecked key was accepted"; fi
            grep -q 'found:    not checked' out || fail "sudo failure not reported: $(cat out)"
            echo "case sudo-unavailable: fails closed"

            # 6. A readable key file is read directly, without sudo.
            chmod 700 root
            : > sudo.log
            machine-key-guard argentum "$expected" 2> out || fail "readable matching key refused: $(cat out)"
            [ ! -s sudo.log ] || fail "sudo used for a readable file"
            echo "case readable: passes without sudo"

            touch "$out"
          '';
    };
}
