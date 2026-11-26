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
# `omnigraph` is a stub answering `--target <root> cluster status --json` the
# way omnigraph 0.15 does, scripted per row: a ledger status and exit 0 when
# the root holds state, the single `state_missing` diagnostic and exit 1 when
# it does not, another diagnostic and exit 1 for a failed read, or exit 0
# without a ledger status; it logs its argv. The
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
# failed status call, or a successful one without a ledger status, exits 1
# without applying. The marker sits in
# `_omnigraph-markers/` beside the root, never inside it. For S3, a HEAD
# answering 500 exits 1 without applying, AWS_ENDPOINT_URL serves when
# AWS_ENDPOINT_URL_S3 is unset, and every request is path-style and
# SigV4-signed for the configured key and region. Roots with no basename
# (`s3://bucket/`, `/`) and unsupported schemes exit 1 before touching
# anything. First initialization of a local root creates its missing
# directory (mode 0700) before the apply, leaves an existing one unchanged,
# and an s3:// root gets no local directory.
#
# Seed-pending markers, for a bootstrap with the seeded graphs magnetite
# declares (one per cookbook, ten at the pinned revision), on both backends:
# the first-initialization branch writes
# `_omnigraph-markers/<root>.<graph>.seed-pending` for every one of them
# before the apply runs (so before `.initialized`), and they stay when the
# apply fails; the adopt, no-op and refusal branches write none; a bootstrap
# without seeded graphs writes none in any branch (the rows above).
#
# The seed program (flake.lib.omnigraphSeed) runs against a loopback stand-in
# for the server's `POST /graphs/<graph>/load/ndjson`, reached through
# http_proxy because its URL is fixed at build time, answering as scripted
# per row. Asserted: with no pending marker it exits 0 and sends nothing; a
# 200 append commit deletes the marker; a 409 `key_conflict` with effects
# `none` deletes it; a 409 `key_conflict` with partial effects, a 500
# `outcome_unknown`, a 200 that is not an append commit, a request that times
# out and an unreadable token each exit 1 and keep it. A 400 `@card`
# violation with effects `unknown`, the answer omnigraph 0.16.0 gives a
# replayed seed with edges under a `@card` maximum, exits 1, keeps the marker
# and prints the graph, the marker and the systemd-run command that clears
# it; `--clear-pending` deletes the marker without a load, on both backends.
# Every load is `mode=append` on `main` and carries the bearer token, the HTTP
# contract the packaged omnigraph reports and the seed as NDJSON. For S3 the
# marker is deleted with a signed DELETE.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      bucket = "rehearsal";
      accessKey = "rehearsal-access-key";

      stubOmnigraph = pkgs.writeShellScriptBin "omnigraph" ''
        printf '%s\n' "$*" >> "$STUB_OMNIGRAPH_LOG"
        case "$*" in
          "--target "*" cluster status --json") ;;
          "version --json")
            echo '{"version":"0.16.0","http_contract":"0.14","internal_schema":{"writes":17,"serves":[14,17]}}'
            exit 0
            ;;
          *)
            echo "stub omnigraph: unexpected invocation: $*" >&2
            exit 97
            ;;
        esac
        case "$STUB_STATE" in
          found)
            echo '{"canonical_root":"rehearsal","ledger_id":"01JREHEARSALLEDGER000000000","state_revision":1,"result_revision":1,"next_sequence":2,"lock_id":null,"outstanding_id":null,"lookup":null}'
            ;;
          missing)
            echo '{"ok":false,"diagnostics":[{"code":"state_missing","severity":"error","path":"cluster","message":"cluster ledger is missing"}]}'
            exit 1
            ;;
          error)
            echo '{"ok":false,"diagnostics":[{"code":"state_read_failed","severity":"error","path":"cluster","message":"storage read failed"}]}'
            exit 1
            ;;
          malformed)
            echo '{"ok":true}'
            ;;
        esac
      '';

      stubApply = pkgs.writeShellScript "stub-cluster-apply" ''
        if [ -e "$STUB_MARKER_FILE" ]; then marker=present; else marker=absent; fi
        # One path per line: row directories contain spaces.
        pending=
        while IFS= read -r p; do
          [ -n "$p" ] || continue
          if [ -e "$p" ]; then pending="$pending present"; else pending="$pending absent"; fi
        done <<<"''${STUB_PENDING_FILES:-}"
        root=
        if [ -n "''${STUB_ROOT_DIR:-}" ]; then
          if [ -d "$STUB_ROOT_DIR" ]; then root=" root=present"; else root=" root=absent"; fi
        fi
        echo "applied marker=$marker pending=''${pending# }$root" >> "$STUB_APPLY_LOG"
        exit "''${STUB_APPLY_EXIT:-0}"
      '';

      # The graphs magnetite seeds, so the rows run with the ids, and the
      # number of graphs, a deployed root is initialized with.
      seededGraphIds =
        let
          ids = lib.attrNames (
            lib.filterAttrs (
              _: graph: graph.seed != null
            ) self.nixosConfigurations.magnetite.config.services.omnigraph.cluster.graphs
          );
        in
        assert lib.assertMsg (
          lib.length ids >= 2
        ) "magnetite seeds fewer than two graphs; the seeded rows need several";
        ids;

      mkBootstrap =
        storageUri:
        self.lib.omnigraphBootstrap pkgs {
          omnigraph = stubOmnigraph;
          applyProgram = stubApply;
          inherit storageUri;
        };
      mkSeededBootstrap =
        storageUri:
        self.lib.omnigraphBootstrap pkgs {
          omnigraph = stubOmnigraph;
          applyProgram = stubApply;
          inherit storageUri;
          seededGraphs = seededGraphIds;
        };

      s3Root = "s3://${bucket}/clusters/dev-graph/";
      s3Bootstrap = mkBootstrap s3Root;
      s3SeededBootstrap = mkSeededBootstrap s3Root;
      s3MarkerKey = "/${bucket}/clusters/_omnigraph-markers/dev-graph.initialized";
      s3PendingKeys = map (
        g: "/${bucket}/clusters/_omnigraph-markers/dev-graph.${g}.seed-pending"
      ) seededGraphIds;
      # Relative, so each row resolves it under its own working directory.
      localRoot = "store/root/";
      localBootstrap = mkBootstrap localRoot;
      localSeededBootstrap = mkSeededBootstrap localRoot;
      localMarker = "store/_omnigraph-markers/root.initialized";
      localPendingMarkers = map (g: "store/_omnigraph-markers/root.${g}.seed-pending") seededGraphIds;
      # The pending marker of graph `dev`, the graph the seed program rows load.
      s3SeedPendingKey = "/${bucket}/clusters/_omnigraph-markers/dev-graph.dev.seed-pending";
      bucketRootBootstrap = mkBootstrap "s3://${bucket}/";
      slashRootBootstrap = mkBootstrap "/";
      gsBootstrap = mkBootstrap "gs://${bucket}/root";

      seedFile = pkgs.writeText "seed.jsonl" ''
        {"type":"Person","data":{"slug":"ada"}}
      '';
      seedServer = "http://omnigraph.rehearsal.invalid:8090";
      mkSeed =
        storageUri:
        self.lib.omnigraphSeed pkgs {
          omnigraph = stubOmnigraph;
          inherit storageUri seedFile;
          graph = "dev";
          serverUrl = seedServer;
          tokenCredential = "seed-token";
          timeout = 3;
          environmentFile = "/run/rehearsal/env";
          environment.AWS_REGION = "auto";
        };
      localSeed = mkSeed localRoot;
      s3Seed = mkSeed s3Root;

      # The server's load route, answering each request as the mode file
      # says: ok, conflict, conflict-partial, unknown, not-append or hang.
      loadStub = pkgs.writeText "load-stub.py" ''
        import json, os, sys, time
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        log_path, port_path, mode_path = sys.argv[1:4]

        def reply_for(mode):
            if mode == "ok":
                return 200, {"branch": "main", "base_branch": None, "branch_created": False, "mode": "append",
                             "nodes": [{"name": "Person", "entities_loaded": 1}], "edges": [], "total_entities": 1,
                             "embedding_generation": None, "actor_id": "seeder",
                             "commit": {"graph_commit_id": "01JREHEARSALCOMMIT00000000", "graph_branch": "main"}}
            if mode == "not-append":
                return 200, {"branch": "main", "mode": "merge", "total_entities": 1, "commit": None}
            if mode == "conflict":
                return 409, {"error": "node type 'Person' already has id 'ada'", "code": "conflict",
                             "disposition": {"effects": "none", "action": "refresh"},
                             "key_conflict": {"entity_kind": "node", "type_name": "Person", "entity_id": "ada"}}
            if mode == "conflict-partial":
                return 409, {"error": "node type 'Person' already has id 'ada'", "code": "conflict",
                             "disposition": {"effects": "partial", "action": "refresh"},
                             "key_conflict": {"entity_kind": "node", "type_name": "Person", "entity_id": "ada"}}
            if mode == "card":
                return 400, {"error": "@card violation on edge OwnedBy: source 'ada' has 2 edges (max 1)",
                             "code": "bad_request", "disposition": {"effects": "unknown", "action": "reconcile"}}
            return 500, {"error": "the write's outcome is unknown", "code": "outcome_unknown",
                         "disposition": {"effects": "unknown", "action": "inspect"}}

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
                with open(log_path, "a") as log:
                    log.write(json.dumps({
                        "path": self.path,
                        "authorization": self.headers.get("Authorization") or "",
                        "contract": self.headers.get("Omnigraph-Http-Api") or "",
                        "content_type": self.headers.get("Content-Type") or "",
                        "body": body,
                    }) + "\n")
                with open(mode_path) as f:
                    mode = f.read().strip()
                if mode == "hang":
                    time.sleep(10)
                status, payload = reply_for(mode)
                data = json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        with open(port_path, "w") as f:
            f.write(str(server.server_port))
        server.serve_forever()
      '';

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

            def do_DELETE(self):
                self._log(None)
                if os.path.isfile(store + self.path):
                    os.remove(store + self.path)
                self._reply(204)

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
              if [ "$backend" = s3 ]; then root=${s3Root}; else root=${localRoot}; fi
              [ "$(cat "$STUB_OMNIGRAPH_LOG")" = "--target $root cluster status --json" ] \
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
              [ "$(cat "$STUB_APPLY_LOG")" = "applied marker=absent pending=" ] \
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

              row_setup "$backend: status succeeds without a ledger status" "$backend" malformed absent
              run_backend
              expect_rc 1
              expect_status_once
              expect_no_apply
              expect_no_put
              expect_no_marker
              grep -qF "without a ledger status or a state_missing refusal" "$TMPDIR/stderr" \
                || fail "did not explain the unrecognized status"
            done

            # The marker lives beside the root, never inside it.
            [ ! -e "$TMPDIR/rows/local: state found, marker absent/store/root" ] \
              || fail "the local bootstrap created the root directory"

            # First initialization creates a missing local root's directory
            # before the apply, leaves an existing one as it is, and creates
            # nothing locally for an s3:// root.
            row_setup "local: missing root created on first initialization" local missing absent
            STUB_ROOT_DIR="$rowdir/store/root" run_backend
            expect_rc 0
            [ "$(cat "$STUB_APPLY_LOG")" = "applied marker=absent pending= root=present" ] \
              || fail "the root directory did not exist when the apply ran: $(cat "$STUB_APPLY_LOG")"
            [ "$(stat -c %a store/root)" = 700 ] || fail "the root directory has mode $(stat -c %a store/root), not 700"
            grep -qF "created the local storage root directory store/root" "$TMPDIR/stdout" \
              || fail "did not report creating the root directory"

            row_setup "local: existing root left alone on first initialization" local missing absent
            mkdir -p store/root
            chmod 0755 store/root
            echo kept > store/root/sentinel
            STUB_ROOT_DIR="$rowdir/store/root" run_backend
            expect_rc 0
            [ "$(cat "$STUB_APPLY_LOG")" = "applied marker=absent pending= root=present" ] \
              || fail "expected one apply: $(cat "$STUB_APPLY_LOG")"
            [ "$(stat -c %a store/root)" = 755 ] || fail "the existing root directory's mode was changed"
            [ "$(cat store/root/sentinel)" = kept ] || fail "the existing root directory's contents were changed"
            ! grep -qF "created the local storage root directory" "$TMPDIR/stdout" \
              || fail "reported creating an existing root directory"

            row_setup "s3: remote root never touched locally" s3 missing absent
            run_backend
            expect_rc 0
            [ -z "$(ls -A .)" ] || fail "created local files for an s3:// root: $(ls -A .)"
            ! grep -qF "created the local storage root directory" "$TMPDIR/stdout" \
              || fail "reported creating a local directory for an s3:// root"

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

            # Seeded graphs dev and ops: pending markers only on first
            # initialization, written before the apply.
            run_seeded() {
              if [ "$backend" = s3 ]; then run ${lib.getExe s3SeededBootstrap}; else run ${lib.getExe localSeededBootstrap}; fi
            }
            pending_files() {
              if [ "$backend" = s3 ]; then
                printf "$s3_store%s\n" ${lib.escapeShellArgs s3PendingKeys}
              else
                printf "$rowdir/%s\n" ${lib.escapeShellArgs localPendingMarkers}
              fi
            }
            seeded_setup() { # <label> <backend> <state> <marker>
              row_setup "$@"
              STUB_PENDING_FILES=$(pending_files)
              export STUB_PENDING_FILES
            }
            expect_no_pending() {
              while IFS= read -r p; do
                [ ! -e "$p" ] || fail "wrote a seed-pending marker: $p"
              done < <(pending_files)
            }
            expect_pending() {
              for graph in ${lib.escapeShellArgs seededGraphIds}; do
                p=$(pending_files | grep -F ".$graph.seed-pending")
                jq -e --arg g "$graph" '.graph == $g and .reason == "first-initialization" and .storage_uri != null and .written_at != null' \
                  "$p" > /dev/null || fail "no seed-pending record for $graph at $p"
              done
            }
            for backend in s3 local; do
              seeded_setup "$backend seeded: state found, marker present" "$backend" found present
              run_seeded
              expect_rc 0
              expect_no_apply
              expect_no_put
              expect_no_pending

              seeded_setup "$backend seeded: state found, marker absent" "$backend" found absent
              run_seeded
              expect_rc 0
              expect_no_apply
              expect_marker_written adopted-existing-root
              expect_no_pending

              seeded_setup "$backend seeded: state missing, marker absent" "$backend" missing absent
              run_seeded
              expect_rc 0
              [ "$(cat "$STUB_APPLY_LOG")" = ${lib.escapeShellArg "applied marker=absent pending=${lib.concatMapStringsSep " " (_: "present") seededGraphIds}"} ] \
                || fail "expected one apply after every pending marker and before the marker, got: $(cat "$STUB_APPLY_LOG")"
              jq -e '.reason == "first-initialization"' "$STUB_MARKER_FILE" > /dev/null \
                || fail "marker missing or not a first-initialization record"
              expect_pending
              if [ "$backend" = s3 ]; then
                [ "$(puts | jq -r .path | tr '\n' ' ')" = "${lib.concatStringsSep " " s3PendingKeys} ${s3MarkerKey} " ] \
                  || fail "expected PUTs of both pending markers, then the marker: $(puts)"
              fi

              seeded_setup "$backend seeded: state missing, marker present" "$backend" missing present
              run_seeded
              expect_rc 1
              expect_no_apply
              expect_no_put
              expect_no_pending

              seeded_setup "$backend seeded: apply fails" "$backend" missing absent
              STUB_APPLY_EXIT=1 run_seeded
              expect_rc 1
              expect_no_marker
              expect_pending
            done
            unset STUB_PENDING_FILES

            # The seed program, against the load route stand-in.
            load_requests="$TMPDIR/load-requests.jsonl"
            load_mode="$TMPDIR/load-mode"
            touch "$load_requests"
            echo ok > "$load_mode"
            python3 ${loadStub} "$load_requests" "$TMPDIR/load-port" "$load_mode" &
            load_pid=$!
            trap 'kill "$stub_pid" "$load_pid"' EXIT
            for _ in $(seq 100); do [ -s "$TMPDIR/load-port" ] && break; sleep 0.1; done
            [ -s "$TMPDIR/load-port" ] || { echo "load stub did not start" >&2; exit 1; }
            export http_proxy="http://127.0.0.1:$(cat "$TMPDIR/load-port")" no_proxy=127.0.0.1
            export CREDENTIALS_DIRECTORY="$TMPDIR/credentials"
            mkdir -p "$CREDENTIALS_DIRECTORY"
            printf 'rehearsal-seed-token' > "$CREDENTIALS_DIRECTORY/seed-token"
            local_pending=store/_omnigraph-markers/root.dev.seed-pending
            s3_pending_key=${s3SeedPendingKey}

            seed_setup() { # <label> <backend> <load answer> <pending: present|absent>
              row_setup "$1" "$2" found present
              : > "$load_requests"
              echo "$3" > "$load_mode"
              if [ "$2" = s3 ]; then pending="$s3_store$s3_pending_key"; else pending="$rowdir/$local_pending"; fi
              if [ "$4" = present ]; then
                mkdir -p "$(dirname "$pending")"
                echo '{"graph":"dev"}' > "$pending"
              fi
            }
            run_seed() {
              if [ "$backend" = s3 ]; then run ${lib.getExe s3Seed}; else run ${lib.getExe localSeed}; fi
            }
            loads() { grep -c . "$load_requests" || true; }
            expect_one_load() {
              [ "$(loads)" = 1 ] || fail "expected one load request, got: $(cat "$load_requests")"
              jq -e --rawfile seed ${seedFile} '
                .path == "${seedServer}/graphs/dev/load/ndjson?mode=append&branch=main"
                and .authorization == "Bearer rehearsal-seed-token"
                and .contract == "0.14"
                and .content_type == "application/x-ndjson"
                and .body == $seed' "$load_requests" > /dev/null \
                || fail "the load request is not an append of the seed with the token and contract: $(cat "$load_requests")"
            }
            expect_pending_kept() { [ -e "$pending" ] || fail "the seed-pending marker was deleted"; }
            expect_pending_deleted() { [ ! -e "$pending" ] || fail "the seed-pending marker was kept"; }

            seed_setup "seed: nothing pending" local ok absent
            run_seed
            expect_rc 0
            [ "$(loads)" = 0 ] || fail "sent a load: $(cat "$load_requests")"
            grep -qF "nothing to do" "$TMPDIR/stdout" || fail "did not say there was nothing to do"

            seed_setup "seed: load commits" local ok present
            run_seed
            expect_rc 0
            expect_one_load
            expect_pending_deleted

            seed_setup "seed: key conflict without effects" local conflict present
            run_seed
            expect_rc 0
            expect_one_load
            expect_pending_deleted
            grep -qF "already holds the seed" "$TMPDIR/stdout" || fail "did not report the seed as present"

            for answer in conflict-partial unknown not-append hang; do
              seed_setup "seed: $answer" local "$answer" present
              run_seed
              expect_rc 1
              expect_one_load
              expect_pending_kept
            done

            # A replay refused as a @card violation with effects unknown names
            # the graph, the marker and the command that clears it.
            for backend in local s3; do
              seed_setup "seed: $backend card refusal" "$backend" card present
              run_seed
              expect_rc 1
              expect_one_load
              expect_pending_kept
              if [ "$backend" = s3 ]; then
                marker_uri=s3://${bucket}/clusters/_omnigraph-markers/dev-graph.dev.seed-pending
                seed_program=${lib.getExe s3Seed}
              else
                marker_uri=$local_pending
                seed_program=${lib.getExe localSeed}
              fi
              for expected in "into graph dev answered HTTP 400" "$marker_uri" \
                "systemd-run --wait --pipe --collect '--property=EnvironmentFile=/run/rehearsal/env' '--setenv=AWS_REGION=auto' $seed_program --clear-pending"; do
                grep -qF -- "$expected" "$TMPDIR/stderr" || fail "the refusal does not name: $expected"
              done

              seed_setup "seed: $backend clear pending" "$backend" ok present
              rc=0
              "$seed_program" --clear-pending > "$TMPDIR/stdout" 2> "$TMPDIR/stderr" || rc=$?
              cat "$TMPDIR/stdout" "$TMPDIR/stderr" >&2
              expect_rc 0
              [ "$(loads)" = 0 ] || fail "--clear-pending sent a load: $(cat "$load_requests")"
              expect_pending_deleted
            done

            seed_setup "seed: token unreadable" local ok present
            CREDENTIALS_DIRECTORY="$TMPDIR/no-credentials" run_seed
            expect_rc 1
            [ "$(loads)" = 0 ] || fail "sent a load without a token: $(cat "$load_requests")"
            expect_pending_kept

            seed_setup "seed: s3 load commits" s3 ok present
            run_seed
            expect_rc 0
            expect_one_load
            expect_pending_deleted
            [ "$(jq -c 'select(.method == "DELETE") | .path' "$requests")" = "\"$s3_pending_key\"" ] \
              || fail "expected one DELETE of $s3_pending_key: $(cat "$requests")"

            seed_setup "seed: s3 nothing pending" s3 ok absent
            run_seed
            expect_rc 0
            [ "$(loads)" = 0 ] || fail "sent a load: $(cat "$load_requests")"
            ! jq -e 'select(.method == "DELETE")' "$requests" > /dev/null || fail "deleted a marker"

            row="every S3 request"
            echo "--- $row is path-style and SigV4-signed for the configured key and region"
            cat "$requests" >> "$TMPDIR/all-requests.jsonl"
            jq -e -s --argjson keys ${
              lib.escapeShellArg (
                builtins.toJSON (
                  [
                    s3MarkerKey
                    s3SeedPendingKey
                  ]
                  ++ s3PendingKeys
                )
              )
            } 'length > 0 and all(.[];
                (.path | IN($keys[]))
                and (.authorization | startswith("AWS4-HMAC-SHA256 Credential=${accessKey}/"))
                and (.authorization | test("/auto/s3/aws4_request, *SignedHeaders=[^,]*, *Signature=[0-9a-f]{64}$"))
              )' "$TMPDIR/all-requests.jsonl" > /dev/null \
              || fail "unsigned or misaddressed request: $(cat "$TMPDIR/all-requests.jsonl")"
            ! grep -q rehearsal-secret-key "$TMPDIR/all-requests.jsonl" || fail "the secret key reached the wire"

            touch $out
          '';
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 20 s, slowest 28 s, all 5 runs 2026-10-02..2026-11-11;
        # with magnetite's ten seeded graphs, 6 s in three --rebuild runs on
        # magnetite's store, 2026-11-25
        omnigraph-bootstrap-rehearsal.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit omnigraph-bootstrap-rehearsal;
      };
    };
}
