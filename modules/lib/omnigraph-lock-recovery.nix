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
#   2. no process whose executable is named `omnigraph` or `omnigraph-server`
#      has an argument naming the root (a direct writer run as root
#      included, which the server's sandbox would hide from it); the
#      executable is matched by name, so a writer started from an older or
#      newer omnigraph package counts too;
#   3. the record is OmniGraph's held-lock shape (version 1, string lock_id,
#      operation and created_at, positive integer pid), its created_at is a
#      date, and `omnigraph cluster status --json` reports the same lock_id;
#   4. its operation is `serve`: any other lock is a direct writer's, whose
#      recovery is the reconciliation of its deployment, not a bare unlock;
#   5. its pid is not running, or the lock was taken before this boot
#      (`btime` in <proc>/stat): the record has no boot id, so a running pid
#      is only another process when the boot changed;
# then it runs `omnigraph --target <root> cluster force-unlock <lock_id>
# --json`, requires `"unlocked": true`, adds one to the integer in
# `counterFile` (0 when absent), which omnigraph-probe publishes, and posts a
# low-priority notice to fleet-alerts through ntfy-send, whose failure does
# not fail the start. Any other case leaves lock.json as it is, prints the
# reason and the manual step, and exits 1, so the start fails visibly.
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

        # The first omnigraph process with an argument naming the root, as
        # `pid <pid>: <argv>`.
        scan_processes() {
          local dir exe arg
          local -a args
          for dir in "$proc"/[0-9]*; do
            exe=$(readlink -- "$dir/exe" 2>/dev/null) || continue
            exe=''${exe% (deleted)}
            case ''${exe##*/} in
              omnigraph | omnigraph-server) ;;
              *) continue ;;
            esac
            mapfile -d "" -t args < <(cat -- "$dir/cmdline" 2>/dev/null || true)
            for arg in "''${args[@]}"; do
              case $arg in
                *"$root" | *"$root"/*)
                  printf 'pid %s: %s\n' "''${dir##*/}" "''${args[*]}"
                  return 0
                  ;;
              esac
            done
          done
          return 1
        }

        [ -e "$lock" ] || exit 0

        # mutant: scanSkipped
        if holder=$(scan_processes); then
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

        btime=$(awk '$1 == "btime" { print $2 }' "$proc/stat")
        if [ -d "$proc/$pid" ] && [ "$created" -ge "$btime" ]; then
          refuse "lock $lock_id was taken in this boot ($created_at) by pid $pid, which is running" \
            "Confirm pid $pid is not an omnigraph-server holding the root (ps -o pid,args -p $pid), then run $manual force-unlock $lock_id and systemctl restart omnigraph-server"
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
