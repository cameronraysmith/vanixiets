# Behavioural check: the omnigraph-server readiness probe stops at the first
# conclusive answer instead of polling out its whole timeout.
#
# The probe from modules/lib/omnigraph-readiness.nix is the server unit's
# ExecStartPost. omnigraph-server exits within seconds when it cannot boot and
# opens graphs only at startup, so a dead main process, a quarantined graph or
# a short served-graph count can never turn into readiness; before this probe
# each of them held the start job open for the full readiness timeout.
#
# Every row builds the probe through self.lib.omnigraphReadinessProbe, the
# function the NixOS module calls, and runs it against a loopback stub of
# GET /readyz that replays a scripted sequence of responses (the last one
# repeats). The probe's URL is fixed at build time, so curl reaches the stub
# through http_proxy; the stub logs the path of every request. Rows assert the
# exit status, the message, the elapsed time where speed is the point, and
# the requests the stub saw.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkProbe =
        args:
        self.lib.omnigraphReadinessProbe pkgs (
          {
            url = "http://omnigraph.rehearsal.invalid:8090";
          }
          // args
        );
      probeExpected = mkProbe {
        expectedGraphCount = 2;
        timeout = 30;
      };
      probeAny = mkProbe { timeout = 30; };
      probeShort = mkProbe {
        expectedGraphCount = 2;
        timeout = 3;
      };

      # A v0.11.0 ReadinessOutput.
      readiness =
        {
          ready ? true,
          served,
          quarantined ? 0,
        }:
        {
          inherit ready;
          status = if ready then "serving" else "draining";
          state_revision = 1;
          served_graph_count = served;
          quarantined_graph_count = quarantined;
          shutdown_grace_seconds = 30;
        };
      draining = [
        503
        (readiness {
          ready = false;
          served = 2;
        })
      ];

      readyzStub = pkgs.writeText "readyz-stub.py" ''
        import json, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from urllib.parse import urlsplit

        port_path, log_path, script = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                path = urlsplit(self.path).path
                with open(log_path, "a") as log:
                    log.write(path + "\n")
                status, reply = script.pop(0) if len(script) > 1 else script[0]
                if path != "/readyz":
                    status, reply = 404, {"message": "Not Found"}
                data = json.dumps(reply).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        with open(port_path, "w") as f:
            f.write(str(server.server_port))
        server.serve_forever()
      '';

      # mainpid: "dead" (a reaped child), "live" (this shell) or null (unset).
      row =
        {
          name,
          probe,
          responses,
          mainpid ? null,
          status,
          expect,
          maxElapsed ? null,
          minElapsed ? null,
          requests ? null,
          minRequests ? null,
        }:
        ''
          echo "--- ${name}"
          rm -f "$TMPDIR/port" "$TMPDIR/requests" "$TMPDIR/output"
          touch "$TMPDIR/requests"
          python3 ${readyzStub} "$TMPDIR/port" "$TMPDIR/requests" ${lib.escapeShellArg (builtins.toJSON responses)} &
          stub_pid=$!
          for _ in $(seq 100); do [ -s "$TMPDIR/port" ] && break; sleep 0.1; done
          [ -s "$TMPDIR/port" ] || fail "readyz stub did not start"
          mainpid_env=()
          ${
            {
              dead = ''
                sleep 0 &
                dead_pid=$!
                wait "$dead_pid"
                mainpid_env=(MAINPID="$dead_pid")
              '';
              live = ''mainpid_env=(MAINPID="$$")'';
            }
            .${if mainpid == null then "none" else mainpid} or ""
          }
          start=$(date +%s)
          status=0
          env -u MAINPID -u no_proxy -u NO_PROXY -u HTTP_PROXY \
            http_proxy="http://127.0.0.1:$(cat "$TMPDIR/port")" "''${mainpid_env[@]}" \
            ${lib.getExe probe} > "$TMPDIR/output" 2>&1 || status=$?
          elapsed=$(( $(date +%s) - start ))
          kill "$stub_pid"
          wait "$stub_pid" || true
          stub_pid=
          cat "$TMPDIR/output"
          echo "elapsed ''${elapsed}s, requests: $(wc -l < "$TMPDIR/requests")"
          [ "$status" = ${toString status} ] || fail "${name}: exit status $status, expected ${toString status}"
          ${lib.concatMapStrings (line: ''
            grep -qF -- ${lib.escapeShellArg line} "$TMPDIR/output" \
              || fail ${lib.escapeShellArg "${name}: output lacks: ${line}"}
          '') expect}
          ${lib.optionalString (maxElapsed != null) ''
            [ "$elapsed" -lt ${toString maxElapsed} ] || fail "${name}: took ''${elapsed}s, expected under ${toString maxElapsed}s"
          ''}
          ${lib.optionalString (minElapsed != null) ''
            [ "$elapsed" -ge ${toString minElapsed} ] || fail "${name}: took ''${elapsed}s, expected at least ${toString minElapsed}s"
          ''}
          ${lib.optionalString (requests != null) ''
            [ "$(wc -l < "$TMPDIR/requests")" -eq ${toString requests} ] || fail "${name}: expected ${toString requests} requests"
          ''}
          ${lib.optionalString (minRequests != null) ''
            [ "$(wc -l < "$TMPDIR/requests")" -ge ${toString minRequests} ] || fail "${name}: expected at least ${toString minRequests} requests"
          ''}
          if grep -vx /readyz "$TMPDIR/requests"; then fail "${name}: probe requested a path other than /readyz"; fi
        '';

      rows = [
        {
          name = "dead MAINPID fails fast without polling";
          probe = probeExpected;
          responses = [ draining ];
          mainpid = "dead";
          status = 1;
          expect = [
            "omnigraph-server exited during startup before serving"
            "journalctl -u omnigraph-server"
            "systemctl restart omnigraph-cluster-apply"
          ];
          maxElapsed = 10;
          requests = 0;
        }
        {
          name = "served equals expected with a live MAINPID is ready";
          probe = probeExpected;
          responses = [
            [
              200
              (readiness { served = 2; })
            ]
          ];
          mainpid = "live";
          status = 0;
          expect = [ ];
          maxElapsed = 10;
          requests = 1;
        }
        {
          name = "served below expected fails fast";
          probe = probeExpected;
          responses = [
            [
              200
              (readiness { served = 1; })
            ]
          ];
          status = 1;
          expect = [
            "serves 1 of 2 declared graphs"
            "systemctl restart omnigraph-cluster-apply"
          ];
          maxElapsed = 10;
          requests = 1;
        }
        {
          name = "a quarantined graph fails fast";
          probe = probeExpected;
          responses = [
            [
              200
              (readiness {
                served = 2;
                quarantined = 1;
              })
            ]
          ];
          status = 1;
          expect = [
            "quarantined 1 graph(s) during startup"
            "graph quarantined during startup"
            "omnigraph-cluster status"
          ];
          maxElapsed = 10;
          requests = 1;
        }
        {
          name = "no expected count accepts zero served graphs";
          probe = probeAny;
          responses = [
            [
              200
              (readiness { served = 0; })
            ]
          ];
          status = 0;
          expect = [ ];
          maxElapsed = 10;
          requests = 1;
        }
        {
          name = "503 then 200 is transient";
          probe = probeExpected;
          responses = [
            draining
            draining
            [
              200
              (readiness { served = 2; })
            ]
          ];
          status = 0;
          expect = [ ];
          maxElapsed = 20;
          requests = 3;
        }
        {
          name = "200 that is not a readiness report fails fast";
          probe = probeExpected;
          responses = [
            [
              200
              { }
            ]
          ];
          status = 1;
          expect = [ "with a body that is not a readiness report" ];
          maxElapsed = 10;
          requests = 1;
        }
        {
          name = "200 with ready false keeps polling, then times out";
          probe = probeShort;
          responses = [
            [
              200
              (readiness {
                ready = false;
                served = 2;
              })
            ]
          ];
          status = 1;
          expect = [ "did not answer http://omnigraph.rehearsal.invalid:8090/readyz within 3 seconds" ];
          minElapsed = 2;
          maxElapsed = 20;
          minRequests = 2;
        }
        {
          name = "never ready within the timeout fails with the timeout message";
          probe = probeShort;
          responses = [ draining ];
          status = 1;
          expect = [ "did not answer http://omnigraph.rehearsal.invalid:8090/readyz within 3 seconds" ];
          minElapsed = 2;
          maxElapsed = 20;
          minRequests = 2;
        }
      ];

      omnigraph-readiness-rehearsal =
        pkgs.runCommand "omnigraph-readiness-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.python3
            ];
            meta.description = "behavioural check: the omnigraph-server readiness probe fails fast on a dead server, quarantined or missing graphs, and waits out transient 503s";
          }
          ''
            set -euo pipefail
            stub_pid=
            trap '[ -z "$stub_pid" ] || kill "$stub_pid" 2>/dev/null || true' EXIT
            fail() {
              echo "FAIL: $*" >&2
              exit 1
            }

            ${lib.concatMapStrings row rows}
            touch "$out"
          '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit omnigraph-readiness-rehearsal;
      };
    };
}
