# The stale-lock recovery of a local omnigraph root, run by omnigraph-server's
# start as its first ExecStartPre, with `+`, only when the root is a local
# path (modules/nixos/omnigraph.nix).
#
# A server killed on a local root leaves `<root>/__cluster/lock.json`
# behind, and every later start refuses with `state_lock_held` until
# `omnigraph cluster force-unlock <lock_id>` runs. A local lock has no lease
# and no stale-holder detection, and force-unlock checks only that the id
# matches: it removes a live server's lock as readily as a dead one's
# (omnigraph 0.16.0, docs/user/operations/storage-failures.md; crates/
# omnigraph-cluster/src/store.rs force_unlock). So the program itself proves
# the lock stale before it unlocks, and clears it only when all of these
# hold, in this order:
#   1. no lock file: exit 0, nothing run;
#   2. the process table can be read: it lists, and every process with a
#      command line has a readable executable and, where the next step needs
#      it, a readable owner; a process with an empty command line (a kernel
#      thread or a zombie) has no executable and holds no file, and is
#      skipped;
#   3. no process that may write the root has an argument naming it: one
#      whose executable is named `omnigraph` or `omnigraph-server` and is
#      either an omnigraph package's in the Nix store, from any version, or
#      run by root or `writerUser` (a direct writer run as root included,
#      which the server's sandbox would hide from it); an executable of that
#      name elsewhere, run by another user, is not omnigraph's, and counting
#      it would let any user hold the server down;
#   4. the record is OmniGraph's held-lock shape (version 1, string lock_id,
#      operation and created_at, positive integer pid), its created_at is a
#      date, and `omnigraph cluster status --json` reports the same lock_id;
#   5. its operation is `serve`: any other lock is a direct writer's, whose
#      recovery is the reconciliation of its deployment, not a bare unlock;
#   6. the boot time (`btime` in <proc>/stat) is an integer;
#   7. its pid is not running an executable named `omnigraph` or
#      `omnigraph-server`, whatever the boot time says: a server the scan
#      missed (another argument form) after a forward clock step would
#      otherwise look like one from an earlier boot;
#   8. its pid is not running, or the lock was taken before this boot: the
#      record has no boot id, so a running pid is only another program when
#      the boot changed;
# then it runs `omnigraph --target <root> cluster force-unlock <lock_id>
# --json`, requires `"unlocked": true`, adds one to the integer in
# `counterFile` (0 when absent), which omnigraph-probe publishes, and posts a
# low-priority notice to fleet-alerts through ntfy-send, whose failure does
# not fail the start. Any other case leaves lock.json as it is, prints the
# reason and the manual step, and exits 1, so the start fails visibly.
#
# A server in another pid namespace (a container) passes steps 7 and 8:
# its record's pid is the namespace's, which on the host is absent or
# another process.
#
# `proc` is the process table and boot time to read, /proc on a host;
# checks.x86_64-linux.omnigraph-lock-recovery-rehearsal builds the program
# over a scripted one, replaces the line after `# mutant: <name>` for each
# mutant, and requires that mutant's row to fail.
{ config, ... }:
{
  flake.lib.omnigraphLockRecovery =
    pkgs:
    {
      omnigraph,
      root,
      hostName,
      ntfySend,
      tokenFile ? null,
      # The command prefix the manual steps name, e.g. the host's
      # omnigraph-cluster wrapper.
      manualCli ? "omnigraph --target ${root} cluster",
      proc ? "/proc",
      # The user owning the root's files, whom omnigraph runs as, so that the
      # unlock leaves no file owned by root; null runs it as the caller.
      runAs ? null,
      # The user besides root whose processes named omnigraph count as
      # writers of the root wherever their executable lies; null counts
      # root's alone.
      writerUser ? runAs,
      counterFile ? config.flake.lib.omnigraphProbe.lockRecoveriesFile,
    }:
    let
      lib = pkgs.lib;
    in
    pkgs.writeShellApplication {
      name = "omnigraph-lock-recovery";
      runtimeInputs = [
        omnigraph
        pkgs.coreutils
        pkgs.gawk
        pkgs.jq
      ];
      text = ''
        root=${lib.escapeShellArg root}
        lock="$root/__cluster/lock.json"
        proc=${lib.escapeShellArg proc}
        counter=${lib.escapeShellArg counterFile}
        og() {
          ${
            if runAs == null then
              ''omnigraph "$@"''
            else
              ''${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg runAs} -- omnigraph "$@"''
          }
        }
        manual=${lib.escapeShellArg manualCli}

        refuse() { # <reason> <manual step>
          printf 'omnigraph-lock-recovery: left %s in place: %s\n' "$lock" "$1" >&2
          printf 'omnigraph-lock-recovery: omnigraph-server stays stopped until the lock is cleared. %s\n' "$2" >&2
          exit 1
        }

        # Reads the process directory $1 into `args` (its command line) and
        # `exe` (its executable, without " (deleted)"). Fails for a process
        # that has exited and for one with an empty command line; refuses
        # when a live process's command line or executable cannot be read.
        read_process() {
          local pid=''${1##*/}
          local check="Confirm with ps -o pid,user,args -p $pid that it is not an omnigraph process using the root, then run: systemctl restart omnigraph-server"
          if ! mapfile -d "" -t args 2>/dev/null <"$1/cmdline"; then
            [ -e "$1" ] || return 1
            refuse "the command line of pid $pid cannot be read" "$check"
          fi
          [ "''${#args[@]}" -gt 0 ] || return 1
          if ! exe=$(readlink -- "$1/exe" 2>/dev/null); then
            [ -e "$1" ] || return 1
            refuse "the executable of pid $pid (''${args[*]}) cannot be read" "$check"
          fi
          exe=''${exe% (deleted)}
        }

        # Whether the process directory $1 runs as root or the writer user,
        # by any of its real, effective, saved and file-system uids.
        writer_owned() {
          local uids uid writer
          if ! uids=$(awk '$1 == "Uid:" { print $2, $3, $4, $5; found = 1 } END { exit !found }' "$1/status" 2>/dev/null); then
            [ -e "$1" ] || return 1
            refuse "the owner of pid ''${1##*/} (''${args[*]}) cannot be read" \
              "Confirm with ps -o pid,user,args -p ''${1##*/} that it is not an omnigraph process using the root, then run: systemctl restart omnigraph-server"
          fi
          for uid in $uids; do
            for writer in "''${writer_uids[@]}"; do
              [ "$uid" != "$writer" ] || return 0
            done
          done
          return 1
        }

        # Sets `holder` to `pid <pid>: <argv>` of the first process that may
        # write the root and has an argument naming it.
        scan_processes() {
          local entries entry arg
          if ! entries=$(ls -- "$proc" 2>/dev/null); then
            refuse "the process table $proc cannot be listed" \
              "Check that $proc is mounted and readable by root (ls $proc), then run: systemctl restart omnigraph-server"
          fi
          for entry in $entries; do
            [[ $entry =~ ^[0-9]+$ ]] || continue
            read_process "$proc/$entry" || continue
            case ''${exe##*/} in
              omnigraph | omnigraph-server) ;;
              *) continue ;;
            esac
            case $exe in
              /nix/store/*-omnigraph-*/bin/omnigraph | /nix/store/*-omnigraph-*/bin/omnigraph-server) ;;
              *) writer_owned "$proc/$entry" || continue ;;
            esac
            for arg in "''${args[@]}"; do
              case $arg in
                *"$root" | *"$root"/*)
                  holder="pid $entry: ''${args[*]}"
                  return 0
                  ;;
              esac
            done
          done
          return 1
        }

        [ -e "$lock" ] || exit 0

        writer_uids=(0)
        ${lib.optionalString (writerUser != null) ''
          if ! writer_uid=$(id -u -- ${lib.escapeShellArg writerUser} 2>/dev/null); then
            refuse ${lib.escapeShellArg "the user ${writerUser} does not exist, so the processes that may write the root cannot be told apart"} \
              "Once no omnigraph process runs against the root (ps -eo pid,user,args), run: $manual force-unlock <lock_id>"
          fi
          writer_uids+=("$writer_uid")
        ''}

        # mutant: scanSkipped
        if scan_processes; then
          refuse "an omnigraph process has the root open ($holder)" \
            "Wait for that process to finish or stop it, then run: systemctl restart omnigraph-server"
        fi

        if ! record=$(jq -er '
          if type == "object" and .version == 1
            and (.lock_id | type) == "string" and (.lock_id | test("^[0-9A-Za-z]+$"))
            and (.operation | type) == "string" and (.operation | test("^[a-z_]+$"))
            and (.created_at | type) == "string"
            and (.created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"))
            and (.pid | type) == "number" and .pid == (.pid | floor) and .pid > 0
          then [.lock_id, .operation, .created_at, (.pid | tostring)] | join("\t")
          else error("not a held lock") end' "$lock" 2>/dev/null); then
          refuse "the record is not the shape omnigraph writes for a held lock (version 1, string lock_id and operation, an RFC 3339 created_at, positive integer pid)" \
            "Read $lock and $manual status --json, and once no omnigraph process runs against the root, run: $manual force-unlock <lock_id>"
        fi
        IFS=$'\t' read -r lock_id operation created_at pid <<<"$record"
        if ! created=$(date -u -d "$created_at" +%s 2>/dev/null); then
          refuse "the record's created_at ($created_at) is not a date" \
            "Read $lock and $manual status --json, and once no omnigraph process runs against the root, run: $manual force-unlock $lock_id"
        fi

        OMNIGRAPH_HOME=$(mktemp -d)
        export OMNIGRAPH_HOME
        trap 'rm -rf -- "$OMNIGRAPH_HOME"' EXIT
        ${lib.optionalString (runAs != null) ''chown ${lib.escapeShellArg runAs} "$OMNIGRAPH_HOME"''}
        if ! status=$(og --target "$root" cluster status --json); then
          refuse "omnigraph cluster status failed, so the record's lock $lock_id cannot be confirmed as the cluster's" \
            "Read $manual status --json, and once no omnigraph process runs against the root, run: $manual force-unlock $lock_id"
        fi
        reported=$(jq -r '.lock_id // "none"' <<<"$status")
        if [ "$reported" != "$lock_id" ]; then
          refuse "the record names lock $lock_id but omnigraph cluster status reports $reported, so the lock changed while it was read" \
            "Run systemctl restart omnigraph-server to read it again; if it persists, compare $lock with $manual status --json"
        fi

        if [ "$operation" != serve ]; then
          refuse "lock $lock_id was taken by a direct $operation writer (pid $pid, $created_at), whose interrupted work needs its own recovery" \
            "With no omnigraph process running against the root, find its deployment with $manual status --json, then run $manual force-unlock $lock_id and $manual apply --deployment-id <deployment_id> --writers-stopped --json; for a writer other than an apply, confirm it stopped and run $manual force-unlock $lock_id"
        fi

        pid_check="Confirm pid $pid is not an omnigraph-server holding the root (ps -o pid,args -p $pid), then run $manual force-unlock $lock_id and systemctl restart omnigraph-server"
        btime=$(awk '$1 == "btime" { print $2 }' "$proc/stat" 2>/dev/null) || btime=
        # mutant: btimeUnchecked
        [[ $btime =~ ^[0-9]+$ ]] || refuse "the boot time in $proc/stat cannot be read, so whether lock $lock_id was taken in this boot cannot be told" "$pid_check"

        if [ -d "$proc/$pid" ]; then
          if read_process "$proc/$pid"; then
            pid_program=''${exe##*/}
            # mutant: omnigraphAtPidExcused
            if [ "$pid_program" = omnigraph ] || [ "$pid_program" = omnigraph-server ]; then
              refuse "pid $pid, which lock $lock_id names, is running $exe (''${args[*]}), so the lock may be that server's whatever the boot time says" \
                "Confirm pid $pid does not serve the root (ps -o pid,args -p $pid); if it does not, run $manual force-unlock $lock_id and systemctl restart omnigraph-server; if it does, stop it, then run systemctl restart omnigraph-server"
            fi
          fi
          if [ "$created" -ge "$btime" ]; then
            refuse "lock $lock_id was taken in this boot ($created_at) by pid $pid, which is running" "$pid_check"
          fi
        fi

        if ! unlocked=$(og --target "$root" cluster force-unlock "$lock_id" --json) \
          || ! jq -e '.unlocked == true' <<<"$unlocked" >/dev/null; then
          printf 'omnigraph-lock-recovery: omnigraph cluster force-unlock %s did not report the lock removed: %s\n' "$lock_id" "''${unlocked:-}" >&2
          exit 1
        fi

        count=0
        if [ -e "$counter" ]; then
          read -r count <"$counter" || true
          if ! [[ $count =~ ^[0-9]+$ ]]; then
            printf 'omnigraph-lock-recovery: %s held no count; counting from 0\n' "$counter" >&2
            count=0
          fi
        fi
        count=$((count + 1))
        install -d -m 0755 -- "$(dirname -- "$counter")"
        printf '%s\n' "$count" >"$counter.tmp"
        chmod 0644 -- "$counter.tmp"
        mv -f -- "$counter.tmp" "$counter"

        message="omnigraph-server on ${hostName} cleared the stale serve lock $lock_id of $root (pid $pid, taken $created_at) and starts; lock recoveries on ${hostName}: $count"
        echo "omnigraph-lock-recovery: $message"
        ${lib.optionalString (tokenFile != null) "NTFY_TOKEN_FILE=${lib.escapeShellArg tokenFile} \\"}
        timeout 30 ${ntfySend} "$message" fleet-alerts -H "Priority: low" -H "Title: omnigraph lock recovered on ${hostName}" \
          || echo "omnigraph-lock-recovery: the recovery notice was not posted" >&2
      '';
    };
}
