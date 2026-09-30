# Behavioural check: every mode of the deploy-docs program the docs effect
# and the docs recipes run, which otherwise only run after a merge, on a pull
# request event or from an operator's shell.
#
# The effect lists this check as a rehearsal in its inputs, so the gated
# `nix build <effect>^*` on pull requests and merge-queue batches runs it.
#
# One python server stands in for the network: nixbot's build API from
# fixture files, GitHub's check-runs and pulls APIs, and a Cloudflare API
# implementing the endpoints wrangler@4.145.0 calls for `preview`
# (@cloudflare/deploy-helpers src/preview/api.ts and
# src/deploy/helpers/assets.ts),
# `preview delete`, `versions list` and `deployments list`
# (src/deploy/helpers/versions-api.ts). An absent Preview answers 404 with
# API error 10025, the code wrangler itself reads as "Preview not found"
# (deploy-helpers src/preview/preview.ts). Every request is logged as JSONL:
# GitHub and nixbot requests in one log, Cloudflare requests in another.
#
# A wrangler stub records each invocation's argv, working directory, env file
# and parsed --config, then runs the pinned real wrangler with the identical
# argv, so wrangler's own grammar and config validation judge deploy.sh:
# `deploy` as a --dry-run (it has no API-free mode otherwise), every other
# command for real against the loopback API through CLOUDFLARE_API_BASE_URL
# (workers-utils src/environment-variables/misc-variables.ts). The stub fails
# a call the real wrangler rejected, and one where wrangler answered its own
# confirmation prompt: without a TTY wrangler's confirm() takes its fallback
# value, `yes` for `preview delete` (wrangler src/dialogs.ts), so a missing
# --skip-confirmation would otherwise pass silently.
#
# nix-store is the real one against a chroot store in $TMPDIR holding one
# registered path, the pull request payload fixture, which is a sandbox input
# and so readable at its real store path. Secrets are fixed dummies, and
# main's head is a file:// URL.
#
# Asserted: production deploys the built-in payload's own config and
# cross-checks the deployments list, a superseded run deploys nothing, and a
# version not at 100% fails. A manual preview deploys a Preview from a config
# synthesized from a fixed shape (previews {}, no main, build, bindings or
# routes) with --ignore-base-config, prints the URL from wrangler's NDJSON
# record, sanitizes its name, refuses a payload holding a symlink and never
# runs a payload's build command. The pull-request rows cover the trust
# matrix, nixbot build and attribute statuses, malformed events, Cloudflare
# failures, the docs-preview check-run lifecycle and the pull request's
# currency: one no longer open at the event's head is skipped before any
# nixbot or Cloudflare request, and one that closed during the upload has
# its Preview deleted again. pull-request-closed deletes the Preview, reports
# an absent one as success and fails on any other API error. The listings
# print the newest rows first, truncated to --limit. A missing Cloudflare
# secret fails every mode before any request.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      deployDocsProgram = config.apps.deploy-docs.program;
      payload = config.packages.vanixiets-docs;
      realWrangler = "${config.packages.vanixiets-docs-deps}/packages/docs/node_modules/.bin/wrangler";

      rev = "0123456789abcdef0123456789abcdef01234567";
      rev12 = builtins.substring 0 12 rev;
      otherRev = "fedcba9876543210fedcba9876543210fedcba98";
      versionId = "11111111-2222-4333-8444-555555555555";
      pr = "7";
      previewUrl = "https://pr-${pr}-infra-docs.sciexp.workers.dev";
      checkRunId = "4242";
      docsAttr = "checks.x86_64-linux.package-vanixiets-docs";
      unrealisable = "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-vanixiets-docs";

      # The docs nixbot built for the pull request: a store path the check
      # can read, distinguishable from the built-in payload by its marker.
      prPayload = pkgs.runCommand "vanixiets-docs-pull-request" { } ''
        mkdir -p $out/dist/client
        echo '<!doctype html><title>pull request</title>' > $out/dist/client/index.html
        printf pull-request > $out/dist/client/marker.txt
        cp ${payload}/dist/client/wrangler.json $out/dist/client/wrangler.json
      '';

      server = pkgs.writeText "deploy-docs-stub-server.py" ''
        import base64
        import email.parser
        import email.policy
        import json
        import os
        import pathlib
        import threading
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        from urllib.parse import unquote, urlsplit

        state = pathlib.Path(os.environ["STUB_STATE"])
        previews = state / "previews"
        builds = "/api/repos/github/cameronraysmith/vanixiets/builds/"
        check_runs = "/repos/cameronraysmith/vanixiets/check-runs"
        pull = "/repos/cameronraysmith/vanixiets/pulls/${pr}"
        account = "/client/v4/accounts/rehearsal-dummy-account"
        worker = "/workers/workers/infra-docs"
        script = "/workers/scripts/infra-docs"
        lock = threading.Lock()
        manifest = {}


        def created(i):
            return "2026-01-%02dT00:00:00.000000Z" % i


        # Twelve of each, served out of order: wrangler keeps the ten most
        # recent versions (src/versions/list.ts) and sorts both lists oldest
        # first. The newest deployment carries the version production deploys.
        order = [5, 12, 1, 9, 3, 11, 7, 2, 10, 4, 8, 6]
        versions = [{
            "id": "rehearsal-version-%02d" % i,
            "number": i,
            "metadata": {"created_on": created(i), "source": "wrangler", "author_email": "rehearsal@example.com"},
            "annotations": {"workers/tag": "tag-%02d" % i, "workers/message": "message %02d" % i},
        } for i in order]


        def deployments():
            percentage = int((state / "percentage").read_text())
            return [{
                "id": "rehearsal-deployment-%02d" % i,
                "created_on": created(i),
                "source": "wrangler",
                "strategy": "percentage",
                "author_email": "rehearsal@example.com",
                "annotations": {"workers/message": "deployment %02d" % i},
                "versions": [{"version_id": "${versionId}", "percentage": percentage}] if i == 12
                    else [{"version_id": "rehearsal-version-%02d" % i, "percentage": 100}],
            } for i in order]


        def preview(name):
            return {
                "id": "rehearsal-preview-" + name,
                "name": name,
                "slug": name,
                "urls": [] if (state / "cf-no-urls").exists() else ["https://%s-infra-docs.sciexp.workers.dev" % name],
                "created_on": created(1),
                "updated_on": created(1),
            }


        def multipart(content_type, raw):
            message = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
                b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + raw)
            return [(part.get_param("name", header="content-disposition"), part.get_filename(),
                     part.get_payload(decode=True)) for part in message.iter_parts()]


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

            def ok(self, result):
                self.reply(200, {"success": True, "errors": [], "messages": [], "result": result})

            def fail(self, status, code, message):
                self.reply(status, {"success": False, "errors": [{"code": code, "message": message}], "messages": [], "result": None})

            def log(self, name, entry):
                with lock, open(state / name, "a") as log:
                    log.write(json.dumps(entry) + "\n")

            def handle_any(self):
                length = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(length) if length else b""
                if self.path.startswith(account):
                    return self.cloudflare(self.path[len(account):], raw)
                self.log("requests.jsonl", {
                    "method": self.command,
                    "path": self.path,
                    "auth": self.headers.get("Authorization"),
                    "body": json.loads(raw) if raw else None,
                })
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
                elif self.command == "GET" and self.path == pull:
                    # The file `pull` names the state this GET reports;
                    # `pull-next`, when present, replaces it afterwards.
                    current = (state / "pull").read_text().strip()
                    if (state / "pull-next").exists():
                        (state / "pull-next").rename(state / "pull")
                    if current == "down":
                        return self.reply(403, {"message": "Resource not accessible"})
                    return self.reply(200, {
                        "number": ${pr},
                        "state": "closed" if current == "closed" else "open",
                        "merged": current == "closed",
                        "head": {"sha": "${otherRev}" if current == "superseded" else "${rev}"},
                    })
                self.reply(404, {"message": "Not Found"})

            def cloudflare(self, path, raw):
                route = urlsplit(path).path
                content_type = self.headers.get("Content-Type") or ""
                if content_type.startswith("multipart/form-data"):
                    parts = multipart(content_type, raw)
                    if route.endswith("/deployments"):
                        body = {
                            "metadata": json.loads(next(data for name, _, data in parts if name == "metadata")),
                            "files": [filename for name, filename, _ in parts if name == "files"],
                        }
                    else:
                        # An asset bucket: one part per file, named by hash,
                        # holding the base64 of its bytes.
                        body = {"files": {}}
                        for name, _, data in parts:
                            content = base64.b64decode(data)
                            body["files"][manifest.get(name, name)] = (
                                content.decode(errors="replace") if len(content) <= 256 else None)
                else:
                    body = json.loads(raw) if raw else None
                self.log("cloudflare.jsonl", {
                    "method": self.command,
                    "path": path,
                    "auth": self.headers.get("Authorization"),
                    "body": body,
                })

                prefix = worker + "/previews/"
                if route.startswith(prefix) and "/" not in route[len(prefix):]:
                    name = unquote(route[len(prefix):])
                    if self.command == "DELETE" and (state / "cf-delete-down").exists():
                        return self.fail(500, 10013, "rehearsal: the API is failing")
                    if not (previews / name).exists():
                        return self.fail(404, 10025, "Preview not found.")
                    if self.command == "GET" or self.command == "PATCH":
                        return self.ok(preview(name))
                    if self.command == "DELETE":
                        (previews / name).unlink()
                        return self.ok(None)
                elif self.command == "POST" and route == worker + "/previews":
                    name = body["name"]
                    (previews / name).touch()
                    return self.ok(preview(name))
                elif self.command == "POST" and route.startswith(prefix) and route.endswith("/deployments"):
                    if (state / "cf-deploy-down").exists():
                        return self.fail(500, 10013, "rehearsal: the API is failing")
                    name = route[len(prefix):-len("/deployments")].removeprefix("rehearsal-preview-")
                    urls = preview(name)["urls"] and ["https://0123abcd-%s-infra-docs.sciexp.workers.dev" % name]
                    return self.ok({
                        "id": "rehearsal-deployment-" + name,
                        "preview_id": "rehearsal-preview-" + name,
                        "preview_name": name,
                        "urls": urls,
                        "created_on": created(1),
                    })
                elif self.command == "POST" and route == script + "/assets-upload-session":
                    entries = body["manifest"]
                    with lock:
                        manifest.update({entry["hash"]: path for path, entry in entries.items()})
                    return self.ok({"jwt": "rehearsal-upload-session",
                                    "buckets": [[entry["hash"] for entry in entries.values()]]})
                elif self.command == "POST" and route == "/workers/assets/upload":
                    return self.ok({"jwt": "rehearsal-assets-completion"})
                elif self.command == "GET" and route == script + "/versions":
                    return self.ok({"items": versions})
                elif self.command == "GET" and route == script + "/deployments":
                    return self.ok({"deployments": deployments()})
                self.fail(500, 10000, "rehearsal API: unexpected %s %s" % (self.command, path))

            do_GET = do_POST = do_PATCH = do_DELETE = handle_any


        httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        (state / "port.tmp").write_text(str(httpd.server_port))
        (state / "port.tmp").rename(state / "port")
        httpd.serve_forever()
      '';

      wranglerStub = pkgs.writeText "wrangler-stub.js" ''
        "use strict";
        const fs = require("fs");
        const os = require("os");
        const path = require("path");
        const { spawn } = require("child_process");

        const REAL_WRANGLER = "${realWrangler}";
        const VERSION = "${versionId}";
        const args = process.argv.slice(2);
        const option = (name) => {
          const arg = args.find((a) => a.startsWith(`''${name}=`));
          return arg === undefined ? null : arg.slice(name.length + 1);
        };
        // Found anywhere in argv, so a misplaced subcommand reaches the real
        // wrangler, whose grammar decides.
        const has = (...words) => args.some((_, i) => words.every((w, j) => args[i + j] === w));
        const command = has("preview", "delete") ? "preview delete"
          : has("preview") ? "preview"
          : has("versions", "list") ? "versions list"
          : has("deployments", "list") ? "deployments list"
          : has("deploy") ? "deploy"
          : null;

        const configPath = option("--config");
        const envFile = option("--env-file");
        const config = configPath === null ? null : JSON.parse(fs.readFileSync(configPath, "utf8"));

        fs.appendFileSync(process.env.STUB_LOG, JSON.stringify({
          args,
          cwdEntries: fs.readdirSync(process.cwd()),
          envFileBytes: envFile === null ? null : fs.statSync(envFile).size,
          configPath,
          config,
        }) + "\n");

        // Runs the real wrangler with deploy.sh's argv in deploy.sh's cwd.
        // HOME is private because the sandbox's is unwritable; the hidden
        // banner skips the npm update check. A .wrangler state directory it
        // leaves in the cwd is removed so the next call's record shows only
        // what deploy.sh put there.
        const real = (extraArgs, extraEnv) => new Promise((resolve) => {
          const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "wrangler-real-"));
          const hadState = fs.existsSync(".wrangler");
          const env = {
            ...process.env,
            HOME: path.join(scratch, "home"),
            WRANGLER_SEND_METRICS: "false",
            WRANGLER_HIDE_BANNER: "true",
            CLOUDFLARE_API_BASE_URL: process.env.STUB_CLOUDFLARE_API,
            ...extraEnv(scratch),
          };
          const child = spawn(process.execPath, [REAL_WRANGLER, ...args, ...extraArgs(scratch)], { env });
          let stdout = "", stderr = "";
          child.stdout.on("data", (d) => (stdout += d));
          child.stderr.on("data", (d) => (stderr += d));
          child.on("close", (status) => {
            if (!hadState) fs.rmSync(".wrangler", { recursive: true, force: true });
            fs.rmSync(scratch, { recursive: true, force: true });
            if (status !== 0) stderr += `wrangler stub: the real wrangler rejected ''${args.join(" ")}\n`;
            if (/Using fallback value in non-interactive context/.test(stdout + stderr)) {
              status = status || 1;
              stderr += `wrangler stub: the real wrangler answered its own prompt for ''${args.join(" ")}\n`;
            }
            resolve({ status, stdout, stderr });
          });
        });

        const main = async () => {
          if (command === "deploy") {
            const run = await real(
              (scratch) => ["--dry-run", "--outdir", path.join(scratch, "out")],
              (scratch) => ({ WRANGLER_OUTPUT_FILE_PATH: path.join(scratch, "events.ndjson") }),
            );
            if (run.status !== 0) return run;
            fs.appendFileSync(process.env.WRANGLER_OUTPUT_FILE_PATH,
              JSON.stringify({ type: "deploy", version_id: VERSION }) + "\n");
            return { status: 0, stdout: `Current Version ID: ''${VERSION}\n`, stderr: "" };
          }
          if (command !== null) return real(() => [], () => ({}));
          return { status: 1, stdout: "", stderr: `wrangler stub: unexpected command: ''${args.join(" ")}\n` };
        };

        main().then(({ status, stdout, stderr }) => {
          process.stdout.write(stdout);
          process.stderr.write(stderr);
          process.exitCode = status;
        });
      '';
    in
    {
      checks.deploy-docs-rehearsal =
        pkgs.runCommand "deploy-docs-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.jq
              pkgs.nix
              pkgs.nodejs_24
              pkgs.python3
            ];
            # The loopback APIs need local networking in the darwin sandbox.
            __darwinAllowLocalNetworking = true;
            meta.description = "behavioural check: every deploy-docs mode against the real wrangler and loopback APIs";
          }
          ''
            set -euo pipefail

            export HOME=$TMPDIR
            export NIX_REMOTE="local?root=$TMPDIR/store-root"
            export NIX_CONFIG="substituters ="
            mkdir -p "$TMPDIR/store-root${prPayload}"
            printf '%s\n\n0\n' ${prPayload} | nix-store --register-validity
            nix-store --realise ${prPayload} > /dev/null
            if nix-store --realise ${unrealisable} > /dev/null 2>&1; then
              echo "control: the chroot store realised an unregistered path" >&2
              exit 1
            fi

            export STUB_STATE=$TMPDIR/stub
            mkdir -p "$STUB_STATE/builds" "$STUB_STATE/previews"
            echo current > "$STUB_STATE/pull"
            echo 100 > "$STUB_STATE/percentage"
            python3 ${server} &
            server_pid=$!
            trap 'kill "$server_pid"' EXIT
            for _ in $(seq 100); do
              [ -f "$STUB_STATE/port" ] && break
              sleep 0.1
            done
            port="$(cat "$STUB_STATE/port")"

            export WRANGLER=${wranglerStub}
            export STUB_CLOUDFLARE_API="http://127.0.0.1:$port/client/v4"
            export CLOUDFLARE_API_TOKEN=rehearsal-dummy-token
            export CLOUDFLARE_ACCOUNT_ID=rehearsal-dummy-account
            export DEPLOY_DOCS_MAIN_SHA_URL="file://$TMPDIR/main.json"
            export NIXBOT_API_URL="http://127.0.0.1:$port"
            export GITHUB_API_URL="http://127.0.0.1:$port"
            export GITHUB_FORGE_TOKEN=rehearsal-forge-token
            export STUB_LOG

            fail() {
              echo "row '$name': $*" >&2
              exit 1
            }
            main_is() {
              printf '{"sha":"%s"}' "$1" > "$TMPDIR/main.json"
            }
            # run <name> <program args...>: runs deploy-docs with fresh
            # wrangler, GitHub and Cloudflare logs and records the exit status.
            run() {
              name=$1
              shift
              echo "--- $name"
              row="$TMPDIR/rows/$name"
              mkdir -p "$row"
              STUB_LOG="$row/wrangler.ndjson"
              : > "$STUB_LOG"
              : > "$STUB_STATE/requests.jsonl"
              : > "$STUB_STATE/cloudflare.jsonl"
              output="$row/output"
              status=0
              ${deployDocsProgram} "$@" > "$output" 2>&1 || status=$?
              cat "$output"
            }
            expect_status() {
              [ "$status" = "$1" ] || fail "exit status $status, expected $1"
            }
            expect_failure() {
              [ "$status" != 0 ] || fail "exit status 0, expected a failure"
            }
            expect_line() {
              grep -qxF -- "$1" "$output" || fail "missing output line: $1"
            }
            expect_no_line() {
              ! grep -q -- "$1" "$output" || fail "unexpected output matching: $1"
            }
            expect_calls() {
              local calls
              calls="$(wc -l < "$STUB_LOG")"
              [ "$calls" = "$1" ] || fail "wrangler invoked $calls times, expected $1"
            }
            # expect <description> <log> <jq filter over its entries> [jq args...]
            expect() {
              local description=$1 log=$2 filter=$3
              shift 3
              jq -se "$@" "$filter" "$log" > /dev/null || fail "$description"
            }
            expect_wrangler() {
              local description=$1
              shift
              expect "$description" "$STUB_LOG" "$@"
            }
            expect_cloudflare() {
              local description=$1
              shift
              expect "$description" "$STUB_STATE/cloudflare.jsonl" "$@"
            }
            expect_requests() {
              expect "requests are $1" "$STUB_STATE/requests.jsonl" \
                'map("\(.method) \(.path)") == $want' --argjson want "$1"
            }
            expect_cloudflare_requests() {
              expect_cloudflare "Cloudflare requests are $1" \
                'map("\(.method) \(.path)") == $want' --argjson want "$1"
            }
            # Neither wrangler nor any API was reached.
            expect_offline() {
              expect_calls 0
              expect_requests '[]'
              expect_cloudflare_requests '[]'
            }
            # expect_preview_argv <name> <message>: the one wrangler call is
            # `preview` with the contract's argv, globals after it.
            expect_preview_argv() {
              expect_calls 1
              expect_wrangler "wrangler preview of $1 with the Preview argv and trailing globals" \
                '.[0].args | .[:10] == ["preview", "--name", $name, "--worker-name", "infra-docs", "--tag", $tag, "--message", $message, "--ignore-base-config"]
                  and (.[10:] | map(split("=")[0])) == ["--config", "--env-file"]' \
                --arg name "$1" --arg tag ${rev12} --arg message "$2"
            }
            # expect_preview_deployed <name> <message> <marker json>: wrangler
            # created one deployment of Preview <name> holding no code but
            # wrangler's own no-op Worker for assets-only configs
            # (src/deployment-bundle/resolve-entry.ts) and no bindings, and
            # uploaded the payload's assets with the Cloudflare token.
            expect_preview_deployed() {
              expect_cloudflare "Cloudflare requests carry the API token" \
                'all(.[]; (.path | startswith("/workers/assets/upload")) or .auth == "Bearer rehearsal-dummy-token")'
              expect_cloudflare "a deployment of Preview $1 carries only assets, the no-op Worker, compatibility settings and annotations" \
                '[.[] | select(.method == "POST" and .path == "/workers/workers/infra-docs/previews/rehearsal-preview-\($name)/deployments")]
                  | length == 1 and (.[0].body | (.files - ["no-op-worker.js", "_headers", "_redirects"]) == []
                    and (.metadata | keys) == ["annotations", "assets", "compatibility_date", "compatibility_flags", "main_module"]
                    and .metadata.main_module == "no-op-worker.js"
                    and .metadata.assets.jwt == "rehearsal-assets-completion"
                    and .metadata.annotations == {"workers/message": $message, "workers/tag": $tag}
                    and .metadata.compatibility_date == $calls[0].config.compatibility_date
                    and .metadata.compatibility_flags == $calls[0].config.compatibility_flags)' \
                --arg name "$1" --arg tag ${rev12} --arg message "$2" \
                --slurpfile calls "$STUB_LOG"
              expect_cloudflare "the payload's assets are uploaded" \
                '[.[] | select(.path == "/workers/assets/upload?base64=true") | .body.files] | add
                  | has("/index.html") and .["/marker.txt"] == $marker' \
                --argjson marker "$3"
            }
            # expect_preview_config: the config wrangler previewed from has
            # only the fixed shape.
            expect_preview_config() {
              expect_wrangler "preview config is the fixed assets-only shape with previews {}" \
                '.[0].config | (keys | sort) == ["assets", "compatibility_date", "compatibility_flags", "name", "preview_urls", "previews", "workers_dev"]
                  and .name == "infra-docs" and .previews == {} and .workers_dev == false and .preview_urls == true
                  and (.assets | keys) == ["directory"] and (.assets.directory | startswith("/"))'
            }

            # Control: the real wrangler behind the stub runs a build command
            # handed to it in a preview config, then rejects the config's
            # missing entry point, so the sentinel's absence below means
            # deploy.sh did not pass it on.
            mkdir "$TMPDIR/fixtures"
            # fixture <name> <wrangler.json>: an assets-only payload.
            fixture() {
              local dir="$TMPDIR/fixtures/$1"
              mkdir -p "$dir/dist/client"
              echo '<!doctype html><title>fixture</title>' > "$dir/dist/client/index.html"
              printf '%s' "$2" > "$dir/dist/client/wrangler.json"
            }
            fixture_config='{"name":"infra-docs","compatibility_date":"2025-10-06","compatibility_flags":["nodejs_compat"]}'
            fixture override "$fixture_config"
            printf override > "$TMPDIR/fixtures/override/dist/client/marker.txt"
            fixture symlink "$fixture_config"
            ln -s /etc/passwd "$TMPDIR/fixtures/symlink/dist/client/leak"
            sentinel="$TMPDIR/build-command-ran"
            fixture build-command "$(jq -n --arg command "touch $sentinel" '{
              name: "attacker",
              main: "worker.js",
              compatibility_date: "2025-10-06",
              compatibility_flags: ["nodejs_compat"],
              build: { command: $command },
              routes: [{ pattern: "infra.cameronraysmith.net", custom_domain: true }],
              kv_namespaces: [{ binding: "KV", id: "0" }],
              previews: { kv_namespaces: [{ binding: "KV", id: "0" }] }
            }')"

            name=stub-runs-build-command
            STUB_LOG="$TMPDIR/control.ndjson" \
              node "$WRANGLER" preview --name control --worker-name infra-docs \
              --config="$TMPDIR/fixtures/build-command/dist/client/wrangler.json" \
              --env-file=/dev/null > /dev/null 2>&1 || true
            [ -e "$sentinel" ] || fail "stub did not run the build command"
            rm "$sentinel"

            # --- production

            main_is ${rev}
            run production-current production --rev ${rev}
            expect_status 0
            expect_line "deployed nix-built payload to production"
            expect_line "  Worker Version ID: ${versionId}"
            expect_line "DEPLOY-DOCS-ACTION: deploy (version ${versionId})"
            expect_calls 2
            expect_wrangler "deploy runs as infra-docs with a message naming the deployer" \
              '.[0].args | index(["deploy", "--name", "infra-docs", "--message", "Deployed by nixbot from main at ${builtins.substring 0 7 rev}"]) == 0'
            expect_wrangler "deploy uses the payload's config" \
              '.[0].config == $config[0] and (.[0].configPath | endswith("/payload/dist/client/wrangler.json"))' \
              --slurpfile config ${payload}/dist/client/wrangler.json
            expect_wrangler "deployments list is cross-checked" \
              '.[1].args | index(["deployments", "list", "--name", "infra-docs", "--json"]) == 0'
            expect_cloudflare_requests '["GET /workers/scripts/infra-docs/deployments"]'

            main_is ${otherRev}
            run production-superseded production --rev ${rev}
            expect_status 0
            expect_line "DEPLOY-DOCS-ACTION: superseded (main is ${otherRev})"
            expect_offline

            main_is ${rev}
            echo 50 > "$STUB_STATE/percentage"
            run production-partial production --rev ${rev}
            echo 100 > "$STUB_STATE/percentage"
            expect_failure
            expect_line "error: version ${versionId} is not at 100% in deployments list"
            expect_calls 2

            run production-missing-rev production
            expect_status 2
            expect_line "error: --rev is required"
            expect_offline

            run production-short-rev production --rev ${rev12}
            expect_status 2
            expect_line "error: --rev must be a full 40-hex commit SHA, got '${rev12}'"
            expect_offline

            run production-rejects-payload production --rev ${rev} --payload "$TMPDIR/fixtures/override"
            expect_status 2
            expect_line "error: --payload is not valid for production"
            expect_offline

            # --- manual preview

            run preview preview --rev ${rev} --name pr-7 --deployed-by rehearsal
            expect_status 0
            [ "$(grep -c '^DEPLOY-DOCS-PREVIEW-URL: ' "$output")" = 1 ] \
              || fail "expected exactly one DEPLOY-DOCS-PREVIEW-URL line"
            expect_line "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
            expect_preview_argv pr-7 "[pr-7] ${rev12} deployed by rehearsal"
            expect_preview_config
            expect_wrangler "preview config keeps the payload's compatibility settings" \
              '.[0].config | .compatibility_date == $config[0].compatibility_date and .compatibility_flags == $config[0].compatibility_flags' \
              --slurpfile config ${payload}/dist/client/wrangler.json
            expect_cloudflare_requests '[
              "GET /workers/workers/infra-docs/previews/pr-7",
              "POST /workers/workers/infra-docs/previews?ignore_base_config=true",
              "POST /workers/scripts/infra-docs/assets-upload-session",
              "POST /workers/assets/upload?base64=true",
              "POST /workers/workers/infra-docs/previews/rehearsal-preview-pr-7/deployments"
            ]'
            expect_cloudflare "the Preview is created as pr-7" '.[1].body == {name: "pr-7"}'
            expect_preview_deployed pr-7 "[pr-7] ${rev12} deployed by rehearsal" null
            expect_requests '[]'

            run preview-existing preview --rev ${rev} --name pr-7
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
            expect_cloudflare "an existing Preview gets a new deployment, not a new Preview" \
              'map(select(.path | startswith("/workers/workers/infra-docs/previews"))) | map("\(.method) \(.path)")
                == ["GET /workers/workers/infra-docs/previews/pr-7", "POST /workers/workers/infra-docs/previews/rehearsal-preview-pr-7/deployments"]'
            rm "$STUB_STATE/previews/pr-7"

            run preview-override preview --rev ${rev} --name feature/Some_Branch --payload "$TMPDIR/fixtures/override"
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW-URL: https://feature-some-branch-infra-docs.sciexp.workers.dev"
            expect_preview_argv feature-some-branch "[feature-some-branch] ${rev12} deployed by nixbot"
            expect_preview_deployed feature-some-branch "[feature-some-branch] ${rev12} deployed by nixbot" '"override"'

            long_name="Feature/$(printf 'x%.0s' $(seq 60))"
            run preview-long-name preview --rev ${rev} --name "$long_name"
            expect_status 0
            expect_calls 1
            expect_wrangler "a long name is sanitized to at most 40 of [a-z0-9-]" \
              '.[0].args[2] | test("^[a-z0-9-]{1,40}$") and startswith("feature-x")'

            run preview-symlink preview --rev ${rev} --name pr-7 --payload "$TMPDIR/fixtures/symlink"
            expect_failure
            expect_line "error: payload entry is neither a regular file nor a directory: $TMPDIR/fixtures/symlink/dist/client/leak"
            expect_offline

            run preview-build-command preview --rev ${rev} --name pr-7 --payload "$TMPDIR/fixtures/build-command"
            expect_status 0
            expect_calls 1
            expect_preview_config
            expect_preview_deployed pr-7 "[pr-7] ${rev12} deployed by nixbot" null
            [ ! -e "$sentinel" ] || fail "the payload's build command ran"
            rm "$STUB_STATE/previews/pr-7"

            touch "$STUB_STATE/cf-no-urls"
            run preview-no-url preview --rev ${rev} --name pr-7
            rm "$STUB_STATE/cf-no-urls" "$STUB_STATE/previews/pr-7"
            expect_status 1
            grep -q '^error: wrangler preview reported no Preview URL in ' "$output" || fail "missing no-URL error"
            expect_no_line '^DEPLOY-DOCS-PREVIEW-URL'

            touch "$STUB_STATE/cf-deploy-down"
            run preview-api-failure preview --rev ${rev} --name pr-7
            rm "$STUB_STATE/cf-deploy-down" "$STUB_STATE/previews/pr-7"
            expect_status 1
            expect_line "error: wrangler preview failed for ${payload}"
            expect_no_line '^DEPLOY-DOCS-PREVIEW-URL'

            run preview-missing-rev preview --name pr-7
            expect_status 2
            expect_line "error: --rev is required"
            expect_offline

            run preview-uppercase-rev preview --rev ${lib.toUpper rev} --name pr-7
            expect_status 2
            expect_offline

            run preview-empty-name preview --rev ${rev} --name ""
            expect_status 2
            expect_line "error: preview requires a non-empty --name"
            expect_offline

            run preview-unsanitizable-name preview --rev ${rev} --name ///
            expect_status 2
            expect_line "error: --name '///' has no [a-z0-9] characters"
            expect_offline

            # --- pull-request

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
            # event <build number> [<pullRequest json> [<actor json>]]: the
            # event payload, a same-repository pull request by default.
            event() {
              jq -n --argjson n "$1" --argjson pr "''${2:-null}" --argjson actor "''${3:-null}" \
                '{build: {number: $n}, pullRequest: ($pr // {isFork: false})}
                  + if $actor then {actor: $actor} else {} end' > "$TMPDIR/event.json"
            }
            pr_message="[pr-${pr}] ${rev12} deployed by nixbot"
            expect_deployed() {
              expect_preview_argv pr-${pr} "$pr_message"
              expect_preview_config
              expect_preview_deployed pr-${pr} "$pr_message" '"pull-request"'
            }
            expect_not_deployed() {
              expect_calls 0
              expect_cloudflare_requests '[]'
            }
            expect_created() {
              expect "check run created in_progress on the head with the forge token" "$STUB_STATE/requests.jsonl" \
                '.[0] | .auth == "Bearer rehearsal-forge-token"
                  and .body == {name: "docs-preview", head_sha: $head, status: "in_progress"}' \
                --arg head ${rev}
            }
            check_run_post="POST /repos/cameronraysmith/vanixiets/check-runs"
            check_run_patch="PATCH /repos/cameronraysmith/vanixiets/check-runs/${checkRunId}"
            pull_get="GET /repos/cameronraysmith/vanixiets/pulls/${pr}"
            build_get() {
              printf 'GET /api/repos/github/cameronraysmith/vanixiets/builds/%s' "$1"
            }
            # requests <line...>: the JSON array of these request lines.
            requests() {
              jq -nc '$ARGS.positional' --args "$@"
            }
            expect_pull_read() {
              expect "the pull request is read with the forge token" "$STUB_STATE/requests.jsonl" \
                'map(select("\(.method) \(.path)" == $pull)) | length > 0 and all(.auth == "Bearer rehearsal-forge-token")' \
                --arg pull "$pull_get"
            }
            # expect_lifecycle <build number>: the pull request read, the
            # build looked up and the check run completed, with no upload.
            expect_lifecycle() {
              expect_requests "$(requests "$check_run_post" "$pull_get" "$(build_get "$1")" "$check_run_patch")"
              expect_created
              expect_pull_read
            }
            # expect_uploaded_lifecycle <build number>: as expect_lifecycle,
            # with the pull request read again after the upload.
            expect_uploaded_lifecycle() {
              expect_requests "$(requests "$check_run_post" "$pull_get" "$(build_get "$1")" "$pull_get" "$check_run_patch")"
              expect_created
              expect_pull_read
            }
            expect_success() {
              expect_uploaded_lifecycle "$1"
              expect "check run completed success with the preview URL" "$STUB_STATE/requests.jsonl" \
                'last | .auth == "Bearer rehearsal-forge-token" and .body == {
                  status: "completed",
                  conclusion: "success",
                  details_url: "${previewUrl}",
                  output: {
                    title: "Docs preview deployed",
                    summary: "Docs preview of ${rev12} for pull request #${pr}: ${previewUrl}"
                  }
                }'
            }
            # expect_completed <conclusion> <title> <summary>: the check run's
            # completion.
            expect_completed() {
              expect "check run completed $1 with title $2 and summary $3" "$STUB_STATE/requests.jsonl" \
                'last.body == {status: "completed", conclusion: $conclusion, output: {title: $title, summary: $summary}}' \
                --arg conclusion "$1" --arg title "$2" --arg summary "$3"
            }
            # expect_pr_failure <build number> <error>: exit 1, the error
            # printed, and the check run completed as a failure carrying it.
            expect_pr_failure() {
              expect_status 1
              expect_line "error: $2"
              expect_lifecycle "$1"
              expect_completed failure "Docs preview failed" "Docs preview of ${rev12} failed: $2"
            }

            export NIXBOT_EVENT_KIND=pull_request
            export NIXBOT_EVENT_JSON=$TMPDIR/event.json
            export NIXBOT_PR_NUMBER=${pr}
            export NIXBOT_PR_HEAD=${rev}
            other="$(attr checks.x86_64-linux.other succeeded /nix/store/00000000000000000000000000000000-other)"

            build 11 succeeded "[$other, $(attr ${docsAttr} succeeded ${prPayload})]"

            # trusted <name> <pullRequest json> [<actor json>]: previews build 11.
            trusted() {
              event 11 "$2" "''${3:-null}"
              run "$1" pull-request
              expect_status 0
              expect_line "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
              expect_deployed
              expect_success 11
            }
            trusted same-repo-bot \
              '{"isFork": false, "author": {"name": "github:renovate[bot]", "permission": "none"}}' \
              '{"name": "github:renovate[bot]", "permission": "none"}'
            trusted same-repo-admin \
              '{"isFork": false, "author": {"name": "github:alice", "permission": "admin"}}'
            trusted fork-labelled-by-writer \
              '{"isFork": true, "author": {"name": "github:mallory", "permission": "none"}}' \
              '{"name": "github:alice", "permission": "write"}'
            trusted fork-by-writer \
              '{"isFork": true, "author": {"name": "github:bob", "permission": "write"}}' \
              '{"name": "github:bob", "permission": "read"}'

            # completed_before_build <conclusion body jq>: the check run was
            # created and completed without a build lookup or a deploy.
            completed_before_build() {
              expect_not_deployed
              expect_requests "$(requests "$check_run_post" "$pull_get" "$check_run_patch")"
              expect_created
              expect_pull_read
              expect "check run completed with $1" "$STUB_STATE/requests.jsonl" "last.body == $1"
            }

            event 11 \
              '{"isFork": true, "author": {"name": "github:mallory", "permission": "read"}}' \
              '{"name": "github:mallory", "permission": "read"}'
            run fork-untrusted pull-request
            expect_status 0
            skip_reason="pull request #${pr} comes from a fork and neither its actor nor its author has write access (actor github:mallory: read, author github:mallory: read)"
            expect_line "skipped: $skip_reason"
            completed_before_build "{
              status: \"completed\",
              conclusion: \"neutral\",
              output: {
                title: \"Docs preview skipped\",
                summary: \"Docs preview of ${rev12} skipped: $skip_reason. A maintainer can preview it by adding any label to the pull request.\"
              }
            }"

            # fork_flag_invalid <name> <pullRequest json>: fails closed.
            fork_flag_invalid() {
              event 11 "$2"
              run "$1" pull-request
              expect_status 1
              expect_line "error: event has no boolean pullRequest.isFork"
              completed_before_build '{
                status: "completed",
                conclusion: "failure",
                output: {
                  title: "Docs preview failed",
                  summary: "Docs preview of ${rev12} failed: event has no boolean pullRequest.isFork"
                }
              }'
            }
            fork_flag_invalid fork-flag-missing '{"author": {"name": "github:alice", "permission": "admin"}}'
            fork_flag_invalid fork-flag-string '{"isFork": "false", "author": {"name": "github:alice", "permission": "admin"}}'

            event 11
            run succeeded pull-request
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
            expect_deployed
            expect_success 11

            build 12 succeeded "[$(attr ${docsAttr} skipped_local ${prPayload})]"
            event 12
            run skipped-local pull-request
            expect_status 0
            expect_deployed
            expect_success 12

            build 13 succeeded "[$(attr ${docsAttr} failed ${prPayload})]"
            event 13
            run failed-attr pull-request
            expect_pr_failure 13 "nixbot build 13 attribute ${docsAttr} is failed"
            expect_not_deployed

            build 14 succeeded "[$other]"
            event 14
            run missing-attr pull-request
            expect_pr_failure 14 "nixbot build 14 has no attribute ${docsAttr}"
            expect_not_deployed

            build 15 failed "[$(attr ${docsAttr} succeeded ${prPayload})]"
            event 15
            run build-not-succeeded pull-request
            expect_pr_failure 15 "nixbot build 15 is failed, not succeeded"
            expect_not_deployed

            event 16
            run build-not-found pull-request
            expect_pr_failure 16 "cannot fetch nixbot build 16 from $NIXBOT_API_URL/api/repos/github/cameronraysmith/vanixiets/builds/16"
            expect_not_deployed

            build 17 succeeded "[$(attr ${docsAttr} succeeded /tmp/payload)]"
            event 17
            run output-not-store-path pull-request
            expect_pr_failure 17 "nixbot build 17 attribute ${docsAttr} has no store path output: /tmp/payload"
            expect_not_deployed

            build 18 succeeded "[$(attr ${docsAttr} succeeded ${unrealisable})]"
            event 18
            run output-unrealisable pull-request
            expect_pr_failure 18 "cannot realise ${unrealisable}"
            expect_not_deployed

            event 11
            touch "$STUB_STATE/cf-deploy-down"
            run deploy-failure pull-request
            expect_pr_failure 11 "wrangler preview failed for ${prPayload}"
            expect_preview_argv pr-${pr} "$pr_message"

            rm "$STUB_STATE/cf-deploy-down"
            touch "$STUB_STATE/cf-no-urls"
            run deploy-no-url pull-request
            rm "$STUB_STATE/cf-no-urls"
            expect_status 1
            expect_lifecycle 11
            expect "check run completed failure naming the missing URL" "$STUB_STATE/requests.jsonl" \
              'last.body | .conclusion == "failure"
                and (.output.summary | startswith("Docs preview of ${rev12} failed: wrangler preview reported no Preview URL in "))'
            expect_preview_argv pr-${pr} "$pr_message"

            # pull_is <state> [<state from the second read on>]: what the
            # pulls API reports, current, closed, superseded or down.
            pull_is() {
              echo "$1" > "$STUB_STATE/pull"
              rm -f "$STUB_STATE/pull-next"
              [ $# -lt 2 ] || echo "$2" > "$STUB_STATE/pull-next"
            }
            # skipped_as <name> <state>: a pull request no longer open at the
            # event's head gets neither a nixbot lookup nor a Preview.
            skipped_as() {
              pull_is "$2"
              run "$1" pull-request
              pull_is current
              expect_status 0
              expect_line "DEPLOY-DOCS-PREVIEW: skipped ($2)"
              expect_no_line '^skipped: '
              completed_before_build "{
                status: \"completed\",
                conclusion: \"neutral\",
                output: {title: \"Docs preview skipped\", summary: \"pull request #${pr} is $2; no preview\"}
              }"
            }
            skipped_as closed-before-upload closed
            skipped_as superseded-before-upload superseded
            # The state is read before the trust rule, whose skip invites a
            # maintainer to label a pull request that is already closed.
            event 11 \
              '{"isFork": true, "author": {"name": "github:mallory", "permission": "read"}}' \
              '{"name": "github:mallory", "permission": "read"}'
            skipped_as closed-untrusted-fork closed
            event 11

            pull_is down
            run pull-state-failure pull-request
            pull_is current
            expect_status 1
            expect_line "error: cannot read the state of pull request #${pr}"
            expect_not_deployed
            expect_requests "$(requests "$check_run_post" "$pull_get" "$check_run_patch")"
            expect_completed failure "Docs preview failed" "Docs preview of ${rev12} failed: cannot read the state of pull request #${pr}"

            # expect_withdrawn_calls: wrangler deployed Preview pr-<N>, then
            # deleted it against the minimal config.
            expect_withdrawn_calls() {
              expect_calls 2
              expect_wrangler "wrangler deploys Preview pr-${pr}, then deletes it without a prompt" \
                '(.[0].args | .[:3] == ["preview", "--name", "pr-${pr}"])
                  and (.[1].args | .[:7] == ["preview", "delete", "--name", "pr-${pr}", "--skip-confirmation", "--worker-name", "infra-docs"])
                  and .[1].config == {name: "infra-docs", previews: {}}'
              expect_preview_deployed pr-${pr} "$pr_message" '"pull-request"'
              expect_cloudflare "Preview pr-${pr} is deleted after its deployment" \
                'map("\(.method) \(.path)") | last == "DELETE /workers/workers/infra-docs/previews/pr-${pr}"'
            }

            pull_is current closed
            run closed-during-upload pull-request
            pull_is current
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
            expect_line "DEPLOY-DOCS-PREVIEW: withdrawn (closed during upload)"
            expect_withdrawn_calls
            [ ! -e "$STUB_STATE/previews/pr-${pr}" ] || fail "the Preview still exists"
            expect_uploaded_lifecycle 11
            expect_completed neutral "Docs preview withdrawn" "pull request #${pr} closed during the upload; Preview pr-${pr} deleted"

            pull_is current closed
            touch "$STUB_STATE/cf-delete-down"
            run closed-during-upload-delete-failure pull-request
            rm "$STUB_STATE/cf-delete-down"
            pull_is current
            expect_status 1
            expect_line "error: wrangler preview delete failed for pr-${pr}"
            expect_no_line '^DEPLOY-DOCS-PREVIEW: '
            expect_withdrawn_calls
            expect_uploaded_lifecycle 11
            expect_completed failure "Docs preview failed" "Docs preview of ${rev12} failed: wrangler preview delete failed for pr-${pr}"

            # The newer head's run replaces this Preview under the same name.
            pull_is current superseded
            run superseded-during-upload pull-request
            pull_is current
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW-URL: ${previewUrl}"
            expect_no_line '^DEPLOY-DOCS-PREVIEW: '
            expect_deployed
            expect_success 11
            [ -e "$STUB_STATE/previews/pr-${pr}" ] || fail "the Preview was deleted"

            pull_is current down
            run pull-state-failure-after-upload pull-request
            pull_is current
            expect_status 1
            expect_line "error: cannot read the state of pull request #${pr}"
            expect_deployed
            expect_uploaded_lifecycle 11
            expect_completed failure "Docs preview failed" "Docs preview of ${rev12} failed: cannot read the state of pull request #${pr}"

            # malformed <name> <error>: refused before any request or deploy.
            malformed() {
              run "$1" pull-request
              expect_status 1
              expect_line "error: $2"
              expect_offline
            }
            NIXBOT_EVENT_KIND=push malformed malformed-kind "expected a pull_request event, got push"
            NIXBOT_PR_HEAD=${rev12} malformed malformed-head "malformed event (pr=${pr} head=${rev12} build=11)"
            NIXBOT_PR_NUMBER=7x malformed malformed-pr "malformed event (pr=7x head=${rev} build=11)"
            GITHUB_FORGE_TOKEN= malformed missing-forge-token "GITHUB_FORGE_TOKEN is not set"
            echo '{"build":{}}' > "$TMPDIR/event.json"
            malformed malformed-build "malformed event (pr=${pr} head=${rev} build=)"
            event 11

            touch "$STUB_STATE/post-down"
            run check-run-create-refused pull-request
            expect_status 0
            expect_deployed
            expect_requests "$(requests "$check_run_post" "$pull_get" "$(build_get 11)" "$pull_get")"
            rm "$STUB_STATE/post-down"

            touch "$STUB_STATE/patch-down"
            run check-run-complete-refused pull-request
            expect_status 0
            expect_deployed
            expect_uploaded_lifecycle 11
            touch "$STUB_STATE/cf-deploy-down"
            run check-run-complete-refused-after-failure pull-request
            rm "$STUB_STATE/cf-deploy-down"
            expect_status 1
            expect_line "error: wrangler preview failed for ${prPayload}"
            expect_lifecycle 11
            rm "$STUB_STATE/patch-down"

            # --- pull-request-closed

            export NIXBOT_EVENT_KIND=pull_request_closed
            expect_delete_argv() {
              expect_calls 1
              expect_wrangler "wrangler preview delete of pr-${pr} without a prompt, globals after it" \
                '.[0].args | .[:7] == ["preview", "delete", "--name", "pr-${pr}", "--skip-confirmation", "--worker-name", "infra-docs"]
                  and (.[7:] | map(split("=")[0])) == ["--config", "--env-file"]'
              expect_wrangler "preview delete runs against the minimal config" \
                '.[0].config == {name: "infra-docs", previews: {}}'
              expect_cloudflare_requests '["DELETE /workers/workers/infra-docs/previews/pr-${pr}"]'
              expect_requests '[]'
            }

            touch "$STUB_STATE/previews/pr-${pr}"
            run closed-deleted pull-request-closed
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW: deleted (pr-${pr})"
            expect_delete_argv
            [ ! -e "$STUB_STATE/previews/pr-${pr}" ] || fail "the Preview still exists"

            run closed-absent pull-request-closed
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW: absent (pr-${pr})"
            expect_delete_argv

            touch "$STUB_STATE/previews/pr-${pr}" "$STUB_STATE/cf-delete-down"
            run closed-api-failure pull-request-closed
            rm "$STUB_STATE/cf-delete-down" "$STUB_STATE/previews/pr-${pr}"
            expect_status 1
            expect_line "error: wrangler preview delete failed for pr-${pr}"
            expect_no_line '^DEPLOY-DOCS-PREVIEW:'
            expect_delete_argv

            NIXBOT_EVENT_KIND=pull_request run closed-wrong-kind pull-request-closed
            expect_status 1
            expect_line "error: expected a pull_request_closed event, got pull_request"
            expect_offline

            NIXBOT_PR_NUMBER=7x run closed-malformed-pr pull-request-closed
            expect_status 1
            expect_line "error: malformed event (pr=7x)"
            expect_offline

            # --- listings

            # expect_listed <kind> <ids...>: the rows name exactly these, in order.
            expect_listed() {
              local kind=$1
              shift
              [ "$(grep -oE "rehearsal-$kind-[0-9]{2}" "$output" | tr '\n' ' ')" = "$* " ] \
                || fail "listed $(grep -oE "rehearsal-$kind-[0-9]{2}" "$output" | tr '\n' ' '), expected $*"
            }
            ids() {
              local kind=$1 i
              shift
              for i in "$@"; do printf 'rehearsal-%s-%02d ' "$kind" "$i"; done
            }

            run versions-default versions
            expect_status 0
            # wrangler itself keeps only the ten most recent versions.
            expect_listed version $(ids version $(seq 12 -1 3))
            expect_wrangler "versions list targets infra-docs as JSON" \
              '.[0].args | .[:5] == ["versions", "list", "--name", "infra-docs", "--json"]'
            expect_cloudflare_requests '["GET /workers/scripts/infra-docs/versions?deployable=true"]'

            run versions-limit versions --limit 3
            expect_status 0
            expect_listed version $(ids version 12 11 10)

            run deployments-default deployments
            expect_status 0
            # The newest deployment's versions name the production version.
            expect_listed deployment $(ids deployment $(seq 12 -1 3))
            expect_wrangler "deployments list targets infra-docs as JSON" \
              '.[0].args | .[:5] == ["deployments", "list", "--name", "infra-docs", "--json"]'

            run deployments-limit deployments --limit 3
            expect_status 0
            expect_listed deployment $(ids deployment 12 11 10)

            run listing-bad-limit versions --limit 0
            expect_status 2
            expect_offline

            # --- missing secrets

            # main is elsewhere, so a secret check placed after main's head
            # fetch would exit 0 as superseded instead of failing.
            main_is ${otherRev}
            export NIXBOT_EVENT_KIND
            for secret in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
              for mode in production preview pull-request pull-request-closed versions deployments; do
                case "$mode" in
                  production) set -- production --rev ${rev} ;;
                  preview) set -- preview --rev ${rev} --name pr-7 ;;
                  *) set -- "$mode" ;;
                esac
                case "$mode" in
                  pull-request) NIXBOT_EVENT_KIND=pull_request ;;
                  *) NIXBOT_EVENT_KIND=pull_request_closed ;;
                esac
                saved="''${!secret}"
                unset "$secret"
                run "$mode-without-$secret" "$@"
                export "$secret=$saved"
                expect_status 1
                grep -qF "$secret is required" "$output" || fail "missing error naming $secret"
                expect_no_line '^DEPLOY-DOCS-'
                expect_offline
              done
            done

            # Every invocation ran from an empty directory with an empty env
            # file, so no .env could redirect wrangler's API base or token.
            cat "$TMPDIR"/rows/*/wrangler.ndjson \
              | jq -se 'all(.[]; .cwdEntries == [] and .envFileBytes == 0)' > /dev/null \
              || { echo "wrangler ran outside an empty directory or with a non-empty env file" >&2; exit 1; }

            touch $out
          '';
    };
}
