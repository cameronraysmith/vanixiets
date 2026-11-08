# checks.x86_64-linux.fleet-alert: regulator R9.2 (ADR-009 R9.2; design D10,
# D11, D13-D16, D19; tasks.md 4.5, 4.6; stand-up-devloop-collection design
# D17, tasks.md 5.1, 5.3-5.5).
#
# Five parts, each a derivation in passthru so it can be built alone:
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
#   and database. The ten runtime mutants (no state write, `for` 0, no
#   store freeze, no absence freeze, no update of when each host last
#   reported, every query sent to fleet, every instance frozen when any
#   database fails, magnetite the only always-on host,
#   LaunchdJobNotRunning's unloaded arm without its kept-alive exclusion,
#   and LaunchdJobFailed without its kept-alive arm's launch window)
#   must each produce a non-empty failure list; the store freezes only the
#   instances of the database that failed (review F7). The legs about pyrite render
#   the host table with its `collect` forced each way, so they hold whatever
#   pyrite's row says. Each leg, each mutant and the server's controls is a
#   derivation of its own in fixtureRehearsal's passthru, which requires
#   them all, so they build in parallel.
# - propertyRehearsal: fleet-alert/test_transition.py compares transition.jq
#   with the reference model fleet-alert/model.py over derandomized
#   Hypothesis timelines over two databases, holds both to leaving fleet's
#   posts unchanged by a devloop failure (stand-up-devloop-collection
#   review F7), and must fail on the no-re-post mutant.
# - deadmanPingRehearsal (R9.6; CAM-76 design D7): the dead-man, built with
#   flake.lib.fleetDeadmanPing, runs against fleet-alert/ntfy_stub.py and
#   fleet-alert/ping_stub.py, which share one request log; each leg compares
#   the recorded requests with the expectation it writes, and the mutants
#   deadmanPingFirst, deadmanPingNoHeartbeat, deadmanPingBeforePosts,
#   pingAcceptsAny200 and pingPrintsConfig must each fail a named leg.
# - pingTransport (CAM-76 design D5): flake.lib.fleetDeadmanPing built with a
#   recording curl must read the ping URL on stdin and put it on no argv,
#   and the mutant pingOnArgv, which passes the URL as an argument, must fail.
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
# `fleet` database on 2026-10-18 (logs/s3/series-labels.md), except the
# file-system rules', which no host stored when those rules were added:
# theirs are the file-system expressions' `by` labels. The NVMe rules' names
# and label sets are pyrite's as stored on 2026-11-01
# (logs/s4-evidence/5.3-smart-20261101T063202Z.log), where the exporter's
# counter-typed fields carry `_total`. The darwin rules' label sets and the
# names in its `selectors` are stibnite's as stored on 2026-11-06, read as
# regulator with the shapes the store answers to those rules' expressions,
# which carry no __name__ (logs/s5-evidence/6.1-replay-20261106T144527Z.log).
# The fixture server cannot evaluate PromQL,
# so the SystemdUnitFailed exclusion leg replays only the failed units the
# rendered exclusion regex keeps, matched here with the full-match
# semantics PromQL uses for `!~`, LaunchdJobNotRunning's legs replay
# the probe's four state series for one label as the rendered expression's
# two arms select them (design D9; tasks.md 8.3a), and LaunchdJobFailed's
# legs replay one job's last exit and the minute its launch count last
# rose as that expression's two arms select it (CAM-92 design D3).
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

      # R9.6 (CAM-76, design D7): the dead-man with its external ping, against
      # the ntfy stand-in and a ping stand-in. The legs compare the stand-ins'
      # recorded requests with the expectations written here.
      pingExe = lib.getExe (self.lib.fleetDeadmanPing pkgs { });
      deadmanPinged = self.lib.fleetAlertDeadman pkgs {
        ntfySend = lib.getExe ntfySendStub;
        ping = pingExe;
      };
      pingUuid = "5bf66975-d4c7-4bf5-bcc8-b8d8a82ea278";

      deadmanPingLegs = pkgs.writeShellScript "fleet-deadman-ping-legs" ''
        set -euo pipefail
        deadman="$1"
        work=$(mktemp -d)
        export FLEET_ALERT_POSTS="$work/posts" NTFY_TOKEN_FILE="${fixtureCredentials}/alerter-token"
        touch "$FLEET_ALERT_POSTS"
        hb_topic=$(jq -er .heartbeatTopic ${deadmanConfigFile})
        empty="$work/empty.jsonl"
        : > "$empty"
        heartbeat="$work/heartbeat.jsonl"
        jq -nc --arg t "$hb_topic" '{id: "hb1", time: 1000, expires: 44200, event: "message", topic: $t, message: "ok 1000", priority: 1}' > "$heartbeat"

        pids=()
        stop_stubs() {
          for p in "''${pids[@]}"; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
          pids=()
        }
        trap stop_stubs EXIT
        fail() {
          echo "FAIL: $*" >&2
          sed 's/^/  request: /' "$work/requests" >&2 || true
          sed 's/^/  out: /' "$work/out" >&2 || true
          exit 1
        }
        reset() {
          rm -f "$work/state.json"
          : > "$FLEET_ALERT_POSTS"
        }
        wait_port() {
          for _ in $(seq 100); do [ -s "$1" ] && return 0; sleep 0.1; done
          fail "a stand-in did not start"
        }
        # run PROBE|closed POLL_STATUS POLL_BODY NOW [POST_STATUS] [ANSWER] [PING_URL]:
        # one dead-man run with its ping; exit status in $code. Both stand-ins
        # log to $work/requests, so a leg sees the order of probe, poll and ping.
        run() {
          local url ping_url
          : > "$work/requests"
          rm -f "$work/ntfy-port" "$work/ping-port"
          if [ "$1" = closed ]; then
            url=http://127.0.0.1:9
          else
            python3 ${./fleet-alert/ntfy_stub.py} --topic "$hb_topic" --probe-status "$1" --poll-status "$2" \
              --poll-body "$3" --port-file "$work/ntfy-port" --log "$work/requests" &
            pids+=($!)
            wait_port "$work/ntfy-port"
            url="http://127.0.0.1:$(cat "$work/ntfy-port")"
          fi
          python3 ${./fleet-alert/ping_stub.py} --answer "''${6:-OK}" --port-file "$work/ping-port" --log "$work/requests" &
          pids+=($!)
          wait_port "$work/ping-port"
          if [ -n "''${7:-}" ]; then
            ping_url="$7"
          else
            ping_url="http://127.0.0.1:$(cat "$work/ping-port")/${pingUuid}"
          fi
          printf 'url = "%s"\n' "$ping_url" > "$work/ping.conf"
          jq --arg url "$url" --arg state "$work/state.json" '.ntfyUrl = $url | .stateFile = $state' \
            ${deadmanConfigFile} > "$work/config.json"
          code=0
          FLEET_DEADMAN_CONFIG="$work/config.json" FLEET_DEADMAN_PING_CONFIG="$work/ping.conf" \
            FLEET_ALERT_NOW="$4" FLEET_ALERT_POST_STATUS="''${5:-0}" \
            "$deadman" > "$work/out" 2>&1 || code=$?
          stop_stubs
          sed 's/^/    /' "$work/out"
        }
        # The ping stand-in's lines are the only ones with "body=".
        pings() { grep -c ' body=' "$work/requests" || true; }

        # The failing legs come first, so a dead-man that pings before its
        # probe is caught by a probe leg rather than by the passing leg.
        for status in 200 500 closed; do
          reset
          run "$status" 200 "$heartbeat" 1000
          [ "$code" != 0 ] || fail "a probe answered $status exited 0"
          [ "$(pings)" = 0 ] || fail "a probe answered $status pinged"
          echo "ok: a probe answered $status sends no ping"
        done

        reset
        run 403 500 "$heartbeat" 1000
        [ "$code" != 0 ] || fail "a failed poll exited 0"
        [ "$(pings)" = 0 ] || fail "a failed poll pinged"
        echo "ok: a failed poll sends no ping"

        reset
        run 403 200 "$heartbeat" 1000
        [ "$code" = 0 ] || fail "a passing run: exit $code"
        [ "$(pings)" = 1 ] || fail "a passing run did not ping exactly once"
        printf '%s\n' "POST /fleet-heartbeat? auth=no" "GET /fleet-heartbeat/json?poll=1&since=10m auth=no" "GET /${pingUuid} body=0" > "$work/expected"
        cmp -s "$work/requests" "$work/expected" || fail "a passing run: the requests are not the probe, the poll and one ping to the configured path, in that order"
        grep -qxF "fleet-deadman: external ping accepted" "$work/out" || fail "a passing run: no accepted line"
        echo "ok: a passing run with a heartbeat pings once"

        reset
        run 403 200 "$empty" 1000
        [ "$code" = 0 ] || fail "an empty window: exit $code"
        [ "$(jq -s length "$FLEET_ALERT_POSTS")" = 1 ] || fail "an empty window did not post one FIRING"
        [ "$(pings)" = 0 ] || fail "an empty window pinged"
        grep -qF "no external ping" "$work/out" || fail "an empty window: no no-ping line"
        echo "ok: an empty window posts one FIRING and sends no ping"

        # The FIRING above is in the state, its absenceFrom 1000. A heartbeat
        # run before 300 s have passed has nothing to post and pings; the run
        # at 1300 has the RESOLVED due (transition.jq resolve_after), its post
        # fails, and that run must fail without pinging.
        run 403 200 "$heartbeat" 1100
        [ "$code" = 0 ] && [ "$(pings)" = 1 ] || fail "heartbeat back with nothing to post: expected exit 0 and one ping"
        run 403 200 "$heartbeat" 1300 1
        [ "$code" != 0 ] || fail "the RESOLVED post never came due"
        [ "$(pings)" = 0 ] || fail "a failed post pinged"
        echo "ok: a failed post sends no ping"

        reset
        run 403 200 "$heartbeat" 1000 0 "OK (not found)"
        [ "$code" != 0 ] || fail "an unknown check answered OK (not found) exited 0"
        grep -qF "answered 'OK (not found)', expected OK" "$work/out" || fail "an unknown check: no answer line"
        if grep -qF "${pingUuid}" "$work/out"; then fail "an unknown check: the URL was printed"; fi
        echo "ok: an unknown check fails the run without printing the URL"

        # The ping's egress fails: curl cannot connect (port 9 is closed, as in
        # the probe-closed leg), the run fails, and the URL stays unprinted.
        reset
        run 403 200 "$heartbeat" 1000 0 OK "http://127.0.0.1:9/${pingUuid}"
        [ "$code" != 0 ] || fail "an unreachable ping exited 0"
        grep -qxF "fleet-deadman: external ping failed" "$work/out" || fail "an unreachable ping: no failure line"
        if grep -qF "${pingUuid}" "$work/out"; then fail "an unreachable ping: the URL was printed"; fi
        echo "ok: an unreachable ping fails the run without printing the URL"
      '';

      deadmanPingRehearsal =
        pkgs.runCommand "fleet-deadman-ping-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.python3
            ];
            meta.description = "behavioural check: the dead-man pings the external check only after a passing run with a heartbeat";
          }
          ''
            ${deadmanPingLegs} ${lib.getExe deadmanPinged}
            if ${deadmanPingLegs} ${deadmanPingFirst}/bin/fleet-deadman > first.log 2>&1; then
              cat first.log; echo "FAIL: the legs accepted a dead-man that pings before its probe" >&2; exit 1
            fi
            grep -qF "FAIL: a probe answered 200 pinged" first.log \
              || { cat first.log; echo "FAIL: deadmanPingFirst failed for another reason" >&2; exit 1; }
            echo "mutant deadmanPingFirst rejected"
            if ${deadmanPingLegs} ${lib.getExe deadmanPingAny200} > any200.log 2>&1; then
              cat any200.log; echo "FAIL: the legs accepted a ping step that accepts any 200" >&2; exit 1
            fi
            grep -qF "FAIL: an unknown check answered OK (not found) exited 0" any200.log \
              || { cat any200.log; echo "FAIL: pingAcceptsAny200 failed for another reason" >&2; exit 1; }
            echo "mutant pingAcceptsAny200 rejected"
            if ${deadmanPingLegs} ${deadmanPingNoHeartbeat}/bin/fleet-deadman > nohb.log 2>&1; then
              cat nohb.log; echo "FAIL: the legs accepted a dead-man that pings without a heartbeat" >&2; exit 1
            fi
            grep -qF "FAIL: an empty window pinged" nohb.log \
              || { cat nohb.log; echo "FAIL: deadmanPingNoHeartbeat failed for another reason" >&2; exit 1; }
            echo "mutant deadmanPingNoHeartbeat rejected"
            if ${deadmanPingLegs} ${deadmanPingBeforePosts}/bin/fleet-deadman > beforeposts.log 2>&1; then
              cat beforeposts.log; echo "FAIL: the legs accepted a dead-man that pings before its posts" >&2; exit 1
            fi
            grep -qF "FAIL: a failed post pinged" beforeposts.log \
              || { cat beforeposts.log; echo "FAIL: deadmanPingBeforePosts failed for another reason" >&2; exit 1; }
            echo "mutant deadmanPingBeforePosts rejected"
            if ${deadmanPingLegs} ${lib.getExe deadmanPingPrints} > prints.log 2>&1; then
              cat prints.log; echo "FAIL: the legs accepted a ping step that prints its configuration" >&2; exit 1
            fi
            grep -qF "FAIL: an unknown check: the URL was printed" prints.log \
              || { cat prints.log; echo "FAIL: pingPrintsConfig failed for another reason" >&2; exit 1; }
            echo "mutant pingPrintsConfig rejected"
            touch "$out"
          '';

      # A dead-man that pings before its probe: rejected by the probe legs.
      deadmanPingFirst = pkgs.runCommand "fleet-deadman-ping-first" { } ''
        mkdir -p "$out/bin"
        cp ${lib.getExe deadmanPinged} "$out/bin/fleet-deadman"
        chmod +w "$out/bin/fleet-deadman"
        substituteInPlace "$out/bin/fleet-deadman" \
          --replace-fail 'config="''${FLEET_DEADMAN_CONFIG:?}"' 'config="''${FLEET_DEADMAN_CONFIG:?}"; ${pingExe}'
      '';
      # A ping step that accepts any 200 body: rejected by the unknown-check leg.
      pingAcceptsAny200 = pkgs.runCommand "fleet-deadman-ping-any-200" { } ''
        mkdir -p "$out/bin"
        cp ${pingExe} "$out/bin/fleet-deadman-ping"
        chmod +w "$out/bin/fleet-deadman-ping"
        substituteInPlace "$out/bin/fleet-deadman-ping" \
          --replace-fail '[ "$answer" != OK ]' '[ -z "$answer" ]'
      '';
      deadmanPingAny200 = self.lib.fleetAlertDeadman pkgs {
        ntfySend = lib.getExe ntfySendStub;
        ping = "${pingAcceptsAny200}/bin/fleet-deadman-ping";
      };
      # A dead-man that pings without a heartbeat: rejected by the empty-window leg.
      deadmanPingNoHeartbeat = pkgs.runCommand "fleet-deadman-ping-no-heartbeat" { } ''
        mkdir -p "$out/bin"
        cp ${lib.getExe deadmanPinged} "$out/bin/fleet-deadman"
        chmod +w "$out/bin/fleet-deadman"
        substituteInPlace "$out/bin/fleet-deadman" \
          --replace-fail 'if [ "$heartbeats" -gt 0 ]; then' 'if true; then'
      '';
      # A dead-man that pings before its post loop: rejected by the failed-post
      # leg. The two replacements run in this order; a mutant that only inserts
      # an early ping is caught at the passing leg as a double ping instead.
      deadmanPingBeforePosts = pkgs.runCommand "fleet-deadman-ping-before-posts" { } ''
        mkdir -p "$out/bin"
        cp ${lib.getExe deadmanPinged} "$out/bin/fleet-deadman"
        chmod +w "$out/bin/fleet-deadman"
        substituteInPlace "$out/bin/fleet-deadman" \
          --replace-fail 'if [ "$heartbeats" -gt 0 ]; then' 'if false; then' \
          --replace-fail 'while IFS= read -r post; do' 'if [ "$heartbeats" -gt 0 ]; then ${pingExe}; fi; while IFS= read -r post; do'
      '';
      # A ping step whose failure line prints its configuration, and so the
      # URL: rejected by the unknown-check leg.
      pingPrintsConfig = pkgs.runCommand "fleet-deadman-ping-prints-config" { } ''
        mkdir -p "$out/bin"
        cp ${pingExe} "$out/bin/fleet-deadman-ping"
        chmod +w "$out/bin/fleet-deadman-ping"
        substituteInPlace "$out/bin/fleet-deadman-ping" \
          --replace-fail "expected OK\" >&2" "expected OK \$(cat \"\$config\")\" >&2"
      '';
      deadmanPingPrints = self.lib.fleetAlertDeadman pkgs {
        ntfySend = lib.getExe ntfySendStub;
        ping = "${pingPrintsConfig}/bin/fleet-deadman-ping";
      };

      # The ping URL reaches curl only on stdin (design D5): the step built
      # with a curl stub that records its argv and stdin and answers OK.
      recordingCurl = pkgs.writeShellScript "recording-curl" ''
        printf '%s\n' "$@" > "$REC/argv"
        cat > "$REC/stdin"
        printf OK
      '';
      pingRecorded = self.lib.fleetDeadmanPing pkgs { curl = "${recordingCurl}"; };
      pingOnArgv = pkgs.runCommand "fleet-deadman-ping-on-argv" { } ''
        mkdir -p "$out/bin"
        cp ${lib.getExe pingRecorded} "$out/bin/fleet-deadman-ping"
        chmod +w "$out/bin/fleet-deadman-ping"
        substituteInPlace "$out/bin/fleet-deadman-ping" \
          --replace-fail '-K - < "$config"' '"$(sed -n '"'"'s/^url = "\(.*\)"$/\1/p'"'"' "$config")" < /dev/null'
      '';
      pingTransportCases = pkgs.writeShellScript "fleet-deadman-ping-transport-cases" ''
        set -uo pipefail
        step="$1"
        work=$(mktemp -d)
        url="https://hc-ping.com/${pingUuid}"
        printf 'url = "%s"\n' "$url" > "$work/ping.conf"
        REC=$(mktemp -d)
        export REC
        out=$(FLEET_DEADMAN_PING_CONFIG="$work/ping.conf" "$step" 2>&1) || { echo "FAIL: exit $?: $out"; exit 1; }
        if grep -qF "$url" "$REC/argv"; then echo "FAIL: the URL is on curl's argv"; exit 1; fi
        cmp -s "$REC/stdin" "$work/ping.conf" || { echo "FAIL: stdin is not the configuration file"; exit 1; }
        [ "$out" = "fleet-deadman: external ping accepted" ] || { echo "FAIL: output: $out"; exit 1; }
        echo "ok: the URL on stdin and on no argv"
      '';
      pingTransport =
        pkgs.runCommand "fleet-deadman-ping-transport"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.gnugrep
              pkgs.gnused
            ];
          }
          ''
            ${pingTransportCases} ${lib.getExe pingRecorded}
            if ${pingTransportCases} ${pingOnArgv}/bin/fleet-deadman-ping > mutant.log 2>&1; then
              cat mutant.log
              echo "FAIL: the mutant passing the URL on argv was accepted" >&2
              exit 1
            fi
            grep -qF "FAIL: the URL is on curl's argv" mutant.log \
              || { cat mutant.log; echo "FAIL: the argv mutant failed for another reason" >&2; exit 1; }
            echo "mutant passing the URL on argv rejected"
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
              }) attributedHosts
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
      # `error` replaces every answer with that HTTP status. The reporting
      # hosts are the fleet's always-on hosts, stated here independently of
      # the rules' `alwaysOn`, and the step's `reporting`, less its `silent`.
      alwaysOnHosts = [
        "magnetite"
        "cinnabar"
      ];
      stepAnswers =
        rulesList: step:
        let
          reporting = lib.subtractLists (step.silent or [ ]) (
            lib.unique (alwaysOnHosts ++ step.reporting or [ ])
          );
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
            // lib.foldl' (acc: host: acc // attributionAnswers step.at host) { } attributedHosts;
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
      # The hosts a fixture leg may report a memory rule firing on, each of
      # whose attribution queries the fixture answers.
      attributedHosts = both ++ [ "pyrite" ];

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
                platform = "nixos";
                alwaysOn = true;
                notifiedUnits = [ "unit-a" ];
                smartDevices = [ ];
              };
              b = {
                collect = true;
                platform = "nixos";
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
      # The always-on hosts' collectors stop exporting while the store answers
      # (S3 review F1): node_vmstat_oom_kill's gap raises nothing, because no
      # expected host reports, but magnetite and cinnabar are always-on, so
      # each one's own silence raises RuleSignalMissing 10 min after it last
      # reported.
      alwaysOnSilentLeg = {
        name = "magnetite and cinnabar silent for 40 min while the store answers raise RuleSignalMissing for each 10 min after they last reported, none for node_vmstat_oom_kill, and resolve when they report again";
        steps =
          map (n: { at = gap n; }) (lib.range 0 1)
          ++ map (n: {
            at = gap n;
            silent = alwaysOnHosts;
            missing = [ "node_vmstat_oom_kill" ];
          }) (lib.range 2 9)
          ++ map (n: { at = gap n; }) (lib.range 10 11);
        expect = [
          "3 [FIRING] RuleSignalMissing cinnabar default"
          "3 [FIRING] RuleSignalMissing magnetite default"
          "10 [RESOLVED] RuleSignalMissing cinnabar default"
          "10 [RESOLVED] RuleSignalMissing magnetite default"
        ];
        messages = [ "selector=system_memory_usage_bytes" ];
      };

      # design D9: the rules read their expected and always-on hosts from
      # flake.lib.observabilityHosts. The legs about pyrite render the real
      # table with its `collect` set each way, so they hold whatever pyrite's
      # row says.
      tableWith =
        pyrite:
        builtins.fromJSON
          (self.lib.fleetAlertRules {
            inherit lib;
            hosts = hosts // {
              pyrite = hosts.pyrite // pyrite;
            };
          }).json;
      pyriteRules = tableWith { collect = true; };
      pyriteConfig = checkConfig pyriteRules;
      # pyrite also always-on, so the leg judges both halves of the filter.
      notCollectingRules = tableWith {
        collect = false;
        alwaysOn = true;
      };
      notCollectingConfig = checkConfig notCollectingRules;
      # The stored names of the NVMe series, which the rules' presence
      # selectors must equal for the legs below to see them missing.
      smartSelectors = map (alert: fixtures.series.${alert}.__name__) [
        "NvmeCriticalWarning"
        "NvmeWearHigh"
      ];

      # cinnabar is always-on (FAI `An always-on host's silence is
      # reported`): silent from 10 min to 50 min while magnetite reports.
      cinnabarSilentLeg = {
        name = "cinnabar silent for 40 min while magnetite reports raises RuleSignalMissing cinnabar 10 min after it last reported, and resolves when it reports again";
        steps =
          map (n: { at = gap n; }) (lib.range 0 1)
          ++ map (n: {
            at = gap n;
            silent = [ "cinnabar" ];
          }) (lib.range 2 9)
          ++ map (n: { at = gap n; }) (lib.range 10 11);
        expect = [
          "3 [FIRING] RuleSignalMissing cinnabar default"
          "10 [RESOLVED] RuleSignalMissing cinnabar default"
        ];
        messages = [ "selector=system_memory_usage_bytes" ];
      };

      # Laptops are not always-on: pyrite, with HostOOMKill firing, and
      # electrum fall silent for 40 min while magnetite and cinnabar report.
      laptopSilentLeg = {
        name = "pyrite, with HostOOMKill firing, and electrum silent for 40 min post nothing after the FIRING: no silence, no resolution, no repeat";
        rules = pyriteRules;
        steps = [
          {
            at = gap 0;
            reporting = [
              "pyrite"
              "electrum"
            ];
            series.HostOOMKill = [ (seriesOn "pyrite" "HostOOMKill") ];
          }
        ]
        ++ map (n: { at = gap n; }) (lib.range 1 8);
        expect = [ "0 [FIRING] HostOOMKill pyrite high" ];
      };

      # The NVMe rules expect only the hosts with SMART devices: no SMART
      # series is missing while pyrite is silent, and both are once it
      # reports host memory for their 30 min.
      nvmeExpectsPyriteLeg = {
        name = "no SMART series for 30 min posts nothing while pyrite is silent, then one RuleSignalMissing for each NVMe rule 30 min after pyrite reports";
        rules = pyriteRules;
        steps =
          map (n: {
            at = gap n;
            missing = smartSelectors;
          }) (lib.range 0 6)
          ++ map (n: {
            at = gap n;
            reporting = [ "pyrite" ];
            missing = smartSelectors;
          }) (lib.range 7 13);
        expect = [
          "13 [FIRING] RuleSignalMissing default"
          "13 [FIRING] RuleSignalMissing default"
        ];
        messages = [
          "rule=NvmeCriticalWarning"
          "rule=NvmeWearHigh"
        ];
      };

      # A host whose collect is false is neither expected nor always-on:
      # pyrite, collect false and alwaysOn true, reports host memory with
      # no SMART series for 35 min, then is silent for 40 min.
      notCollectingLeg = {
        name = "pyrite, not collecting, reporting without SMART series for 35 min and then silent for 40 min posts nothing";
        rules = notCollectingRules;
        steps =
          map (n: {
            at = gap n;
            reporting = [ "pyrite" ];
            missing = smartSelectors;
          }) (lib.range 0 7)
          ++ map (n: {
            at = gap n;
            missing = smartSelectors;
          }) (lib.range 8 15);
        expect = [ ];
      };

      # cinnabar's / is above 85 % from minute 0 and above 95 % from minute
      # 15: each rule fires after its own `for`, at its own priority.
      filesystemLeg = {
        name = "cinnabar's / above 85 % for 15 min fires FilesystemFillingWarn at default, then above 95 % for 5 min fires FilesystemFull at high";
        steps = map (n: {
          at = minute n;
          series = {
            FilesystemFillingWarn = [ (seriesOn "cinnabar" "FilesystemFillingWarn") ];
          }
          // lib.optionalAttrs (n >= 15) { FilesystemFull = [ (seriesOn "cinnabar" "FilesystemFull") ]; };
        }) (lib.range 0 20);
        expect = [
          "15 [FIRING] FilesystemFillingWarn cinnabar default"
          "20 [FIRING] FilesystemFull cinnabar high"
        ];
      };

      nvmeLeg = {
        name = "pyrite's NVMe critical warning on one run fires NvmeCriticalWarning pyrite at once at high";
        rules = pyriteRules;
        steps = [
          {
            at = minute 0;
            reporting = [ "pyrite" ];
            series.NvmeCriticalWarning = [ (seriesOn "pyrite" "NvmeCriticalWarning") ];
          }
        ]
        ++ map (n: {
          at = minute n;
          reporting = [ "pyrite" ];
        }) (lib.range 1 2);
        expect = [ "0 [FIRING] NvmeCriticalWarning pyrite high" ];
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

      # Store errors and silent hosts freeze instance state: a time-relative
      # rule's pending instance across a freeze, over the rendered
      # HostProbeStale. Value sources: the step-indexed posts typed in each
      # leg from the requirement's scenarios, against the evaluator's posts
      # over the fixture server.
      stale = [ fixtures.series.HostProbeStale ];
      # stibnite reports from minute 0 to 5, its probe stale from its last
      # sample at 5; silent from 10 to 125 (24 runs 5 min apart), the store
      # answering its last sample at 10 only; then reports from 126 with the
      # condition as `wake` gives it.
      freezeTimeline =
        wake:
        map (n: {
          at = minute n;
          reporting = [ "stibnite" ];
          series = lib.optionalAttrs (n == 5) { HostProbeStale = stale; };
        }) (lib.range 0 5)
        ++ map (n: {
          at = minute (10 + 5 * n);
          series = lib.optionalAttrs (n == 0) { HostProbeStale = stale; };
        }) (lib.range 0 23)
        ++ map (n: {
          at = minute n;
          reporting = [ "stibnite" ];
          series = lib.optionalAttrs (wake n) { HostProbeStale = stale; };
        }) (lib.range 126 140);
      pendingAcrossFreeze = {
        name = "pendingAcrossFreeze: HostProbeStale true at stibnite's last sample, 2 h silent, then true for 2 runs after wake and false after posts nothing";
        steps = freezeTimeline (n: n <= 127);
        expect = [ ];
      };
      pendingAfterWake = {
        name = "pendingAfterWake: HostProbeStale true for 11 min after stibnite wakes fires once, 10 min after wake";
        steps = freezeTimeline (n: n <= 137);
        # Step 40 is minute 136: 6 runs before the silence, 24 silent, then 126 + 10.
        expect = [ "40 [FIRING] HostProbeStale stibnite default" ];
      };

      # Expected hosts by platform. Value sources: the Linux-only selectors
      # typed here from the design's applicability table, against the
      # presence selectors and expected hosts the rules render from a host
      # table in which stibnite collects. magnetite and cinnabar are not
      # marked always-on, so their silence, which leaves stibnite the only
      # reporting host, raises nothing of its own.
      linuxSelectors = [
        "system_linux_memory_available_bytes"
        "system_paging_usage_bytes"
        "node_zfs_arc_size"
        "node_zfs_zpool_state"
        "node_vmstat_oom_kill"
        "systemd_unit_state"
        "systemd_service_restarts_total"
      ];
      onlyStibniteTable =
        stibnite:
        hosts
        // {
          stibnite = hosts.stibnite // stibnite;
          magnetite = hosts.magnetite // {
            alwaysOn = false;
          };
          cinnabar = hosts.cinnabar // {
            alwaysOn = false;
          };
        };
      onlyStibniteRules =
        stibnite:
        builtins.fromJSON
          (self.lib.fleetAlertRules {
            inherit lib;
            hosts = onlyStibniteTable stibnite;
          }).json;
      stibniteOnlySteps =
        missing:
        map (n: {
          at = gap n;
          reporting = [ "stibnite" ];
          silent = alwaysOnHosts;
          inherit missing;
        }) (lib.range 0 7);
      linuxSelectorDarwinOnly = {
        name = "linuxSelectorDarwinOnly: stibnite, the only host reporting, with every Linux-only selector absent for 35 min, raises nothing";
        rules = onlyStibniteRules { collect = true; };
        steps = stibniteOnlySteps linuxSelectors;
        expect = [ ];
      };
      stibniteNotCollecting = {
        name = "stibniteNotCollecting: stibnite, not collecting and the only host reporting, with every selector but host memory absent for 35 min, raises nothing";
        # Explicit, so the leg holds whatever stibnite's row says.
        rules = onlyStibniteRules { collect = false; };
        steps = stibniteOnlySteps (lib.remove "system_memory_usage_bytes" selectors);
        expect = [ ];
      };

      # The darwin rules (design D9). Value sources: the rendered rule table,
      # in which stibnite collects on darwin, against the fixture's replayed
      # store answers, whose label sets and selector names are stibnite's as
      # stored (fixtures `series` and `selectors`). Each leg states its
      # condition as the steps on which the store answers the rule's
      # expression with a label set; stibnite reports host memory on each
      # step unless the leg says otherwise, so its instances are not frozen.
      darwinSeries = alert: extra: fixtures.series.${alert} // extra;
      onStibnite = step: { reporting = [ "stibnite" ]; } // step;
      # LaunchdJobFailed's arms as a rule list renders them: `excluded`, the
      # exclusion of the arm that judges a job by its last exit alone, and
      # `relaunched`, null when the expression has no second arm, else the
      # kept-alive regex, the notified exclusion and the window in minutes of
      # the arm that judges a kept-alive job only while its launch count rose
      # within that window. A rendered expression of another shape fails the
      # evaluation.
      failedArms =
        rulesList:
        let
          rule = lib.findFirst (
            r: r.alert == "LaunchdJobFailed"
          ) (throw "fleet-alert check: no LaunchdJobFailed rule") rulesList;
          m = builtins.match ''launchd_job_last_exit_code[{]launchd_label!~"([^"]*)"[}] != 0( or [(]launchd_job_last_exit_code[{]launchd_label=~"([^"]*)", launchd_label!~"([^"]*)"[}] != 0 and on [(]host_name, launchd_label[)] increase[(]launchd_job_runs_total[[]([0-9]+)m[]][)] > 0[)])?'' rule.expr;
        in
        if m == null then
          throw "fleet-alert check: LaunchdJobFailed's expression has an unmodelled shape: ${rule.expr}"
        else
          {
            excluded = builtins.elemAt m 0;
            relaunched =
              if builtins.elemAt m 1 == null then
                null
              else
                {
                  kept = builtins.elemAt m 2;
                  notified = builtins.elemAt m 3;
                  window = lib.toInt (builtins.elemAt m 4);
                };
          };
      # The store's answer to that expression at minute n over the probe's
      # series of some jobs, each { label; exit; launchedAt ? null; }, the
      # minute its launch count last rose: each arm selects with the
      # full-match semantics PromQL uses for `=~` and `!~`, the launch count
      # rose within the window when the launch is less than the window before
      # n, and the answer is the arms' union.
      failedAnswer =
        rulesList: n: jobs:
        let
          arms = failedArms rulesList;
          matches = re: label: builtins.match re label != null;
          launchedWithin =
            window: job: (job.launchedAt or null) != null && n >= job.launchedAt && n - job.launchedAt < window;
          judged =
            job:
            job.exit != 0
            && (
              !matches arms.excluded job.label
              || (
                arms.relaunched != null
                && matches arms.relaunched.kept job.label
                && !matches arms.relaunched.notified job.label
                && launchedWithin arms.relaunched.window job
              )
            );
        in
        map (job: darwinSeries "LaunchdJobFailed" { launchd_label = job.label; }) (
          builtins.filter judged jobs
        );
      failedOn =
        label:
        failedAnswer evaluatorRules 0 [
          {
            inherit label;
            exit = 1;
          }
        ];

      darwinSignalMissing = {
        name = "darwinSignalMissing: stibnite reporting host memory with no launchd_job_state for 30 min, the other launchd selectors present, raises one RuleSignalMissing for LaunchdJobNotRunning";
        steps = map (
          n:
          onStibnite {
            at = gap n;
            missing = [ fixtures.selectors.LaunchdJobNotRunning ];
          }
        ) (lib.range 0 7);
        expect = [ "6 [FIRING] RuleSignalMissing default" ];
        messages = [
          "rule=LaunchdJobNotRunning"
          "selector=${fixtures.selectors.LaunchdJobNotRunning}"
        ];
      };
      # The probe's four launchd_job_state series for one label in one state
      # (modules/lib/otel-host-probe.nix), each label set with its value.
      probeStates =
        label: state:
        map
          (s: {
            labels = darwinSeries "LaunchdJobNotRunning" {
              launchd_label = label;
              launchd_state = s;
            };
            value = if s == state then 1 else 0;
          })
          [
            "running"
            "not_running"
            "unloaded"
            "other"
          ];
      # LaunchdJobNotRunning's two arms as a rule list renders them: the
      # kept-alive regex of the running arm and the exclusion of the unloaded
      # arm, null if it has none. A rendered expression of another shape
      # fails the evaluation.
      notRunningArms =
        rulesList:
        let
          rule = lib.findFirst (
            r: r.alert == "LaunchdJobNotRunning"
          ) (throw "fleet-alert check: no LaunchdJobNotRunning rule") rulesList;
          m = builtins.match ''launchd_job_state[{]launchd_state="running", launchd_label=~"([^"]*)"[}] == 0 or launchd_job_state[{]launchd_state="unloaded"(, launchd_label!~"([^"]*)")?[}] == 1'' rule.expr;
        in
        if m == null then
          throw "fleet-alert check: LaunchdJobNotRunning's expression has an unmodelled shape: ${rule.expr}"
        else
          {
            kept = builtins.elemAt m 0;
            excluded = builtins.elemAt m 2;
          };
      # The store's answer to that expression over the probe's series: each
      # arm selects with the full-match semantics PromQL uses for `=~` and
      # `!~`, and the answer is their union, the arms' label sets differing
      # in launchd_state.
      notRunningAnswer =
        rulesList: series:
        let
          arms = notRunningArms rulesList;
          runningArm =
            s:
            s.labels.launchd_state == "running"
            && builtins.match arms.kept s.labels.launchd_label != null
            && s.value == 0;
          unloadedArm =
            s:
            s.labels.launchd_state == "unloaded"
            && (arms.excluded == null || builtins.match arms.excluded s.labels.launchd_label == null)
            && s.value == 1;
        in
        map (s: s.labels) (builtins.filter (s: runningArm s || unloadedArm s) series);
      # The answer on minutes 0 to 14 and none after: one FIRING at 10, one
      # RESOLVED 5 min after it was last seen at 14.
      notRunningFor15 = rulesList: label: state: {
        rules = rulesList;
        steps = map (
          n:
          onStibnite {
            at = minute n;
            series = lib.optionalAttrs (n <= 14) {
              LaunchdJobNotRunning = notRunningAnswer rulesList (probeStates label state);
            };
          }
        ) (lib.range 0 20);
        expect = [
          "10 [FIRING] LaunchdJobNotRunning stibnite default"
          "19 [RESOLVED] LaunchdJobNotRunning stibnite default"
        ];
      };
      keptAliveStopped = notRunningFor15 evaluatorRules "org.nixos.nix-grpc-daemon" "not_running" // {
        name = "keptAliveStopped: nix-grpc-daemon not running for 15 min fires one LaunchdJobNotRunning stibnite after 10 min and resolves once";
      };
      # 8.3's bootout: a kept-alive label unloaded has running 0 and unloaded
      # 1, which must make one instance, not one per arm.
      keptAliveUnloaded =
        rulesList:
        notRunningFor15 rulesList "org.nixos.nix-grpc-daemon" "unloaded"
        // {
          name = "keptAliveUnloaded: nix-grpc-daemon unloaded for 15 min, its running 0 and unloaded 1 both written, fires one LaunchdJobNotRunning stibnite after 10 min and resolves once";
        };
      envelopeUnloaded = notRunningFor15 evaluatorRules "org.nixos.otel-envelope" "unloaded" // {
        name = "envelopeUnloaded: otel-envelope, not kept alive, unloaded for 15 min fires one LaunchdJobNotRunning stibnite after 10 min and resolves once";
      };
      envelopeFailedNotReported = {
        name = "envelopeFailedNotReported: otel-envelope's non-zero exit for 15 min, which the rendered exclusion removes, posts no LaunchdJobFailed";
        steps = map (
          n:
          onStibnite {
            at = minute n;
            series.LaunchdJobFailed = failedOn "org.nixos.otel-envelope";
          }
        ) (lib.range 0 15);
        expect = [ ];
      };
      harmoniaFailedReported = {
        name = "harmoniaFailedReported: harmonia-gc's non-zero exit for 15 min fires one LaunchdJobFailed stibnite after 5 min and nothing more";
        steps = map (
          n:
          onStibnite {
            at = minute n;
            series.LaunchdJobFailed = failedOn "org.nixos.harmonia-gc";
          }
        ) (lib.range 0 15);
        expect = [ "5 [FIRING] LaunchdJobFailed stibnite default" ];
      };
      # One job whose last exit is `exit` from minute 0, its launch count
      # last rising at minute 0, answered on minutes 0 to `last`.
      failedSinceLaunch = rulesList: label: exit: last: {
        rules = rulesList;
        steps = map (
          n:
          onStibnite {
            at = minute n;
            series.LaunchdJobFailed = failedAnswer rulesList n [
              {
                inherit label exit;
                launchedAt = 0;
              }
            ];
          }
        ) (lib.range 0 last);
      };
      # The nix-daemon abort of 2026-11-08: launchd relaunched the job, which
      # runs, and kept its abnormal exit as the last one.
      keptAliveRestarted =
        rulesList:
        failedSinceLaunch rulesList "org.nixos.nix-daemon" (-1) 40
        // {
          name = "keptAliveRestarted: nix-daemon relaunched at minute 0 after an abnormal exit, running since with its last exit still -1, fires one LaunchdJobFailed stibnite at 5 and resolves once at 34, 30 min after its launch and 5 min after it was last seen";
          expect = [
            "5 [FIRING] LaunchdJobFailed stibnite default"
            "34 [RESOLVED] LaunchdJobFailed stibnite default"
          ];
        };
      keptAliveCrashed = failedSinceLaunch evaluatorRules "org.nixos.otelcol-process" (-1) 10 // {
        name = "keptAliveCrashed: otelcol-process relaunched at minute 0 after a SIGKILL, its last exit -1 for 10 min, fires one LaunchdJobFailed stibnite at 5";
        expect = [ "5 [FIRING] LaunchdJobFailed stibnite default" ];
      };
      notKeptAliveHeld = failedSinceLaunch evaluatorRules "org.nixos.harmonia-gc" 1 40 // {
        name = "notKeptAliveHeld: harmonia-gc, not kept alive, launched at minute 0 and exiting 1, fires one LaunchdJobFailed stibnite at 5 and stays firing through minute 40";
        expect = [ "5 [FIRING] LaunchdJobFailed stibnite default" ];
      };
      # nix-grpc-daemon relaunched once a minute from minute -3, so its
      # 15 min increase exceeds 5 on minutes 3 to 7, after which it stays up.
      restartLoop = {
        name = "restartLoop: nix-grpc-daemon's 15 min launch increase above 5 on minutes 3 to 7 fires one LaunchdJobRestartLoop stibnite at 3 and resolves once at 12";
        steps = map (
          n:
          onStibnite {
            at = minute n;
            series = lib.optionalAttrs (n >= 3 && n <= 7) {
              LaunchdJobRestartLoop = [ (darwinSeries "LaunchdJobRestartLoop" { }) ];
            };
          }
        ) (lib.range 0 14);
        expect = [
          "3 [FIRING] LaunchdJobRestartLoop stibnite default"
          "12 [RESOLVED] LaunchdJobRestartLoop stibnite default"
        ];
      };
      probeStaleLeg = {
        name = "probeStale: launchd.prom stale for 20 min while stibnite reports fires one HostProbeStale stibnite 10 min after the first stale run";
        steps = map (
          n:
          onStibnite {
            at = minute n;
            series.HostProbeStale = [ (darwinSeries "HostProbeStale" { }) ];
          }
        ) (lib.range 0 19);
        expect = [ "10 [FIRING] HostProbeStale stibnite default" ];
      };
      nvmeExpectsStibnite = {
        name = "nvmeExpectsStibnite: stibnite reporting host memory with no SMART series for 30 min while pyrite is silent raises one RuleSignalMissing for each NVMe rule";
        steps = map (
          n:
          onStibnite {
            at = gap n;
            silent = [ "pyrite" ];
            missing = smartSelectors;
          }
        ) (lib.range 0 6);
        expect = [
          "6 [FIRING] RuleSignalMissing default"
          "6 [FIRING] RuleSignalMissing default"
        ];
        messages = [
          "rule=NvmeCriticalWarning"
          "rule=NvmeWearHigh"
        ];
      };
      # The darwin counterpart of laptopSilentLeg: harmonia-gc's failure
      # fires at 5, then stibnite is silent from 10 to 45 while the store
      # still answers the label set.
      stibniteSilent = {
        name = "stibniteSilent: stibnite silent for 40 min with LaunchdJobFailed firing posts nothing after the FIRING: no silence, no resolution, no repeat";
        steps =
          map (
            n:
            onStibnite {
              at = minute n;
              series.LaunchdJobFailed = failedOn "org.nixos.harmonia-gc";
            }
          ) (lib.range 0 5)
          ++ map (n: {
            at = minute (10 + 5 * n);
            silent = [ "stibnite" ];
            series.LaunchdJobFailed = failedOn "org.nixos.harmonia-gc";
          }) (lib.range 0 7);
        expect = [ "5 [FIRING] LaunchdJobFailed stibnite default" ];
      };
      darwinLegs = [
        darwinSignalMissing
        keptAliveStopped
        (keptAliveUnloaded evaluatorRules)
        envelopeUnloaded
        envelopeFailedNotReported
        harmoniaFailedReported
        (keptAliveRestarted evaluatorRules)
        keptAliveCrashed
        notKeptAliveHeld
        restartLoop
        probeStaleLeg
        nvmeExpectsStibnite
        stibniteSilent
      ];

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
          cinnabarSilentLeg
          filesystemLeg
          windowLeg
          budgetFleetLeg
          budgetLaptopLeg
          budgetFailedLogLeg
          budgetOldLogLeg
          unreadableLogLeg
          retryLeg
          burnRuleLeg
          devloopFailureLeg
          pendingAcrossFreeze
          pendingAfterWake
        ]
        ++ darwinLegs;

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
        alwaysOnMagnetiteOnly = {
          evaluator = realEvaluator;
          config = checkConfig (
            map (
              r: if r.alert == "RuleSignalMissing" then r // { alwaysOn = [ "magnetite" ]; } else r
            ) evaluatorRules
          );
          legs = [ cinnabarSilentLeg ];
        };
        # 8.3's defect restored: the unloaded arm without its kept-alive
        # exclusion answers a booted-out kept-alive label twice.
        notRunningBothArms =
          let
            rulesList = map (
              r:
              if r.alert == "LaunchdJobNotRunning" then
                r
                // {
                  expr =
                    mutateText "notRunningBothArms" '', launchd_label!~"${(notRunningArms evaluatorRules).excluded}"''
                      ""
                      r.expr;
                }
              else
                r
            ) evaluatorRules;
          in
          {
            evaluator = realEvaluator;
            config = checkConfig rulesList;
            legs = [ (keptAliveUnloaded rulesList) ];
          };
        # CAM-92's defect restored: a kept-alive job's abnormal last exit
        # counted for as long as the relaunched job runs.
        failedIgnoresLaunch =
          let
            rulesList = map (
              r:
              if r.alert == "LaunchdJobFailed" then
                r
                // {
                  expr = ''launchd_job_last_exit_code{launchd_label!~"${(failedArms evaluatorRules).relaunched.notified}"} != 0'';
                }
              else
                r
            ) evaluatorRules;
          in
          {
            evaluator = realEvaluator;
            config = checkConfig rulesList;
            legs = [ (keptAliveRestarted rulesList) ];
          };
      };

      # A mutant passes only when its legs record a miss.
      mutantCheck =
        name: mutant:
        fixtureCheck "mutant-${name}" (runsOf mutant.legs) "R9.2: the runtime mutant ${name} fails a leg" ''
          echo "=== mutant ${name}"
          ${lib.concatMapStrings (runLeg {
            evaluator = lib.getExe mutant.evaluator;
            inherit (mutant) config;
          }) mutant.legs}
          if [ -s "$misses" ]; then
            echo "mutant ${name} rejected: $(head -n 1 "$misses")"
          else
            echo "FAIL: mutant ${name} produced no failure" >&2
            exit 1
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

      # Each leg, each mutant and the server's controls is its own
      # derivation, so they build in parallel and cache apart: a leg's runs
      # are sequential, and each run spawns some hundred jq and curl
      # processes, about a second, so one derivation holding all of them
      # took over 12 min. `runs`, in passthru, is the number of evaluator
      # runs the derivation performs, which the work budget below bounds.
      fixtureCheck =
        id: runs: description: body:
        pkgs.runCommand "fleet-alert-fixtures-${id}"
          {
            passthru = { inherit runs; };
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.diffutils
              pkgs.gnugrep
              pkgs.jq
              pkgs.python3
            ];
            meta.description = description;
          }
          ''
            set -euo pipefail
            server_pid=
            trap '[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true' EXIT
            misses="$TMPDIR/misses"
            : > "$misses"
            miss() {
              printf 'MISS %s\n' "$*" >&2
              printf '%s\n' "$*" >> "$misses"
            }
            ${body}
            touch "$out"
          '';
      # A leg's derivation name is its name's alphanumeric words.
      legId =
        leg:
        builtins.substring 0 100 (
          lib.concatStringsSep "-" (
            lib.filter (w: builtins.isString w && w != "") (builtins.split "[^A-Za-z0-9]+" leg.name)
          )
        );
      runsOf = lib.foldl' (n: leg: n + lib.length leg.steps) 0;
      legCheck =
        config: leg:
        lib.nameValuePair (legId leg) (
          fixtureCheck (legId leg) (runsOf [ leg ]) "R9.2: ${leg.name}" ''
            ${runLeg {
              evaluator = lib.getExe realEvaluator;
              inherit config;
            } leg}
            if [ -s "$misses" ]; then
              echo "FAIL: the evaluator failed this leg:" >&2
              cat "$misses" >&2
              exit 1
            fi
            echo "ok: the leg passed"
          ''
        );
      legChecks =
        map (legCheck realConfig) legs
        ++ [
          (legCheck twoDatabaseConfig twoDatabaseLeg)
          (legCheck twoHostConfig twoHostExclusionLeg)
        ]
        ++ map (legCheck pyriteConfig) [
          laptopSilentLeg
          nvmeExpectsPyriteLeg
          nvmeLeg
        ]
        ++ [
          (legCheck notCollectingConfig notCollectingLeg)
          (legCheck (checkConfig linuxSelectorDarwinOnly.rules) linuxSelectorDarwinOnly)
          (legCheck (checkConfig stibniteNotCollecting.rules) stibniteNotCollecting)
        ];
      # The work budget, in evaluator runs, checked at evaluation: no
      # derivation may run more than maxFixtureRuns, nor all of them more
      # than fixtureRunBudget. Measured on magnetite (16 vCPU) on
      # 2026-11-08, building these derivations 8 at a time, a run took
      # 1.35 s in the longest leg (70 runs, 95 s) and 1.44 s on average
      # (808 runs, 1164 s of work); with nixbot building beside them it
      # took up to 2.5 s. A leg's runs are sequential, so 75 runs keep a
      # derivation near 100 s; 1000 runs in all is about 24 min of work,
      # about 1.5 min on 16 cores, so the longest leg stays the bound.
      maxFixtureRuns = 75;
      fixtureRunBudget = 1000;
      fixtureParts =
        let
          byLeg = lib.listToAttrs legChecks;
          parts = {
            controls = fixtureCheck "controls" 0 "R9.2: the fixture server's own clauses" serverControls;
          }
          // byLeg
          // lib.mapAttrs' (
            name: mutant: lib.nameValuePair "mutant-${name}" (mutantCheck name mutant)
          ) runtimeMutants;
          over = lib.filterAttrs (_: part: part.runs > maxFixtureRuns) parts;
          total = lib.foldl' (n: part: n + part.runs) 0 (lib.attrValues parts);
        in
        assert lib.assertMsg (
          lib.length (lib.attrNames byLeg) == lib.length legChecks
        ) "fleet-alert check: two fixture legs share a derivation name";
        assert lib.assertMsg (over == { }) (
          "fleet-alert check: fixture derivations over the work budget of ${toString maxFixtureRuns} evaluator runs each: "
          + lib.concatStringsSep ", " (
            lib.mapAttrsToList (name: part: "${name} (${toString part.runs})") over
          )
        );
        assert lib.assertMsg (total <= fixtureRunBudget)
          "fleet-alert check: the fixture derivations run the evaluator ${toString total} times, over the budget of ${toString fixtureRunBudget}";
        parts;
      fixtureRehearsal =
        pkgs.runCommand "fleet-alert-fixtures"
          {
            passthru = fixtureParts;
            meta.description = "R9.2: the evaluator against a replaying fixture server; every leg passes and every runtime mutant fails a leg";
          }
          ''
            ${lib.concatMapStrings (part: ''
              test -e ${part}
            '') (lib.attrValues fixtureParts)}
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
                  deadmanPingRehearsal
                  pingTransport
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
              test -e ${deadmanPingRehearsal}
              test -e ${pingTransport}
              test -e ${deadmanClause}
              touch "$out"
            '';
      };
    };
}
