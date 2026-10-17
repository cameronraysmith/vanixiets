# The telemetry store's hourly runtime envelope (design D12) and the SQL
# helper its every query goes through.
#
# greptimedbSql posts one statement to GreptimeDB's /v1/sql as `user`,
# reading the password from $CREDENTIALS_DIRECTORY/<user>-password and
# passing it to curl on stdin so it never appears in argv, and prints the
# rows of the one records result as TSV with NULL for null. It exits 1 on a
# transport failure, on any answer but 200 (a missing table is HTTP 400 with
# code 4001 TableNotFound), on a body that is not exactly one records
# result, and on zero rows: a regulator query that matches nothing fails
# instead of passing vacuously (F3). modules/checks/greptimedb-envelope.nix
# runs this function's output against recorded v1.2.1 answers.
#
# greptimedbEnvelope is greptimedb-envelope.service's ExecStart. It reports
# every failed property as one `FAIL <id>: ...` line on stderr and exits 1
# if any failed:
#
# - R6.4 readiness: GET <url>/ready answers 200.
# - R6.2: information_schema.region_statistics reports sst_size for at least
#   one region, and the sum is under GREPTIMEDB_ENVELOPE_SST_MAX_BYTES.
# - R6.3 and per-table retention: the base tables of `databases` exist, none
#   sets sst_format=primary_key (the legacy format) and none sets a ttl of
#   its own, which would override its database's (F1).
# - R7.2: the unit cgroup's memory.peak is under
#   GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES; memory.events oom_kill and max
#   have not risen since the last run of the same invocation. Both files
#   restart from zero with each invocation, so across invocations the run
#   instead fails if systemd logged a kernel OOM kill in the unit since the
#   last run, or if NRestarts rose (an automatic restart). The baseline is
#   rewritten on every run, so one rise fails one run. The first run only
#   records a baseline.
# - R7.3: the dataset's quota and reservation equal
#   GREPTIMEDB_ENVELOPE_{QUOTA,RESERVATION}_BYTES and used space is under
#   GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT of the quota.
# - R7.4: the sha256 the running store recorded for the users file it loaded
#   (`loadedUsersHashFile`) equals the deployed users file's public sha256
#   (GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE). sops-nix rewrites every secret,
#   with a new mtime, on each activation while restartUnits restarts only on
#   a changed value, so a hash comparison is the one that holds.
#
# Thresholds and host facts come from the environment so a runtime drop-in
# can force a failure (tasks.md 8.6).
{ lib, ... }:
let
  greptimedbSql =
    pkgs:
    { url, user }:
    pkgs.writeShellApplication {
      name = "greptimedb-sql";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: greptimedb-sql SQL" >&2
          exit 2
        fi
        sql=$1
        password_file="''${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY is unset}/${user}-password"
        body=$(mktemp)
        trap 'rm -f "$body"' EXIT
        if ! status=$(printf 'user = "%s:%s"\n' ${lib.escapeShellArg user} "$(< "$password_file")" \
          | curl --config - --silent --show-error --max-time 30 \
              --output "$body" --write-out '%{http_code}' \
              --data-urlencode "sql=$sql" ${lib.escapeShellArg "${url}/v1/sql"}); then
          printf 'greptimedb-sql: request failed: %s\n' "$sql" >&2
          exit 1
        fi
        if [ "$status" != 200 ]; then
          printf 'greptimedb-sql: HTTP %s: %s: %s\n' "$status" \
            "$(jq -r '"\(.code) \(.error)"' "$body" 2>/dev/null || cat "$body")" "$sql" >&2
          exit 1
        fi
        if ! jq -e '(.output | length) == 1 and (.output[0].records.rows | type) == "array"' "$body" > /dev/null; then
          printf 'greptimedb-sql: not one records result: %s: %s\n' "$sql" "$(cat "$body")" >&2
          exit 1
        fi
        if jq -e '(.output[0].records.rows | length) == 0' "$body" > /dev/null; then
          printf 'greptimedb-sql: empty result: %s\n' "$sql" >&2
          exit 1
        fi
        jq -r '.output[0].records.rows[] | map(if . == null then "NULL" else tostring end) | @tsv' "$body"
      '';
    };

  # systemd 261.3 src/systemd/sd-messages.h:198-199, logged with UNIT= by
  # src/core/cgroup.c:3099-3102 when the kernel OOM killer kills in a unit.
  unitOutOfMemoryMessageId = "fe6faa94e7774663a0da52717891d8ef";

  greptimedbEnvelope =
    pkgs:
    {
      url,
      databases,
      unit,
      loadedUsersHashFile,
      zfsPackage,
      systemdPackage,
    }:
    let
      sql = greptimedbSql pkgs {
        inherit url;
        user = "regulator";
      };
      schemaList = lib.concatMapStringsSep ", " (db: "'${db}'") databases;
    in
    pkgs.writeShellApplication {
      name = "greptimedb-envelope";
      runtimeInputs = [
        sql
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
        zfsPackage
        systemdPackage
      ];
      text = ''
        : "''${GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT:?}"
        : "''${GREPTIMEDB_ENVELOPE_SST_MAX_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_DATASET:?}"
        : "''${GREPTIMEDB_ENVELOPE_QUOTA_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_RESERVATION_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE:?}"
        : "''${STATE_DIRECTORY:?}"

        failed=0
        fail() {
          printf 'FAIL %s\n' "$*" >&2
          failed=1
        }
        field() {
          awk -v key="$1" '$1 == key { print $2 }'
        }

        # R6.4 readiness
        if ! curl --fail --silent --show-error --max-time 10 --output /dev/null ${lib.escapeShellArg "${url}/ready"}; then
          fail "R6.4: ${url}/ready did not answer 200"
        fi

        # R6.2
        if regions=$(greptimedb-sql 'SELECT region_id, sst_size FROM information_schema.region_statistics'); then
          read -r reported sst_bytes < <(awk -F '\t' '$2 != "NULL" { n++; s += $2 } END { printf "%d %.0f\n", n, s }' <<< "$regions")
          if [ "$reported" -eq 0 ]; then
            fail "R6.2: no region in information_schema.region_statistics reports sst_size"
          elif [ "$sst_bytes" -ge "$GREPTIMEDB_ENVELOPE_SST_MAX_BYTES" ]; then
            fail "R6.2: summed sst_size $sst_bytes >= GREPTIMEDB_ENVELOPE_SST_MAX_BYTES $GREPTIMEDB_ENVELOPE_SST_MAX_BYTES"
          fi
        else
          fail "R6.2: information_schema.region_statistics gave no rows"
        fi

        # R6.3 and per-table retention
        if tables=$(greptimedb-sql "SELECT table_schema, table_name, create_options FROM information_schema.tables WHERE table_schema IN (${schemaList}) AND table_type = 'BASE TABLE'"); then
          while IFS=$'\t' read -r schema table options; do
            if [[ " $options " == *" sst_format=primary_key "* ]]; then
              fail "R6.3: $schema.$table uses the legacy sst_format=primary_key"
            fi
            if [[ " $options " == *" ttl="* ]]; then
              fail "TTL: $schema.$table sets a ttl of its own ($options), overriding its database's"
            fi
          done <<< "$tables"
        else
          fail "R6.3: information_schema.tables gave no base table in ${schemaList}"
        fi

        # R7.2
        cgroup=/sys/fs/cgroup/system.slice/${unit}
        if ! peak=$(< "$cgroup/memory.peak"); then
          fail "R7.2: cannot read $cgroup/memory.peak"
        elif [ "$peak" -ge "$GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES" ]; then
          fail "R7.2: memory.peak $peak >= GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES $GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES"
        fi
        oom_kill=$(field oom_kill < "$cgroup/memory.events" || true)
        max=$(field max < "$cgroup/memory.events" || true)
        invocation=$(systemctl show --property=InvocationID --value ${unit} || true)
        nrestarts=$(systemctl show --property=NRestarts --value ${unit} || true)
        now=$(date +%s)
        if [ -z "$oom_kill" ] || [ -z "$max" ]; then
          fail "R7.2: $cgroup/memory.events lacks oom_kill or max"
        elif [ -z "$invocation" ] || [ -z "$nrestarts" ]; then
          fail "R7.2: ${unit} has no current invocation"
        else
          baseline="$STATE_DIRECTORY/memory-baseline"
          if [ -s "$baseline" ]; then
            read -r base_invocation base_oom_kill base_max base_nrestarts base_time < "$baseline"
            if [ "$invocation" = "$base_invocation" ]; then
              if [ "$oom_kill" -gt "$base_oom_kill" ]; then
                fail "R7.2: memory.events oom_kill rose from $base_oom_kill to $oom_kill"
              fi
              if [ "$max" -gt "$base_max" ]; then
                fail "R7.2: memory.events max rose from $base_max to $max"
              fi
            else
              # systemd logged the new invocation's start with UNIT=, so an
              # empty answer means the journal is unreadable, not quiet.
              if ! ids=$(journalctl --quiet --since "@$base_time" --output=json --output-fields=MESSAGE_ID UNIT=${unit} | jq -r '.MESSAGE_ID // "-"') || [ -z "$ids" ]; then
                fail "R7.2: no journal entries for ${unit} since @$base_time; the journal is unreadable"
              elif grep -qx ${unitOutOfMemoryMessageId} <<< "$ids"; then
                fail "R7.2: the kernel OOM killer killed processes in ${unit} since @$base_time"
              fi
              if [ "$nrestarts" -gt "$base_nrestarts" ]; then
                fail "R7.2: ${unit} restarted automatically since @$base_time (NRestarts $base_nrestarts -> $nrestarts)"
              fi
            fi
          fi
          printf '%s %s %s %s %s\n' "$invocation" "$oom_kill" "$max" "$nrestarts" "$now" > "$baseline"
        fi

        # R7.3
        if ! props=$(zfs get -Hp -o property,value used,quota,reservation "$GREPTIMEDB_ENVELOPE_DATASET"); then
          fail "R7.3: zfs get failed for $GREPTIMEDB_ENVELOPE_DATASET"
        else
          used=$(field used <<< "$props")
          quota=$(field quota <<< "$props")
          reservation=$(field reservation <<< "$props")
          if [ -z "$used" ] || [ -z "$quota" ] || [ -z "$reservation" ]; then
            fail "R7.3: zfs get answered without used, quota or reservation: $props"
          else
            if [ "$quota" != "$GREPTIMEDB_ENVELOPE_QUOTA_BYTES" ]; then
              fail "R7.3: quota $quota != GREPTIMEDB_ENVELOPE_QUOTA_BYTES $GREPTIMEDB_ENVELOPE_QUOTA_BYTES"
            fi
            if [ "$reservation" != "$GREPTIMEDB_ENVELOPE_RESERVATION_BYTES" ]; then
              fail "R7.3: reservation $reservation != GREPTIMEDB_ENVELOPE_RESERVATION_BYTES $GREPTIMEDB_ENVELOPE_RESERVATION_BYTES"
            fi
            if [ $((used * 100)) -ge $((quota * GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT)) ]; then
              fail "R7.3: used $used >= $GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT% of quota $quota"
            fi
          fi
        fi

        # R7.4
        if ! current=$(< "$GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE"); then
          fail "R7.4: cannot read $GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE"
        elif ! loaded=$(< ${loadedUsersHashFile}); then
          fail "R7.4: ${loadedUsersHashFile} is missing; the store has not recorded the users file it loaded"
        elif [ -z "$current" ] || [ "$current" != "$loaded" ]; then
          fail "R7.4: the running store loaded users file sha256 '$loaded', the deployed one is '$current'; restart ${unit}"
        fi

        if [ "$failed" -ne 0 ]; then
          exit 1
        fi
        echo "greptimedb-envelope: all checks passed"
      '';
    };
in
{
  flake.lib = {
    inherit greptimedbSql greptimedbEnvelope;
  };
}
