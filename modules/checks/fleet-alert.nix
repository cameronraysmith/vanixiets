# checks.x86_64-linux.fleet-alert: regulator R9.2 (ADR-009 R9.2; design D10,
# D11, D13-D16, D19; tasks.md 4.5, 4.6).
#
# Three parts, each a derivation in passthru so it can be built alone:
# - promtoolRehearsal: `promtool check rules` over the YAML rendered from
#   modules/nixos/fleet-alert/rules.nix, and a malformed-expression mutant
#   that promtool must reject.
# - fixtureRehearsal: the evaluator, flake.lib.fleetAlertEvaluator built with
#   a recording ntfy-send, runs in the build sandbox against
#   fleet-alert/fixture_server.py, which replays canned answers to the
#   store's PromQL API per run. A leg is a timeline of runs at
#   FLEET_ALERT_NOW. Every run must record one heartbeat at priority min and
#   post only with NTFY_TOKEN_FILE naming the fixture credential, and the
#   alert posts of the leg must equal its list. The four runtime R9.2
#   mutants (no state write, `for` 0, no store freeze, no absence freeze)
#   must each produce a non-empty failure list.
# - propertyRehearsal: fleet-alert/test_transition.py compares transition.jq
#   with the reference model fleet-alert/model.py over derandomized
#   Hypothesis timelines, and must fail on the no-re-post mutant.
#
# The alerter token's wiring (tasks.md 4.7) is asserted where the units are
# declared: modules/nixos/observability-notify.nix (template and resolve
# hooks), modules/nixos/fleet-alert.nix (the evaluator) and magnetite's
# configuration (both read the ntfy-alerter token): a relation within one
# host is a module assertion, which CI already pays for when it evaluates
# the host (S1 review F5).
#
# The fixtures cannot see the store's real metric names (ADR-009
# Consequences); RuleSignalMissing watches those after deploy. The label
# sets in fleet-alert/fixtures/series.json are those measured on magnetite's
# `fleet` database on 2026-10-18 (logs/s3/series-labels.md). The fixture
# server cannot evaluate PromQL, so the SystemdUnitFailed exclusion leg
# replays only the failed units the rendered exclusion regex keeps, matched
# here with the full-match semantics PromQL uses for `!~`.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      notifiedUnits = magnetite.services.observability-notify.units;
      rules = self.lib.fleetAlertRules { inherit lib notifiedUnits; };
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
      cinnabarPkgs = self.nixosConfigurations.cinnabar.pkgs;

      # The dead-man (tasks.md 5.1; design D12, "Failure path"; ADR-009 R9.3,
      # R9.4), built from the function cinnabar deploys with the recording
      # ntfy-send, and run against cinnabar's own rendered configuration with
      # only ntfyUrl and stateFile pointed at the sandbox.
      deadmanRehearsed = self.lib.fleetAlertDeadman pkgs { ntfySend = lib.getExe ntfySendStub; };
      deadmanConfigFile = cinnabar.systemd.services.fleet-deadman.environment.FLEET_DEADMAN_CONFIG;

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
      # magnetite (tasks.md 5.1-5.3; design D5 step 3, D12). The access
      # decision reproduces ntfy 2.28.0's: one row decides, rows for the user
      # or `*` whose pattern matches, ordered user DESC, pattern length DESC,
      # write DESC (world assumption A38; user/manager.go:702-735,
      # user/manager_sqlite.go:90-96); no matching row means
      # auth-default-access, here unset and so read-write (cmd/serve.go:53).
      deadmanInput = {
        execStart = cinnabar.systemd.services.fleet-deadman.serviceConfig.ExecStart;
        deployedDeadman = lib.getExe (
          self.lib.fleetAlertDeadman cinnabarPkgs { ntfySend = lib.getExe cinnabarPkgs.ntfy-send; }
        );
        deadman = cinnabar.services.fleet-alert.deadman;
        pollTopic = cinnabar.services.fleet-alert.evaluator.heartbeatTopic;
        evaluator = magnetite.services.fleet-alert.evaluator;
        evaluatorHostName = magnetite.networking.hostName;
        deadmanHostName = cinnabar.networking.hostName;
        deadmanAfter = cinnabar.systemd.services.fleet-deadman.after;
        deadmanWants = cinnabar.systemd.services.fleet-deadman.wants;
        # The path's units that exist on the dead-man's host: ntfy behind
        # listenHttp, caddy serving https://ntfy.zt to ntfy-send, and the
        # ZeroTier address caddy binds (modules/machines/nixos/cinnabar/caddy.nix,
        # zt-dns.nix).
        pathUnits = builtins.filter (name: cinnabar.systemd.services ? ${name}) deadmanPathUnits;
        listenHttp = cinnabar.services.ntfy-sh.settings.listen-http;
        access = cinnabar.services.ntfy-sh.settings.auth-access or [ ];
      };

      decision =
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

      # The units a dead-man run needs: the probe and poll reach ntfy, and
      # every post goes through caddy on cinnabar's ZeroTier address.
      deadmanPathUnits = [
        "ntfy-sh"
        "caddy"
        "zerotierone"
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

      deadmanFailures =
        i:
        let
          check = name: ok: lib.optional (!ok) name;
          anonymous = decision i.access "*";
          alerter = decision i.access "alerter";
        in
        lib.concatLists [
          (check "deadman: fleet-deadman does not run the rehearsed fleetAlertDeadman built with ntfy-send" (
            i.execStart == i.deployedDeadman
          ))
          # Ordered after every unit on its path, and never starting one, so
          # a boot neither probes a half-started path nor starts a unit the
          # operator stopped (design D12).
          (check
            "deadman: fleet-deadman is not ordered after ntfy-sh, caddy and zerotierone on its host, or wants one of them"
            (
              i.pathUnits == deadmanPathUnits
              && lib.all (name: builtins.elem "${name}.service" i.deadmanAfter) i.pathUnits
              && !(lib.any (name: builtins.elem "${name}.service" i.deadmanWants) i.pathUnits)
            )
          )
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
          (check "deadman: ntfyUrl is not ntfy's listener on the dead-man's host" (
            i.deadman.ntfyUrl == "http://${i.listenHttp}"
          ))
          # E9.4 and R9.4's premise: anonymous clients may read but not write
          # both fleet topics, alerter may write both, host topics stay open.
          (check "deadman: an anonymous write to the heartbeat or alert topic is not refused" (
            lib.all (t: anonymous t != null && readOnly (anonymous t)) [
              i.pollTopic
              i.deadman.topic
            ]
          ))
          (check "deadman: alerter may not write the heartbeat or alert topic" (
            lib.all (t: alerter t != null && readWrite (alerter t)) [
              i.pollTopic
              i.deadman.topic
            ]
          ))
          (check "deadman: an access entry decides a host-named topic" (
            lib.all (t: anonymous t == null) [
              i.evaluatorHostName
              i.deadmanHostName
            ]
          ))
        ];

      deadmanActual = deadmanFailures deadmanInput;

      deadmanMutants = {
        execStartOther =
          i:
          i
          // {
            execStart = "/nix/store/${lib.fixedWidthString 32 "0" ""}-fleet-deadman/bin/fleet-deadman";
          };
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
        listenerMoved = i: i // { listenHttp = "[::1]:2587"; };
        caddyOrderDropped = i: i // { deadmanAfter = lib.remove "caddy.service" i.deadmanAfter; };
        zerotierOrderDropped = i: i // { deadmanAfter = lib.remove "zerotierone.service" i.deadmanAfter; };
        ntfyWanted = i: i // { deadmanWants = i.deadmanWants ++ [ "ntfy-sh.service" ]; };
        # R9.4's acceptance negative control, at evaluation time.
        anonymousReadOnlyRemoved = i: i // { access = lib.remove "*:fleet-*:ro" i.access; };
        alerterEntryRemoved = i: i // { access = lib.remove "alerter:fleet-*:rw" i.access; };
        hostTopicsCovered = i: i // { access = i.access ++ [ "*:*:ro" ]; };
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

      checkConfig =
        rulesList:
        pkgs.writeText "fleet-alert-check-config.json" (
          builtins.toJSON {
            storeUrl = "http://127.0.0.1:1";
            database = "fleet";
            user = "regulator";
            queryTimeoutSec = 10;
            queryDeadlineSec = 30;
            postDeadlineSec = 40;
            topic = "fleet-alerts";
            heartbeatTopic = "fleet-heartbeat";
            stateFile = "/nonexistent/state.json";
            failedLog = "/nonexistent/failed.log";
            rules = rulesList;
          }
        );
      realConfig = checkConfig evaluatorRules;

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
      # listed in `missing`; rule expressions return the step's `series`;
      # `error` replaces every answer with that HTTP status.
      stepAnswers =
        step:
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
          ruleAnswers = lib.listToAttrs (
            map (
              r:
              lib.nameValuePair r.expr (
                vector step.at (
                  map (labels: {
                    metric = labels;
                    value = "1";
                  }) (series.${r.alert} or [ ])
                )
              )
            ) (builtins.filter (r: r ? expr) evaluatorRules)
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
            lib.listToAttrs (lib.imap0 (i: step: lib.nameValuePair (toString i) (stepAnswers step)) leg.steps)
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

      exclusionRegex =
        let
          m = builtins.match ''.*systemd_unit_name!~"([^"]*)".*'' (ruleNamed "SystemdUnitFailed").expr;
        in
        if m == null then
          throw "fleet-alert check: SystemdUnitFailed has no systemd_unit_name exclusion"
        else
          builtins.head m;
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

      storeErrorLeg = {
        name = "a store error freezes a firing HostOOMKill, raises StoreQueryFailing after 3 min, heartbeats, and resumes";
        steps = [
          {
            at = minute 0;
            series.HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
          }
        ]
        ++ map (n: {
          at = minute n;
          error = 503;
          requests = 1;
        }) (lib.range 1 8)
        ++ map (n: { at = minute n; }) (lib.range 9 14);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "4 [FIRING] StoreQueryFailing high"
          "13 [RESOLVED] StoreQueryFailing high"
          "14 [RESOLVED] HostOOMKill magnetite high"
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
            requests = 1;
          }) (lib.range 3 9)
          ++ map (n: { at = minute n; }) (lib.range 10 16);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "6 [FIRING] StoreQueryFailing high"
          "14 [RESOLVED] StoreQueryFailing high"
          "15 [RESOLVED] HostOOMKill magnetite high"
        ];
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
      silentGapLeg = {
        name = "the same 30 min gap while every expected host is silent raises nothing";
        steps = map (n: {
          at = gap n;
          reporting = [ ];
          missing = [ "node_vmstat_oom_kill" ];
        }) (lib.range 0 7);
        expect = [ ];
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

      legs =
        map fireAndResolve [
          "HostMemoryPressure"
          "HostOOMKill"
          "ZfsPoolUnhealthy"
          "SystemdUnitRestartLoop"
          "SystemdUnitFailed"
          "LocalExporterDown"
        ]
        ++ [
          exclusionLeg
          storeErrorLeg
          silentHostLeg
          storeThawLeg
          hostThawLeg
          signalGapLeg
          silentGapLeg
          windowLeg
          budgetFleetLeg
          budgetLaptopLeg
          budgetFailedLogLeg
          budgetOldLogLeg
          retryLeg
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
          [ "$(jq -s 'map(select(.topic == "fleet-heartbeat" and any(.headers[]; . == "Priority: min"))) | length' "${posts}")" = 1 ] \
            || miss "${leg.name}: run ${i} did not record exactly one heartbeat at priority min"
          [ "$(jq -s --arg token ${fixtureCredentials}/alerter-token 'all(.[]; .tokenFile == $token)' "${posts}")" = true ] \
            || miss "${leg.name}: run ${i} posted without NTFY_TOKEN_FILE naming the alerter credential"
          ${lib.optionalString ((step.postStatus or 0) == 0) ''
            jq -r 'select(.topic == "fleet-alerts") | "${i} " + ([.headers[] | select(startswith("Title: ")) | ltrimstr("Title: ")] | first) + " " + ([.headers[] | select(startswith("Priority: ")) | ltrimstr("Priority: ")] | first)' "${posts}" >> "$leg_dir/actual"
            jq -r 'select(.topic == "fleet-alerts") | .message' "${posts}" >> "$leg_dir/messages"
          ''}
          ${lib.optionalString (step ? requests) ''
            [ "$(grep -c '^REQUEST ${i} ' "$leg_dir/server.log")" = ${toString step.requests} ] \
              || miss "${leg.name}: run ${i} queried again after a failed query"
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
          python3 ${fixtureServer} --responses ${responsesFile leg} \
            --step-file "$leg_dir/step" --port-file "$leg_dir/port" > "$leg_dir/server.log" 2>&1 &
          server_pid=$!
          for _ in $(seq 100); do [ -s "$leg_dir/port" ] && break; sleep 0.1; done
          if [ -s "$leg_dir/port" ]; then
            jq --arg url "http://127.0.0.1:$(cat "$leg_dir/port")" --arg state "$leg_dir/state.json" \
              --arg failed "$leg_dir/failed.log" \
              '.storeUrl = $url | .stateFile = $state | .failedLog = $failed' ${config} > "$leg_dir/config.json"
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
            mutantTransition "noStoreFreeze" "  elif $observations.storeError then true\n"
              "  elif $observations.storeError then false\n"
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

      controlResponses = pkgs.writeText "fleet-alert-control-responses.json" (
        builtins.toJSON { "0".up = vector t0 [ ]; }
      );

      # The fixture server's own clauses, each with its negative control.
      serverControls = ''
        echo "--- the fixture server refuses other paths, databases and accounts, and detects two open requests"
        control=$(mktemp -d)
        echo 0 > "$control/step"
        python3 ${fixtureServer} --responses ${controlResponses} \
          --step-file "$control/step" --port-file "$control/port" > "$control/server.log" 2>&1 &
        server_pid=$!
        for _ in $(seq 100); do [ -s "$control/port" ] && break; sleep 0.1; done
        [ -s "$control/port" ] || { echo "FAIL: the control fixture server did not start" >&2; exit 1; }
        port=$(cat "$control/port")
        query_url="http://127.0.0.1:$port/v1/prometheus/api/v1/query"
        ask() {
          printf 'user = "%s"\n' "$1" | curl --config - --silent --output /dev/null --write-out '%{http_code}' "''${@:2}" || true
        }
        expect_code() {
          [ "$2" = "$3" ] || { echo "FAIL: fixture server: $1 answered $2, expected $3" >&2; exit 1; }
        }
        good=regulator:${fixturePassword}
        expect_code "the query path" "$(ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 200
        expect_code "another path" "$(ask "$good" -H 'x-greptime-db-name: fleet' "http://127.0.0.1:$port/v1/sql")" 404
        expect_code "a query without the database header" "$(ask "$good" --get --data-urlencode 'query=up' "$query_url")" 400
        expect_code "another account" "$(ask perses:${fixturePassword} -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
        expect_code "a wrong password" "$(ask regulator:wrong -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
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
        echo "ok: fixture server refusals and the concurrency guard"
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

      propertyRehearsal =
        pkgs.runCommand "fleet-alert-property"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (p: [ p.hypothesis ]))
              pkgs.jq
              pkgs.gnugrep
            ];
            meta.description = "D11: transition.jq equals the reference model on derandomized Hypothesis timelines, and the no-re-post mutant is caught";
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
            grep -q 'Falsifying' no-repost.log
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
