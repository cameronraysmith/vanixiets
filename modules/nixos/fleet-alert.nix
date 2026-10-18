# Fleet alert evaluator (ADR-009 Decision items 1-8, 10, 14, 17; R9.1, R9.5;
# design D11-D16, D18; tasks.md 4.3, 4.4).
#
# fleet-alert.timer starts fleet-alert.service every minute. The evaluator
# reads its configuration from the JSON at FLEET_ALERT_CONFIG, queries the
# store's PromQL API one query at a time as `regulator` (password from
# $CREDENTIALS_DIRECTORY/regulator-password, passed to curl on stdin, as
# modules/lib/greptimedb-envelope.nix does), each with --max-time
# queryTimeoutSec, and ends the query phase at the first failed query or at
# queryDeadlineSec: a store error, which transition.jq turns into a freeze
# and, after 3 min, StoreQueryFailing. It reads the notifier's failed.log,
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
# fleet-alert.service runs with MemoryMax = 64M and TimeoutStartSec = 50s.
# The kill order (evaluator 900, store 500, collector 300, this unit 0) is
# asserted by magnetite's configuration, which holds all four. An assertion
# below also requires the unit to load evaluator.tokenFile and name that
# credential in NTFY_TOKEN_FILE.
{ config, ... }:
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
        database=$(setting database)
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

        # One instant query; its body lands in $work/body. Fails on a
        # transport error, a timeout, any status but 200, a body that is not
        # a vector, or when the query deadline has passed.
        query() {
          local remaining status
          remaining=$((query_deadline - SECONDS))
          if [ "$remaining" -le 0 ]; then
            echo "fleet-alert: query deadline of ''${query_deadline}s reached" >&2
            return 1
          fi
          if [ "$remaining" -gt "$query_timeout" ]; then
            remaining=$query_timeout
          fi
          if ! status=$(printf 'user = "%s:%s"\n' "$user" "$(< "$credentials/regulator-password")" \
            | curl --config - --silent --show-error --max-time "$remaining" \
                --header "x-greptime-db-name: $database" \
                --get --data-urlencode "query=$1" \
                --output "$work/body" --write-out '%{http_code}' \
                "$store_url/v1/prometheus/api/v1/query"); then
            printf 'fleet-alert: query failed: %s\n' "$1" >&2
            return 1
          fi
          if [ "$status" != 200 ] \
            || ! jq -e '.status == "success" and .data.resultType == "vector"' "$work/body" > /dev/null; then
            printf 'fleet-alert: HTTP %s for query: %s\n' "$status" "$1" >&2
            return 1
          fi
        }

        # Presence selectors (system_memory_usage_bytes first among them is
        # what `reporting` reads), then rule expressions, then attribution
        # for the hosts in the results of rules that name attribution
        # queries. Stops at the first failed query.
        collect() {
          local selector rule alert expr window inside host attr name label attr_query
          while IFS= read -r selector; do
            query "count by (host_name) ($selector)" || return 1
            jq -c --arg selector "$selector" \
              '{selector: $selector, hosts: [.data.result[].metric.host_name // empty]}' \
              "$work/body" >> "$work/presence.jsonl"
          done < <(jq -r '["system_memory_usage_bytes"] + [.rules[].presence[]?.selector] | unique | .[]' "$config")

          while IFS= read -r rule; do
            alert=$(jq -r .alert <<< "$rule")
            expr=$(jq -r .expr <<< "$rule")
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
            query "$expr" || return 1
            jq -c --arg alert "$alert" \
              '{alert: $alert, result: [.data.result[] | {labels: .metric, value: .value[1]}]}' \
              "$work/body" >> "$work/results.jsonl"
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
              query "''${attr_query//<host>/$host}" || return 1
              jq -c --arg host "$host" --arg name "$name" --arg label "$label" \
                '{host: $host, name: $name, label: $label, result: .data.result}' \
                "$work/body" >> "$work/attribution.jsonl"
            done < <(jq -c '[.rules[].attribution[]?] | unique | .[]' "$config")
          done < <(jq -r --slurpfile results "$work/results.jsonl" '
            [.rules[] | select((.attribution // []) | length > 0) | .alert] as $attributed
            | [$results[] | select(.alert as $a | any($attributed[]; . == $a)) | .result[].labels.host_name // empty]
            | unique | .[]' "$config")
        }

        store_error=false
        if ! collect; then
          store_error=true
        fi

        if [ -r "$failed_log" ]; then
          jq -R -s '[split("\n")[] | select(test("^[0-9]+ [^ ]+ [^ ]+$")) | split(" ")
            | {at: (.[0] | tonumber), unit: .[1], host: .[2]}]' "$failed_log" > "$work/failed.json"
        else
          echo '[]' > "$work/failed.json"
        fi

        jq -n --argjson storeError "$store_error" \
          --slurpfile presence "$work/presence.jsonl" \
          --slurpfile results "$work/results.jsonl" \
          --slurpfile windows "$work/windows.jsonl" \
          --slurpfile attribution "$work/attribution.jsonl" \
          --slurpfile failed "$work/failed.json" '
          def mb: (tonumber / 1000000 | floor | tostring) + " MB";
          {
            storeError: $storeError,
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

        if [ "$store_error" = true ]; then
          echo "fleet-alert: the store did not answer; instances are frozen" >&2
        fi
      '';
    };
in
{
  flake.lib = { inherit fleetAlertEvaluator; };

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

      rendered = flakeLib.fleetAlertRules {
        inherit lib;
        notifiedUnits = config.services.observability-notify.units or [ ];
      };
      evaluatorConfig = pkgs.writeText "fleet-alert-config.json" (
        builtins.toJSON {
          inherit (cfg.evaluator) storeUrl topic heartbeatTopic;
          database = "fleet";
          user = "regulator";
          queryTimeoutSec = 10;
          queryDeadlineSec = 30;
          postDeadlineSec = 40;
          stateFile = "/var/lib/fleet-alert/state.json";
          failedLog = "/var/lib/observability-notify/failed.log";
          rules = builtins.fromJSON rendered.json;
        }
      );
      evaluator = fleetAlertEvaluator pkgs { ntfySend = lib.getExe pkgs.ntfy-send; };
      unit = config.systemd.services.fleet-alert.serviceConfig;
      tokenIds = lib.concatMap (
        entry:
        let
          m = builtins.match "([^:]+):(.+)" entry;
        in
        lib.optional (m != null && builtins.elemAt m 1 == cfg.evaluator.tokenFile) (builtins.head m)
      ) (lib.toList (unit.LoadCredential or [ ]));
      tokenEnv = config.systemd.services.fleet-alert.environment.NTFY_TOKEN_FILE or null;
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
          default = "fleet-alerts";
          description = "ntfy topic for FIRING and RESOLVED posts.";
        };
        heartbeatTopic = lib.mkOption {
          type = lib.types.str;
          default = "fleet-heartbeat";
          description = "ntfy topic for the heartbeat each completed run posts at priority min.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.evaluator.enable {
          assertions = [
            {
              assertion = cfg.evaluator.tokenFile != null && cfg.evaluator.regulatorPasswordFile != null;
              message = "fleet-alert: services.fleet-alert.evaluator.tokenFile and regulatorPasswordFile must be set when the evaluator is enabled.";
            }
            # R9.5 (ADR-009 E9.5).
            {
              assertion = (unit.MemoryMax or null) == "64M" && (unit.TimeoutStartSec or null) == "50s";
              message = "fleet-alert: R9.5 requires fleet-alert.service to run with MemoryMax = \"64M\" and TimeoutStartSec = \"50s\" (ADR-009 E9.5); it has MemoryMax = ${
                builtins.toJSON (unit.MemoryMax or null)
              }, TimeoutStartSec = ${builtins.toJSON (unit.TimeoutStartSec or null)}.";
            }
            # Design D3: the evaluator's posts carry the alerter token.
            {
              assertion = tokenIds != [ ] && builtins.elem tokenEnv (map (id: "%d/${id}") tokenIds);
              message = "fleet-alert: fleet-alert.service must load evaluator.tokenFile (${toString cfg.evaluator.tokenFile}) as a credential and name it in NTFY_TOKEN_FILE; it loads ${
                builtins.toJSON (unit.LoadCredential or [ ])
              } and sets NTFY_TOKEN_FILE = ${builtins.toJSON tokenEnv}.";
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
      ];
    };
}
