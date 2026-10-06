# Behavioural check: the create-once omnigraph cluster bootstrap decides each
# cell of its truth table correctly, for both marker backends.
#
# flake.lib.omnigraphBootstrap (modules/lib/omnigraph-bootstrap.nix) guards
# the one operation that cannot be undone: initializing a storage root. Its
# whole value is in the verdict per (cluster state, marker) pair, and above
# all in refusing to apply over a root that was initialized and then lost.
# None of that shows in the generated script's text, so every row runs the
# real program and asserts its exit status, its output, whether the converge
# program ran, and what happened to the marker.
#
# `omnigraph` is a stub answering `cluster status --json` with a scripted
# state_found (or an error-severity failure) and logging its argv. The
# converge program is a stub that logs each run, notes whether the marker
# already existed, and fails on request. S3 markers go to a loopback S3
# stand-in that serves HEAD and PUT from a directory, logs every request with
# its Authorization header, and answers HEAD with 500 on request; local
# markers live under a fresh directory per row.
#
# Asserted for both backends: state and marker present is a no-op; state
# without a marker adopts the root by writing the marker and never applies; no
# state and no marker applies once, then writes the marker; no state with a
# marker refuses, never applies, leaves the marker, and names the marker and
# the deliberate-reset instruction; a failed apply exits 1 with no marker; a
# failed status call exits 1 without applying. The marker sits in
# `_omnigraph-markers/` beside the root, never inside it. For S3, a HEAD
# answering 500 exits 1 without applying, AWS_ENDPOINT_URL serves when
# AWS_ENDPOINT_URL_S3 is unset, and every request is path-style and
# SigV4-signed for the configured key and region. Roots with no basename
# (`s3://bucket/`, `/`) and unsupported schemes exit 1 before touching
# anything.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      configDir = "/rehearsal/cluster-config";
      bucket = "rehearsal";
      accessKey = "rehearsal-access-key";

      stubOmnigraph = pkgs.writeShellScriptBin "omnigraph" ''
        printf '%s\n' "$*" >> "$STUB_OMNIGRAPH_LOG"
        if [ "$*" != "cluster status --config ${configDir} --json" ]; then
          echo "stub omnigraph: unexpected invocation: $*" >&2
          exit 97
        fi
        case "$STUB_STATE" in
          found)
            echo '{"ok":true,"state_observations":{"state_found":true},"diagnostics":[]}'
            ;;
          missing)
            echo '{"ok":true,"state_observations":{"state_found":false},"diagnostics":[{"severity":"warning","code":"state_missing"}]}'
            ;;
          error)
            echo '{"ok":false,"diagnostics":[{"severity":"error","code":"state_read_error"}]}'
            exit 1
            ;;
        esac
      '';

      stubApply = pkgs.writeShellScript "stub-cluster-apply" ''
        if [ -e "$STUB_MARKER_FILE" ]; then marker=present; else marker=absent; fi
        echo "applied marker=$marker" >> "$STUB_APPLY_LOG"
        exit "''${STUB_APPLY_EXIT:-0}"
      '';

      mkBootstrap =
        storageUri:
        self.lib.omnigraphBootstrap pkgs {
          omnigraph = stubOmnigraph;
          applyProgram = stubApply;
          inherit configDir storageUri;
        };

      s3Bootstrap = mkBootstrap "s3://${bucket}/clusters/dev-graph/";
      s3MarkerKey = "/${bucket}/clusters/_omnigraph-markers/dev-graph.initialized";
      # Relative, so each row resolves it under its own working directory.
      localBootstrap = mkBootstrap "store/root/";
      localMarker = "store/_omnigraph-markers/root.initialized";
      bucketRootBootstrap = mkBootstrap "s3://${bucket}/";
      slashRootBootstrap = mkBootstrap "/";
      gsBootstrap = mkBootstrap "gs://${bucket}/root";

      # Path-style S3: objects are files under the store directory at their
      # request path. A HEAD while the fail flag exists answers 500.
      s3Stub = pkgs.writeText "s3-stub.py" ''
        import json, os, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer

        store, log_path, port_path, fail_flag = sys.argv[1:5]

        class Handler(BaseHTTPRequestHandler):
            def _reply(self, status):
                self.send_response(status)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def _log(self, body):
                with open(log_path, "a") as log:
                    log.write(json.dumps({
                        "method": self.command,
                        "path": self.path,
                        "authorization": self.headers.get("Authorization") or "",
                        "body": body,
                    }) + "\n")

            def do_HEAD(self):
                self._log(None)
                if os.path.exists(fail_flag):
                    self._reply(500)
                elif os.path.isfile(store + self.path):
                    self._reply(200)
                else:
                    self._reply(404)

            def do_PUT(self):
                body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
                self._log(body.decode())
                os.makedirs(os.path.dirname(store + self.path), exist_ok=True)
                with open(store + self.path, "wb") as f:
                    f.write(body)
                self._reply(200)

            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        with open(port_path, "w") as f:
            f.write(str(server.server_port))
        server.serve_forever()
      '';

      omnigraph-bootstrap-rehearsal =
        pkgs.runCommand "omnigraph-bootstrap-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.jq
              pkgs.coreutils
              pkgs.gnugrep
            ];
            meta.description = "behavioural check: omnigraph cluster bootstrap's create-once truth table for S3 and local markers";
          }
          ''
            set -euo pipefail

            s3_store="$TMPDIR/s3"
            fail_flag="$TMPDIR/head-fails"
            requests="$TMPDIR/requests.jsonl"
            mkdir -p "$s3_store"
            touch "$requests"
            python3 ${s3Stub} "$s3_store" "$requests" "$TMPDIR/port" "$fail_flag" &
            stub_pid=$!
            trap 'kill "$stub_pid"' EXIT
            for _ in $(seq 100); do [ -s "$TMPDIR/port" ] && break; sleep 0.1; done
            [ -s "$TMPDIR/port" ] || { echo "S3 stub did not start" >&2; exit 1; }
            endpoint="http://127.0.0.1:$(cat "$TMPDIR/port")"

            export STUB_OMNIGRAPH_LOG="$TMPDIR/omnigraph.log"
            export STUB_APPLY_LOG="$TMPDIR/apply.log"
            export AWS_REGION=auto
            export AWS_ACCESS_KEY_ID=${accessKey}
            export AWS_SECRET_ACCESS_KEY=rehearsal-secret-key
            export AWS_ENDPOINT_URL_S3="$endpoint"
            unset AWS_ENDPOINT_URL

            fail() { echo "omnigraph-bootstrap-rehearsal: $row: $*" >&2; exit 1; }

            # Starts a row: fresh logs, an empty S3 store and working directory,
            # cluster state <found|missing|error>, the marker <present|absent>
            # for <s3|local>.
            row_setup() { # <label> <backend> <state> <marker>
              row=$1 backend=$2
              echo "--- $row"
              : > "$STUB_OMNIGRAPH_LOG"
              : > "$STUB_APPLY_LOG"
              cat "$requests" >> "$TMPDIR/all-requests.jsonl"
              : > "$requests"
              rm -rf "$s3_store" "$fail_flag"
              mkdir -p "$s3_store"
              rowdir="$TMPDIR/rows/$row"
              mkdir -p "$rowdir"
              cd "$rowdir"
              export STUB_STATE=$3 STUB_APPLY_EXIT=0
              if [ "$backend" = s3 ]; then
                export STUB_MARKER_FILE="$s3_store${s3MarkerKey}"
              else
                export STUB_MARKER_FILE="$rowdir/${localMarker}"
              fi
              if [ "$4" = present ]; then
                mkdir -p "$(dirname "$STUB_MARKER_FILE")"
                echo '{"seeded":true}' > "$STUB_MARKER_FILE"
              fi
            }

            run() { # <bootstrap program>
              rc=0
              "$1" > "$TMPDIR/stdout" 2> "$TMPDIR/stderr" || rc=$?
              cat "$TMPDIR/stdout" "$TMPDIR/stderr" >&2
            }
            run_backend() {
              if [ "$backend" = s3 ]; then run ${lib.getExe s3Bootstrap}; else run ${lib.getExe localBootstrap}; fi
            }

            expect_rc() { [ "$rc" = "$1" ] || fail "exited $rc, expected $1"; }
            applies() { grep -c . "$STUB_APPLY_LOG" || true; }
            expect_no_apply() { [ "$(applies)" = 0 ] || fail "applied: $(cat "$STUB_APPLY_LOG")"; }
            expect_status_once() {
              [ "$(cat "$STUB_OMNIGRAPH_LOG")" = "cluster status --config ${configDir} --json" ] \
                || fail "omnigraph saw: $(cat "$STUB_OMNIGRAPH_LOG")"
            }
            puts() { jq -c 'select(.method == "PUT")' "$requests"; }
            expect_no_put() { [ -z "$(puts)" ] || fail "wrote the marker: $(puts)"; }
            expect_marker_seeded() {
              [ "$(cat "$STUB_MARKER_FILE")" = '{"seeded":true}' ] || fail "marker was rewritten or removed"
            }
            expect_marker_written() { # <reason>
              jq -e --arg r "$1" '.reason == $r and .storage_uri != null and .written_at != null' \
                "$STUB_MARKER_FILE" > /dev/null || fail "marker missing or not a $1 record"
              if [ "$backend" = s3 ]; then
                [ "$(puts | grep -c .)" = 1 ] || fail "expected one PUT, got: $(puts)"
                [ "$(puts | jq -r .path)" = ${s3MarkerKey} ] || fail "PUT the wrong key: $(puts)"
              fi
            }
            expect_no_marker() {
              [ ! -e "$STUB_MARKER_FILE" ] || fail "marker exists: $(cat "$STUB_MARKER_FILE")"
              [ ! -e "$s3_store${s3MarkerKey}" ] || fail "S3 marker exists"
            }

            for backend in s3 local; do
              row_setup "$backend: state found, marker present" "$backend" found present
              run_backend
              expect_rc 0
              expect_status_once
              expect_no_apply
              expect_no_put
              expect_marker_seeded

              row_setup "$backend: state found, marker absent" "$backend" found absent
              run_backend
              expect_rc 0
              expect_no_apply
              expect_marker_written adopted-existing-root

              row_setup "$backend: state missing, marker absent" "$backend" missing absent
              run_backend
              expect_rc 0
              [ "$(cat "$STUB_APPLY_LOG")" = "applied marker=absent" ] \
                || fail "expected one apply before the marker, got: $(cat "$STUB_APPLY_LOG")"
              expect_marker_written first-initialization

              row_setup "$backend: state missing, marker present" "$backend" missing present
              run_backend
              expect_rc 1
              expect_no_apply
              expect_no_put
              expect_marker_seeded
              grep -q "REFUSING TO INITIALIZE" "$TMPDIR/stderr" || fail "no refusal"
              if [ "$backend" = s3 ]; then
                marker_location=s3://${bucket}/clusters/_omnigraph-markers/dev-graph.initialized
              else
                marker_location=${localMarker}
              fi
              grep -qF "delete the marker" "$TMPDIR/stderr" || fail "no reset instruction"
              grep -qF "$marker_location and then: systemctl restart omnigraph-cluster-bootstrap" "$TMPDIR/stderr" \
                || fail "refusal does not name the marker $marker_location with the restart"

              row_setup "$backend: apply fails" "$backend" missing absent
              STUB_APPLY_EXIT=1 run_backend
              expect_rc 1
              [ "$(applies)" = 1 ] || fail "expected one apply, got: $(cat "$STUB_APPLY_LOG")"
              expect_no_put
              expect_no_marker

              row_setup "$backend: status fails" "$backend" error absent
              run_backend
              expect_rc 1
              expect_status_once
              expect_no_apply
              expect_no_put
              expect_no_marker
            done

            # The marker lives beside the root, never inside it.
            [ ! -e "$TMPDIR/rows/local: state found, marker absent/store/root" ] \
              || fail "the local bootstrap created the root directory"

            row_setup "s3: HEAD answers 500" s3 missing absent
            touch "$fail_flag"
            run_backend
            expect_rc 1
            expect_no_apply
            expect_no_put
            grep -q "HTTP 500" "$TMPDIR/stderr" || fail "did not report the HEAD status"

            row_setup "s3: endpoint from AWS_ENDPOINT_URL" s3 found absent
            AWS_ENDPOINT_URL_S3= AWS_ENDPOINT_URL="$endpoint" run_backend
            expect_rc 0
            expect_marker_written adopted-existing-root

            row_setup "s3: endpoint unset" s3 missing absent
            AWS_ENDPOINT_URL_S3= run_backend
            expect_rc 1
            expect_no_apply
            [ ! -s "$requests" ] || fail "made requests: $(cat "$requests")"

            reject_row() { # <label> <bootstrap program> <expected message>
              row_setup "$1" s3 missing absent
              run "$2"
              expect_rc 1
              grep -qF "$3" "$TMPDIR/stderr" || fail "did not report: $3"
              grep -qF "nothing was applied" "$TMPDIR/stderr" || fail "did not say nothing was applied"
              [ ! -s "$STUB_OMNIGRAPH_LOG" ] || fail "called omnigraph: $(cat "$STUB_OMNIGRAPH_LOG")"
              expect_no_apply
              [ ! -s "$requests" ] || fail "made requests: $(cat "$requests")"
            }
            reject_row "rejected root s3 bucket" ${lib.getExe bucketRootBootstrap} \
              "the storage root s3://${bucket}/ has no basename"
            reject_row "rejected root slash" ${lib.getExe slashRootBootstrap} \
              "the storage root / has no basename"
            reject_row "rejected root gs" ${lib.getExe gsBootstrap} \
              "unsupported storage scheme in gs://${bucket}/root"

            row="every S3 request"
            echo "--- $row is path-style and SigV4-signed for the configured key and region"
            cat "$requests" >> "$TMPDIR/all-requests.jsonl"
            jq -e -s 'length > 0 and all(.[];
                .path == "${s3MarkerKey}"
                and (.authorization | startswith("AWS4-HMAC-SHA256 Credential=${accessKey}/"))
                and (.authorization | test("/auto/s3/aws4_request, *SignedHeaders=[^,]*, *Signature=[0-9a-f]{64}$"))
              )' "$TMPDIR/all-requests.jsonl" > /dev/null \
              || fail "unsigned or misaddressed request: $(cat "$TMPDIR/all-requests.jsonl")"
            ! grep -q rehearsal-secret-key "$TMPDIR/all-requests.jsonl" || fail "the secret key reached the wire"

            touch $out
          '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit omnigraph-bootstrap-rehearsal;
      };
    };
}
