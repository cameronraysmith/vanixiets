### Task 2: The ping step, the dead-man and R9.6

Implements `tasks.md` 2.1–2.5 (design D2, D4, D5, D7, D8; FAI `The dead-man pings the watch service only after a passing run`, `The ping URL travels only as a credential read on stdin`, `The rule check runs promtool, fixture mutants and a property test`; FA `An outage of the alert path reaches the operator by email from outside the fleet`).
This is the first part of pull request 1.
The legs (Step 1) and the transport test (Step 2) are written first and seen failing; the ping step (Step 3) and the dead-man's call (Step 4) make them pass; the option and its assertion follow (Step 5).
No host sets the option in this task, so no deployed configuration changes.

**Files:**
- Create: `modules/checks/fleet-alert/ping_stub.py`
- Modify: `modules/nixos/fleet-alert.nix` (`fleetAlertDeadman`, `:447-535`; `flake.lib`, `:538-540`; the module's `let`, `:622-630`; `options.services.fleet-alert.deadman`, `:690-711`; the dead-man's `config`, `:782-843`)
- Modify: `modules/checks/fleet-alert.nix` (after `deadmanRehearsal`, `:296-319`; the check's `passthru` and build, `:1560-1582`)
- Create (git-ignored): `logs/cam76-evidence/2.<n>-*.log`

**Interfaces:**
- Consumes: `self.lib.fleetAlertDeadman`, `self.lib.fleetAlertDeadmanConfig`, `ntfySendStub`, `fixtureCredentials` and `modules/checks/fleet-alert/ntfy_stub.py` as S3 left them (`modules/checks/fleet-alert.nix:121-175`).
- Produces: `flake.lib.fleetDeadmanPing`, the `ping` argument of `flake.lib.fleetAlertDeadman`, the option `services.fleet-alert.deadman.pingConfigFile`, and the check parts `deadmanPingRehearsal` and `pingTransport`, all as named in plan "Interface contract"; Task 3 sets the option on cinnabar.

- [ ] **Step 1: The ping stand-in and the R9.6 legs, seen failing (tasks.md 2.1)**

Create `modules/checks/fleet-alert/ping_stub.py`:

```python
"""Loopback stand-in for healthchecks.io's Pinging API, for the dead-man's
external-ping legs of checks.x86_64-linux.fleet-alert (CAM-76, design D7).

Every request, whatever its method or path, is answered 200 with the --answer
body, as healthchecks.io answers 200 with "OK", "OK (not found)" or
"OK (rate limited)" (https://healthchecks.io/docs/http_api/). Each request is
appended to --log as "<METHOD> <path> body=<bytes>".
"""

import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("--answer", required=True)
parser.add_argument("--port-file", required=True)
parser.add_argument("--log", required=True)
args = parser.parse_args()


class Handler(BaseHTTPRequestHandler):
    def handle_any(self):
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        with open(args.log, "a") as log:
            log.write(f"{self.command} {self.path} body={length}\n")
        data = args.answer.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    do_GET = do_POST = do_HEAD = handle_any

    def log_message(self, *_):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(args.port_file, "w") as port_file:
    port_file.write(str(server.server_port))
server.serve_forever()
```

In `modules/checks/fleet-alert.nix`, after `deadmanRehearsal`, add:

```nix
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
          sed 's/^/  ping: /' "$work/pings" >&2 || true
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
        # run PROBE|closed POLL_STATUS POLL_BODY NOW [POST_STATUS] [ANSWER]:
        # one dead-man run with its ping; exit status in $code.
        run() {
          local url
          : > "$work/requests"
          : > "$work/pings"
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
          python3 ${./fleet-alert/ping_stub.py} --answer "''${6:-OK}" --port-file "$work/ping-port" --log "$work/pings" &
          pids+=($!)
          wait_port "$work/ping-port"
          printf 'url = "http://127.0.0.1:%s/${pingUuid}"\n' "$(cat "$work/ping-port")" > "$work/ping.conf"
          jq --arg url "$url" --arg state "$work/state.json" '.ntfyUrl = $url | .stateFile = $state' \
            ${deadmanConfigFile} > "$work/config.json"
          code=0
          FLEET_DEADMAN_CONFIG="$work/config.json" FLEET_DEADMAN_PING_CONFIG="$work/ping.conf" \
            FLEET_ALERT_NOW="$4" FLEET_ALERT_POST_STATUS="''${5:-0}" \
            "$deadman" > "$work/out" 2>&1 || code=$?
          stop_stubs
          sed 's/^/    /' "$work/out"
        }
        pings() { grep -c . "$work/pings" || true; }

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
        [ "$(cat "$work/pings")" = "GET /${pingUuid} body=0" ] || fail "a passing run pinged another path or with a body"
        grep -qxF "fleet-deadman: external ping accepted" "$work/out" || fail "a passing run: no accepted line"
        echo "ok: a passing run with a heartbeat pings once"

        reset
        run 403 200 "$empty" 1000
        [ "$code" = 0 ] || fail "an empty window: exit $code"
        [ "$(jq -s length "$FLEET_ALERT_POSTS")" = 1 ] || fail "an empty window did not post one FIRING"
        [ "$(pings)" = 0 ] || fail "an empty window pinged"
        grep -qF "no external ping" "$work/out" || fail "an empty window: no no-ping line"
        echo "ok: an empty window posts one FIRING and sends no ping"

        # The FIRING above is in the state. The first run with the heartbeat
        # back has nothing to post yet and pings; once the absence has lasted
        # its 5 min the RESOLVED is due, its post fails, and that run must
        # fail without pinging (transition.jq's resolve delay, as in S3's
        # resumed-heartbeat leg).
        run 403 200 "$heartbeat" 1300
        [ "$code" = 0 ] && [ "$(pings)" = 1 ] || fail "heartbeat back with nothing to post: expected exit 0 and one ping"
        for now in 1600 1900; do
          run 403 200 "$heartbeat" "$now" 1
          [ "$code" != 0 ] && break
        done
        [ "$code" != 0 ] || fail "the RESOLVED post never came due"
        [ "$(pings)" = 0 ] || fail "a failed post pinged"
        echo "ok: a failed post sends no ping"

        reset
        run 403 200 "$heartbeat" 1000 0 "OK (not found)"
        [ "$code" != 0 ] || fail "an unknown check answered OK (not found) exited 0"
        grep -qF "answered 'OK (not found)', expected OK" "$work/out" || fail "an unknown check: no answer line"
        if grep -qF "${pingUuid}" "$work/out"; then fail "an unknown check: the URL was printed"; fi
        echo "ok: an unknown check fails the run without printing the URL"
      '';

      deadmanPingRehearsal =
        pkgs.runCommand "fleet-deadman-ping-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.python3
            ];
            meta.description = "behavioural check: the dead-man pings the external check only after a passing run with a heartbeat";
          }
          ''
            ${deadmanPingLegs} ${lib.getExe deadmanPinged}
            touch "$out"
          '';
```

Add `deadmanPingRehearsal` to the check's `passthru` list and `test -e ${deadmanPingRehearsal}` to its build script.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.fleet-alert.passthru.deadmanPingRehearsal -L 2>&1 | tee logs/cam76-evidence/2.1-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | tail -5
```

Expected: FAIL at evaluation, `attribute 'fleetDeadmanPing' missing` (RED).

- [ ] **Step 2: The transport test, seen failing (tasks.md 2.2)**

After `deadmanPingRehearsal`, add:

```nix
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
```

Add `pingTransport` to the check's `passthru` and `test -e ${pingTransport}` to its build.
Run `nix build .#checks.x86_64-linux.fleet-alert.passthru.pingTransport -L 2>&1 | tee logs/cam76-evidence/2.2-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | tail -5`.

Expected: FAIL at evaluation, `attribute 'fleetDeadmanPing' missing` (RED).

- [ ] **Step 3: The ping step (tasks.md 2.3)**

In `modules/nixos/fleet-alert.nix`, before `fleetAlertDeadman`, add:

```nix
  # The external watch's ping (CAM-76, design D4, D5): one request to the
  # healthchecks.io URL that the curl configuration at
  # FLEET_DEADMAN_PING_CONFIG holds, read by curl on stdin so the URL, a
  # bearer credential, is on no argv. healthchecks.io answers 200 for an
  # unknown or rate-limited check too, so only the body "OK" counts.
  fleetDeadmanPing =
    pkgs:
    {
      curl ? lib.getExe pkgs.curl,
    }:
    pkgs.writeShellApplication {
      name = "fleet-deadman-ping";
      text = ''
        config="''${FLEET_DEADMAN_PING_CONFIG:?}"
        if ! answer=$(${curl} -sS --max-time 10 --retry 2 -K - < "$config"); then
          echo "fleet-deadman: external ping failed" >&2
          exit 1
        fi
        if [ "$answer" != OK ]; then
          echo "fleet-deadman: external ping answered '$answer', expected OK" >&2
          exit 1
        fi
        echo "fleet-deadman: external ping accepted"
      '';
    };
```

and add `fleetDeadmanPing` to the `inherit` in `flake.lib`.
Run `nix build .#checks.x86_64-linux.fleet-alert.passthru.pingTransport -L 2>&1 | tee logs/cam76-evidence/2.3-transport-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`.

Expected: PASS, printing `ok: the URL on stdin and on no argv` and `mutant passing the URL on argv rejected`.

- [ ] **Step 4: The dead-man calls the ping last, with a heartbeat (tasks.md 2.4)**

Give `fleetAlertDeadman` the argument `ping ? null`:

```nix
  fleetAlertDeadman =
    pkgs:
    {
      ntfySend,
      ping ? null,
      transition ? transitionJq,
    }:
```

and append to its `text`, after the post loop's `done <<< …` line:

```nix
        ${lib.optionalString (ping != null) ''
          # The external watch (CAM-76, design D2): the run's last step, so a
          # failed probe, poll or post has already exited non-zero; and only
          # with a heartbeat in the window, so the check stays down while the
          # path from magnetite is broken (O4).
          if [ "$heartbeats" -gt 0 ]; then
            ${ping}
          else
            echo "fleet-deadman: no heartbeat in the last $window; no external ping"
          fi
        ''}
```

Then add the two mutants after `deadmanPingRehearsal`'s definition and run them inside it:

```nix
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
```

and in `deadmanPingRehearsal`'s build script, after the unmutated run:

```bash
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
```

Run, then measure:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/cam76-evidence/2.4-green-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^ok:|mutant|FAIL'
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath >/dev/null
jq -r '[.gc.totalBytes, .cpuTime] | @tsv' /tmp/fleet-alert-stats.json | tee -a logs/cam76-evidence/2.4-cost-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: PASS; every `ok:` line of `deadmanPingLegs`, `mutant deadmanPingFirst rejected` and `mutant pingAcceptsAny200 rejected`; S3's dead-man legs unchanged and passing; the cost below 536,870,912 B and recorded beside Task 1's.

- [ ] **Step 5: The option, its credential and the store-path assertion (tasks.md 2.5)**

In the module's `let`, replace `deadman = …` with:

```nix
      deadman = fleetAlertDeadman pkgs (
        { ntfySend = lib.getExe pkgs.ntfy-send; }
        // lib.optionalAttrs (cfg.deadman.pingConfigFile != null) {
          ping = lib.getExe (fleetDeadmanPing pkgs { });
        }
      );
```

In `options.services.fleet-alert.deadman`, add:

```nix
        pingConfigFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Path of a curl configuration file holding `url = "<healthchecks.io ping URL>"`,
            loaded through LoadCredential as external-ping. When set, a run that passes
            with a heartbeat in its window pings that URL as its last step (CAM-76).
            A string, never a Nix path, so the URL never enters the store.
          '';
        };
```

In the dead-man's `assertions`, add:

```nix
            {
              assertion =
                cfg.deadman.pingConfigFile == null
                || !lib.hasPrefix builtins.storeDir cfg.deadman.pingConfigFile;
              message = "fleet-alert: deadman.pingConfigFile is under the Nix store (${toString cfg.deadman.pingConfigFile}); the ping URL is a credential and must come from a secret file.";
            }
```

and in `systemd.services.fleet-deadman`:

```nix
            environment = {
              FLEET_DEADMAN_CONFIG = "${deadmanConfig}";
              NTFY_TOKEN_FILE = "%d/alerter-token";
            }
            // lib.optionalAttrs (cfg.deadman.pingConfigFile != null) {
              FLEET_DEADMAN_PING_CONFIG = "%d/external-ping";
            };
```

```nix
              LoadCredential = [
                "alerter-token:${cfg.deadman.tokenFile}"
              ]
              ++ lib.optional (cfg.deadman.pingConfigFile != null) "external-ping:${cfg.deadman.pingConfigFile}";
```

Show the assertion failing, then cinnabar unmodified evaluating:

```bash
L=logs/cam76-evidence/2.5-store-path-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake "git+file://'"$PWD"'";
    c = flake.nixosConfigurations.cinnabar.extendModules {
      modules = [ ({ lib, pkgs, ... }: { services.fleet-alert.deadman.pingConfigFile = lib.mkForce "${pkgs.writeText "ping.conf" "url = \"https://hc-ping.com/x\""}"; }) ];
    };
  in c.config.system.build.toplevel.drvPath' 2>&1 | tee "$L" | grep -F 'deadman.pingConfigFile is under the Nix store'
nix eval --raw .#nixosConfigurations.cinnabar.config.system.build.toplevel.drvPath 2>&1 | tee -a "$L"
```

Expected: the first prints the assertion's message (the override fails evaluation); the second prints a `.drv` path.
Commit Steps 1 to 5 as one change, `Ping an external heartbeat check from the alert dead-man when configured`, after `nix fmt`.
