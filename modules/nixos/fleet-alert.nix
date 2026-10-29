# Fleet alert evaluator (ADR-009 Decision items 1-8, 10, 14, 17; R9.1, R9.5;
# design D11-D16, D18; tasks.md 4.3, 4.4).
#
# fleet-alert.timer starts fleet-alert.service every minute. The evaluator
# reads its configuration from the JSON at FLEET_ALERT_CONFIG and queries
# the store one query at a time as `regulator`, each rule in its own
# `database` and `language` (stand-up-devloop-collection design D2): PromQL
# to /v1/prometheus/api/v1/query with x-greptime-db-name, SQL as POST
# /v1/sql?db=<database> with the form field sql (password from
# $CREDENTIALS_DIRECTORY/regulator-password, passed to curl on stdin, as
# modules/lib/greptimedb-envelope.nix does), each with --max-time
# queryTimeoutSec. A failed query, or the passing of queryDeadlineSec, ends
# querying of that database for the run while other databases' queries
# continue (review F7); the failed databases reach transition.jq as
# storeErrors, which freezes the instances on them and, after 3 min, raises
# one StoreQueryFailing per database. It reads the notifier's failed.log,
# applies transition.jq's pure transition to state.json, writes the state,
# posts the heartbeat at priority min, then posts each alert through
# ntfy-send, which reads the alerter token from NTFY_TOKEN_FILE, and records
# each successful post with mark_posted, writing the state through a
# temporary file and a rename. No post starts after postDeadlineSec, and a
# failed heartbeat or post fails the run, so the notifier reports it and the
# next run retries what is unposted. A run with a store error that posts
# its heartbeat exits 0.
#
# WeeklyPipelineTest's window is evaluated under TZ=<window zone> with the
# tz database at TZDIR, for that rule only; the host's time zone is not
# used. FLEET_ALERT_NOW, set only by checks.x86_64-linux.fleet-alert,
# replaces the clock.
#
# Site-neutral and free of clan vars, as modules/nixos/greptimedb.nix is:
# the host sets tokenFile and regulatorPasswordFile. The rules come from
# fleet-alert/rules.nix with the host's services.observability-notify.units.
# The check runs flake.lib.fleetAlertEvaluator, the same function, against a
# fixture server with a recording ntfy-send. R9.5 is an assertion below:
# fleet-alert.service runs with MemoryMax = 64M, and a run's worst case,
# max(query deadline + heartbeat, post deadline) + one post + the notifier's
# ExecStartPost post, ends before TimeoutStartSec, which ends before the
# timer's next run.
# The kill order (evaluator 900, store 500, collector 300, this unit 0) is
# asserted by magnetite's configuration, which holds all four.
#
# With services.fleet-alert.deadman.enable, fleet-deadman.timer runs
# fleet-deadman.service every 5 min on the ntfy host. Each run first
# publishes anonymously to the heartbeat topic on ntfy's own listener and
# fails unless ntfy answers 403 (R9.4). It then polls the topic's last
# 10 min and applies transition.jq to the single rule AlertEvaluatorSilent,
# keeping /var/lib/fleet-deadman/state.json. It posts through ntfy-send
# with the alerter credential. The host lists fleet-deadman in
# services.observability-notify.units, so a failed run reaches fleet-alerts
# through the notifier. Assertions below hold R9.4's premise on that host:
# ntfyUrl is ntfy's listener, and ntfy's auth-access refuses an anonymous
# write to both fleet topics, lets alerter write them, and decides no
# host-named topic. flake.lib.fleetAlertDeadmanConfig renders the dead-man's
# configuration, from the option defaults when the check calls it.
{ config, lib, ... }:
let
  flakeLib = config.flake.lib;
  transitionJq = ./fleet-alert/transition.jq;
  jqLib =
    pkgs: transition:
    pkgs.linkFarm "fleet-alert-jq" [
      {
        name = "transition.jq";
        path = transition;
      }
    ];

  fleetAlertEvaluator =
    pkgs:
    {
      ntfySend,
      transition ? transitionJq,
    }:
    pkgs.writeShellApplication {
      name = "fleet-alert";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      # `$name` inside the jq programs is a jq variable, not a shell expansion.
      excludeShellChecks = [ "SC2016" ];
      text = ''
        config=''${FLEET_ALERT_CONFIG:?FLEET_ALERT_CONFIG is unset}
        credentials=''${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY is unset}
        now=''${FLEET_ALERT_NOW:-$(date +%s)}
        export TZDIR=${pkgs.tzdata}/share/zoneinfo
        jqlib=${jqLib pkgs transition}

        setting() {
          jq -er --arg key "$1" '.[$key]' "$config"
        }
        store_url=$(setting storeUrl)
        # system_memory_usage_bytes, which `reporting` reads, is queried in
        # RuleSignalMissing's database; the run fails without exactly one.
        reporting_database=$(jq -er '[.rules[] | select(.alert == "RuleSignalMissing") | .database]
          | if length == 1 then .[0] else error("the rules must list RuleSignalMissing exactly once") end' "$config")
        user=$(setting user)
        query_timeout=$(setting queryTimeoutSec)
        query_deadline=$(setting queryDeadlineSec)
        post_deadline=$(setting postDeadlineSec)
        topic=$(setting topic)
        heartbeat_topic=$(setting heartbeatTopic)
        state_file=$(setting stateFile)
        failed_log=$(setting failedLog)

        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        : > "$work/presence.jsonl"
        : > "$work/results.jsonl"
        : > "$work/windows.jsonl"
        : > "$work/attribution.jsonl"

        # One query of a rule's language in a rule's database: promql as an
        # instant query with x-greptime-db-name, sql as POST
        # /v1/sql?db=<database> with the form field sql. The answer lands in
        # $work/body as a Prometheus vector: an SQL answer must be 200 with
        # exactly one output holding records with a `value` column, and each
        # row becomes one result with that column as its value and every
        # other column as a label (GreptimeTeam/greptimedb@v1.2.1
        # src/servers/src/http.rs:291-338, 395-400). Fails on a transport
        # error, a timeout, any other status or body, or when the query
        # deadline has passed; ask_store below turns a failure into the
        # failure of the query's database for the run.
        query() {
          local language=$1 database=$2 expr=$3
          local remaining status
          local -a request
          remaining=$((query_deadline - SECONDS))
          if [ "$remaining" -le 0 ]; then
            echo "fleet-alert: query deadline of ''${query_deadline}s reached" >&2
            return 1
          fi
          if [ "$remaining" -gt "$query_timeout" ]; then
            remaining=$query_timeout
          fi
          case "$language" in
            promql)
              request=(--header "x-greptime-db-name: $database" --get --data-urlencode "query=$expr"
                "$store_url/v1/prometheus/api/v1/query")
              ;;
            sql)
              request=(--url-query "db=$database" --data-urlencode "sql=$expr" "$store_url/v1/sql")
              ;;
            *)
              printf 'fleet-alert: unknown query language %s for: %s\n' "$language" "$expr" >&2
              return 1
              ;;
          esac
          if ! status=$(printf 'user = "%s:%s"\n' "$user" "$(< "$credentials/regulator-password")" \
            | curl --config - --silent --show-error --max-time "$remaining" \
                --output "$work/answer" --write-out '%{http_code}' "''${request[@]}"); then
            printf 'fleet-alert: query failed: %s\n' "$expr" >&2
            return 1
          fi
          if [ "$status" != 200 ]; then
            printf 'fleet-alert: HTTP %s for query: %s\n' "$status" "$expr" >&2
            return 1
          fi
          if [ "$language" = sql ]; then
            if ! jq -e '(.output | length) == 1 and (.output[0] | has("records"))
                and any(.output[0].records.schema.column_schemas[]; .name == "value")' "$work/answer" > /dev/null; then
              printf 'fleet-alert: no single records answer with a value column for query: %s\n' "$expr" >&2
              return 1
            fi
            jq '.output[0].records as $records
              | [$records.schema.column_schemas[].name] as $columns
              | {status: "success", data: {resultType: "vector", result: [$records.rows[]
                  | [$columns, .] | transpose | map({key: .[0], value: .[1]}) | from_entries
                  | {metric: (del(.value) | map_values(tostring)), value: [null, (.value | tostring)]}]}}' \
              "$work/answer" > "$work/body"
          else
            mv -f "$work/answer" "$work/body"
          fi
          if ! jq -e '.status == "success" and .data.resultType == "vector"' "$work/body" > /dev/null; then
            printf 'fleet-alert: HTTP %s for query: %s\n' "$status" "$expr" >&2
            return 1
          fi
        }

        # Databases whose queries failed this run, each followed by a space
        # (review F7); names come from the rule table and hold no space.
        failed_databases=""

        # ask_store LANGUAGE DATABASE EXPR: query EXPR unless DATABASE has
        # already failed this run. A failed query marks DATABASE failed, so
        # its remaining rule, presence and attribution queries are skipped
        # while other databases' queries continue; once the query deadline
        # has passed every query fails, so a database not reached by then
        # counts as failed.
        ask_store() {
          if [[ " $failed_databases" == *" $2 "* ]]; then
            return 1
          fi
          if ! query "$1" "$2" "$3"; then
            failed_databases+="$2 "
            printf 'fleet-alert: the store did not answer queries on %s; its instances are frozen this run\n' "$2" >&2
            return 1
          fi
        }

        # Presence selectors, each in the database of the rule naming it, and
        # system_memory_usage_bytes, what `reporting` reads, in
        # RuleSignalMissing's; then rule expressions, each in its rule's
        # database and language; then attribution, in the attributing rule's
        # database, for the hosts in the results of rules that name
        # attribution queries. A query whose database has failed is skipped
        # and records nothing.
        collect() {
          local presence selector database language rule alert expr window inside host attr name label attr_query
          while IFS= read -r presence; do
            selector=$(jq -r .selector <<< "$presence")
            database=$(jq -r .database <<< "$presence")
            if ask_store promql "$database" "count by (host_name) ($selector)"; then
              jq -c --arg selector "$selector" \
                '{selector: $selector, hosts: [.data.result[].metric.host_name // empty]}' \
                "$work/body" >> "$work/presence.jsonl"
            fi
          done < <(jq -c --arg reporting "$reporting_database" \
            '[{selector: "system_memory_usage_bytes", database: $reporting}]
              + [.rules[] | .database as $database | .presence[]? | {selector, database: $database}]
              | unique | .[]' "$config")

          while IFS= read -r rule; do
            alert=$(jq -r .alert <<< "$rule")
            expr=$(jq -r .expr <<< "$rule")
            database=$(jq -r .database <<< "$rule")
            language=$(jq -r .language <<< "$rule")
            window=$(jq -c '.window // empty' <<< "$rule")
            if [ -n "$window" ]; then
              inside=$(TZ=$(jq -r .zone <<< "$window") jq -n -L "$jqlib" \
                --argjson window "$window" --argjson now "$now" \
                'include "transition"; in_window($window; $now)')
              jq -nc --arg alert "$alert" --argjson inside "$inside" \
                '{alert: $alert, inside: $inside}' >> "$work/windows.jsonl"
              if [ "$inside" != true ]; then
                continue
              fi
            fi
            if ask_store "$language" "$database" "$expr"; then
              jq -c --arg alert "$alert" \
                '{alert: $alert, result: [.data.result[] | {labels: .metric, value: .value[1]}]}' \
                "$work/body" >> "$work/results.jsonl"
            fi
          done < <(jq -c '.rules[] | select(has("expr"))' "$config")

          while IFS= read -r host; do
            if ! [[ "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
              printf 'fleet-alert: no attribution for host label %q\n' "$host" >&2
              continue
            fi
            while IFS= read -r attr; do
              name=$(jq -r .name <<< "$attr")
              label=$(jq -r '.label // ""' <<< "$attr")
              attr_query=$(jq -r .query <<< "$attr")
              database=$(jq -r .database <<< "$attr")
              if ask_store promql "$database" "''${attr_query//<host>/$host}"; then
                jq -c --arg host "$host" --arg name "$name" --arg label "$label" \
                  '{host: $host, name: $name, label: $label, result: .data.result}' \
                  "$work/body" >> "$work/attribution.jsonl"
              fi
            done < <(jq -c '[.rules[] | .database as $database | .attribution[]? | . + {database: $database}] | unique | .[]' "$config")
          done < <(jq -r --slurpfile results "$work/results.jsonl" '
            [.rules[] | select((.attribution // []) | length > 0) | .alert] as $attributed
            | [$results[] | select(.alert as $a | any($attributed[]; . == $a)) | .result[].labels.host_name // empty]
            | unique | .[]' "$config")
        }

        # As before review F7, a command other than a query failing inside
        # collect does not end the run; a failed query marks its database.
        collect || true
        store_errors=$(jq -cn --arg failed "$failed_databases" '$failed | split(" ") | map(select(. != "")) | unique')

        # A missing log is an empty one; an unreadable one fails the run, so
        # a permissions fault cannot undercount the notifier's posts (R9.1).
        if [ -e "$failed_log" ]; then
          if [ ! -r "$failed_log" ]; then
            echo "fleet-alert: $failed_log exists but cannot be read" >&2
            exit 1
          fi
          jq -R -s '[split("\n")[] | select(test("^[0-9]+ [^ ]+ [^ ]+$")) | split(" ")
            | {at: (.[0] | tonumber), unit: .[1], host: .[2]}]' "$failed_log" > "$work/failed.json"
        else
          echo '[]' > "$work/failed.json"
        fi

        jq -n --argjson storeErrors "$store_errors" \
          --slurpfile presence "$work/presence.jsonl" \
          --slurpfile results "$work/results.jsonl" \
          --slurpfile windows "$work/windows.jsonl" \
          --slurpfile attribution "$work/attribution.jsonl" \
          --slurpfile failed "$work/failed.json" '
          def mb: (tonumber / 1000000 | floor | tostring) + " MB";
          {
            storeErrors: $storeErrors,
            presence: ($presence | map({key: .selector, value: .hosts}) | from_entries),
            reporting: ([$presence[] | select(.selector == "system_memory_usage_bytes") | .hosts[]] | unique),
            results: ($results | map({key: .alert, value: .result}) | from_entries),
            windows: ($windows | map({key: .alert, value: .inside}) | from_entries),
            attribution: ($attribution | group_by(.host) | map({
              key: .[0].host,
              value: (map(.label as $l | "\(.name): " + (.result
                | map((if $l == "" then "" else (.metric[$l] // "?") + " " end) + (.value[1] | mb))
                | join(", "))) | join("\n"))
            }) | from_entries),
            failedLog: $failed[0]
          }' > "$work/observations.json"

        if [ -s "$state_file" ]; then
          cp "$state_file" "$work/state.json"
        else
          echo null > "$work/state.json"
        fi
        jq -n -L "$jqlib" --slurpfile state "$work/state.json" \
          --slurpfile observations "$work/observations.json" \
          --slurpfile config "$config" --argjson now "$now" --arg topic "$topic" '
          include "transition";
          $state[0] | transition($observations[0]; $now; $config[0].rules)
          | .posts |= map({topic: $topic} + .)' > "$work/result.json"

        save_state() {
          cat > "$state_file.tmp"
          mv -f "$state_file.tmp" "$state_file"
        }
        jq .state "$work/result.json" | save_state

        if ! ${ntfySend} "ok $now" "$heartbeat_topic" -H "Priority: min"; then
          echo "fleet-alert: heartbeat post failed" >&2
          exit 1
        fi

        while IFS= read -r post; do
          if [ "$SECONDS" -ge "$post_deadline" ]; then
            echo "fleet-alert: post deadline of ''${post_deadline}s reached; unposted transitions stay pending" >&2
            exit 1
          fi
          if ! ${ntfySend} "$(jq -r .message <<< "$post")" "$(jq -r .topic <<< "$post")" \
            -H "Title: $(jq -r .title <<< "$post")" -H "Priority: $(jq -r .priority <<< "$post")"; then
            printf 'fleet-alert: post failed: %s\n' "$(jq -r .title <<< "$post")" >&2
            exit 1
          fi
          jq -L "$jqlib" --argjson post "$post" 'include "transition"; mark_posted($post)' "$state_file" | save_state
        done < <(jq -c '.posts[]' "$work/result.json")

        if [ "$store_errors" != '[]' ]; then
          printf 'fleet-alert: the store did not answer queries on %s; the instances on them are frozen\n' \
            "$(jq -r 'join(", ")' <<< "$store_errors")" >&2
        fi
      '';
    };

  # AlertEvaluatorSilent (ADR-009 rule table; design D12): raised on the
  # dead-man's host when no heartbeat reached ntfy in the poll window. The
  # poll is its query, so it has no `expr`; transition.jq evaluates it from
  # the results entry the dead-man builds, and the single-rule list enables
  # neither StoreQueryFailing nor RuleSignalMissing.
  alertEvaluatorSilent = {
    alert = "AlertEvaluatorSilent";
    for = 0;
    severity = "critical";
    annotations.summary = "No fleet-heartbeat message reached ntfy in 10 min: the evaluator, its host or its path to ntfy is down, and no other alert can be sent.";
    presence = [ ];
    attribution = [ ];
  };

  # The defaults of the options below, and the dead-man's configuration
  # rendered from them, so checks.x86_64-linux.fleet-alert rehearses the
  # dead-man without evaluating a host (S3 review F3).
  defaults = {
    topic = "fleet-alerts";
    heartbeatTopic = "fleet-heartbeat";
    ntfyUrl = "http://[::1]:2586";
    evaluatorHost = "magnetite";
  };
  fleetAlertDeadmanConfig =
    {
      ntfyUrl ? defaults.ntfyUrl,
      topic ? defaults.topic,
      evaluatorHost ? defaults.evaluatorHost,
      heartbeatTopic ? defaults.heartbeatTopic,
    }:
    {
      inherit
        ntfyUrl
        topic
        evaluatorHost
        heartbeatTopic
        ;
      window = "10m";
      stateFile = "/var/lib/fleet-deadman/state.json";
      rules = [ alertEvaluatorSilent ];
    };

  # ntfy 2.28.0's access decision (world assumption A38;
  # user/manager.go:702-735, user/manager_sqlite.go:90-96): one row decides,
  # rows for the user or `*` whose pattern matches, ordered user DESC,
  # pattern length DESC, write DESC; null when no row matches, which leaves
  # auth-default-access (cmd/serve.go:53).
  ntfyDecision =
    access: user: topic:
    let
      rows = lib.concatMap (
        entry:
        let
          parts = lib.splitString ":" entry;
          pattern = builtins.elemAt parts 1;
        in
        lib.optional
          (
            builtins.length parts == 3
            && builtins.elem (builtins.head parts) (
              lib.unique [
                user
                "*"
              ]
            )
            && builtins.match (builtins.replaceStrings [ "*" ] [ ".*" ] pattern) topic != null
          )
          {
            user = builtins.head parts;
            length = builtins.stringLength pattern;
            permission = builtins.elemAt parts 2;
          }
      ) access;
      writes =
        row:
        builtins.elem row.permission [
          "rw"
          "read-write"
          "wo"
          "write-only"
          "write"
        ];
      ordered = lib.sort (
        a: b:
        if a.user != b.user then
          a.user > b.user
        else if a.length != b.length then
          a.length > b.length
        else
          writes a && !writes b
      ) rows;
    in
    if ordered == [ ] then null else (builtins.head ordered).permission;

  # The dead-man (design D12, "Failure path"; ADR-009 item 9, R9.4), a
  # function so checks.x86_64-linux.fleet-alert runs it against a loopback
  # ntfy stand-in and a recording ntfy-send. Configuration comes from the
  # JSON file at FLEET_DEADMAN_CONFIG, the token from NTFY_TOKEN_FILE (the
  # unit sets it to its alerter-token credential), and time from
  # FLEET_ALERT_NOW when set, which only the check does.
  fleetAlertDeadman =
    pkgs:
    {
      ntfySend,
      transition ? transitionJq,
    }:
    pkgs.writeShellApplication {
      name = "fleet-deadman";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      text = ''
        config="''${FLEET_DEADMAN_CONFIG:?}"
        : "''${NTFY_TOKEN_FILE:?}"
        ntfy_url=$(jq -er .ntfyUrl "$config")
        heartbeat_topic=$(jq -er .heartbeatTopic "$config")
        window=$(jq -er .window "$config")
        topic=$(jq -er .topic "$config")
        state_file=$(jq -er .stateFile "$config")
        now="''${FLEET_ALERT_NOW:-$(date +%s)}"
        jqlib=${jqLib pkgs transition}

        # R9.4 (ADR-009): an anonymous publish to the heartbeat topic must be
        # refused with 403 (binwiederhier/ntfy@v2.28.0
        # server/server_middleware.go:153-171, server/errors.go:156). Any other
        # answer, or none (000), fails the unit before the poll, so OnFailure's
        # notifier reports it and an accepted probe never counts as a heartbeat.
        probe=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
          -d "fleet-deadman anonymous-publish probe" "$ntfy_url/$heartbeat_topic" || true)
        if [ "$probe" != 403 ]; then
          echo "fleet-deadman: R9.4: anonymous publish to $heartbeat_topic answered HTTP $probe, expected 403" >&2
          exit 1
        fi
        echo "fleet-deadman: R9.4 probe refused with HTTP 403"

        if ! poll=$(curl -sf --max-time 10 "$ntfy_url/$heartbeat_topic/json?poll=1&since=$window"); then
          echo "fleet-deadman: poll of $heartbeat_topic failed" >&2
          exit 1
        fi
        heartbeats=$(jq -s '[.[] | select(.event == "message")] | length' <<< "$poll")
        echo "fleet-deadman: $heartbeats heartbeat(s) on $heartbeat_topic in the last $window"

        # One instance of the single rule while the window is empty, labelled
        # with the evaluator's host, which counts as reporting so the
        # transition's host freeze never holds it.
        observations=$(jq -c --argjson heartbeats "$heartbeats" '{
          storeErrors: [],
          results: {(.rules[0].alert): (if $heartbeats == 0 then [{labels: {host_name: .evaluatorHost}, value: "1"}] else [] end)},
          presence: {},
          reporting: [.evaluatorHost],
          failedLog: []
        }' "$config")
        rules=$(jq -c .rules "$config")
        state='{}'
        if [ -s "$state_file" ]; then
          state=$(< "$state_file")
        fi
        result=$(jq -n -c -L "$jqlib" --argjson state "$state" --argjson observations "$observations" \
          --argjson now "$now" --argjson rules "$rules" --arg topic "$topic" \
          'include "transition"; $state | transition($observations; $now; $rules) | .posts |= map({topic: $topic} + .)')

        write_state() {
          printf '%s\n' "$state" > "$state_file.tmp"
          mv "$state_file.tmp" "$state_file"
        }
        state=$(jq -c .state <<< "$result")
        write_state

        # After each successful post the state records it (mark_posted); a
        # failed post fails the run and stays pending for the next one
        # (design D15).
        while IFS= read -r post; do
          [ -n "$post" ] || continue
          ${ntfySend} "$(jq -r .message <<< "$post")" "$(jq -r .topic <<< "$post")" \
            -H "Title: $(jq -r .title <<< "$post")" \
            -H "Priority: $(jq -r .priority <<< "$post")"
          state=$(jq -c -L "$jqlib" --argjson post "$post" 'include "transition"; mark_posted($post)' <<< "$state")
          write_state
        done <<< "$(jq -c '.posts[]' <<< "$result")"
      '';
    };
in
{
  flake.lib = {
    inherit fleetAlertEvaluator fleetAlertDeadman fleetAlertDeadmanConfig;
  };

  flake.modules.nixos.fleet-alert =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.fleet-alert;

      # greptimedb-envelope's set (modules/nixos/greptimedb.nix:305-326),
      # less its journal group.
      hardening = {
        DynamicUser = true;
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };

      rendered = flakeLib.fleetAlertRules { inherit lib; };
      # The run's time budget (design D13), read by R9.5's relation below.
      deadlines = {
        queryTimeoutSec = 10;
        queryDeadlineSec = 30;
        postDeadlineSec = 35;
      };
      # ntfy-send bounds each post, the heartbeat and the notifier hook's
      # RESOLVED alike, with curl's -m.
      postTimeoutSec = lib.foldl lib.max 0 (
        map (m: lib.toInt (builtins.head m)) (
          builtins.filter builtins.isList (
            builtins.split "-m ([0-9]+)" (builtins.readFile ../../pkgs/by-name/ntfy-send/ntfy-send.sh)
          )
        )
      );
      seconds =
        s:
        let
          m = builtins.match "([0-9]+)s" s;
        in
        if m == null then null else lib.toInt (builtins.head m);
      timeoutStartSec = seconds (unit.TimeoutStartSec or "");
      periodSec = { minutely = 60; }.${config.systemd.timers.fleet-alert.timerConfig.OnCalendar} or null;
      # Worst case of one run: posts start before postDeadlineSec, which
      # may come after the query phase and the heartbeat; the last post and
      # the notifier's ExecStartPost hook each take up to postTimeoutSec.
      worstRunSec =
        lib.max (deadlines.queryDeadlineSec + postTimeoutSec) deadlines.postDeadlineSec
        + 2 * postTimeoutSec;
      evaluatorConfig = pkgs.writeText "fleet-alert-config.json" (
        builtins.toJSON (
          deadlines
          // {
            inherit (cfg.evaluator) storeUrl topic heartbeatTopic;
            user = "regulator";
            stateFile = "/var/lib/fleet-alert/state.json";
            failedLog = "/var/lib/observability-notify/failed.log";
            rules = builtins.fromJSON rendered.json;
          }
        )
      );
      evaluator = fleetAlertEvaluator pkgs { ntfySend = lib.getExe pkgs.ntfy-send; };
      unit = config.systemd.services.fleet-alert.serviceConfig;

      deadman = fleetAlertDeadman pkgs { ntfySend = lib.getExe pkgs.ntfy-send; };
      deadmanConfig = pkgs.writeText "fleet-deadman.json" (
        builtins.toJSON (fleetAlertDeadmanConfig {
          inherit (cfg.deadman) ntfyUrl topic evaluatorHost;
          # The option the evaluator posts its heartbeat to; declared
          # whether or not this host runs the evaluator.
          heartbeatTopic = cfg.evaluator.heartbeatTopic;
        })
      );

      # The dead-man's ntfy, on its own host: the access entries R9.4's
      # probe presumes (E9.4), and the listener ntfyUrl names.
      ntfySettings = config.services.ntfy-sh.settings;
      access = ntfySettings.auth-access or [ ];
      anonymous = ntfyDecision access "*";
      alerter = ntfyDecision access "alerter";
      fleetTopics = [
        cfg.evaluator.heartbeatTopic
        cfg.deadman.topic
      ];
      hostTopics = [
        config.networking.hostName
        cfg.deadman.evaluatorHost
      ];
      readOnly =
        p:
        builtins.elem p [
          "ro"
          "read-only"
          "read"
        ];
      readWrite =
        p:
        builtins.elem p [
          "rw"
          "read-write"
        ];
    in
    {
      options.services.fleet-alert.evaluator = {
        enable = lib.mkEnableOption "the fleet alert evaluator (ADR-009)";
        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path of the ntfy `alerter` token, loaded as the credential `alerter-token`.";
        };
        regulatorPasswordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path of the store's `regulator` password, loaded as the credential `regulator-password`.";
        };
        storeUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:4000";
          description = "Base URL of the store's HTTP API.";
        };
        topic = lib.mkOption {
          type = lib.types.str;
          default = defaults.topic;
          description = "ntfy topic for FIRING and RESOLVED posts.";
        };
        heartbeatTopic = lib.mkOption {
          type = lib.types.str;
          default = defaults.heartbeatTopic;
          description = "ntfy topic for the heartbeat each completed run posts at priority min.";
        };
      };

      options.services.fleet-alert.deadman = {
        enable = lib.mkEnableOption "the fleet alert dead-man (fleet-deadman.timer), which probes ntfy's access entries and raises AlertEvaluatorSilent when the heartbeat stops";
        tokenFile = lib.mkOption {
          type = lib.types.str;
          description = "Path of the alerter token, loaded through LoadCredential as alerter-token.";
        };
        ntfyUrl = lib.mkOption {
          type = lib.types.str;
          default = defaults.ntfyUrl;
          description = "ntfy's own listener, reached directly so the anonymous probe and the poll bypass the proxy.";
        };
        topic = lib.mkOption {
          type = lib.types.str;
          default = defaults.topic;
          description = "Topic the dead-man posts AlertEvaluatorSilent to.";
        };
        evaluatorHost = lib.mkOption {
          type = lib.types.str;
          default = defaults.evaluatorHost;
          description = "host_name the AlertEvaluatorSilent instance carries: the host whose evaluator posts the heartbeat.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.evaluator.enable {
          assertions = [
            {
              assertion = cfg.evaluator.tokenFile != null && cfg.evaluator.regulatorPasswordFile != null;
              message = "fleet-alert: services.fleet-alert.evaluator.tokenFile and regulatorPasswordFile must be set when the evaluator is enabled.";
            }
            # R9.5 (ADR-009 E9.5): the memory bound, and a run that ends
            # before its timeout, which ends before the next run (design D13).
            {
              assertion = (unit.MemoryMax or null) == "64M";
              message = "fleet-alert: R9.5 requires fleet-alert.service to run with MemoryMax = \"64M\" (ADR-009 E9.5); it has MemoryMax = ${
                builtins.toJSON (unit.MemoryMax or null)
              }.";
            }
            {
              assertion =
                postTimeoutSec > 0
                && timeoutStartSec != null
                && periodSec != null
                && worstRunSec < timeoutStartSec
                && timeoutStartSec < periodSec;
              message = "fleet-alert: R9.5 requires max(queryDeadlineSec + post timeout, postDeadlineSec) + 2 post timeouts < TimeoutStartSec < timer period; it has max(${toString deadlines.queryDeadlineSec} + ${toString postTimeoutSec}, ${toString deadlines.postDeadlineSec}) + 2 * ${toString postTimeoutSec} = ${toString worstRunSec}, TimeoutStartSec = ${
                builtins.toJSON (unit.TimeoutStartSec or null)
              }, period = ${builtins.toJSON periodSec} s.";
            }
          ];

          systemd.services.fleet-alert = {
            description = "Fleet alert evaluator (ADR-009)";
            # Ordered, never pulled in: a store the operator stopped must
            # surface as StoreQueryFailing (design D12).
            after = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "zerotierone.service"
            ];
            environment = {
              FLEET_ALERT_CONFIG = "${evaluatorConfig}";
              NTFY_TOKEN_FILE = "%d/alerter-token";
            };
            serviceConfig = hardening // {
              Type = "oneshot";
              ExecStart = lib.getExe evaluator;
              StateDirectory = "fleet-alert";
              LoadCredential =
                lib.optional (
                  cfg.evaluator.regulatorPasswordFile != null
                ) "regulator-password:${cfg.evaluator.regulatorPasswordFile}"
                ++ lib.optional (cfg.evaluator.tokenFile != null) "alerter-token:${cfg.evaluator.tokenFile}";
              # Last of the four the kernel takes on magnetite: the unit that
              # reports an OOM kill must outlive it (design D12).
              OOMScoreAdjust = 0;
              MemoryMax = "64M";
              TimeoutStartSec = "50s";
            };
          };

          systemd.timers.fleet-alert = {
            description = "Run the fleet alert evaluator every minute";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "minutely";
              AccuracySec = "1s";
            };
          };
        })

        (lib.mkIf cfg.deadman.enable {
          # R9.4's premise on the dead-man's own host (E9.4): its probe and
          # poll reach ntfy's listener, which refuses an anonymous write to
          # either fleet topic, lets alerter write both, and leaves
          # host-named topics to auth-default-access.
          assertions = [
            {
              assertion = cfg.deadman.ntfyUrl == "http://${ntfySettings.listen-http or ""}";
              message = "fleet-alert: deadman.ntfyUrl (${cfg.deadman.ntfyUrl}) is not ntfy's listener on this host, http://${
                toString (ntfySettings.listen-http or "<unset>")
              }.";
            }
            {
              assertion = lib.all (t: anonymous t != null && readOnly (anonymous t)) fleetTopics;
              message = "fleet-alert: ntfy's auth-access ${builtins.toJSON access} does not refuse an anonymous write to ${builtins.toJSON fleetTopics}.";
            }
            {
              assertion = lib.all (t: alerter t != null && readWrite (alerter t)) fleetTopics;
              message = "fleet-alert: ntfy's auth-access ${builtins.toJSON access} does not let alerter write ${builtins.toJSON fleetTopics}.";
            }
            {
              assertion = lib.all (t: anonymous t == null) hostTopics;
              message = "fleet-alert: an entry of ntfy's auth-access ${builtins.toJSON access} decides a host-named topic of ${builtins.toJSON hostTopics}.";
            }
          ];

          systemd.services.fleet-deadman = {
            description = "Fleet alert dead-man: R9.4 anonymous-publish probe and heartbeat poll";
            # Ordered, never pulled in: a boot does not probe ntfy or post
            # through caddy and ZeroTier before they are up (every post goes
            # to https://ntfy.zt), and the dead-man never starts a unit the
            # operator stopped; ntfy's outage is CAM-76's (design D12).
            after = [
              "ntfy-sh.service"
              "caddy.service"
              "zerotierone.service"
            ];
            environment = {
              FLEET_DEADMAN_CONFIG = "${deadmanConfig}";
              NTFY_TOKEN_FILE = "%d/alerter-token";
            };
            serviceConfig = hardening // {
              Type = "oneshot";
              ExecStart = lib.getExe deadman;
              DynamicUser = true;
              StateDirectory = "fleet-deadman";
              LoadCredential = [ "alerter-token:${cfg.deadman.tokenFile}" ];
            };
          };

          # A silence that starts just after a run is seen 10 min later and
          # reported by the next run, inside E9.3's 15 min.
          systemd.timers.fleet-deadman = {
            description = "Five-minute fleet alert dead-man";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*:0/5";
              AccuracySec = "5s";
            };
          };
        })
      ];
    };
}
