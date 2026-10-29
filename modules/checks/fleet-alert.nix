# checks.x86_64-linux.fleet-alert: regulator R9.2 (ADR-009 R9.2; design D10,
# D11, D13-D16, D19; tasks.md 4.5, 4.6; stand-up-devloop-collection design
# D17, tasks.md 5.1, 5.3-5.5).
#
# Three parts, each a derivation in passthru so it can be built alone:
# - promtoolRehearsal: `promtool check rules` over the YAML rendered from
#   modules/nixos/fleet-alert/rules.nix, and a malformed-expression mutant
#   that promtool must reject.
# - fixtureRehearsal: the evaluator, flake.lib.fleetAlertEvaluator built with
#   a recording ntfy-send, runs in the build sandbox against
#   fleet-alert/fixture_server.py, which replays canned answers to the
#   store's PromQL and SQL APIs per run and answers 400 to a query sent to
#   any database but the one its rule declares. A leg is a timeline of runs
#   at FLEET_ALERT_NOW. Every run must record one heartbeat at priority min
#   and post only with NTFY_TOKEN_FILE naming the fixture credential, and
#   the alert posts of the leg must equal its list; the two-database leg
#   also requires the server to record each rule's query once on its path
#   and database. The seven runtime mutants (no state write, `for` 0, no
#   store freeze, no absence freeze, no update of when each host last
#   reported, every query sent to fleet, and every instance frozen when any
#   database fails) must each produce a non-empty failure list; the store
#   freezes only the instances of the database that failed (review F7).
# - propertyRehearsal: fleet-alert/test_transition.py compares transition.jq
#   with the reference model fleet-alert/model.py over derandomized
#   Hypothesis timelines over two databases, holds both to leaving fleet's
#   posts unchanged by a devloop failure (stand-up-devloop-collection
#   review F7), and must fail on the no-re-post mutant.
#
# Relations within one host are assertions where the units are declared,
# which CI already pays for when it evaluates the host (S1 review F5, S3
# review F3): the notifier's resolve hooks in
# modules/nixos/observability-notify.nix, the dead-man's ntfy listener and
# access entries in modules/nixos/fleet-alert.nix, and its ordering in
# cinnabar's configuration. Two dead-man parts remain here: its rehearsal,
# against the configuration flake.lib.fleetAlertDeadmanConfig renders from
# the option defaults, and the relations between cinnabar and magnetite.
#
# The fixtures cannot see the store's real metric names (ADR-009
# Consequences); RuleSignalMissing watches those after deploy. The label
# sets in fleet-alert/fixtures/series.json are those measured on magnetite's
# `fleet` database on 2026-10-18 (logs/s3/series-labels.md). The fixture
# server cannot evaluate PromQL, so the SystemdUnitFailed exclusion leg
# replays only the failed units the rendered exclusion regex keeps, matched
# here with the full-match semantics PromQL uses for `!~`.
# Nor can it run SQL: vmTests.x86_64-linux.devloop-ingest's burnRule case
# runs PullRequestQueueWaitBurn's query on GreptimeDB 1.2.1 (design D1, D16).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      hosts = self.lib.observabilityHosts;
      notifiedUnits = lib.unique (lib.concatMap (h: h.notifiedUnits) (builtins.attrValues hosts));
      rules = self.lib.fleetAlertRules { inherit lib hosts; };
      evaluatorRules = builtins.fromJSON rules.json;
      transitionJq = ../nixos/fleet-alert/transition.jq;
      fixtureServer = ./fleet-alert/fixture_server.py;
      fixtures = lib.importJSON ./fleet-alert/fixtures/series.json;

      # ADR-009 item 10, stated here independently of transition.jq.
      priorityOf =
        severity:
        {
          critical = "high";
          warning = "default";
          info = "low";
        }
        .${severity};

      ruleNamed =
        alert:
        lib.findFirst (r: r.alert == alert) (throw "fleet-alert check: no rule ${alert}") evaluatorRules;

      # --- promtool -----------------------------------------------------------

      rulesYaml = pkgs.writeText "fleet-alert-rules.yaml" rules.yaml;

      mutateText =
        name: from: to: text:
        assert lib.assertMsg (lib.hasInfix from text)
          "fleet-alert check: mutant ${name} found nothing to replace";
        builtins.replaceStrings [ from ] [ to ] text;

      malformedYaml = pkgs.writeText "fleet-alert-rules-malformed.yaml" (
        mutateText "malformedExpression" "increase(node_vmstat_oom_kill[10m]) > 0"
          "increase(node_vmstat_oom_kill[10m] > 0"
          rules.yaml
      );

      promtoolRehearsal =
        pkgs.runCommand "fleet-alert-promtool"
          {
            nativeBuildInputs = [ pkgs.prometheus.cli ];
            meta.description = "R9.2: every rendered rule parses as PromQL, and a malformed expression is rejected";
          }
          ''
            set -euo pipefail
            promtool check rules ${rulesYaml}
            if promtool check rules ${malformedYaml} > malformed.log 2>&1; then
              cat malformed.log
              echo "FAIL: promtool accepted the malformed-expression mutant" >&2
              exit 1
            fi
            cat malformed.log
            echo "mutant malformedExpression rejected"
            touch "$out"
          '';

      # --- fixture legs -------------------------------------------------------

      fixturePassword = "00112233445566778899aabbccddeeff";
      fixtureCredentials = pkgs.runCommand "fleet-alert-fixture-credentials" { } ''
        mkdir "$out"
        printf '%s' ${fixturePassword} > "$out/regulator-password"
        printf '%s' tk_fixture00000000000000000000000 > "$out/alerter-token"
      '';

      # Records each call as { topic, message, headers, tokenFile } and exits
      # with FLEET_ALERT_POST_STATUS.
      ntfySendStub = pkgs.writeShellScriptBin "ntfy-send" ''
        set -euo pipefail
        message=$1
        topic=$2
        shift 2
        headers=()
        while [ "$#" -gt 0 ]; do
          if [ "$1" = -H ]; then
            headers+=("$2")
            shift 2
          else
            shift
          fi
        done
        ${lib.getExe pkgs.jq} -nc --arg topic "$topic" --arg message "$message" \
          --arg tokenFile "''${NTFY_TOKEN_FILE:-}" \
          '{topic: $topic, message: $message, headers: $ARGS.positional, tokenFile: $tokenFile}' \
          --args "''${headers[@]}" >> "$FLEET_ALERT_POSTS"
        exit "''${FLEET_ALERT_POST_STATUS:-0}"
      '';

      cinnabar = self.nixosConfigurations.cinnabar.config;

      # The dead-man (tasks.md 5.1; design D12, "Failure path"; ADR-009 R9.3,
      # R9.4), built from the function cinnabar deploys with the recording
      # ntfy-send, and run against the configuration rendered from the
      # module's defaults with only ntfyUrl and stateFile pointed at the
      # sandbox.
      deadmanRehearsed = self.lib.fleetAlertDeadman pkgs { ntfySend = lib.getExe ntfySendStub; };
      deadmanConfigFile = pkgs.writeText "fleet-deadman.json" (
        builtins.toJSON (self.lib.fleetAlertDeadmanConfig { })
      );

      # R9.4's build-time negative control: a dead-man that passes any HTTP
      # answer to its probe. --replace-fail proves the edit hit the script.
      deadmanProbeMutant = pkgs.runCommand "fleet-deadman-probe-mutant" { } ''
        mkdir -p "$out/bin"
        cp ${lib.getExe deadmanRehearsed} "$out/bin/fleet-deadman"
        chmod +w "$out/bin/fleet-deadman"
        substituteInPlace "$out/bin/fleet-deadman" \
          --replace-fail '[ "$probe" != 403 ]' '[ "$probe" = 000 ]'
      '';

      # The legs take the dead-man executable and fail at the first broken
      # expectation, printing `FAIL: <leg>`; the stand-in serves
      # binwiederhier/ntfy@v2.28.0's answers (ntfy_stub.py).
      deadmanLegs = pkgs.writeShellScript "fleet-deadman-legs" ''
        set -euo pipefail
        deadman="$1"
        work=$(mktemp -d)
        export FLEET_ALERT_POSTS="$work/posts" NTFY_TOKEN_FILE="${fixtureCredentials}/alerter-token"
        touch "$FLEET_ALERT_POSTS"
        hb_topic=$(jq -er .heartbeatTopic ${deadmanConfigFile})
        alert_topic=$(jq -er .topic ${deadmanConfigFile})
        host=$(jq -er .evaluatorHost ${deadmanConfigFile})
        empty="$work/empty.jsonl"
        : > "$empty"
        heartbeat="$work/heartbeat.jsonl"
        jq -nc --arg t "$hb_topic" '{id: "hb1", time: 1000, expires: 44200, event: "message", topic: $t, message: "ok 1000", priority: 1}' > "$heartbeat"

        stub_pid=
        stop_stub() {
          if [ -n "$stub_pid" ]; then
            kill "$stub_pid"
            wait "$stub_pid" || true
            stub_pid=
          fi
        }
        trap stop_stub EXIT
        fail() {
          echo "FAIL: $*" >&2
          sed 's/^/  request: /' "$work/requests" >&2
          sed 's/^/  post: /' "$FLEET_ALERT_POSTS" >&2
          exit 1
        }
        reset() {
          rm -f "$work/state.json"
          : > "$FLEET_ALERT_POSTS"
        }
        # run PROBE_STATUS|closed POLL_STATUS POLL_BODY NOW [POST_STATUS]:
        # one dead-man run; its exit status in $code.
        run() {
          local url
          : > "$work/requests"
          if [ "$1" = closed ]; then
            url=http://127.0.0.1:9
          else
            rm -f "$work/port"
            python3 ${./fleet-alert/ntfy_stub.py} --topic "$hb_topic" --probe-status "$1" --poll-status "$2" \
              --poll-body "$3" --port-file "$work/port" --log "$work/requests" &
            stub_pid=$!
            for _ in $(seq 100); do [ -s "$work/port" ] && break; sleep 0.1; done
            [ -s "$work/port" ] || fail "ntfy stub did not start"
            url="http://127.0.0.1:$(cat "$work/port")"
          fi
          jq --arg url "$url" --arg state "$work/state.json" '.ntfyUrl = $url | .stateFile = $state' \
            ${deadmanConfigFile} > "$work/config.json"
          code=0
          FLEET_DEADMAN_CONFIG="$work/config.json" FLEET_ALERT_NOW="$4" FLEET_ALERT_POST_STATUS="''${5:-0}" \
            "$deadman" > "$work/out" 2>&1 || code=$?
          stop_stub
          sed 's/^/    /' "$work/out"
        }
        # posts TITLE: posts with that title, priority high (critical), the
        # alert topic and the token file.
        posts() {
          jq -s --arg title "Title: $1" --arg topic "$alert_topic" --arg token "$NTFY_TOKEN_FILE" \
            '[.[] | select(any(.headers[]; . == $title) and any(.headers[]; . == "Priority: high") and .topic == $topic and .tokenFile == $token)] | length' \
            "$FLEET_ALERT_POSTS"
        }
        total() { jq -s length "$FLEET_ALERT_POSTS"; }
        probe_line="POST /$hb_topic? auth=no"
        poll_line="GET /$hb_topic/json?poll=1&since=10m auth=no"
        firing="[FIRING] AlertEvaluatorSilent $host"
        resolved="[RESOLVED] AlertEvaluatorSilent $host"

        reset
        run 403 200 "$heartbeat" 1000
        [ "$code" = 0 ] || fail "a refused probe and one heartbeat: exit $code, expected 0"
        [ "$(cat "$work/requests")" = "$probe_line"$'\n'"$poll_line" ] \
          || fail "a refused probe and one heartbeat: requests are not the anonymous probe then the anonymous poll"
        grep -qxF "fleet-deadman: R9.4 probe refused with HTTP 403" "$work/out" || fail "no probe-refused line"
        [ "$(total)" = 0 ] || fail "a heartbeat in the window raised a post"
        echo "ok: a refused probe and one heartbeat exit 0 with no post"

        for status in 200 500 closed; do
          reset
          run "$status" 200 "$heartbeat" 1000
          [ "$code" != 0 ] || fail "an anonymous publish answered $status exited 0"
          answered=$([ "$status" = closed ] && echo 000 || echo "$status")
          grep -qF "answered HTTP $answered, expected 403" "$work/out" || fail "probe answered $status: no R9.4 failure line"
          if [ "$status" != closed ]; then
            [ "$(cat "$work/requests")" = "$probe_line" ] || fail "probe answered $status: the run polled anyway"
          fi
          [ "$(total)" = 0 ] || fail "probe answered $status: a post was made"
          echo "ok: a probe answered $status fails the run before the poll"
        done

        reset
        run 403 500 "$heartbeat" 1000
        [ "$code" != 0 ] || fail "a failed poll exited 0"
        grep -qF "fleet-deadman: poll of $hb_topic failed" "$work/out" || fail "a failed poll: no poll failure line"
        echo "ok: a failed poll fails the run"

        reset
        run 403 200 "$empty" 1000
        [ "$code" = 0 ] || fail "an empty window: exit $code"
        [ "$(posts "$firing")" = 1 ] && [ "$(total)" = 1 ] || fail "an empty window did not post exactly one $firing"
        run 403 200 "$empty" 1300
        [ "$(total)" = 1 ] || fail "a second empty window posted again"
        run 403 200 "$heartbeat" 1600
        run 403 200 "$heartbeat" 1900
        [ "$code" = 0 ] || fail "heartbeats resumed: exit $code"
        [ "$(posts "$resolved")" = 1 ] && [ "$(total)" = 2 ] || fail "resumed heartbeats did not post exactly one $resolved"
        echo "ok: an empty window posts one FIRING, resumed heartbeats one RESOLVED"

        reset
        run 403 200 "$empty" 1000 1
        [ "$code" != 0 ] || fail "a failed post exited 0"
        [ -s "$work/state.json" ] || fail "a failed post left no state"
        run 403 200 "$empty" 1300
        [ "$code" = 0 ] || fail "the retry run: exit $code"
        run 403 200 "$empty" 1600
        [ "$(posts "$firing")" = 2 ] || fail "a failed FIRING was not retried exactly once"
        echo "ok: a failed post fails the run and the next run posts it once"
      '';

      deadmanRehearsal =
        pkgs.runCommand "fleet-deadman-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.python3
            ];
            meta.description = "behavioural check: the dead-man passes only on a refused probe and posts one FIRING and one RESOLVED";
          }
          ''
            ${deadmanLegs} ${lib.getExe deadmanRehearsed}
            if ${deadmanLegs} ${deadmanProbeMutant}/bin/fleet-deadman > mutant.log 2>&1; then
              cat mutant.log
              echo "FAIL: the legs accepted a dead-man that passes any HTTP answer to its probe" >&2
              exit 1
            fi
            grep -qF "FAIL: an anonymous publish answered 200 exited 0" mutant.log \
              || { cat mutant.log; echo "FAIL: the probe mutant failed for another reason" >&2; exit 1; }
            echo "ok: the probe mutant is rejected"
            touch "$out"
          '';

      # Relations between independently written values on cinnabar and
      # magnetite (tasks.md 5.1; design D12).
      deadmanInput = {
        deadman = cinnabar.services.fleet-alert.deadman;
        pollTopic = cinnabar.services.fleet-alert.evaluator.heartbeatTopic;
        evaluator = magnetite.services.fleet-alert.evaluator;
        evaluatorHostName = magnetite.networking.hostName;
      };

      deadmanFailures =
        i:
        let
          check = name: ok: lib.optional (!ok) name;
        in
        lib.concatLists [
          (check
            "deadman: the dead-man polls a heartbeat topic other than the one magnetite's evaluator posts to"
            (i.pollTopic == i.evaluator.heartbeatTopic)
          )
          (check "deadman: the dead-man posts to a topic other than magnetite's evaluator" (
            i.deadman.topic == i.evaluator.topic
          ))
          (check "deadman: evaluatorHost is not the host whose evaluator is enabled" (
            i.evaluator.enable && i.deadman.evaluatorHost == i.evaluatorHostName
          ))
        ];

      deadmanActual = deadmanFailures deadmanInput;

      deadmanMutants = {
        evaluatorHeartbeatRenamed =
          i:
          i
          // {
            evaluator = i.evaluator // {
              heartbeatTopic = "fleet-beat";
            };
          };
        deadmanTopicOther =
          i:
          i
          // {
            deadman = i.deadman // {
              topic = "fleet-alert";
            };
          };
        evaluatorHostWrong =
          i:
          i
          // {
            deadman = i.deadman // {
              evaluatorHost = "cinnabar";
            };
          };
      };

      deadmanClause =
        assert lib.assertMsg (
          deadmanActual == [ ]
        ) "fleet-alert dead-man failures: ${builtins.toJSON deadmanActual}";
        assert lib.assertMsg
          (lib.all (mutant: deadmanFailures (mutant deadmanInput) != [ ]) (lib.attrValues deadmanMutants))
          "fleet-alert accepted a dead-man mutant: ${
            builtins.toJSON (
              builtins.attrNames (lib.filterAttrs (_: m: deadmanFailures (m deadmanInput) == [ ]) deadmanMutants)
            )
          }";
        pkgs.runCommand "fleet-alert-deadman-clause" { } ''
          echo "ok: dead-man relations hold and ${toString (builtins.length (lib.attrNames deadmanMutants))} mutants are rejected"
          touch "$out"
        '';

      evaluatorWith =
        transition:
        self.lib.fleetAlertEvaluator pkgs {
          ntfySend = lib.getExe ntfySendStub;
          inherit transition;
        };
      realEvaluator = evaluatorWith transitionJq;

      # The evaluator's configuration for a rule list, and the database each
      # query of that list belongs to, which the fixture server enforces.
      checkConfig = rulesList: {
        file = pkgs.writeText "fleet-alert-check-config.json" (
          builtins.toJSON {
            storeUrl = "http://127.0.0.1:1";
            user = "regulator";
            queryTimeoutSec = 10;
            queryDeadlineSec = 30;
            postDeadlineSec = 35;
            topic = "fleet-alerts";
            heartbeatTopic = "fleet-heartbeat";
            stateFile = "/nonexistent/state.json";
            failedLog = "/nonexistent/failed.log";
            rules = rulesList;
          }
        );
        databases = queryDatabases rulesList;
      };
      realConfig = checkConfig evaluatorRules;

      # The database of every query the evaluator may send, read from each
      # rule's declared `database` (stand-up-devloop-collection design D2,
      # D17): its expression, presence selectors and attribution queries in
      # its own, and the reporting selector system_memory_usage_bytes in
      # RuleSignalMissing's. The fixture server answers 400 to a query sent
      # to any other database, so the evaluator's routing is judged against
      # the rule table.
      queryDatabases =
        rulesList:
        let
          missing = lib.findFirst (
            r: r.alert == "RuleSignalMissing"
          ) (throw "fleet-alert check: no RuleSignalMissing rule") rulesList;
          pairs = [
            {
              query = "count by (host_name) (system_memory_usage_bytes)";
              inherit (missing) database;
            }
          ]
          ++ lib.concatMap (
            r:
            lib.optional (r ? expr) {
              query = r.expr;
              inherit (r) database;
            }
            ++ map (p: {
              query = "count by (host_name) (${p.selector})";
              inherit (r) database;
            }) r.presence
            ++ lib.concatMap (
              a:
              map (host: {
                query = builtins.replaceStrings [ "<host>" ] [ host ] a.query;
                inherit (r) database;
              }) both
            ) r.attribution
          ) rulesList;
          byQuery = lib.mapAttrs (_: ps: lib.unique (map (p: p.database) ps)) (
            lib.groupBy (p: p.query) pairs
          );
          conflicting = lib.filterAttrs (_: ds: builtins.length ds > 1) byQuery;
        in
        assert lib.assertMsg (
          conflicting == { }
        ) "fleet-alert check: queries declared in two databases: ${builtins.toJSON conflicting}";
        pkgs.writeText "fleet-alert-databases.json" (
          builtins.toJSON (lib.mapAttrs (_: builtins.head) byQuery)
        );

      # Tuesday 2026-10-27 12:00 UTC: outside WeeklyPipelineTest's window.
      t0 = 1793102400;
      minute = n: t0 + 60 * n;

      selectors = lib.unique (
        [ "system_memory_usage_bytes" ] ++ lib.concatMap (r: map (p: p.selector) r.presence) evaluatorRules
      );

      seriesOn =
        host: alert:
        fixtures.series.${alert}
        // lib.optionalAttrs (fixtures.series.${alert} ? host_name) { host_name = host; };

      vector = at: series: {
        status = "success";
        data = {
          resultType = "vector";
          result = map (s: {
            inherit (s) metric;
            value = [
              at
              s.value
            ];
          }) series;
        };
      };

      # An SQL answer in GreptimeDB 1.2.1's records shape
      # (GreptimeTeam/greptimedb@v1.2.1 src/servers/src/http.rs:291-338): the
      # column `value` and one array per row; no row keeps the schema, as
      # HttpRecordsOutput::try_new does for an empty result (:365-375).
      sqlAnswer = rows: {
        records = {
          schema.column_schemas = [
            {
              name = "value";
              data_type = "Float64";
            }
          ];
          rows = map (row: [ row.value ]) rows;
        };
      };

      attributionAnswers =
        at: host:
        lib.listToAttrs (
          lib.zipListsWith (
            entry: series:
            lib.nameValuePair (builtins.replaceStrings [ "<host>" ] [ host ] entry.query) (
              vector at (
                map (
                  s: s // { metric = s.metric // lib.optionalAttrs (s.metric != { }) { host_name = host; }; }
                ) series
              )
            )
          ) (ruleNamed "HostMemoryPressure").attribution fixtures.attribution
        );

      # Every query the evaluator may issue in one run, with this step's
      # answers: presence selectors return the reporting hosts unless
      # listed in `missing`; the expressions of the leg's rules (its `rules`,
      # the real table by default) return the step's `series`;
      # `error` replaces every answer with that HTTP status.
      stepAnswers =
        rulesList: step:
        let
          reporting =
            step.reporting or [
              "magnetite"
            ];
          missing = step.missing or [ ];
          series = step.series or { };
          presence = lib.listToAttrs (
            map (
              selector:
              lib.nameValuePair "count by (host_name) (${selector})" (
                vector step.at (
                  map (host: {
                    metric.host_name = host;
                    value = "1";
                  }) (if builtins.elem selector missing then [ ] else reporting)
                )
              )
            ) selectors
          );
          # A PromQL rule's series are label sets, each answered with value
          # "1"; an SQL rule's are rows, each { value = <number>; }, and a
          # step's `sqlError` replaces every SQL rule's answer with that HTTP
          # status.
          ruleAnswers = lib.listToAttrs (
            map (
              r:
              lib.nameValuePair r.expr (
                if r.language == "sql" then
                  if step ? sqlError then { status = step.sqlError; } else sqlAnswer (series.${r.alert} or [ ])
                else
                  vector step.at (
                    map (labels: {
                      metric = labels;
                      value = "1";
                    }) (series.${r.alert} or [ ])
                  )
              )
            ) (builtins.filter (r: r ? expr) rulesList)
          );
          answers =
            presence
            // ruleAnswers
            // attributionAnswers step.at "magnetite"
            // attributionAnswers step.at "stibnite";
        in
        if step ? error then lib.mapAttrs (_: _: { status = step.error; }) answers else answers;

      responsesFile =
        leg:
        pkgs.writeText "fleet-alert-responses.json" (
          builtins.toJSON (
            lib.listToAttrs (
              lib.imap0 (
                i: step: lib.nameValuePair (toString i) (stepAnswers (leg.rules or evaluatorRules) step)
              ) leg.steps
            )
          )
        );

      both = [
        "magnetite"
        "stibnite"
      ];

      # A rule's condition holds from minute 0 to its `for` plus one, then
      # clears: one FIRING at its `for`, none on the next run, one RESOLVED
      # 5 min after it was last seen.
      fireAndResolve =
        alert:
        let
          f = (ruleNamed alert).for / 60;
          priority = priorityOf (ruleNamed alert).severity;
        in
        {
          name = "${alert} fires once after its for of ${toString f} min and resolves once 5 min after it clears";
          steps = map (n: {
            at = minute n;
            series = lib.optionalAttrs (n <= f + 1) { ${alert} = [ (seriesOn "magnetite" alert) ]; };
          }) (lib.range 0 (f + 7));
          expect = [
            "${toString f} [FIRING] ${alert} magnetite ${priority}"
            "${toString (f + 6)} [RESOLVED] ${alert} magnetite ${priority}"
          ];
          messages = lib.optionals ((ruleNamed alert).attribution != [ ]) [
            "nix-instantiate 471 MB, nix-eval-jobs 400 MB, niks3 314 MB"
            "4120 MB"
            "960 MB"
            "omits swapped-out pages"
          ];
        };

      # The SystemdUnitFailed exclusion a rule list renders.
      exclusionRegexOf =
        rulesList:
        let
          rule = lib.findFirst (
            r: r.alert == "SystemdUnitFailed"
          ) (throw "fleet-alert check: no SystemdUnitFailed rule") rulesList;
          m = builtins.match ''.*systemd_unit_name!~"([^"]*)".*'' rule.expr;
        in
        if m == null then
          throw "fleet-alert check: SystemdUnitFailed has no systemd_unit_name exclusion"
        else
          builtins.head m;
      exclusionRegex = exclusionRegexOf evaluatorRules;
      failedCandidates = map (unit: "${unit}.service") notifiedUnits ++ [ "nginx.service" ];
      storeKeeps = name: builtins.match exclusionRegex name == null;

      exclusionLeg = {
        name = "a failed state for every notified unit posts no SystemdUnitFailed, and nginx, not notified, posts one";
        steps = map (n: {
          at = minute n;
          series.SystemdUnitFailed = map (
            name: fixtures.series.SystemdUnitFailed // { systemd_unit_name = name; }
          ) (builtins.filter storeKeeps failedCandidates);
        }) (lib.range 0 5);
        expect = [ "5 [FIRING] SystemdUnitFailed magnetite default" ];
      };

      # design D9: the exclusion is the union of every host's notified units,
      # so a unit notified on one host is excluded on every host. Rules from a
      # two-host table; the fixture replays the failed states the rendered
      # exclusion keeps, unit-a on b, unit-b on a and nginx on a.
      twoHostRules =
        builtins.fromJSON
          (self.lib.fleetAlertRules {
            inherit lib;
            hosts = {
              a = {
                collect = true;
                alwaysOn = true;
                notifiedUnits = [ "unit-a" ];
                smartDevices = [ ];
              };
              b = {
                collect = true;
                alwaysOn = false;
                notifiedUnits = [ "unit-b" ];
                smartDevices = [ ];
              };
            };
          }).json;
      twoHostConfig = checkConfig twoHostRules;
      twoHostExclusionLeg = {
        name = "a unit notified on one host posts no SystemdUnitFailed on another, and nginx, notified nowhere, posts one";
        rules = twoHostRules;
        steps = map (n: {
          at = minute n;
          # a and b report, so their instances are not frozen as silent.
          reporting = [
            "magnetite"
            "a"
            "b"
          ];
          series.SystemdUnitFailed = map (s: fixtures.series.SystemdUnitFailed // s) (
            builtins.filter (s: builtins.match (exclusionRegexOf twoHostRules) s.systemd_unit_name == null) [
              {
                host_name = "b";
                systemd_unit_name = "unit-a.service";
              }
              {
                host_name = "a";
                systemd_unit_name = "unit-b.service";
              }
              {
                host_name = "a";
                systemd_unit_name = "nginx.service";
              }
            ]
          );
        }) (lib.range 0 5);
        expect = [ "5 [FIRING] SystemdUnitFailed a default" ];
      };

      # Every answer of runs 1 to 8 is an error, so the first query of each
      # database fails and its other queries are skipped: two requests per
      # run, and one StoreQueryFailing for each of fleet and devloop.
      storeErrorLeg = {
        name = "a store error on fleet and devloop freezes a firing HostOOMKill, raises one StoreQueryFailing per database after 3 min, heartbeats, and resumes";
        steps = [
          {
            at = minute 0;
            series.HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
          }
        ]
        ++ map (n: {
          at = minute n;
          error = 503;
          requests = 2;
        }) (lib.range 1 8)
        ++ map (n: { at = minute n; }) (lib.range 9 14);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "4 [FIRING] StoreQueryFailing devloop high"
          "4 [FIRING] StoreQueryFailing fleet high"
          "13 [RESOLVED] StoreQueryFailing devloop high"
          "13 [RESOLVED] StoreQueryFailing fleet high"
          "14 [RESOLVED] HostOOMKill magnetite high"
        ];
        messages = [
          "the store did not answer queries on fleet"
          "the store did not answer queries on devloop"
        ];
      };

      silentHostLeg = {
        name = "stibnite falls silent with HostOOMKill firing, posts nothing until it reports, then resolves once";
        steps = [
          {
            at = minute 0;
            reporting = both;
            series.HostOOMKill = [ (seriesOn "stibnite" "HostOOMKill") ];
          }
        ]
        ++ map (n: { at = minute n; }) (lib.range 1 10)
        ++ [
          {
            at = minute 11;
            reporting = both;
            series.HostOOMKill = [ (seriesOn "stibnite" "HostOOMKill") ];
          }
        ]
        ++ map (n: {
          at = minute n;
          reporting = both;
        }) (lib.range 12 16);
        expect = [
          "0 [FIRING] HostOOMKill stibnite high"
          "16 [RESOLVED] HostOOMKill stibnite high"
        ];
      };

      # Frozen time is not absence (design D11, D15): S3's live timeline of
      # 2026-10-18 (logs/s3-evidence/7.6-oom-store-resolved-20261018T095420Z.log),
      # where HostOOMKill, last seen before a 7 min store stop, resolved on
      # the first run after the store returned. The absence clock restarts at
      # the first unfrozen run, so the instance resolves 5 min after it.
      storeThawLeg = {
        name = "HostOOMKill last seen before 7 runs of store error resolves 5 min after the store answers again, not on its first answer";
        steps =
          map oomRuns (lib.range 0 2)
          ++ map (n: {
            at = minute n;
            error = 503;
            requests = 2;
          }) (lib.range 3 9)
          ++ map (n: { at = minute n; }) (lib.range 10 16);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "6 [FIRING] StoreQueryFailing devloop high"
          "6 [FIRING] StoreQueryFailing fleet high"
          "14 [RESOLVED] StoreQueryFailing devloop high"
          "14 [RESOLVED] StoreQueryFailing fleet high"
          "15 [RESOLVED] HostOOMKill magnetite high"
        ];
      };

      # Review F7 (FA scenario `The dev-loop database stops answering`): the
      # burn rule's SQL answers 500 on runs 1 to 6 while fleet answers.
      # HostOOMKill, seen on run 0 only, resolves 5 min later on run 5,
      # inside the devloop failure; StoreQueryFailing for devloop, first
      # raised on run 1, fires on run 4 after its 3 min, names devloop, and
      # resolves 5 min after run 6, its last failing run.
      devloopFailureLeg = {
        name = "a devloop failure raises StoreQueryFailing for devloop after 3 min while HostOOMKill on fleet fires and resolves as usual";
        steps = [
          (oomRuns 0)
        ]
        ++ map (n: {
          at = minute n;
          sqlError = 500;
        }) (lib.range 1 6)
        ++ map (n: { at = minute n; }) (lib.range 7 11);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "4 [FIRING] StoreQueryFailing devloop high"
          "5 [RESOLVED] HostOOMKill magnetite high"
          "11 [RESOLVED] StoreQueryFailing devloop high"
        ];
        messages = [ "the store did not answer queries on devloop" ];
      };

      hostThawLeg = {
        name = "HostOOMKill on stibnite last seen before 7 silent runs resolves 5 min after stibnite reports again, not on its first report";
        steps =
          map (n: {
            at = minute n;
            reporting = both;
            series.HostOOMKill = [ (seriesOn "stibnite" "HostOOMKill") ];
          }) (lib.range 0 1)
          ++ map (n: { at = minute n; }) (lib.range 2 8)
          ++ map (n: {
            at = minute n;
            reporting = both;
          }) (lib.range 9 15);
        expect = [
          "0 [FIRING] HostOOMKill stibnite high"
          "14 [RESOLVED] HostOOMKill stibnite high"
        ];
      };

      gap = n: t0 + 300 * n;
      signalGapLeg = {
        name = "node_vmstat_oom_kill empty for 30 min while magnetite reports raises one RuleSignalMissing";
        steps = map (n: {
          at = gap n;
          missing = [ "node_vmstat_oom_kill" ];
        }) (lib.range 0 7);
        expect = [ "6 [FIRING] RuleSignalMissing default" ];
        messages = [ "rule=HostOOMKill" ];
      };
      # magnetite's collector stops exporting while the store answers (S3
      # review F1): node_vmstat_oom_kill's gap raises nothing, because no
      # expected host reports, but magnetite is always-on, so its own silence
      # raises RuleSignalMissing 10 min after it last reported.
      alwaysOnSilentLeg = {
        name = "magnetite silent for 40 min while the store answers raises RuleSignalMissing magnetite 10 min after it last reported, none for node_vmstat_oom_kill, and resolves when it reports again";
        steps =
          map (n: { at = gap n; }) (lib.range 0 1)
          ++ map (n: {
            at = gap n;
            reporting = [ ];
            missing = [ "node_vmstat_oom_kill" ];
          }) (lib.range 2 9)
          ++ map (n: { at = gap n; }) (lib.range 10 11);
        expect = [
          "3 [FIRING] RuleSignalMissing magnetite default"
          "10 [RESOLVED] RuleSignalMissing magnetite default"
        ];
        messages = [ "selector=system_memory_usage_bytes" ];
      };

      # Mondays: 2026-10-26 is EDT (UTC-4), 2026-11-02 is EST (UTC-5).
      weekly = at: {
        inherit at;
        series.WeeklyPipelineTest = [ fixtures.series.WeeklyPipelineTest ];
      };
      windowLeg = {
        name = "WeeklyPipelineTest posts once at 09:02 New York time on both sides of the daylight-saving change, never at 08:59, 09:06 or 09:02 EDT clock time in EST";
        steps = map weekly [
          1793019720 # 2026-10-26 09:02 EDT
          1793019960 # 2026-10-26 09:06 EDT
          1793624520 # 2026-11-02 08:02 EST (13:02 UTC, 09:02 under a fixed EDT offset)
          1793627940 # 2026-11-02 08:59 EST
          1793628120 # 2026-11-02 09:02 EST
          1793628360 # 2026-11-02 09:06 EST
        ];
        expect = [
          "0 [FIRING] WeeklyPipelineTest low"
          "4 [FIRING] WeeklyPipelineTest low"
        ];
      };

      restartLoopOn =
        host: unit: (seriesOn host "SystemdUnitRestartLoop") // { systemd_unit_name = unit; };
      budgetUnits = n: map (i: "budget-${toString i}.service") (lib.range 1 n);
      budgetFleetLeg = {
        name = "11 instances within 24 h post all 11 FIRINGs and exactly one AlertBudgetExceeded";
        steps = map (n: {
          at = minute n;
          series.SystemdUnitRestartLoop = map (restartLoopOn "magnetite") (budgetUnits 11);
        }) (lib.range 0 2);
        expect = lib.replicate 11 "0 [FIRING] SystemdUnitRestartLoop magnetite default" ++ [
          "1 [FIRING] AlertBudgetExceeded default"
        ];
      };
      budgetLaptopLeg = {
        name = "4 instances on stibnite within 24 h post exactly one AlertBudgetExceeded";
        steps = map (n: {
          at = minute n;
          reporting = both;
          series.SystemdUnitRestartLoop = map (restartLoopOn "stibnite") (budgetUnits 4);
        }) (lib.range 0 2);
        expect = lib.replicate 4 "0 [FIRING] SystemdUnitRestartLoop stibnite default" ++ [
          "1 [FIRING] AlertBudgetExceeded default"
        ];
      };
      failedLine = at: "${toString at} greptimedb.service magnetite";
      oomRuns = n: {
        at = minute n;
        series.HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
      };
      budgetFailedLogLeg = {
        name = "10 FAILED lines of the last 24 h and one FIRING exceed the budget";
        failedLog = map (i: failedLine (t0 - 600 * i)) (lib.range 1 10);
        steps = map oomRuns (lib.range 0 2);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "1 [FIRING] AlertBudgetExceeded default"
        ];
      };
      budgetOldLogLeg = {
        name = "FAILED lines older than 24 h are not counted";
        failedLog =
          map (i: failedLine (t0 - 600 * i)) (lib.range 1 9)
          ++ map (i: failedLine (t0 - 90000 - i)) (lib.range 1 5);
        steps = map oomRuns (lib.range 0 2);
        expect = [ "0 [FIRING] HostOOMKill magnetite high" ];
      };
      unreadableLogLeg = {
        name = "an existing failed.log that cannot be read fails the run before any post";
        failedLogMode = "000";
        steps = [
          (
            oomRuns 0
            // {
              exit = 1;
              heartbeats = 0;
            }
          )
        ];
        expect = [ ];
      };
      retryLeg = {
        name = "a failed heartbeat fails the run, and the FIRING it left pending is posted once on the next run";
        steps = [
          (
            oomRuns 0
            // {
              postStatus = 1;
              exit = 1;
            }
          )
          (oomRuns 1)
          (oomRuns 2)
        ];
        expect = [ "1 [FIRING] HostOOMKill magnetite high" ];
      };

      # The fleet-alerting-interface scenario `The timeline is replayed`
      # (stand-up-devloop-collection design D17; tasks.md 5.1): the burn
      # rule's SQL answers one row, value 0.15, on 65 consecutive runs (runs
      # 1-65, indices 0-64), then no row. The expected posts are the spec's:
      # one FIRING at priority default on the 61st run (index 60), nothing on
      # runs 62-65 while the row persists, so a re-posting evaluator fails,
      # and one RESOLVED 5 min after the row disappears, on run 70 (index
      # 69), both titled without a host.
      burnRuleLeg = {
        name = "PullRequestQueueWaitBurn answered 0.15 on 65 runs fires once on the 61st, posts nothing on the 62nd to 65th, and resolves once 5 min after its row disappears";
        steps = map (n: {
          at = minute n;
          series = lib.optionalAttrs (n <= 64) { PullRequestQueueWaitBurn = [ { value = 0.15; } ]; };
        }) (lib.range 0 69);
        expect = [
          "60 [FIRING] PullRequestQueueWaitBurn default"
          "69 [RESOLVED] PullRequestQueueWaitBurn default"
        ];
        messages = [ "value 0.15" ];
      };

      # Design D17's two-database leg (tasks.md 5.5): one PromQL rule on fleet
      # and the burn rule on devloop in one run. The server records each
      # request's path and database; the leg requires exactly one PromQL
      # request for HostOOMKill's expression on fleet and one /v1/sql request
      # for the burn rule's on devloop, the spec scenario's databases.
      twoDatabaseRules = builtins.filter (
        r:
        builtins.elem r.alert [
          "HostOOMKill"
          "PullRequestQueueWaitBurn"
          "StoreQueryFailing"
          "RuleSignalMissing"
        ]
      ) evaluatorRules;
      twoDatabaseConfig = checkConfig twoDatabaseRules;
      twoDatabaseLeg = {
        name = "one run queries HostOOMKill on fleet through PromQL and PullRequestQueueWaitBurn on devloop through SQL";
        steps = [
          {
            at = minute 0;
            series = {
              HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
              PullRequestQueueWaitBurn = [ { value = 0.15; } ];
            };
          }
        ];
        expect = [ "0 [FIRING] HostOOMKill magnetite high" ];
        recorded = [
          "0 /v1/prometheus/api/v1/query fleet ${(ruleNamed "HostOOMKill").expr}"
          "0 /v1/sql devloop ${(ruleNamed "PullRequestQueueWaitBurn").expr}"
        ];
      };

      legs =
        map fireAndResolve [
          "HostMemoryPressure"
          "HostOOMKill"
        ]
        ++ [
          exclusionLeg
          storeErrorLeg
          silentHostLeg
          storeThawLeg
          hostThawLeg
          signalGapLeg
          alwaysOnSilentLeg
          windowLeg
          budgetFleetLeg
          budgetLaptopLeg
          budgetFailedLogLeg
          budgetOldLogLeg
          unreadableLogLeg
          retryLeg
          burnRuleLeg
          devloopFailureLeg
        ];

      runStep =
        leg: step:
        let
          i = toString step.i;
          posts = "$leg_dir/posts-${i}.jsonl";
          exit = toString (step.exit or 0);
        in
        ''
          echo ${i} > "$leg_dir/step"
          : > "${posts}"
          code=0
          FLEET_ALERT_CONFIG="$leg_dir/config.json" FLEET_ALERT_NOW=${toString step.at} \
            FLEET_ALERT_POSTS="${posts}" FLEET_ALERT_POST_STATUS=${toString (step.postStatus or 0)} \
            CREDENTIALS_DIRECTORY=${fixtureCredentials} NTFY_TOKEN_FILE=${fixtureCredentials}/alerter-token \
            "$evaluator" > "$leg_dir/run-${i}.log" 2>&1 || code=$?
          [ "$code" = ${exit} ] \
            || miss "${leg.name}: run ${i} exited $code, expected ${exit}: $(tail -n 3 "$leg_dir/run-${i}.log" | tr '\n' ' ')"
          [ "$(jq -s 'map(select(.topic == "fleet-heartbeat" and any(.headers[]; . == "Priority: min"))) | length' "${posts}")" = ${
            toString (step.heartbeats or 1)
          } ] \
            || miss "${leg.name}: run ${i} did not record exactly ${
              toString (step.heartbeats or 1)
            } heartbeat(s) at priority min"
          [ "$(jq -s --arg token ${fixtureCredentials}/alerter-token 'all(.[]; .tokenFile == $token)' "${posts}")" = true ] \
            || miss "${leg.name}: run ${i} posted without NTFY_TOKEN_FILE naming the alerter credential"
          ${lib.optionalString ((step.postStatus or 0) == 0) ''
            jq -r 'select(.topic == "fleet-alerts") | "${i} " + ([.headers[] | select(startswith("Title: ")) | ltrimstr("Title: ")] | first) + " " + ([.headers[] | select(startswith("Priority: ")) | ltrimstr("Priority: ")] | first)' "${posts}" >> "$leg_dir/actual"
            jq -r 'select(.topic == "fleet-alerts") | .message' "${posts}" >> "$leg_dir/messages"
          ''}
          ${lib.optionalString (step ? requests) ''
            [ "$(grep -c '^REQUEST ${i} ' "$leg_dir/server.log")" = ${toString step.requests} ] \
              || miss "${leg.name}: run ${i} did not send exactly ${toString step.requests} queries, the first of each database, which then failed"
          ''}
        '';

      runLeg =
        { evaluator, config }:
        leg:
        let
          expected = pkgs.writeText "fleet-alert-expected" (
            lib.concatMapStrings (line: line + "\n") leg.expect
          );
        in
        ''
          echo "--- ${leg.name}"
          evaluator=${evaluator}
          leg_dir=$(mktemp -d)
          : > "$leg_dir/actual"
          : > "$leg_dir/messages"
          printf '%s' ${
            lib.escapeShellArg (lib.concatMapStrings (line: line + "\n") (leg.failedLog or [ ]))
          } > "$leg_dir/failed.log"
          ${lib.optionalString (leg ? failedLogMode) ''chmod ${leg.failedLogMode} "$leg_dir/failed.log"''}
          python3 ${fixtureServer} --responses ${responsesFile leg} --databases ${config.databases} \
            --step-file "$leg_dir/step" --port-file "$leg_dir/port" > "$leg_dir/server.log" 2>&1 &
          server_pid=$!
          for _ in $(seq 100); do [ -s "$leg_dir/port" ] && break; sleep 0.1; done
          if [ -s "$leg_dir/port" ]; then
            jq --arg url "http://127.0.0.1:$(cat "$leg_dir/port")" --arg state "$leg_dir/state.json" \
              --arg failed "$leg_dir/failed.log" \
              '.storeUrl = $url | .stateFile = $state | .failedLog = $failed' ${config.file} > "$leg_dir/config.json"
            ${lib.concatMapStrings (runStep leg) (lib.imap0 (i: step: step // { inherit i; }) leg.steps)}
          else
            miss ${lib.escapeShellArg "${leg.name}: the fixture server did not start"}
          fi
          kill "$server_pid" 2>/dev/null || true
          wait "$server_pid" 2>/dev/null || true
          server_pid=
          if grep -E '^(VIOLATION|UNEXPECTED) ' "$leg_dir/server.log" >&2; then
            miss ${lib.escapeShellArg "${leg.name}: the fixture server recorded a violation or an unexpected query"}
          fi
          ${lib.concatMapStrings (line: ''
            [ "$(grep -cxF -- ${lib.escapeShellArg "REQUEST ${line}"} "$leg_dir/server.log")" = 1 ] \
              || miss ${lib.escapeShellArg "${leg.name}: the server did not record exactly one: REQUEST ${line}"}
          '') (leg.recorded or [ ])}
          if ! diff -u ${expected} "$leg_dir/actual" >&2; then
            miss ${lib.escapeShellArg "${leg.name}: the alert posts differ from the expected list"}
          fi
          ${lib.concatMapStrings (text: ''
            grep -qF -- ${lib.escapeShellArg text} "$leg_dir/messages" \
              || miss ${lib.escapeShellArg "${leg.name}: no posted message carries: ${text}"}
          '') (leg.messages or [ ])}
        '';

      mutantTransition =
        name: from: to:
        pkgs.writeText "transition-${name}.jq" (mutateText name from to (builtins.readFile transitionJq));

      # ADR-009 R9.2's runtime mutants; the fifth, a malformed expression, is
      # promtoolRehearsal's.
      runtimeMutants = {
        noStateWrite = {
          evaluator = realEvaluator.overrideAttrs (old: {
            text =
              mutateText "noStateWrite" ''mv -f "$state_file.tmp" "$state_file"'' ''rm -f "$state_file.tmp"''
                old.text;
          });
          config = realConfig;
          legs = [ (fireAndResolve "HostOOMKill") ];
        };
        forZero = {
          evaluator = realEvaluator;
          config = checkConfig (
            map (r: if r.alert == "HostMemoryPressure" then r // { for = 0; } else r) evaluatorRules
          );
          legs = [ (fireAndResolve "HostMemoryPressure") ];
        };
        noStoreFreeze = {
          evaluator = evaluatorWith (
            mutantTransition "noStoreFreeze"
              "  elif store_failed($observations; database_of($inst)) then true\n"
              "  elif store_failed($observations; database_of($inst)) then false\n"
          );
          config = realConfig;
          legs = [ storeErrorLeg ];
        };
        noAbsenceFreeze = {
          evaluator = evaluatorWith (
            mutantTransition "noAbsenceFreeze"
              "  else (($inst.labels.host_name) as $h | any(($observations.reporting // [])[]; . == $h) | not)\n"
              "  else false\n"
          );
          config = realConfig;
          legs = [ silentHostLeg ];
        };
        noHostsUpdate = {
          evaluator = evaluatorWith (
            mutantTransition "noHostsUpdate"
              "else .hosts += (reduce ($observations.reporting // [])[] as $h ({}; .[$h] = $now)) end"
              "else . end"
          );
          config = realConfig;
          legs = [ alwaysOnSilentLeg ];
        };
        everyQueryToFleet = {
          evaluator = realEvaluator.overrideAttrs (old: {
            text =
              mutateText "everyQueryToFleet" "local language=$1 database=$2 expr=$3"
                "local language=$1 database=fleet expr=$3"
                old.text;
          });
          config = twoDatabaseConfig;
          legs = [ twoDatabaseLeg ];
        };
        allDatabasesFreeze = {
          evaluator = evaluatorWith allDatabasesFreezeTransition;
          config = realConfig;
          legs = [ devloopFailureLeg ];
        };
      };

      mutantRun = name: mutant: ''
        echo "=== mutant ${name}"
        misses="$TMPDIR/misses-${name}"
        : > "$misses"
        ${lib.concatMapStrings (runLeg {
          evaluator = lib.getExe mutant.evaluator;
          inherit (mutant) config;
        }) mutant.legs}
        if [ -s "$misses" ]; then
          echo "mutant ${name} rejected: $(head -n 1 "$misses")"
        else
          echo "FAIL: mutant ${name} produced no failure" >&2
          mutant_missed=1
        fi
      '';

      controlQuery = "SELECT 1 AS value";
      controlResponses = pkgs.writeText "fleet-alert-control-responses.json" (
        builtins.toJSON {
          "0" = {
            up = vector t0 [ ];
            "${controlQuery}" = sqlAnswer [ ];
          };
        }
      );
      controlDatabases = pkgs.writeText "fleet-alert-control-databases.json" (
        builtins.toJSON {
          up = "fleet";
          "${controlQuery}" = "devloop";
        }
      );

      # The fixture server's own clauses, each with its negative control.
      serverControls = ''
        echo "--- the fixture server refuses other paths, databases and accounts, replays SQL as GreptimeDB does, and detects two open requests"
        control=$(mktemp -d)
        echo 0 > "$control/step"
        python3 ${fixtureServer} --responses ${controlResponses} --databases ${controlDatabases} \
          --step-file "$control/step" --port-file "$control/port" > "$control/server.log" 2>&1 &
        server_pid=$!
        for _ in $(seq 100); do [ -s "$control/port" ] && break; sleep 0.1; done
        [ -s "$control/port" ] || { cat "$control/server.log" >&2; echo "FAIL: the control fixture server did not start" >&2; exit 1; }
        port=$(cat "$control/port")
        query_url="http://127.0.0.1:$port/v1/prometheus/api/v1/query"
        sql_url="http://127.0.0.1:$port/v1/sql"
        sql_arg=${lib.escapeShellArg "sql=${controlQuery}"}
        ask() {
          printf 'user = "%s"\n' "$1" | curl --config - --silent --output /dev/null --write-out '%{http_code}' "''${@:2}" || true
        }
        expect_code() {
          [ "$2" = "$3" ] || { echo "FAIL: fixture server: $1 answered $2, expected $3" >&2; exit 1; }
        }
        good=regulator:${fixturePassword}
        expect_code "the PromQL path" "$(ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 200
        expect_code "the SQL path" "$(ask "$good" --url-query 'db=devloop' --data-urlencode "$sql_arg" "$sql_url")" 200
        expect_code "another path" "$(ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "http://127.0.0.1:$port/v1/promql")" 404
        expect_code "a PromQL query without the database header" "$(ask "$good" --get --data-urlencode 'query=up' "$query_url")" 400
        expect_code "a PromQL query to another database" "$(ask "$good" -H 'x-greptime-db-name: devloop' --get --data-urlencode 'query=up' "$query_url")" 400
        expect_code "an SQL query without db" "$(ask "$good" --data-urlencode "$sql_arg" "$sql_url")" 400
        expect_code "an SQL query to another database" "$(ask "$good" --url-query 'db=fleet' --data-urlencode "$sql_arg" "$sql_url")" 400
        expect_code "another account on the PromQL path" "$(ask perses:${fixturePassword} -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
        expect_code "another account on the SQL path" "$(ask perses:${fixturePassword} --url-query 'db=devloop' --data-urlencode "$sql_arg" "$sql_url")" 401
        expect_code "a wrong password" "$(ask regulator:wrong -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
        printf 'user = "%s"\n' "$good" | curl --config - --silent --url-query 'db=devloop' --data-urlencode "$sql_arg" "$sql_url" > "$control/sql.json"
        jq -e '(.output | length) == 1 and (.output[0].records.schema.column_schemas | map(.name)) == ["value"] and .output[0].records.rows == []' "$control/sql.json" > /dev/null \
          || { cat "$control/sql.json" >&2; echo "FAIL: fixture server: the SQL answer is not GreptimeDB's output[0].records shape" >&2; exit 1; }
        python3 -c 'import socket, sys, time; s = socket.create_connection(("127.0.0.1", int(sys.argv[1]))); time.sleep(10)' "$port" &
        holder=$!
        sleep 1
        ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url" > /dev/null
        for _ in $(seq 50); do kill -0 "$server_pid" 2>/dev/null || break; sleep 0.1; done
        if kill -0 "$server_pid" 2>/dev/null; then
          kill "$server_pid" "$holder" 2>/dev/null || true
          echo "FAIL: the fixture server kept serving with two requests open" >&2
          exit 1
        fi
        server_status=0
        wait "$server_pid" || server_status=$?
        server_pid=
        kill "$holder" 2>/dev/null || true
        if [ "$server_status" = 0 ] || ! grep -q '^VIOLATION two requests open at once' "$control/server.log"; then
          cat "$control/server.log" >&2
          echo "FAIL: the fixture server did not record two open requests" >&2
          exit 1
        fi
        echo "ok: fixture server refusals, the SQL answer shape and the concurrency guard"
      '';

      fixtureRehearsal =
        pkgs.runCommand "fleet-alert-fixtures"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.diffutils
              pkgs.gnugrep
              pkgs.jq
              pkgs.python3
            ];
            meta.description = "R9.2: the evaluator against a replaying fixture server; every leg passes and every runtime mutant fails a leg";
          }
          ''
            set -euo pipefail
            server_pid=
            trap '[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true' EXIT
            miss() {
              printf 'MISS %s\n' "$*" >&2
              printf '%s\n' "$*" >> "$misses"
            }
            ${serverControls}
            misses="$TMPDIR/misses-real"
            : > "$misses"
            ${lib.concatMapStrings (runLeg {
              evaluator = lib.getExe realEvaluator;
              config = realConfig;
            }) legs}
            ${runLeg {
              evaluator = lib.getExe realEvaluator;
              config = twoDatabaseConfig;
            } twoDatabaseLeg}
            ${runLeg {
              evaluator = lib.getExe realEvaluator;
              config = twoHostConfig;
            } twoHostExclusionLeg}
            mutant_missed=0
            ${lib.concatStrings (lib.mapAttrsToList mutantRun runtimeMutants)}
            if [ -s "$TMPDIR/misses-real" ]; then
              echo "FAIL: the evaluator failed these legs:" >&2
              cat "$TMPDIR/misses-real" >&2
              exit 1
            fi
            echo "ok: every leg passed"
            [ "$mutant_missed" = 0 ]
            touch "$out"
          '';

      # --- property test ------------------------------------------------------

      jqLibOf =
        name: transition:
        pkgs.linkFarm "fleet-alert-jq-${name}" [
          {
            name = "transition.jq";
            path = transition;
          }
        ];
      noRepostTransition =
        mutantTransition "noRepost" ''>= repost_every then "repost"''
          ''>= repost_every and false then "repost"'';
      # Review F7's negative control: any failed database freezes every
      # instance, as before per-database freezing.
      allDatabasesFreezeTransition =
        mutantTransition "allDatabasesFreeze"
          "  elif store_failed($observations; database_of($inst)) then true\n"
          "  elif (store_errors($observations) | length) > 0 then true\n";

      propertyRehearsal =
        pkgs.runCommand "fleet-alert-property"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (p: [ p.hypothesis ]))
              pkgs.jq
              pkgs.gnugrep
            ];
            meta.description = "D11, review F7: transition.jq equals the reference model on derandomized Hypothesis timelines, a devloop failure leaves fleet's posts alone, and the no-re-post mutant is caught";
          }
          ''
            set -euo pipefail
            export HOME="$TMPDIR"
            cd "$TMPDIR"
            FLEET_ALERT_JQ_LIB=${jqLibOf "real" transitionJq} python3 ${./fleet-alert}/test_transition.py
            if FLEET_ALERT_JQ_LIB=${jqLibOf "noRepost" noRepostTransition} python3 ${./fleet-alert}/test_transition.py > no-repost.log 2>&1; then
              cat no-repost.log
              echo "FAIL: the property test accepted the no-re-post mutant" >&2
              exit 1
            fi
            cat no-repost.log
            # Hypothesis 6.159.0 renamed the banner "Falsifying example" to "Failing test case".
            grep -Eq 'Falsifying example|Failing test case' no-repost.log
            echo "mutant noRepost rejected"
            touch "$out"
          '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        fleet-alert =
          pkgs.runCommand "fleet-alert"
            {
              passthru = {
                inherit
                  rules
                  promtoolRehearsal
                  fixtureRehearsal
                  propertyRehearsal
                  deadmanRehearsal
                  deadmanClause
                  ;
              };
            }
            ''
              # R9.2: rules parse; the evaluator against fixtures; the model.
              test -e ${promtoolRehearsal}
              test -e ${fixtureRehearsal}
              test -e ${propertyRehearsal}
              test -e ${deadmanRehearsal}
              test -e ${deadmanClause}
              touch "$out"
            '';
      };
    };
}
