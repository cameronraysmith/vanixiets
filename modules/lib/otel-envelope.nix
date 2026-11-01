# otel-envelope: each agent host's collector judged from its own telemetry
# endpoint every five minutes (ADR-003 R3.2; S4 design D7).
#
# flake.lib.otelEnvelope pkgs { hostName; telemetryUrl; targets; exporters;
# ingress; budget; } is otel-envelope.service's ExecStart. `targets` is a
# list of { job; url; credential ? null; }, the collector's own scrape
# targets; a target with a credential is probed with `Authorization: Bearer`
# read from $CREDENTIALS_DIRECTORY/<credential> and passed to curl on stdin.
# `exporters` names the collector's configured exporters. Each run
# prints one `otel-envelope: <clause> <name>: ok|FAIL <detail>` line per
# clause and exits 1 if any failed:
#
# - C1 telemetry: the endpoint did not answer within 10 s on this run and
#   the previous one.
# - C2 targets: a target did not answer GET with 200 within 10 s on this run
#   and the previous one.
# - C3 queue: a configured exporter has no otelcol_exporter_queue_size or no
#   otelcol_exporter_queue_capacity series in telemetry that answered, or an
#   exporter's size reached 90 % of its capacity, or the capacity is absent.
# - C4 loss: since the previous run, otelcol_exporter_send_failed_* rose on
#   any exporter, otelcol_receiver_refused_* on any receiver but the
#   ingress's otlp/mesh, or, off the ingress host, any
#   otelcol_exporter_enqueue_failed_*. On the ingress host otlp/mesh
#   refusals and the store exporters' enqueue failures are back-pressure
#   that the agents' queues absorb; a full store queue fails C3.
#
# With `budget` = { storeUrl; notifiedUnits; databases; } (the ingress host,
# S4 design D8), a run whose minute is 00 (OTEL_ENVELOPE_MINUTE, default the
# UTC minute of OTEL_ENVELOPE_NOW, itself default `date -u +%s`, both read
# before C1) or with OTEL_ENVELOPE_FORCE_HOURLY=1 is a budget run: it also
# judges the store as its read-only `regulator`, through
# flake.lib.greptimedbSql, whose failure (no answer, an error, a missing
# table, no rows) fails the clause that sent the query:
#
# - B1 active-series: over budget.activeSeries series (`__tsid`) in `fleet`
#   in the last hour.
# - B2 label-values: a tag column of fleet's physical table, other than the
#   store's own `__tsid` and `__table_id` and the three that B3 bounds per
#   host, over budget.labelValues values within one metric in the last hour.
#   A column within the limit across all metrics is within it for each, so
#   only a column above it is grouped by metric.
# - B3 per-host: a host with over budget.processNames
#   process_executable_name values, over OTEL_ENVELOPE_MAX_UNITS (default
#   budget.units) systemd_unit_name values other than notifier instances, or
#   over budget.launchdLabels launchd_label values in the last hour; the
#   launchd count is skipped, with a note, while no table carries that label.
# - B4 notifier-instances: an `observability-notify@<unit>.service.service`
#   instance stored for a host whose `notifiedUnits` lacks `<unit>`.
# - B5 devloop-rows: over budget.devloopRows rows in devloop's tables with a
#   time index in the last 24 h.
# - B6 ttl: a database of `databases` whose ttl is not the declared one,
#   compared as durations (flake.lib.humantimeDurationAwk).
#
# Every run with `budget`, budget run or not, also judges:
#
# - B1 to B6 carried: a run that is not a budget run repeats each clause the
#   last budget run failed, with its message, so the failure episode lasts
#   until a budget run passes it rather than ending at the next run with a
#   false RESOLVED (review F1).
# - B0 budget-run: the last budget run was over 65 min ago, the hourly
#   calendar's 60 plus the timer's 1 min accuracy and a run's own minutes. A
#   state with no budget run recorded, fresh or written before this clause
#   existed, counts from the first run that found none, so it fails only
#   when a whole calendar hour has passed it without a budget run.
#
# $STATE_DIRECTORY/state holds one `<key> <value>` line per loss series,
# keyed without the labels that change at every collector start, plus
# `telemetry 0|1` and `down:<target> 0|1`, and with `budget` one
# `budget:<clause> ok|FAIL <message>` line per budget clause (its spaces as
# `:`), `budget-run <epoch>` or, before the first, `budget-since <epoch>`; it
# is replaced as a whole at the end of each run.
# checks.x86_64-linux.otel-envelope replaces each line marked
# `# mutant: <name>`, in the script or in this file, and requires that
# mutant's case to fail.
#
# The budget limits are flake.lib.otelCollectorSchema.budget, ADR-004's,
# which the agent role's unit-cap assertion reads too.
#
# flake.lib.otelEnvelopeTargets receivers renders `targets` from a
# collector's evaluated receivers: every target of every job of every
# `prometheus*` receiver, so the envelope probes what the collector scrapes.
# A target is named by its job, or `<job>@<host:port>` in a job with more
# than one target, and a job's authorization.credentials_file becomes the
# credential of that file's name.
{ config, lib, ... }:
let
  flakeLib = config.flake.lib;

  # The budget run's clock, read before C1 and C2, whose 10 s probes could
  # otherwise carry a run started at minute 00 into minute 01.
  budgetClock = ''
    now=''${OTEL_ENVELOPE_NOW:-$(date -u +%s)}
    minute=''${OTEL_ENVELOPE_MINUTE:-$(date -u -d "@$now" +%M)}
    utc() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
  '';

  # The hourly clauses' script text, interpolated after C4.
  budgetClauses =
    pkgs: budget:
    let
      hour = "greptime_timestamp > now() - INTERVAL '1 hour'";
      limits = flakeLib.otelCollectorSchema.budget;
      devloopRows = lib.concatStringsSep " UNION ALL " (
        lib.mapAttrsToList (
          name: table:
          "SELECT count(*) AS n FROM devloop.${name} WHERE \"${table.timeIndex}\" > now() - INTERVAL '24 hours'"
        ) flakeLib.otelCollectorSchema.devloop.tables
      );
      databaseList = lib.concatMapStringsSep ", " (db: "'${db}'") (lib.attrNames budget.databases);
      notified = pkgs.writeText "otel-envelope-notified-units" (
        lib.concatStrings (
          lib.mapAttrsToList (
            host: units: lib.concatMapStrings (unit: "${host}\t${unit}\n") units
          ) budget.notifiedUnits
        )
      );
      declaredTtls = pkgs.writeText "otel-envelope-database-ttls" (
        lib.concatStrings (lib.mapAttrsToList (db: ttl: "${db}\t${ttl}\n") budget.databases)
      );
      # The store's `options` column renders each option as `'key'='value'`
      # and ends it with a newline, which greptimedb-sql's TSV shows as `\n`.
      ttlProgram = pkgs.writeText "otel-envelope-ttl.awk" ''
        ${flakeLib.humantimeDurationAwk}
        BEGIN {
          FS = "\t"
          humantime_units()
        }
        FILENAME == ARGV[1] {
          declared[$1] = $2
          next
        }
        {
          seen[$1] = 1
          if (!match($2, /\047ttl\047=\047[^\047]*\047/)) {
            printf "%s sets no ttl, declared %s; ", $1, declared[$1]
            next
          }
          ttl = substr($2, RSTART + 7, RLENGTH - 8)
          if (duration(ttl) == "invalid" || duration(ttl) != duration(declared[$1])) {
            printf "%s %s, declared %s; ", $1, ttl, declared[$1]
          }
        }
        END {
          for (db in declared) if (!(db in seen)) printf "%s absent; ", db
        }
      '';
    in
    ''
      # B1 to B6 (design D8): the store's budget, on the hour.
      if [ "$minute" = 00 ] || [ "''${OTEL_ENVELOPE_FORCE_HOURLY:-0}" = 1 ]; then
        max_units=''${OTEL_ENVELOPE_MAX_UNITS:-${toString limits.units}}
        hour=${lib.escapeShellArg hour}
        problems=""
        # query FILE SQL: the rows in FILE, or the helper's error added to the
        # clause's problems.
        query() {
          greptimedb-sql "$2" > "$1" 2> "$tmp/sql-error" && return 0
          problems+="$(tr '\n' ' ' < "$tmp/sql-error"); "
          return 1
        }
        verdict() {
          if [ -n "$problems" ]; then
            fail "$1" "''${problems%; }"
            echo "budget:''${1// /:} FAIL ''${problems%; }" >> "$next"
          else
            ok "$1"
            echo "budget:''${1// /:} ok" >> "$next"
          fi
          problems=""
        }

        if query "$tmp/b1" "SELECT count(DISTINCT __tsid) FROM fleet.greptime_physical_table WHERE $hour"; then
          series=$(< "$tmp/b1")
          if [ "$series" -gt ${toString limits.activeSeries} ]; then problems="$series series in fleet over the last hour, above ${toString limits.activeSeries}; "; fi
        fi
        verdict "B1 active-series"

        if query "$tmp/tags" "SELECT column_name FROM information_schema.columns WHERE table_schema = 'fleet' AND table_name = 'greptime_physical_table' AND semantic_type = 'TAG' ORDER BY column_name"; then
          mapfile -t tags < <(grep -vxE '__tsid|__table_id|process_executable_name|systemd_unit_name|launchd_label' "$tmp/tags" || true)
          if [ "''${#tags[@]}" -gt 0 ]; then
            counts=$(printf 'count(DISTINCT "%s"), ' "''${tags[@]}")
            if query "$tmp/values" "SELECT ''${counts%, } FROM fleet.greptime_physical_table WHERE $hour"; then
              read -r -a values < "$tmp/values"
              for i in "''${!tags[@]}"; do
                [ "''${values[$i]}" -gt ${toString limits.labelValues} ] || continue
                tag=''${tags[$i]}
                query "$tmp/per-table" "SELECT __table_id, count(DISTINCT \"$tag\") FROM fleet.greptime_physical_table WHERE $hour GROUP BY __table_id" || continue
                awk -F '\t' '$2 > ${toString limits.labelValues}' "$tmp/per-table" > "$tmp/wide"
                [ -s "$tmp/wide" ] || continue
                query "$tmp/names" "SELECT table_id, table_name FROM information_schema.tables WHERE table_schema = 'fleet' AND table_id IN ($(cut -f 1 "$tmp/wide" | paste -s -d , -))" || continue
                problems+=$(awk -F '\t' -v tag="$tag" '
                  FILENAME == ARGV[1] { name[$1] = $2; next }
                  { printf "%s %s %s; ", ($1 in name) ? name[$1] : "table_id " $1, tag, $2 }' "$tmp/names" "$tmp/wide")
              done
            fi
          fi
        fi
        verdict "B2 label-values"

        if query "$tmp/processes" "SELECT host_name, count(DISTINCT process_executable_name) FROM fleet.process_memory_usage_bytes WHERE $hour GROUP BY host_name"; then
          problems+=$(awk -F '\t' '$2 > ${toString limits.processNames} { printf "%s process_executable_name %s; ", $1, $2 }' "$tmp/processes")
        fi
        if query "$tmp/units" "SELECT host_name, count(DISTINCT systemd_unit_name) FROM (SELECT host_name, systemd_unit_name FROM fleet.systemd_unit_state WHERE $hour UNION ALL SELECT host_name, systemd_unit_name FROM fleet.systemd_service_restarts_total WHERE $hour) AS u WHERE systemd_unit_name NOT LIKE 'observability-notify@%' GROUP BY host_name"; then
          problems+=$(awk -F '\t' -v max="$max_units" '$2 > max + 0 { printf "%s systemd_unit_name %s; ", $1, $2 }' "$tmp/units")
        fi
        if query "$tmp/launchd" "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'fleet' AND column_name = 'launchd_label'"; then
          if [ "$(< "$tmp/launchd")" = 0 ]; then
            echo "otel-envelope: B3 per-host: launchd_label table absent"
          # The constant row keeps an hour without launchd series from
          # reading as an empty answer.
          elif query "$tmp/labels" "SELECT host_name, count(DISTINCT launchd_label) FROM fleet.greptime_physical_table WHERE $hour AND launchd_label IS NOT NULL GROUP BY host_name UNION ALL SELECT '-', 0"; then
            problems+=$(awk -F '\t' '$1 != "-" && $2 > ${toString limits.launchdLabels} { printf "%s launchd_label %s; ", $1, $2 }' "$tmp/labels")
          fi
        fi
        verdict "B3 per-host"

        if query "$tmp/notifiers" "SELECT DISTINCT host_name, systemd_unit_name FROM fleet.systemd_unit_state WHERE $hour AND systemd_unit_name LIKE 'observability-notify@%'"; then
          problems+=$(awk -F '\t' '
            FILENAME == ARGV[1] { allowed[$1 "\t" $2] = 1; next }
            {
              unit = $2
              sub(/^observability-notify@/, "", unit)
              sub(/\.service\.service$/, "", unit)
              if (!(($1 "\t" unit) in allowed)) printf "%s %s; ", $1, unit
            }' ${notified} "$tmp/notifiers")
        fi
        verdict "B4 notifier-instances"

        if query "$tmp/rows" ${lib.escapeShellArg "SELECT sum(n) FROM (${devloopRows}) AS t"}; then
          rows=$(< "$tmp/rows")
          if [ "$rows" -gt ${toString limits.devloopRows} ]; then problems="$rows devloop rows in the last 24 h, above ${toString limits.devloopRows}; "; fi
        fi
        verdict "B5 devloop-rows"

        if query "$tmp/ttls" "SELECT schema_name, options FROM information_schema.schemata WHERE schema_name IN (${databaseList})"; then
          problems+=$(awk -f ${ttlProgram} ${declaredTtls} "$tmp/ttls")
        fi
        verdict "B6 ttl"
        last=$now
      else
        last=$(prev budget-run)
        while read -r key verdict message; do
          echo "$key $verdict''${message:+ $message}" >> "$next"
          clause=''${key#budget:}
          # mutant: budgetVerdictNotCarried
          if [ "$verdict" = FAIL ]; then fail "''${clause//:/ }" "$message (carried from the budget run at $(utc "$last"))"; fi
        done < <(grep '^budget:' "$state" 2> /dev/null || true)
      fi

      # B0: the budget's own heartbeat.
      if [ "$last" != absent ]; then
        since=$last
        echo "budget-run $last" >> "$next"
        what="the last budget run was at $(utc "$last")"
      else
        since=$(prev budget-since)
        [ "$since" != absent ] || since=$now
        echo "budget-since $since" >> "$next"
        what="no budget run since this state's first run at $(utc "$since")"
      fi
      # mutant: staleBudgetIgnored
      if [ $((now - since)) -gt 3900 ]; then
        fail "B0 budget-run" "$what, $(((now - since) / 60)) min ago, over 65 min"
      else
        ok "B0 budget-run"
      fi
    '';
in
{
  flake.lib.otelEnvelopeTargets =
    receivers:
    lib.concatMap (
      name:
      lib.concatMap (
        job:
        let
          # mutant: firstTargetOnly
          hostPorts = lib.concatMap (c: c.targets) job.static_configs;
        in
        map (hostPort: {
          job = if builtins.length hostPorts == 1 then job.job_name else "${job.job_name}@${hostPort}";
          url = "${job.scheme or "http"}://${hostPort}${job.metrics_path or "/metrics"}";
          credential =
            if job ? authorization.credentials_file then
              baseNameOf job.authorization.credentials_file
            else
              null;
        }) hostPorts
      ) receivers.${name}.config.scrape_configs
    ) (builtins.filter (lib.hasPrefix "prometheus") (builtins.attrNames receivers));

  flake.lib.otelEnvelope =
    pkgs:
    {
      hostName,
      telemetryUrl ? "http://127.0.0.1:8888/metrics",
      targets,
      exporters,
      ingress ? false,
      budget ? null,
    }:
    pkgs.writeShellApplication {
      name = "otel-envelope";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
      ]
      ++ lib.optional (budget != null) (
        flakeLib.greptimedbSql pkgs {
          url = budget.storeUrl;
          user = "regulator";
        }
      );
      text = ''
        # The collector of ${hostName}.
        telemetry_url=${lib.escapeShellArg telemetryUrl}
        ingress=${if ingress then "1" else "0"}
        targets=${
          lib.escapeShellArg (
            lib.concatMapStrings (
              t: "${t.job} ${t.url} ${if t.credential or null == null then "-" else t.credential}\n"
            ) targets
          )
        }

        : "''${STATE_DIRECTORY:?}"
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        state="$STATE_DIRECTORY/state"
        next="$STATE_DIRECTORY/state.next"
        : > "$next"
        # A first run, with no state file, records the baseline and judges C1
        # to C3 only, so a host whose counters were already non-zero before the
        # envelope existed does not fail its first run.
        baseline=0
        [ -e "$state" ] || baseline=1
        failed=0${lib.optionalString (budget != null) "\n${budgetClock}"}

        ok() { echo "otel-envelope: $1: ok"; }
        fail() {
          echo "otel-envelope: $1: FAIL $2"
          failed=1
        }
        prev() {
          if [ -e "$state" ]; then
            awk -v k="$1" '$1 == k { v = $2; f = 1 } END { print f ? v : "absent" }' "$state"
          else
            echo absent
          fi
        }
        # A series' key: its name and labels without the per-start identity.
        normalise() { sed -E 's/(service_instance_id|service_name|service_version|otel_scope_[a-z_]+)="[^"]*",?//g; s/,}/}/; s/\{\}//'; }

        # C1: a run without telemetry fails only if the previous run had none.
        if curl -fsS --max-time 10 "$telemetry_url" -o "$tmp/now" 2> "$tmp/c1"; then
          echo "telemetry 0" >> "$next"
          ok "C1 telemetry"
        else
          echo "telemetry 1" >> "$next"
          : > "$tmp/now"
          # One missed read keeps the previous counters, so the next run does
          # not see their whole cumulative value as an increase.
          # mutant: noCarryForward
          { grep -E '^otelcol_' "$state" 2> /dev/null || true; } >> "$next"
          if [ "$(prev telemetry)" = 1 ]; then
            fail "C1 telemetry" "no answer from $telemetry_url on this run and the previous one: $(tr '\n' ' ' < "$tmp/c1")"
          else
            ok "C1 telemetry"
          fi
        fi

        # C2: each declared target, down on this run and the previous one.
        down=""
        while read -r job url credential; do
          [ -n "$job" ] || continue
          if [ "$credential" = - ]; then
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
          else
            code=$(printf 'header = "Authorization: Bearer %s"\n' "$(cat "$CREDENTIALS_DIRECTORY/$credential")" \
              | curl -s -o /dev/null -w '%{http_code}' --max-time 10 --config - "$url" || true)
          fi
          if [ "$code" = 200 ]; then
            echo "down:$job 0" >> "$next"
          else
            echo "down:$job 1" >> "$next"
            # mutant: targetDownOneRun
            if [ "$(prev "down:$job")" = 1 ]; then down="$down $job"; fi
          fi
        done <<< "$targets"
        if [ -n "$down" ]; then
          fail "C2 targets" "''${down# } down on this run and the previous one"
        else
          ok "C2 targets"
        fi

        # C3: each configured exporter's two queue series, then size against
        # capacity per exporter and data type. The exporter names come from
        # the configuration, not the telemetry, so a renamed series is absent
        # rather than unseen; telemetry that did not answer is C1's.
        full=$(awk -v exporters=${lib.escapeShellArg (lib.concatStringsSep " " exporters)} '
          function label(s, k) {
            return match(s, "[{,]" k "=\"[^\"]*\"") ? substr(s, RSTART + length(k) + 3, RLENGTH - length(k) - 4) : ""
          }
          /^otelcol_exporter_queue_(size|capacity)\{/ {
            exporter = label($1, "exporter")
            id = exporter "/" label($1, "data_type")
            if ($1 ~ /^otelcol_exporter_queue_size\{/) {
              size[id] = $2
              sized[exporter] = 1
            } else {
              capacity[id] = $2
              bounded[exporter] = 1
            }
          }
          END {
            # mutant: queueSeriesOptional
            n = NR ? split(exporters, configured, " ") : 0
            for (i = 1; i <= n; i++) {
              if (!(configured[i] in sized)) printf "%s otelcol_exporter_queue_size absent; ", configured[i]
              if (!(configured[i] in bounded)) printf "%s otelcol_exporter_queue_capacity absent; ", configured[i]
            }
            for (id in size) {
              if (!(id in capacity)) printf "%s capacity absent; ", id
              else if (size[id] * 10 >= capacity[id] * 9) printf "%s %s of %s; ", id, size[id], capacity[id]
            }
          }' "$tmp/now")
        if [ -n "$full" ]; then fail "C3 queue" "$full"; else ok "C3 queue"; fi

        # C4: an absent counter reads 0; a value below the recorded one is a
        # restart, and the current value is the increase.
        loss_re='^otelcol_exporter_send_failed_|^otelcol_receiver_refused_'
        [ "$ingress" = 1 ] || loss_re="$loss_re|^otelcol_exporter_enqueue_failed_"
        : > "$tmp/loss"
        if [ -s "$tmp/now" ]; then
          # The braces keep an empty match from failing the run under pipefail.
          # mutant: missingCounterFails
          { grep -E "$loss_re" "$tmp/now" || true; } | while read -r series value; do
            # mutant: meshRefusalIsLoss
            if [ "$ingress" = 1 ] && [[ $series == otelcol_receiver_refused_*'receiver="otlp/mesh"'* ]]; then continue; fi
            key=$(printf '%s' "$series" | normalise)
            was=$(prev "$key")
            echo "$key $value" >> "$next"
            [ "$baseline" = 0 ] || continue
            [ "$was" != absent ] || was=0
            # mutant: resetNegative
            inc=$(awk -v n="$value" -v p="$was" 'BEGIN { print (n < p) ? n : n - p }')
            if awk -v i="$inc" 'BEGIN { exit !(i > 0) }'; then echo "$key +$inc" >> "$tmp/loss"; fi
          done
        fi
        if [ -s "$tmp/loss" ]; then fail "C4 loss" "$(tr '\n' ' ' < "$tmp/loss")"; else ok "C4 loss"; fi
        ${lib.optionalString (budget != null) (budgetClauses pkgs budget)}

        mv "$next" "$state"
        exit "$failed"
      '';
    };
}
