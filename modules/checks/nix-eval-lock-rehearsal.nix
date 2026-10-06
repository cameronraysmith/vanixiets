# Behavioural check for the host evaluation lock around nix-eval-jobs
# (modules/lib/nix-eval-lock.sh, installed by modules/nixos/nix-eval-lock.nix).
#
# What matters is runtime behaviour no reading of the script shows: that the
# lock survives the exec into the evaluator, that a second evaluation really
# waits and says who it is waiting for, that it proceeds the moment the holder
# exits however it exits, and that the evaluator's exit status and arguments
# pass through untouched. Each row runs the real wrapper, built by the same
# function the hosts use, around a stub evaluator that reports its arguments
# and oom_score_adj and can be held open until the row releases it.
#
# The rows that need /proc check the oom_score_adj the evaluator runs at, the
# holder named from /proc/locks, and nixbot's situation reproduced with
# bubblewrap — the lock reached through a read-only bind mount from a separate
# PID namespace, in both directions. Defined for x86_64-linux only: the hosts
# that install the wrapper are Linux.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      stub = pkgs.writeScriptBin "nix-eval-jobs-stub" ''
        #!${pkgs.runtimeShell}
        echo "EVALUATOR: args=$*"
        if [ -e /proc/self/oom_score_adj ]; then
          echo "EVALUATOR: oom_score_adj=$(cat /proc/self/oom_score_adj)"
        fi
        if [ -n "''${HOLD_UNTIL:-}" ]; then
          : > "$HOLD_UNTIL.started"
          while [ ! -e "$HOLD_UNTIL" ]; do sleep 0.1; done
        fi
        exit "''${EXIT_STATUS:-0}"
      '';

      # Relative, so the same build serves the sandbox's working directory on
      # every platform; rows run from $TMPDIR/work.
      wrapper = self.lib.mkNixEvalLockWrapper pkgs {
        evaluator = "${stub}/bin/nix-eval-jobs-stub";
        lockFile = "lock/eval.lock";
      };

      waitingTail = "; evaluations on this host run one at a time to avoid exhausting memory";
      invisibleLine = "nix-eval-jobs: waiting for the host evaluation lock held by another evaluation on this host (its process is not visible from here)${waitingTail}";

      # bubblewrap as nixbot runs the evaluator (nixbot/nixbot/nix_eval.py
      # build_sandbox_command): every namespace unshared, a fresh /proc, the
      # store read-only, the lock directory read-only (nixbot sees /etc/nix
      # that way), the row's scratch directory writable.
      bwrap = ''
        bwrap --unshare-all --share-net --die-with-parent \
          --proc /proc --dev /dev --tmpfs /tmp \
          --ro-bind /nix/store /nix/store \
          --bind "$TMPDIR/work" "$TMPDIR/work" \
          --ro-bind "$TMPDIR/work/lock" "$TMPDIR/work/lock" \
          --chdir "$TMPDIR/work"'';

      nix-eval-lock-rehearsal =
        pkgs.runCommand "nix-eval-lock-rehearsal"
          {
            nativeBuildInputs = [
              wrapper
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.bubblewrap
            ];
            meta.description = "behavioural check: host evaluation lock around nix-eval-jobs";
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

            mkdir -p "$TMPDIR/work/lock" "$TMPDIR/work/run"
            cd "$TMPDIR/work"
            : > lock/eval.lock
            : > lock/eval.lock.owner
            # Read-only, as /etc/nix/eval.lock{,.owner} are (0444 root);
            # flock(2) needs only a read descriptor.
            chmod 0444 lock/eval.lock lock/eval.lock.owner
            chmod 0555 lock
            me=$(id -un)

            echo "--- uncontended: execs the evaluator with the arguments"
            nix-eval-jobs --flake '.#checks' --workers 2 > run/a.out 2> run/a.err
            expect_line run/a.out "EVALUATOR: args=--flake .#checks --workers 2"
            expect_line run/a.out "EVALUATOR: oom_score_adj=900"
            [ ! -s run/a.err ] || { cat run/a.err; fail "uncontended run wrote to stderr"; }

            echo "--- exit status propagates"
            status=0
            EXIT_STATUS=7 nix-eval-jobs > /dev/null 2>&1 || status=$?
            [ "$status" = 7 ] || fail "exit status $status, expected 7"

            echo "--- missing lock file refuses to evaluate"
            status=0
            (cd run && nix-eval-jobs > ../run/missing.out 2> ../run/missing.err) || status=$?
            [ "$status" = 1 ] || fail "missing lock: exit status $status, expected 1"
            grep -q '^EVALUATOR' run/missing.out && fail "evaluator ran without the lock"
            expect_line run/missing.err "nix-eval-jobs: the host evaluation lock lock/eval.lock is missing or unreadable; refusing to run an unserialised evaluation"

            echo "--- second evaluation waits for the holder, then proceeds"
            HOLD_UNTIL=run/release1 nix-eval-jobs holder > run/h1.out 2>&1 &
            holder=$!
            await_file run/release1.started || fail "holder never started"
            nix-eval-jobs waiter > run/w1.out 2> run/w1.err &
            waiter=$!
            await -F "nix-eval-jobs: waiting for the host evaluation lock" run/w1.err || fail "waiter printed no waiting line"
            # Named from /proc/locks: the holder is the wrapper's own pid,
            # which exec handed to the evaluator.
            grep -qE "^nix-eval-jobs: waiting for the host evaluation lock held by $me pid $holder since [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2} \(bash .*/bin/nix-eval-jobs-stub holder\)${lib.escapeRegex waitingTail}$" run/w1.err \
              || { cat run/w1.err; fail "waiting line does not name the holder"; }
            sleep 1
            grep -q '^EVALUATOR' run/w1.out && fail "waiter ran its evaluator while the lock was held"
            : > run/release1
            wait "$holder" || fail "holder failed"
            wait "$waiter" || fail "waiter failed after the holder released"
            expect_line run/w1.out "EVALUATOR: args=waiter"

            echo "--- holder killed: the lock goes with it"
            HOLD_UNTIL=run/never nix-eval-jobs doomed > /dev/null 2>&1 &
            holder=$!
            await_file run/never.started || fail "doomed holder never started"
            nix-eval-jobs survivor > run/w2.out 2> run/w2.err &
            waiter=$!
            await -F "waiting for the host evaluation lock" run/w2.err || fail "waiter printed no waiting line"
            kill -9 "$holder"
            wait "$holder" || true
            wait "$waiter" || fail "waiter did not proceed after the holder was killed"
            expect_line run/w2.out "EVALUATOR: args=survivor"

            echo "--- sandboxed waiter (nixbot's case): read-only lock, holder invisible"
            HOLD_UNTIL=run/release3 nix-eval-jobs outside > /dev/null 2>&1 &
            holder=$!
            await_file run/release3.started || fail "holder never started"
            ${bwrap} nix-eval-jobs inside > run/w3.out 2> run/w3.err &
            waiter=$!
            await -F "waiting for the host evaluation lock" run/w3.err || { cat run/w3.err; fail "sandboxed waiter printed no waiting line"; }
            expect_line run/w3.err ${lib.escapeShellArg invisibleLine}
            sleep 1
            grep -q '^EVALUATOR' run/w3.out && fail "sandboxed waiter ran while the lock was held outside"
            : > run/release3
            wait "$holder" || fail "holder failed"
            wait "$waiter" || { cat run/w3.err; fail "sandboxed waiter failed after release"; }
            expect_line run/w3.out "EVALUATOR: args=inside"
            expect_line run/w3.out "EVALUATOR: oom_score_adj=900"

            echo "--- sandboxed holder: an outside waiter names it"
            HOLD_UNTIL=run/release4 ${bwrap} nix-eval-jobs sandboxed > /dev/null 2>&1 &
            holder=$!
            await_file run/release4.started || fail "sandboxed holder never started"
            nix-eval-jobs outside > run/w4.out 2> run/w4.err &
            waiter=$!
            await -F "waiting for the host evaluation lock" run/w4.err || fail "outside waiter printed no waiting line"
            grep -qE "^nix-eval-jobs: waiting for the host evaluation lock held by $me pid [0-9]+ since .* \(bash .*/bin/nix-eval-jobs-stub sandboxed\)${lib.escapeRegex waitingTail}$" run/w4.err \
              || { cat run/w4.err; fail "outside waiter does not name the sandboxed holder"; }
            : > run/release4
            wait "$holder" || fail "sandboxed holder failed"
            wait "$waiter" || fail "outside waiter failed after release"
            expect_line run/w4.out "EVALUATOR: args=outside"

            mkdir -p "$out"
            cp run/*.err "$out/"
          '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit nix-eval-lock-rehearsal;
      };
    };
}
