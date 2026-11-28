# Behavioural check for nix-build-locked (modules/lib/nix-build-lock.sh): the
# real wrapper around a stub build, against a pressure file in the format of
# /proc/pressure/memory, waits on the lock's holder and on pressure and says
# why, gives up at its bound without building, outlives a killed holder,
# serialises with a flock(1) session on a symlink to the lock, passes
# arguments and exit status through, and leaves the lock file in place.
# x86_64-linux only: the hosts that install the wrapper are Linux.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      stub = pkgs.writeScriptBin "build-stub" ''
        #!${pkgs.runtimeShell}
        echo "BUILD: args=$*"
        if [ -n "''${HOLD_UNTIL:-}" ]; then
          : > "$HOLD_UNTIL.started"
          while [ ! -e "$HOLD_UNTIL" ]; do sleep 0.1; done
        fi
        exit "''${EXIT_STATUS:-0}"
      '';

      # Relative paths: rows run from $TMPDIR/work.
      wrapper =
        maxWait:
        self.lib.mkNixBuildLockWrapper pkgs {
          lockFile = "lock/build.lock";
          pressureFile = "run/pressure";
          pressureThreshold = 20;
          inherit maxWait;
          reportInterval = 1;
        };
      patient = wrapper 60;
      impatient = wrapper 2;

      lockTail = "; builds on this host run one at a time to avoid exhausting memory";
      pressureLine =
        value:
        "nix-build-locked: waiting for memory pressure to fall: some avg60 in run/pressure is ${value}, at or above 20; a build started now risks exhausting the host's memory";

      nix-build-lock-rehearsal =
        pkgs.runCommand "nix-build-lock-rehearsal"
          {
            nativeBuildInputs = [
              stub
              pkgs.coreutils
              pkgs.gnugrep
              (lib.getBin pkgs.util-linux)
            ];
            meta.description = "behavioural check: nix-build-locked's build lock and memory-pressure ceiling";
          }
          ''
            fail() { echo "FAIL: $*" >&2; exit 1; }
            # Polls up to 20 s for a fixed line (or, with -E, a pattern) in a file.
            await() {
              local i
              for i in $(seq 200); do
                if grep -q "$@" 2>/dev/null; then return 0; fi
                sleep 0.1
              done
              return 1
            }
            await_file() {
              local i
              for i in $(seq 200); do
                if [ -e "$1" ]; then return 0; fi
                sleep 0.1
              done
              return 1
            }
            expect_line() { grep -qxF -- "$2" "$1" || { cat "$1"; fail "$1 lacks: $2"; }; }
            pressure() {
              printf 'some avg10=%s avg60=%s avg300=0.00 total=1\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=1\n' "$1" "$1" > run/pressure.new
              mv run/pressure.new run/pressure
            }
            locked=${patient}/bin/nix-build-locked
            impatient=${impatient}/bin/nix-build-locked

            mkdir -p "$TMPDIR/work/lock" "$TMPDIR/work/run"
            cd "$TMPDIR/work"
            : > lock/build.lock
            : > lock/build.lock.owner
            ln -s build.lock lock/legacy.lock
            # Read-only, as /etc/nix/build.lock{,.owner} are (0444 root).
            chmod 0444 lock/build.lock lock/build.lock.owner
            chmod 0555 lock
            inode=$(stat -c %i lock/build.lock)
            me=$(id -un)
            pressure 0.18

            echo "--- uncontended, low pressure: runs the build with its arguments"
            $locked build-stub --flake '.#checks' -L > run/a.out 2> run/a.err
            expect_line run/a.out "BUILD: args=--flake .#checks -L"
            [ ! -s run/a.err ] || { cat run/a.err; fail "uncontended run wrote to stderr"; }

            echo "--- exit status passes through"
            status=0
            EXIT_STATUS=7 $locked build-stub > /dev/null 2>&1 || status=$?
            [ "$status" = 7 ] || fail "exit status $status, expected 7"

            echo "--- no command is a usage error"
            status=0
            $locked 2> run/usage.err || status=$?
            [ "$status" = 2 ] || fail "no command: exit status $status, expected 2"

            echo "--- missing lock file refuses to build"
            status=0
            (cd run && $locked build-stub > ../run/missing.out 2> ../run/missing.err) || status=$?
            [ "$status" = 1 ] || fail "missing lock: exit status $status, expected 1"
            grep -q '^BUILD' run/missing.out && fail "build ran without the lock"
            expect_line run/missing.err "nix-build-locked: the host build lock lock/build.lock is missing or unreadable; refusing to run an unserialised build"

            echo "--- unreadable pressure refuses to build"
            mv run/pressure run/pressure.saved
            status=0
            $locked build-stub > run/nopsi.out 2> run/nopsi.err || status=$?
            mv run/pressure.saved run/pressure
            [ "$status" = 1 ] || fail "unreadable pressure: exit status $status, expected 1"
            grep -q '^BUILD' run/nopsi.out && fail "build ran without a pressure reading"
            expect_line run/nopsi.err "nix-build-locked: cannot read some avg60 from run/pressure; refusing to build without knowing the host's memory pressure"

            echo "--- pressure at the threshold waits, and the build runs once it falls"
            pressure 20.00
            $locked build-stub calm > run/p.out 2> run/p.err &
            waiter=$!
            await -F ${lib.escapeShellArg (pressureLine "20.00")} run/p.err || { cat run/p.err; fail "no pressure waiting line"; }
            sleep 1.5
            grep -q '^BUILD' run/p.out && fail "build ran at the threshold"
            pressure 19.99
            wait "$waiter" || fail "build failed after pressure fell"
            expect_line run/p.out "BUILD: args=calm"

            echo "--- pressure that stays high gives up after max_wait without building"
            pressure 57.30
            status=0
            $impatient build-stub never > run/g.out 2> run/g.err || status=$?
            [ "$status" = 75 ] || { cat run/g.err; fail "high pressure: exit status $status, expected 75"; }
            grep -q '^BUILD' run/g.out && fail "build ran under high pressure"
            expect_line run/g.err ${lib.escapeShellArg (pressureLine "57.30")}
            expect_line run/g.err "nix-build-locked: gave up after 2s waiting for memory pressure to fall below 20; the build did not run"
            pressure 0.18

            echo "--- second build waits for the holder, naming it, then proceeds"
            HOLD_UNTIL=run/release1 $locked build-stub holder > run/h1.out 2>&1 &
            holder=$!
            await_file run/release1.started || fail "holder never started"
            $locked build-stub waiter > run/w1.out 2> run/w1.err &
            waiter=$!
            await -F "nix-build-locked: waiting for the host build lock" run/w1.err || fail "waiter printed no waiting line"
            grep -qE "^nix-build-locked: waiting for the host build lock held by $me pid $holder since [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} \(bash .*/bin/build-stub holder\)${lib.escapeRegex lockTail}$" run/w1.err \
              || { cat run/w1.err; fail "waiting line does not name the holder"; }
            sleep 1
            grep -q '^BUILD' run/w1.out && fail "waiter built while the lock was held"
            : > run/release1
            wait "$holder" || fail "holder failed"
            wait "$waiter" || fail "waiter failed after the holder released"
            expect_line run/w1.out "BUILD: args=waiter"

            echo "--- holder killed: the lock goes with it"
            HOLD_UNTIL=run/never $locked build-stub doomed > /dev/null 2>&1 &
            holder=$!
            await_file run/never.started || fail "doomed holder never started"
            $locked build-stub survivor > run/w2.out 2> run/w2.err &
            waiter=$!
            await -F "waiting for the host build lock" run/w2.err || fail "waiter printed no waiting line"
            kill -9 "$holder"
            wait "$holder" || true
            wait "$waiter" || fail "waiter did not proceed after the holder was killed"
            expect_line run/w2.out "BUILD: args=survivor"

            echo "--- a session holding the legacy path with flock(1) is waited for"
            (
              exec 9<lock/legacy.lock
              flock 9
              : > run/legacy.started
              while [ ! -e run/release3 ]; do sleep 0.1; done
            ) &
            holder=$!
            await_file run/legacy.started || fail "legacy holder never started"
            $locked build-stub after-legacy > run/w3.out 2> run/w3.err &
            waiter=$!
            await -F "nix-build-locked: waiting for the host build lock held by another build on this host (its process is not visible from here)${lockTail}" run/w3.err \
              || { cat run/w3.err; fail "waiter did not wait for the legacy holder"; }
            grep -q '^BUILD' run/w3.out && fail "build ran beside the legacy holder"
            : > run/release3
            wait "$holder" || fail "legacy holder failed"
            wait "$waiter" || fail "waiter failed after the legacy holder released"
            expect_line run/w3.out "BUILD: args=after-legacy"

            echo "--- a held lock that is never released gives up after max_wait"
            HOLD_UNTIL=run/release4 $locked build-stub hog > /dev/null 2>&1 &
            holder=$!
            await_file run/release4.started || fail "hog never started"
            status=0
            $impatient build-stub starved > run/w4.out 2> run/w4.err || status=$?
            [ "$status" = 75 ] || { cat run/w4.err; fail "held lock: exit status $status, expected 75"; }
            grep -q '^BUILD' run/w4.out && fail "build ran while the lock was held"
            expect_line run/w4.err "nix-build-locked: gave up after 2s waiting for the host build lock; the build did not run"
            : > run/release4
            wait "$holder" || fail "hog failed"

            echo "--- the lock file is never removed or replaced"
            [ "$(stat -c %i lock/build.lock)" = "$inode" ] || fail "lock file was replaced"

            mkdir -p "$out"
            cp run/*.err "$out/"
          '';
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        nix-build-lock-rehearsal = {
          class = "small";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit nix-build-lock-rehearsal;
      };
    };
}
