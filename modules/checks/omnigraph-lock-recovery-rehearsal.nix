# Behavioural check of flake.lib.omnigraphLockRecovery, the program
# omnigraph-server's start runs before it serves a local root
# (modules/lib/omnigraph-lock-recovery.nix).
#
# Each row runs the program inside bubblewrap with a fresh /var/lib of its
# own, laid out as on a host: /var/lib/omnigraph a plain directory, the
# root /var/lib/omnigraph/clusters/cookbooks-f17 and
# its __cluster/lock.json, and the counter under /var/lib/omnigraph-metrics.
# The program is built with a stub `omnigraph`, which logs its arguments,
# answers `cluster status --json` with the lock file's lock_id (or the row's,
# or the row's raw answer) and removes the lock on `cluster force-unlock`;
# with a stub ntfy-send,
# which logs its arguments and NTFY_TOKEN_FILE; and with a scripted process
# table, a directory of `<pid>/exe` links, `<pid>/cmdline` files and
# `<pid>/status` files holding the owner's uids, and a `stat` holding
# btime; an /etc/passwd names root, `omnigraph` and one other user. A row
# asserts the exit status, the stub's argument log, the lock file
# (unchanged, byte for byte, or removed), the counter, the notices posted
# and, for a refusal, the reason printed and the one notice carrying that
# reason and the manual step and nothing of the lock file's content or of
# any process's arguments, which only the journal gets.
#
# There is one row per scenario of the requirement `The server's start
# clears a stale serve lock` (openspec change serve-omnigraph-from-local-disk,
# graph-store-interface), and rows for an unconfirmed unlock, a failed
# recovery notice, a failed refusal notice, a counter that already holds a
# count, a counter that cannot be written, the processes the scan counts as
# writers, a writer or a configured root that spells the root with a
# doubled slash, a `.` or `..` segment or a trailing slash, a `cluster
# status` answer that is not one JSON object with a string or null lock_id
# (not JSON, an array, a number lock_id, nothing), jq missing from the
# program's PATH, and a step that fails where the program has no guard of
# its own (its working directory cannot be made). The row `packaged-record`
# runs the packaged omnigraph instead: it applies a one-graph cluster to the
# root,
# starts omnigraph-server, kills it with SIGKILL, and requires the record it
# left to have exactly the fields the program reads, the program built with
# the packaged omnigraph and the real /proc to clear it, and the server to
# serve again; so a release that changes the record's shape fails here.
#
# Each mutant is the program with one line replaced: scanSkipped skips the
# process scan, and the rows running-writer and running-server must fail
# under it; btimeUnchecked accepts any boot time, and the rows btime-missing
# and stat-unreadable must fail; omnigraphAtPidExcused lets the boot time
# excuse an omnigraph server at the lock's pid, and the row
# stepped-clock-server must fail; statusUnguarded reads `cluster status`
# without its guard, and the row status-answers must fail; errTrapRemoved
# drops the trap on unexpected failures, and the row later-step-fails must
# fail.
{ self, lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      packages = self'.packages;
      root = "/var/lib/omnigraph/clusters/cookbooks-f17";
      procDir = "/run/rehearsal-proc";
      tokenFile = "/run/alerter-token";

      stubOmnigraph = pkgs.writeShellApplication {
        name = "omnigraph";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          printf '%s\n' "$*" >>"$STUB_LOG"
          target=$2
          case "$*" in
            *" cluster status --json")
              [ -z "''${STUB_STATUS_FAIL:-}" ] || exit 1
              if [ -n "''${STUB_STATUS_RAW+set}" ]; then
                printf '%s' "$STUB_STATUS_RAW"
              elif [ -n "''${STUB_STATUS_LOCK:-}" ]; then
                jq -n --arg id "$STUB_STATUS_LOCK" '{lock_id: $id}'
              else
                jq '{lock_id}' "$target/__cluster/lock.json"
              fi
              ;;
            *" cluster force-unlock "*)
              if [ -n "''${STUB_UNLOCK_REFUSED:-}" ]; then
                echo '{"unlocked":false}'
              else
                rm -f -- "$target/__cluster/lock.json"
                echo '{"unlocked":true}'
              fi
              ;;
            *) exit 2 ;;
          esac
        '';
      };

      stubNtfySend = pkgs.writeShellScript "ntfy-send" ''
        printf '%s|%s\n' "''${NTFY_TOKEN_FILE:-}" "$*" >>"$NTFY_LOG"
        [ -z "''${NTFY_FAIL:-}" ]
      '';

      recoveryAt =
        root: omnigraph: proc:
        self.lib.omnigraphLockRecovery pkgs {
          inherit
            omnigraph
            root
            proc
            tokenFile
            ;
          hostName = "rehearsal";
          ntfySend = stubNtfySend;
          manualCli = "omnigraph-cluster";
          writerUser = "omnigraph";
        };
      recovery = recoveryAt root;
      program = recovery stubOmnigraph procDir;
      packagedProgram = recovery packages.omnigraph "/proc";
      spelledRootProgram =
        recoveryAt "/var/lib/omnigraph//clusters/./cookbooks-f17/" stubOmnigraph
          procDir;
      # The program with jq taken out of the PATH it sets.
      jqMissingProgram = pkgs.runCommand "omnigraph-lock-recovery-without-jq" { } ''
        mkdir -p "$out/bin"
        cp ${lib.getExe program} "$out/bin/omnigraph-lock-recovery"
        chmod +w "$out/bin/omnigraph-lock-recovery"
        substituteInPlace "$out/bin/omnigraph-lock-recovery" --replace-fail ${lib.escapeShellArg "${lib.getBin pkgs.jq}/bin:"} ""
      '';

      mutants = {
        scanSkipped = {
          from = "if scan_processes; then";
          to = "if false; then";
          rows = [
            "running-writer"
            "running-server"
          ];
        };
        btimeUnchecked = {
          from = "[[ $btime =~ ^[0-9]+$ ]] ||";
          to = "true ||";
          rows = [
            "btime-missing"
            "stat-unreadable"
          ];
        };
        omnigraphAtPidExcused = {
          from = ''if [ "$pid_program" = omnigraph ] || [ "$pid_program" = omnigraph-server ]; then'';
          to = "if false; then";
          rows = [ "stepped-clock-server" ];
        };
        statusUnguarded = {
          from = ''if ! reported=$(jq -ser "$status_filter" <<<"$status" 2>/dev/null); then'';
          to = ''reported=$(jq -r '.lock_id // "none"' <<<"$status"); if false; then'';
          rows = [ "status-answers" ];
        };
        errTrapRemoved = {
          from = ''trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR'';
          to = "true";
          rows = [ "later-step-fails" ];
        };
      };
      mutantProgram =
        name: m:
        pkgs.runCommand "omnigraph-lock-recovery-${name}" { } ''
          script=${lib.getExe program}
          awk -v marker=${lib.escapeShellArg "# mutant: ${name}"} -v line=${lib.escapeShellArg m.from} '
            found { if (index($0, line)) ok = 1; exit }
            index($0, marker) { found = 1 }
            END { exit !ok }' "$script" || { echo "mutant ${name}: the line after its marker is not the one replaced" >&2; exit 1; }
          mkdir -p "$out/bin"
          cp "$script" "$out/bin/omnigraph-lock-recovery"
          chmod +w "$out/bin/omnigraph-lock-recovery"
          substituteInPlace "$out/bin/omnigraph-lock-recovery" --replace-fail ${lib.escapeShellArg m.from} ${lib.escapeShellArg m.to}
        '';

      # A one-graph cluster on the root, for the packaged-record row.
      clusterConfig = pkgs.runCommand "omnigraph-lock-recovery-cluster" { } ''
        mkdir -p "$out/cookbooks/beads"
        cp ${packages.omnigraph-cookbooks}/beads/schema.pg "$out/cookbooks/beads/schema.pg"
        cp -r ${packages.omnigraph-cookbooks}/beads/queries "$out/cookbooks/beads/queries"
        cp ${
          pkgs.writeText "cluster.yaml" (
            builtins.toJSON {
              version = 1;
              metadata.name = "rehearsal";
              graphs.cookbook-beads = {
                schema = "cookbooks/beads/schema.pg";
                queries = "cookbooks/beads/queries/";
              };
              state = {
                backend = "cluster";
                lock = true;
              };
              storage = root;
            }
          )
        } "$out/cluster.yaml"
      '';
      tokensFile = pkgs.writeText "tokens.json" (builtins.toJSON { admin = "rehearsal-token"; });

      # A lock taken at 2026-11-26T03:41:14Z, 1795664474; the boot below is
      # an hour before it, and an hour after it for a lock from before the
      # boot.
      lockId = "01M8AZ48WDAT8ZSGR1QVDFR0CM";
      createdAt = "2026-11-26T03:41:14.126542Z";
      bootBefore = 1795660874;
      bootAfter = 1795668074;
      omnigraphExe = "${packages.omnigraph}/bin/omnigraph";
      serverExe = "${packages.omnigraph}/bin/omnigraph-server";
      # The users of the scripted process table: `omnigraph` stands for the
      # static user of modules/nixos/omnigraph.nix, whose uid differs per
      # host, and 1000 for any other user.
      omnigraphUid = 400;
      otherUid = 1000;
      passwd = pkgs.writeText "passwd" ''
        root:x:0:0::/root:/bin/sh
        omnigraph:x:${toString omnigraphUid}:${toString omnigraphUid}::/var/empty:/bin/sh
        mallory:x:${toString otherUid}:${toString otherUid}::/home/mallory:/bin/sh
      '';

      rehearsal =
        pkgs.runCommand "omnigraph-lock-recovery-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.bubblewrap
              pkgs.coreutils
              pkgs.curl
              pkgs.gnugrep
              pkgs.jq
              packages.omnigraph
            ];
            meta.description = "behavioural check: the local-root lock recovery clears a crashed server's lock only when it is provably stale, and refuses every other case";
          }
          ''
            set -euo pipefail
            fail() {
              echo "FAIL ($current): $*" >&2
              exit 1
            }

            # --- a row's world --------------------------------------------------
            start_row() { # <name>
              current=$1
              dir="$TMPDIR/rows/$1-$RANDOM"
              mkdir -p "$dir/var-lib/omnigraph/clusters/cookbooks-f17/__cluster" "$dir/proc" "$dir/log"
              lock="$dir/var-lib/omnigraph/clusters/cookbooks-f17/__cluster/lock.json"
              counter="$dir/var-lib/omnigraph-metrics/lock-recoveries"
              printf 'cpu  1 2 3 4\nbtime %s\nprocesses 9\n' ${toString bootBefore} >"$dir/proc/stat"
              : >"$dir/log/omnigraph"
              : >"$dir/log/ntfy"
              unset STUB_STATUS_LOCK STUB_STATUS_FAIL STUB_STATUS_RAW STUB_UNLOCK_REFUSED NTFY_FAIL ROW_TMPDIR ROW_PATH
            }
            boot_at() { # <btime>
              printf 'cpu  1 2 3 4\nbtime %s\nprocesses 9\n' "$1" >"$dir/proc/stat"
            }
            write_lock() { # <json>
              printf '%s\n' "$1" >"$lock"
              sha256sum "$lock" >"$dir/lock.sha256"
            }
            serve_lock() { # [operation] [pid] [created_at]
              write_lock "$(jq -n --arg op "''${1:-serve}" --argjson pid "''${2:-4242}" --arg at "''${3:-${createdAt}}" \
                '{version: 1, lock_id: "${lockId}", operation: $op, created_at: $at, pid: $pid}')"
            }
            process() { # <pid> <uid> <exe, or - for none> <argv...>
              local pid=$1 uid=$2 exe=$3
              shift 3
              mkdir -p "$dir/proc/$pid"
              [ "$exe" = - ] || ln -s "$exe" "$dir/proc/$pid/exe"
              printf '%s\0' "$@" >"$dir/proc/$pid/cmdline"
              printf 'Name:\t%s\nUid:\t%s\t%s\t%s\t%s\n' "''${exe##*/}" "$uid" "$uid" "$uid" "$uid" >"$dir/proc/$pid/status"
            }
            kernel_thread() { # <pid>: an empty command line and no executable
              mkdir -p "$dir/proc/$1"
              : >"$dir/proc/$1/cmdline"
              printf 'Name:\tkworker/0:1\nUid:\t0\t0\t0\t0\n' >"$dir/proc/$1/status"
            }
            run_program() {
              set +e
              STUB_LOG=/run/log/omnigraph NTFY_LOG=/run/log/ntfy \
                bwrap --unshare-all --die-with-parent \
                  --proc /proc --dev /dev --tmpfs /tmp --setenv TMPDIR "''${ROW_TMPDIR:-/tmp}" \
                  --setenv PATH "''${ROW_PATH:-$PATH}" \
                  --ro-bind /nix/store /nix/store \
                  --ro-bind ${passwd} /etc/passwd \
                  --bind "$dir/var-lib" /var/lib \
                  --bind "$dir/proc" ${procDir} \
                  --bind "$dir/log" /run/log \
                  "$program" >"$dir/out" 2>"$dir/err"
              code=$?
              set -e
            }

            # --- expectations ---------------------------------------------------
            expect_code() { # 0 | refused
              if [ "$1" = 0 ]; then
                [ "$code" = 0 ] || { cat "$dir/err" >&2; fail "exit $code, expected 0"; }
              else
                [ "$code" = 1 ] || { cat "$dir/err" >&2; fail "exit $code, expected a refusal's 1"; }
              fi
            }
            expect_calls() { # <argument lines...>
              local expected=""
              [ "$#" = 0 ] || expected=$(printf '%s\n' "$@")
              [ "$(cat "$dir/log/omnigraph")" = "$expected" ] \
                || fail "omnigraph was run with:
            $(cat "$dir/log/omnigraph")
            expected:
            $expected"
            }
            status_call="--target ${root} cluster status --json"
            unlock_call="--target ${root} cluster force-unlock ${lockId} --json"
            expect_lock_unchanged() {
              sha256sum --check --status "$dir/lock.sha256" || fail "lock.json changed"
            }
            expect_lock_cleared() {
              [ ! -e "$lock" ] || fail "lock.json is still there"
            }
            expect_counter() { # <n> | absent
              if [ "$1" = absent ]; then
                [ ! -e "$counter" ] || fail "the counter exists: $(cat "$counter")"
              else
                [ "$(cat "$counter" 2>/dev/null)" = "$1" ] || fail "the counter holds '$(cat "$counter" 2>/dev/null)', expected $1"
              fi
            }
            expect_notices() { # <n>
              [ "$(grep -c . "$dir/log/ntfy" || true)" = "$1" ] || fail "notices posted: $(cat "$dir/log/ntfy")"
            }
            expect_reason() { # <fixed string>
              grep -qF -- "$1" "$dir/err" || fail "the reason does not name '$1': $(cat "$dir/err")"
              grep -qF -- "$1" "$dir/log/ntfy" || fail "the notice does not name '$1': $(cat "$dir/log/ntfy")"
            }
            expect_journal_only() { # <fixed string>: printed, never posted
              grep -qF -- "$1" "$dir/err" || fail "the journal does not name '$1': $(cat "$dir/err")"
              if grep -qF -- "$1" "$dir/log/ntfy"; then
                fail "the notice carries '$1': $(cat "$dir/log/ntfy")"
              fi
            }
            # One notice, to fleet-alerts with the alerter token, carrying the
            # printed reason and manual step, none of lock.json's content and
            # none of a process's arguments.
            expect_refusal_notice() {
              local reason manual
              expect_notices 1
              reason=$(sed -n 's/^omnigraph-lock-recovery: left .* in place: //p' "$dir/err")
              manual=$(sed -n 's/^omnigraph-lock-recovery: omnigraph-server stays stopped until the lock is cleared\. //p' "$dir/err")
              [ -n "$reason" ] && [ -n "$manual" ] || fail "no reason or manual step printed: $(cat "$dir/err")"
              grep -qF '${tokenFile}|' "$dir/log/ntfy" || fail "the refusal notice did not use the alerter token"
              grep -qF ' fleet-alerts ' "$dir/log/ntfy" || fail "the refusal notice is not a fleet-alerts post: $(cat "$dir/log/ntfy")"
              grep -qF -- "$reason" "$dir/log/ntfy" || fail "the refusal notice lacks the reason '$reason': $(cat "$dir/log/ntfy")"
              grep -qF -- "$manual" "$dir/log/ntfy" || fail "the refusal notice lacks the manual step '$manual': $(cat "$dir/log/ntfy")"
              if grep -qE '"lock_id"|lock_id=' "$dir/log/ntfy"; then
                fail "the refusal notice carries lock.json's content: $(cat "$dir/log/ntfy")"
              fi
              if grep -qE -- '--target |--data |--bind |--cluster |seed\.jsonl|sleep 600' "$dir/log/ntfy"; then
                fail "the refusal notice carries a process's arguments: $(cat "$dir/log/ntfy")"
              fi
            }
            refused_untouched() {
              expect_code refused
              expect_lock_unchanged
              expect_counter absent
              expect_refusal_notice
            }

            # --- rows -----------------------------------------------------------
            row_no_lock() {
              start_row no-lock
              run_program
              expect_code 0
              expect_calls
              expect_counter absent
              expect_notices 0
            }
            row_dead_server() {
              start_row dead-server
              serve_lock
              run_program
              expect_code 0
              expect_calls "$status_call" "$unlock_call"
              expect_lock_cleared
              expect_counter 1
              expect_notices 1
              grep -qF '${tokenFile}|' "$dir/log/ntfy" || fail "the notice did not use the alerter token"
              grep -qF 'fleet-alerts -H Priority: low' "$dir/log/ntfy" || fail "the notice is not a low-priority fleet-alerts post"
              grep -qF '${lockId}' "$dir/log/ntfy" || fail "the notice does not name the lock"
            }
            row_running_writer() {
              start_row running-writer
              serve_lock
              process 77 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target ${root} load --data /tmp/seed.jsonl --graph cookbook-beads
              run_program
              refused_untouched
              expect_calls
              expect_reason "an omnigraph process has the root open (pid 77, omnigraph)"
              expect_journal_only "pid 77 runs ${omnigraphExe}: omnigraph --target ${root} load --data /tmp/seed.jsonl"
            }
            row_running_server() {
              start_row running-server
              serve_lock
              process 91 ${toString omnigraphUid} "${serverExe} (deleted)" omnigraph-server --cluster ${root} --bind 127.0.0.1:8090
              run_program
              refused_untouched
              expect_calls
              expect_reason "an omnigraph process has the root open (pid 91, omnigraph-server)"
              expect_journal_only "pid 91 runs ${serverExe}: omnigraph-server --cluster ${root} --bind"
            }
            row_unrelated_processes() {
              start_row unrelated-processes
              serve_lock
              process 12 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target ${root}-r2 cluster status
              process 13 ${toString otherUid} /run/current-system/sw/bin/ls ls ${root}
              process 14 ${toString omnigraphUid} ${omnigraphExe} omnigraph version
              process 15 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target /var/lib/omnigraph//clusters/cookbooks-f17-r2/ cluster status
              process 16 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target /var/lib/omnigraph/clusters/cookbooks-f17/../cookbooks-f17-r2 cluster status
              kernel_thread 2
              run_program
              expect_code 0
              expect_calls "$status_call" "$unlock_call"
              expect_lock_cleared
              expect_counter 1
            }
            row_direct_writer_lock() {
              start_row direct-writer-lock
              serve_lock apply
              run_program
              refused_untouched
              expect_calls "$status_call"
              expect_reason "omnigraph-cluster apply --deployment-id <deployment_id> --writers-stopped"
            }
            row_live_pid_this_boot() {
              start_row live-pid-this-boot
              serve_lock serve 4242
              process 4242 ${toString otherUid} /run/current-system/sw/bin/sleep sleep 600
              run_program
              refused_untouched
              expect_calls "$status_call"
              expect_reason "pid 4242, which is running"
            }
            row_lock_before_boot() {
              start_row lock-before-boot
              serve_lock serve 4242
              boot_at ${toString bootAfter}
              process 4242 ${toString otherUid} /run/current-system/sw/bin/sleep sleep 600
              run_program
              expect_code 0
              expect_calls "$status_call" "$unlock_call"
              expect_lock_cleared
              expect_counter 1
              expect_notices 1
            }
            row_id_mismatch() {
              start_row id-mismatch
              serve_lock
              export STUB_STATUS_LOCK=01M8AZ4CZZZZZZZZZZZZZZZZZZ
              run_program
              refused_untouched
              expect_calls "$status_call"
              expect_reason "reports 01M8AZ4CZZZZZZZZZZZZZZZZZZ"
            }
            row_status_failed() {
              start_row status-failed
              serve_lock
              export STUB_STATUS_FAIL=1
              run_program
              refused_untouched
              expect_calls "$status_call"
            }
            # A `cluster status` that exits 0 with an answer the program
            # cannot read as one JSON object with a string or null lock_id.
            status_answer() { # <name> <raw answer>
              start_row "status-$1"
              serve_lock
              export STUB_STATUS_RAW="$2"
              run_program
              refused_untouched
              expect_calls "$status_call"
              expect_reason "omnigraph cluster status --json did not answer with one JSON object whose lock_id is a string or null"
            }
            row_status_answers() {
              status_answer not-json 'not json'
              status_answer array '[1]'
              status_answer number-lock-id '{"lock_id":5}'
              status_answer two-objects '{"lock_id":null}{"lock_id":null}'
              status_answer empty ""
            }
            row_jq_missing() {
              start_row jq-missing
              serve_lock
              export ROW_PATH=/var/empty
              program=${lib.getExe' jqMissingProgram "omnigraph-lock-recovery"}
              run_program
              refused_untouched
              expect_calls
              expect_reason "jq is not on the PATH of omnigraph-lock-recovery"
            }
            # A step the program has no guard for fails (its working
            # directory for omnigraph cannot be made): the trap refuses,
            # naming the step, and exits 1 whether or not the notice posts.
            row_later_step_fails() {
              start_row later-step-fails
              serve_lock
              export ROW_TMPDIR=/nonexistent
              run_program
              refused_untouched
              expect_calls
              expect_reason "mktemp -d"
              expect_reason "failed with exit status 1"
              start_row later-step-fails-notice-fails
              serve_lock
              export ROW_TMPDIR=/nonexistent NTFY_FAIL=1
              run_program
              refused_untouched
              grep -qF 'omnigraph-lock-recovery: the refusal notice was not posted' "$dir/err" || fail "the failed post is not logged: $(cat "$dir/err")"
            }
            unreadable() { # <name> <record>
              start_row "unreadable-$1"
              write_lock "$2"
              run_program
              refused_untouched
              expect_calls
            }
            row_unreadable() {
              unreadable no-lock-id '{"version":1,"operation":"serve","created_at":"${createdAt}","pid":4242}'
              unreadable pid-string '{"version":1,"lock_id":"${lockId}","operation":"serve","created_at":"${createdAt}","pid":"4242"}'
              unreadable pid-fraction '{"version":1,"lock_id":"${lockId}","operation":"serve","created_at":"${createdAt}","pid":42.5}'
              unreadable released '{"version":2,"lock_id":"${lockId}","operation":"serve","created_at":"${createdAt}","pid":4242,"release_id":"01M8AZ4DAAAAAAAAAAAAAAAAAA"}'
              unreadable not-json 'lock_id=${lockId}'
              unreadable created-at-not-a-date '{"version":1,"lock_id":"${lockId}","operation":"serve","created_at":"yesterday","pid":4242}'
            }
            row_unlock_unconfirmed() {
              start_row unlock-unconfirmed
              serve_lock
              export STUB_UNLOCK_REFUSED=1
              run_program
              expect_code refused
              expect_calls "$status_call" "$unlock_call"
              expect_counter absent
              expect_notices 1
              grep -qF 'did not report the lock removed' "$dir/log/ntfy" || fail "the notice does not say the unlock was not confirmed: $(cat "$dir/log/ntfy")"
            }
            row_counter_counts_on() {
              start_row counter-counts-on
              serve_lock
              mkdir -p "$(dirname "$counter")"
              echo 2 >"$counter"
              run_program
              expect_code 0
              expect_counter 3
              expect_notices 1
            }
            row_notice_fails() {
              start_row notice-fails
              serve_lock
              export NTFY_FAIL=1
              run_program
              expect_code 0
              expect_lock_cleared
              expect_counter 1
              expect_notices 1
            }
            # A counter that cannot be written after a confirmed unlock: the
            # recovery notice still posts, the journal says so, and the
            # start goes on.
            row_counter_unwritable() {
              start_row counter-unwritable
              serve_lock
              : >"$dir/var-lib/omnigraph-metrics"
              run_program
              expect_code 0
              expect_calls "$status_call" "$unlock_call"
              expect_lock_cleared
              expect_notices 1
              grep -qF 'fleet-alerts -H Priority: low' "$dir/log/ntfy" || fail "the notice is not a low-priority fleet-alerts post: $(cat "$dir/log/ntfy")"
              grep -qF 'cleared the stale serve lock ${lockId}' "$dir/log/ntfy" || fail "the notice does not say the lock was cleared: $(cat "$dir/log/ntfy")"
              grep -qF 'could not be written' "$dir/err" || fail "the journal does not say the counter could not be written: $(cat "$dir/err")"
            }

            # Process state the program cannot read makes it refuse rather
            # than count as no process.
            row_listing_unreadable() {
              start_row listing-unreadable
              serve_lock
              process 77 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target ${root} load --data /tmp/seed.jsonl --graph cookbook-beads
              chmod 0311 "$dir/proc"
              run_program
              chmod 0755 "$dir/proc"
              refused_untouched
              expect_calls
              expect_reason "the process table ${procDir} cannot be listed"
            }
            row_exe_unreadable() {
              start_row exe-unreadable
              serve_lock
              process 78 ${toString omnigraphUid} - omnigraph --target ${root} load --data /tmp/seed.jsonl --graph cookbook-beads
              run_program
              refused_untouched
              expect_calls
              expect_reason "the executable of pid 78 cannot be read"
              expect_journal_only "pid 78's command line: omnigraph --target ${root} load --data /tmp/seed.jsonl"
            }
            row_owner_unreadable() {
              start_row owner-unreadable
              serve_lock
              process 79 ${toString otherUid} /home/mallory/omnigraph omnigraph --target ${root} status
              rm "$dir/proc/79/status"
              run_program
              refused_untouched
              expect_calls
              expect_reason "the owner of pid 79 (omnigraph) cannot be read"
              expect_journal_only "pid 79 runs /home/mallory/omnigraph: omnigraph --target ${root} status"
            }
            row_btime_missing() {
              start_row btime-missing
              serve_lock serve 4242
              printf 'cpu  1 2 3 4\nprocesses 9\n' >"$dir/proc/stat"
              process 4242 ${toString otherUid} /run/current-system/sw/bin/sleep sleep 600
              run_program
              refused_untouched
              expect_calls "$status_call"
              expect_reason "the boot time in ${procDir}/stat cannot be read"
            }
            row_stat_unreadable() {
              start_row stat-unreadable
              serve_lock
              chmod 0 "$dir/proc/stat"
              run_program
              refused_untouched
              expect_calls "$status_call"
              expect_reason "the boot time in ${procDir}/stat cannot be read"
            }

            # An omnigraph server at the lock's pid is refused whatever the
            # boot time says: here the clock stepped forward after the lock
            # was taken, and the server addresses the root by a form the scan
            # does not match.
            row_stepped_clock_server() {
              start_row stepped-clock-server
              serve_lock serve 4242
              boot_at ${toString bootAfter}
              process 4242 ${toString omnigraphUid} ${serverExe} omnigraph-server --target cookbooks --bind 127.0.0.1:8090
              run_program
              refused_untouched
              expect_calls "$status_call"
              expect_reason "pid 4242, which lock ${lockId} names, is running omnigraph-server, so"
              expect_journal_only "pid 4242 runs ${serverExe}: omnigraph-server --target cookbooks --bind"
            }

            # Which processes the scan counts as writers of the root.
            row_imposter_ignored() {
              start_row imposter-ignored
              serve_lock
              process 55 ${toString otherUid} /home/mallory/omnigraph omnigraph 1d ${root}
              run_program
              expect_code 0
              expect_calls "$status_call" "$unlock_call"
              expect_lock_cleared
              expect_counter 1
            }
            counted_writer() { # <name> <uid> <exe>
              start_row "$1"
              serve_lock
              process 56 "$2" "$3" omnigraph --target ${root} load --data /tmp/seed.jsonl
              run_program
              refused_untouched
              expect_calls
              expect_reason "an omnigraph process has the root open (pid 56, omnigraph)"
              expect_journal_only "pid 56 runs $3: omnigraph --target ${root} load --data /tmp/seed.jsonl"
            }
            row_counted_writers() {
              counted_writer store-binary-other-user ${toString otherUid} ${omnigraphExe}
              counted_writer other-binary-as-omnigraph ${toString omnigraphUid} /home/mallory/omnigraph
              counted_writer other-binary-as-root 0 /usr/local/bin/omnigraph
            }

            # A writer may spell the root with doubled slashes, `.` and `..`
            # segments, a trailing slash or as a file URI, and so may the
            # configured root; the scan compares both normalised.
            spelled_writer() { # <name> <root as the writer names it>
              start_row "$1"
              serve_lock
              process 57 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target "$2" load --data /tmp/seed.jsonl
              run_program
              refused_untouched
              expect_calls
              expect_reason "an omnigraph process has the root open (pid 57, omnigraph)"
              expect_journal_only "pid 57 runs ${omnigraphExe}: omnigraph --target $2 load"
            }
            row_spelled_writers() {
              spelled_writer doubled-slash /var/lib/omnigraph//clusters/cookbooks-f17
              spelled_writer dot-segment-trailing-slash /var/lib/omnigraph/./clusters/cookbooks-f17/
              spelled_writer file-uri file:///var/lib/omnigraph//clusters/cookbooks-f17/
              spelled_writer dot-dot-segment /var/lib/omnigraph/clusters/x/../cookbooks-f17
              spelled_writer dot-dot-above-root /../var/lib/omnigraph/clusters/cookbooks-f17
            }
            row_spelled_root() {
              start_row spelled-root
              serve_lock
              process 58 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target ${root} load --data /tmp/seed.jsonl
              program=${lib.getExe spelledRootProgram}
              run_program
              refused_untouched
              expect_calls
              expect_reason "an omnigraph process has the root open (pid 58, omnigraph)"
              expect_journal_only "pid 58 runs ${omnigraphExe}: omnigraph --target ${root} load"
            }

            # A refusal whose notice fails still refuses, with exit status 1.
            row_refusal_notice_fails() {
              start_row refusal-notice-fails
              serve_lock
              process 77 ${toString omnigraphUid} ${omnigraphExe} omnigraph --target ${root} load --data /tmp/seed.jsonl --graph cookbook-beads
              export NTFY_FAIL=1
              run_program
              [ "$code" = 1 ] || fail "exit $code, expected 1"
              expect_lock_unchanged
              expect_counter absent
              expect_refusal_notice
              grep -qF 'omnigraph-lock-recovery: the refusal notice was not posted' "$dir/err" || fail "the failed post is not logged: $(cat "$dir/err")"
            }

            # The packaged omnigraph's own record: apply, serve, SIGKILL, then
            # the program built with the packaged omnigraph and the real /proc.
            row_packaged_record() {
              start_row packaged-record
              rm -rf "$dir/var-lib/omnigraph/clusters/cookbooks-f17/__cluster"
              cat >"$dir/log/crash.sh" <<'EOF'
            set -euo pipefail
            export OMNIGRAPH_HOME=/tmp/omnigraph-home OMNIGRAPH_SERVER_BEARER_TOKENS_FILE=${tokensFile}
            mkdir -p "$OMNIGRAPH_HOME"
            omnigraph --target ${root} cluster apply --config ${clusterConfig} --json >/run/log/apply.json
            serve() {
              omnigraph-server --cluster ${root} --bind 127.0.0.1:18090 >>/run/log/server.log 2>&1 &
              server=$!
              for _ in $(seq 120); do
                curl -sf http://127.0.0.1:18090/readyz >/dev/null && return 0
                kill -0 "$server" 2>/dev/null || { cat /run/log/server.log >&2; return 1; }
                sleep 0.5
              done
              return 1
            }
            serve
            kill -9 "$server"
            wait "$server" || true
            cp ${root}/__cluster/lock.json /run/log/lock.json
            ${lib.getExe packagedProgram} >/run/log/recovery.out 2>/run/log/recovery.err
            omnigraph --target ${root} cluster status --json >/run/log/status.json
            serve
            kill -TERM "$server"
            wait "$server"
            EOF
              set +e
              NTFY_LOG=/run/log/ntfy bwrap --unshare-all --share-net --die-with-parent \
                --proc /proc --dev /dev --tmpfs /tmp --setenv TMPDIR /tmp \
                --ro-bind /nix/store /nix/store \
                --ro-bind ${passwd} /etc/passwd \
                --bind "$dir/var-lib" /var/lib \
                --bind "$dir/log" /run/log \
                bash /run/log/crash.sh >"$dir/out" 2>"$dir/err"
              code=$?
              set -e
              [ "$code" = 0 ] || { cat "$dir/err" "$dir/log/server.log" "$dir/log/recovery.err" >&2 || true; fail "the crash and recovery exited $code"; }
              jq -e 'keys == ["created_at", "lock_id", "operation", "pid", "version"] and .version == 1 and .operation == "serve" and (.pid | type) == "number"' \
                "$dir/log/lock.json" >/dev/null || fail "omnigraph-server's lock record changed shape: $(cat "$dir/log/lock.json")"
              id=$(jq -r .lock_id "$dir/log/lock.json")
              grep -qF "cleared the stale serve lock $id" "$dir/log/recovery.out" || fail "the recovery did not clear $id: $(cat "$dir/log/recovery.out" "$dir/log/recovery.err")"
              jq -e '.lock_id == null' "$dir/log/status.json" >/dev/null || fail "the cluster still reports a lock: $(cat "$dir/log/status.json")"
              expect_counter 1
              expect_notices 1
            }

            rows=(
              no_lock dead_server running_writer running_server unrelated_processes
              direct_writer_lock live_pid_this_boot lock_before_boot id_mismatch status_failed
              unreadable unlock_unconfirmed counter_counts_on notice_fails refusal_notice_fails
              listing_unreadable exe_unreadable owner_unreadable btime_missing stat_unreadable
              stepped_clock_server imposter_ignored counted_writers spelled_writers spelled_root
              status_answers jq_missing later_step_fails counter_unwritable
            )
            program=${lib.getExe program}
            for r in "''${rows[@]}"; do
              ( "row_$r" )
              echo "ok: $r"
            done
            ( row_packaged_record )
            echo "ok: packaged_record"

            ${lib.concatStrings (
              lib.mapAttrsToList (
                name: m:
                lib.concatMapStrings (row: ''
                  if ( program=${lib.getExe' (mutantProgram name m) "omnigraph-lock-recovery"}; row_${
                    builtins.replaceStrings [ "-" ] [ "_" ] row
                  } ) 2>"$TMPDIR/mutant.log"; then
                    echo "FAIL: mutant ${name} passed the row ${row}" >&2
                    exit 1
                  fi
                  echo "mutant ${name} rejected: $(tail -n 1 "$TMPDIR/mutant.log")"
                '') m.rows
              ) mutants
            )}
            touch "$out"
          '';
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-lock-recovery-rehearsal.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-lock-recovery-rehearsal = rehearsal;
      };
    };
}
