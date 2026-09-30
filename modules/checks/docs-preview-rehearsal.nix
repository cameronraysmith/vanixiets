# Behavioural check: the docs-preview program run by the pull_request event
# effect, which otherwise only runs after a pull request is opened.
#
# A python stub serves nixbot's build API from fixture files and GitHub's
# check-runs API, logging every request as JSONL. A stub deploy-docs records
# its argv and Cloudflare env and prints the DEPLOY-DOCS-PREVIEW-URL line,
# fails, or omits the line on demand. nix-store is the real one against a
# chroot store in $TMPDIR holding one registered payload path, so a store
# path nixbot reports but the store cannot realise fails the run. Secrets are
# fixed dummies.
#
# Asserted per case: exit status, the error line, deploy-docs' exact argv (or
# that it did not run), and the check-run lifecycle: POST in_progress, the
# build lookup, then one PATCH completing it with the matching conclusion and
# details_url, in that order. A malformed event makes no request at all, and
# a failing check-runs API neither fails a successful preview nor changes a
# failed one's exit status.
{ ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      docsPreviewProgram = config.apps.docs-preview.program;

      head = "0123456789abcdef0123456789abcdef01234567";
      head12 = builtins.substring 0 12 head;
      pr = "7";
      previewUrl = "https://b-pr-7-infra-docs.sciexp.workers.dev";
      checkRunId = "4242";
      docsAttr = "checks.x86_64-linux.package-vanixiets-docs";
      payload = "/nix/store/0123456789abcdfghijklmnpqrsvwxyz-vanixiets-docs";
      unrealisable = "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-vanixiets-docs";

      server = pkgs.writeText "docs-preview-stub-server.py" ''
        import json
        import os
        import pathlib
        from http.server import BaseHTTPRequestHandler, HTTPServer

        state = pathlib.Path(os.environ["STUB_STATE"])
        builds = "/api/repos/github/cameronraysmith/vanixiets/builds/"
        check_runs = "/repos/cameronraysmith/vanixiets/check-runs"


        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, code, body):
                data = json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def handle_any(self):
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                with open(state / "requests.jsonl", "a") as log:
                    log.write(json.dumps({
                        "method": self.command,
                        "path": self.path,
                        "auth": self.headers.get("Authorization"),
                        "body": json.loads(raw) if raw else None,
                    }) + "\n")
                if self.command == "GET" and self.path.startswith(builds):
                    fixture = state / "builds" / (self.path[len(builds):] + ".json")
                    if fixture.is_file():
                        return self.reply(200, json.loads(fixture.read_text()))
                elif self.command == "POST" and self.path == check_runs:
                    if (state / "post-down").exists():
                        return self.reply(403, {"message": "Resource not accessible"})
                    return self.reply(201, {"id": ${checkRunId}})
                elif self.command == "PATCH" and self.path == check_runs + "/${checkRunId}":
                    if (state / "patch-down").exists():
                        return self.reply(403, {"message": "Resource not accessible"})
                    return self.reply(200, {"id": ${checkRunId}})
                self.reply(404, {"message": "Not Found"})

            do_GET = do_POST = do_PATCH = handle_any


        httpd = HTTPServer(("127.0.0.1", 0), Handler)
        (state / "port.tmp").write_text(str(httpd.server_port))
        (state / "port.tmp").rename(state / "port")
        httpd.serve_forever()
      '';

      deployDocsStub = pkgs.writeShellScript "deploy-docs-stub" ''
        jq -nc '{
          argv: $ARGS.positional,
          token: env.CLOUDFLARE_API_TOKEN,
          account: env.CLOUDFLARE_ACCOUNT_ID
        }' --args -- "$@" >> "$STUB_STATE/deploy-docs.jsonl"
        case "''${STUB_DEPLOY:-ok}" in
          fail)
            echo "error: wrangler versions upload failed" >&2
            exit 1
            ;;
          no-url)
            echo "uploaded"
            ;;
          *)
            echo "  Preview URL: ${previewUrl}"
            echo "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
            ;;
        esac
      '';
    in
    {
      checks.docs-preview-rehearsal =
        pkgs.runCommand "docs-preview-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.jq
              pkgs.nix
              pkgs.python3
            ];
            __darwinAllowLocalNetworking = true;
            meta.description = "behavioural check: docs-preview against nixbot, GitHub and deploy-docs stubs";
          }
          ''
            set -euo pipefail

            export HOME=$TMPDIR
            export NIX_REMOTE="local?root=$TMPDIR/store-root"
            export NIX_CONFIG="substituters ="
            mkdir -p "$TMPDIR/store-root${payload}"
            echo '<!doctype html><title>payload</title>' > "$TMPDIR/store-root${payload}/index.html"
            printf '%s\n\n0\n' ${payload} | nix-store --register-validity
            nix-store --realise ${payload} > /dev/null
            if nix-store --realise ${unrealisable} > /dev/null 2>&1; then
              echo "control: the chroot store realised an unregistered path" >&2
              exit 1
            fi

            export STUB_STATE=$TMPDIR/stub
            mkdir -p "$STUB_STATE/builds"
            python3 ${server} &
            server_pid=$!
            trap 'kill "$server_pid"' EXIT
            for _ in $(seq 100); do
              [ -f "$STUB_STATE/port" ] && break
              sleep 0.1
            done
            port="$(cat "$STUB_STATE/port")"

            export NIXBOT_API_URL="http://127.0.0.1:$port"
            export GITHUB_API_URL="http://127.0.0.1:$port"
            export DOCS_PREVIEW_DEPLOY_DOCS=${deployDocsStub}
            export GITHUB_FORGE_TOKEN=rehearsal-forge-token
            export CLOUDFLARE_API_TOKEN=rehearsal-dummy-token
            export CLOUDFLARE_ACCOUNT_ID=rehearsal-dummy-account

            fail() {
              echo "row '$name': $*" >&2
              exit 1
            }
            # build <number> <build status> <attributes json>: a build fixture.
            build() {
              jq -n --argjson n "$1" --arg status "$2" --argjson attributes "$3" \
                '{build: {number: $n, status: $status}, attributes: $attributes}' \
                > "$STUB_STATE/builds/$1.json"
            }
            # attr <name> <status> <out>: one attribute entry.
            attr() {
              jq -nc --arg attr "$1" --arg status "$2" --arg out "$3" \
                '{attr: $attr, status: $status, outputs: {out: $out}}'
            }
            event() {
              printf '{"build":{"number":%s}}' "$1" > "$TMPDIR/event.json"
            }
            # run <name>: runs docs-preview for the current event env with a
            # fresh request and deploy-docs log; records the exit status.
            run() {
              name=$1
              echo "--- $name"
              : > "$STUB_STATE/requests.jsonl"
              : > "$STUB_STATE/deploy-docs.jsonl"
              output="$TMPDIR/$name.output"
              status=0
              ${docsPreviewProgram} > "$output" 2>&1 || status=$?
              cat "$output"
            }
            expect_status() {
              [ "$status" = "$1" ] || fail "exit status $status, expected $1"
            }
            expect_line() {
              grep -qxF -- "$1" "$output" || fail "missing output line: $1"
            }
            # expect <description> <log> <jq filter over its entries> [jq args...]
            expect() {
              local description=$1 log=$2 filter=$3
              shift 3
              jq -se "$@" "$filter" "$STUB_STATE/$log.jsonl" > /dev/null || fail "$description"
            }
            expect_requests() {
              expect "requests are $1" requests 'map("\(.method) \(.path)") == $want' --argjson want "$1"
            }
            expect_deployed() {
              expect "deploy-docs previews the payload once, with the Cloudflare env" deploy-docs \
                '. == [{
                  argv: ["preview", "--rev", $head, "--alias", "pr-${pr}", "--payload", $payload],
                  token: "rehearsal-dummy-token",
                  account: "rehearsal-dummy-account"
                }]' --arg head ${head} --arg payload ${payload}
            }
            expect_not_deployed() {
              expect "deploy-docs did not run" deploy-docs '. == []'
            }
            expect_created() {
              expect "check run created in_progress on the head with the forge token" requests \
                '.[0] | .auth == "Bearer rehearsal-forge-token"
                  and .body == {name: "docs-preview", head_sha: $head, status: "in_progress"}' \
                --arg head ${head}
            }
            expect_lifecycle() {
              expect_requests "[\"POST /repos/cameronraysmith/vanixiets/check-runs\", \"GET /api/repos/github/cameronraysmith/vanixiets/builds/$1\", \"PATCH /repos/cameronraysmith/vanixiets/check-runs/${checkRunId}\"]"
              expect_created
            }
            expect_success() {
              expect_lifecycle "$1"
              expect "check run completed success with the preview URL" requests \
                '.[2] | .auth == "Bearer rehearsal-forge-token" and .body == {
                  status: "completed",
                  conclusion: "success",
                  details_url: "${previewUrl}",
                  output: {
                    title: "Docs preview deployed",
                    summary: "Docs preview of ${head12} for pull request #${pr}: ${previewUrl}"
                  }
                }'
            }
            # expect_failure <build number> <error>: exit 1, the error printed,
            # and the check run completed as a failure carrying it.
            expect_failure() {
              expect_status 1
              expect_line "error: $2"
              expect_lifecycle "$1"
              expect "check run completed failure with the error" requests \
                '.[2].body == {
                  status: "completed",
                  conclusion: "failure",
                  output: {
                    title: "Docs preview failed",
                    summary: ("Docs preview of ${head12} failed: " + $error)
                  }
                }' --arg error "$2"
            }

            export NIXBOT_EVENT_KIND=pull_request
            export NIXBOT_EVENT_JSON=$TMPDIR/event.json
            export NIXBOT_PR_NUMBER=${pr}
            export NIXBOT_PR_HEAD=${head}
            other="$(attr checks.x86_64-linux.other succeeded /nix/store/00000000000000000000000000000000-other)"

            build 11 succeeded "[$other, $(attr ${docsAttr} succeeded ${payload})]"
            event 11
            run succeeded
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
            expect_deployed
            expect_success 11

            build 12 succeeded "[$(attr ${docsAttr} skipped_local ${payload})]"
            event 12
            run skipped-local
            expect_status 0
            expect_deployed
            expect_success 12

            build 13 succeeded "[$(attr ${docsAttr} failed ${payload})]"
            event 13
            run failed-attr
            expect_failure 13 "nixbot build 13 attribute ${docsAttr} is failed"
            expect_not_deployed

            build 14 succeeded "[$other]"
            event 14
            run missing-attr
            expect_failure 14 "nixbot build 14 has no attribute ${docsAttr}"
            expect_not_deployed

            build 15 failed "[$(attr ${docsAttr} succeeded ${payload})]"
            event 15
            run build-not-succeeded
            expect_failure 15 "nixbot build 15 is failed, not succeeded"
            expect_not_deployed

            event 16
            run build-not-found
            expect_failure 16 "cannot fetch nixbot build 16 from $NIXBOT_API_URL/api/repos/github/cameronraysmith/vanixiets/builds/16"
            expect_not_deployed

            build 17 succeeded "[$(attr ${docsAttr} succeeded /tmp/payload)]"
            event 17
            run output-not-store-path
            expect_failure 17 "nixbot build 17 attribute ${docsAttr} has no store path output: /tmp/payload"
            expect_not_deployed

            build 18 succeeded "[$(attr ${docsAttr} succeeded ${unrealisable})]"
            event 18
            run output-unrealisable
            expect_failure 18 "cannot realise ${unrealisable}"
            expect_not_deployed

            event 11
            STUB_DEPLOY=fail run deploy-failure
            expect_failure 11 "deploy-docs preview failed for ${payload}"
            expect_deployed

            STUB_DEPLOY=no-url run deploy-no-url
            expect_failure 11 "deploy-docs preview did not print exactly one DEPLOY-DOCS-PREVIEW-URL line"
            expect_deployed

            # malformed <name> <error>: refused before any request or deploy.
            malformed() {
              run "$1"
              expect_status 1
              expect_line "error: $2"
              expect_requests '[]'
              expect_not_deployed
            }
            NIXBOT_EVENT_KIND=push malformed malformed-kind "expected a pull_request event, got push"
            NIXBOT_PR_HEAD=${head12} malformed malformed-head "malformed event (pr=${pr} head=${head12} build=11)"
            NIXBOT_PR_NUMBER=7x malformed malformed-pr "malformed event (pr=7x head=${head} build=11)"
            GITHUB_FORGE_TOKEN= malformed missing-forge-token "GITHUB_FORGE_TOKEN is not set"
            echo '{"build":{}}' > "$TMPDIR/event.json"
            malformed malformed-build "malformed event (pr=${pr} head=${head} build=)"
            event 11

            touch "$STUB_STATE/post-down"
            run check-run-create-refused
            expect_status 0
            expect_deployed
            expect_requests '["POST /repos/cameronraysmith/vanixiets/check-runs", "GET /api/repos/github/cameronraysmith/vanixiets/builds/11"]'
            rm "$STUB_STATE/post-down"

            touch "$STUB_STATE/patch-down"
            run check-run-complete-refused
            expect_status 0
            expect_deployed
            expect_lifecycle 11
            STUB_DEPLOY=fail run check-run-complete-refused-after-failure
            expect_status 1
            expect_line "error: deploy-docs preview failed for ${payload}"
            expect_lifecycle 11
            rm "$STUB_STATE/patch-down"

            touch $out
          '';
    };
}
