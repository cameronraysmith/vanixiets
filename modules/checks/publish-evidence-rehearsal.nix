# Behavioural check: the publish-evidence program, which otherwise only runs
# as the browser-evidence nixbot effect (build_finished and default-branch
# pushes) against nixbot, R2 and a pull request.
#
# A python server stands in for nixbot's build API and pr-comment API and
# for R2's S3 API at a path prefix, storing objects in $TMPDIR (where a row
# may seed a baseline receipt or a pull request marker) and logging every
# request (as JSONL, with each S3 request's credential scope and prefix, and
# raw bytes). nix-store is the real one against a chroot store in $TMPDIR
# holding the report fixtures, which are sandbox inputs and so readable at
# their real store paths.
#
# The report fixtures are synthetic trees in the artifact contract's shape
# (packages/docs/tests/report/README.md), built from the repository's own
# policy.ts matrix. A control first runs the repository validator on each:
# the publisher's rejections below are then its own, not the validator's,
# except for the invalid-evidence row and the absolute path, which the
# validator would reject too.
#
# Asserted: a passing and an assertion-failing report are published with the
# exact bundle (run.json, completion.json, referenced PNG screenshots) and
# the schemaVersion 3 receipt, a function of the report alone: its identity
# is [attribute, outPath] and <obs> the first 32 hex of that identity's
# compact JSON's SHA-256, so another build of the same report (a failed
# aggregate, a skipped_local attribute) reproduces it byte for byte. A
# repeat run is a no-op and a fresh destination receives identical bytes.
# Every rejected run exits 1 with its exact message and leaves no receipt
# or staging directory behind: another report's --out, a missing, failed,
# unfetchable or unrealisable report, traversal, absolute, symlinked or
# non-PNG attachments, build/report identity mismatches, a wrong event kind,
# malformed events and invalid evidence. Rows rejected from the event alone
# make no API request.
#
# Upload rows, each with its exact exit status, output lines, S3 requests
# (method, key, status, credential scope and prefix), comments and marker:
# main uploads to ttl-90d/v1/<obs>/ receipt last and never comments, and
# another main build of the same report writes nothing. A pull request build
# first probes ttl-90d for main's receipt of its report with a read-only
# credential: present, it is unaffected and uploads nothing; absent, it
# uploads to ttl-30d with a credential confined to ttl-30d/, upserts one
# marker comment linking the Worker URLs on evidence.vanixiets.net and
# records a `current` marker at ttl-30d/pr/<n>.json; a probe failure names
# its key. Retries and later builds of one report write no new objects. A
# reverted pull request supersedes its current comment once. The stub
# accepts only requests SigV4-signed with a temporary credential minted from
# the parent secret, enforces the token's scope and prefixPaths (negative
# controls sign their own read-only and ttl-30d credentials), no pull request
# row ever writes into ttl-90d, and no request in any row carries the parent
# secret. Other builds land under ttl-90d without probe or comment; a failed
# PUT names its key and writes no receipt; a corrupted remote receipt
# conflicts; missing R2 variables or NIXBOT_API_URL (main) fail before any
# request.
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
      publishEvidenceProgram = config.apps.publish-evidence.program;
      reportTools = ../../packages/docs/tests/report;

      rev = "0123456789abcdef0123456789abcdef01234567";
      otherRev = "fedcba9876543210fedcba9876543210fedcba98";
      reportAttr = "checks.x86_64-linux.package-vanixiets-docs-test-e2e-report";
      unrealisable = "/nix/store/zyxwvsrqpnmlkjihgfdcba9876543210-vanixiets-docs-e2e-report";
      screenshot = "test-results/reader-journey-chromium/test-failed-1.png";

      # Fixture credentials: the parent secret must never reach the stub.
      accountId = "abcdefabcdefabcdefabcdefabcdef01";
      accessKeyId = "a1b2c3d4e5f60718293a4b5c6d7e8f90";
      parentSecret = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0";
      taskToken = "rehearsal-task-token";
      prRev = "1111111111111111111111111111111111111111";
      mainRev = "2222222222222222222222222222222222222222";
      mainRev2 = "3333333333333333333333333333333333333333";
      affectedRev = "4444444444444444444444444444444444444444";
      laterRev = "5555555555555555555555555555555555555555";
      revertedRev = "6666666666666666666666666666666666666666";
      evidenceKeyRoot = "projects/vanixiets/browser-evidence";
      # The Worker URL of evidenceKeyRoot: the key without `projects/`.
      evidenceOrigin = "https://evidence.vanixiets.net/vanixiets/browser-evidence";

      # node fixture.mjs <variant> <out>: one synthetic report. The reader
      # journey of the first project carries the failed attempt, retried to
      # a pass (flaky) in `passing` and final everywhere else it fails;
      # `steady` passes at the first attempt, so it has no screenshot.
      fixture = pkgs.writeText "publish-evidence-report-fixture.mjs" ''
        import { mkdirSync, symlinkSync, writeFileSync } from "node:fs";
        import { dirname, join } from "node:path";
        import { requiredCases, requiredEngines } from "${reportTools}/policy.ts";

        const [variant, root] = process.argv.slice(2);
        // A 1x1 PNG: the publisher checks the signature, not the extension.
        const png = Buffer.from(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
          "base64",
        );
        const system = variant === "darwin" ? "aarch64-darwin" : "x86_64-linux";
        const config = variant === "negative-config" ? "playwright.negative.config.ts" : "playwright.config.ts";
        const projects = config === "playwright.config.ts" ? requiredEngines[system] : ["chromium"];
        const failing = ["failing", "traversal", "absolute", "symlink", "not-png"].includes(variant);
        const dir = "test-results/reader-journey-chromium";
        const shot =
          { traversal: dir + "/../reader-journey-chromium/test-failed-1.png", absolute: join(root, "${screenshot}") }[
            variant
          ] ?? "${screenshot}";
        const failure = [dir + "/trace.zip", shot];

        function write(name, data) {
          mkdirSync(dirname(join(root, name)), { recursive: true });
          writeFileSync(join(root, name), data);
        }
        write("playwright-report/index.html", "<html>report</html>");
        write(dir + "/trace.zip", "trace fixture");
        if (variant === "symlink") {
          write(dir + "/real.png", png);
          symlinkSync("real.png", join(root, "${screenshot}"));
        } else {
          write("${screenshot}", variant === "not-png" ? "screenshot fixture" : png);
        }

        const counts = { expected: 0, unexpected: 0, skipped: 0, flaky: 0 };
        const tests = [];
        const specs = [];
        const cases = requiredCases[config];
        for (const project of projects) {
          for (const [index, name] of cases.entries()) {
            const passed = { status: "passed", retry: 0, failureKind: null, attachments: [] };
            const failed = { status: "failed", retry: 0, failureKind: "product", attachments: failure };
            let attempts = [passed];
            if (project === projects[0] && name.startsWith("reader-journey.spec.ts::")) {
              if (failing) attempts = [failed];
              else if (variant === "passing") attempts = [failed, { ...passed, retry: 1 }];
            }
            const outcome =
              attempts.at(-1).status === "failed" ? "unexpected" : attempts.length > 1 ? "flaky" : "expected";
            counts[outcome]++;
            const id = project + "-" + index;
            tests.push({ id, project, case: name, title: name, outcome, expectedStatus: "passed", attempts });
            specs.push({
              id,
              tests: [
                {
                  expectedStatus: "passed",
                  status: outcome,
                  results: attempts.map(({ status, retry, attachments }) => ({
                    status,
                    retry,
                    attachments: attachments.map((path) => ({ path })),
                  })),
                },
              ],
            });
          }
        }
        write(
          "playwright-report/completion.json",
          JSON.stringify({
            schemaVersion: 1,
            status: failing ? "failed" : "passed",
            projects,
            errors: variant === "invalid" ? [{ message: "worker crashed" }] : [],
            tests,
          }),
        );
        write("playwright-report/results.json", JSON.stringify({ errors: [], stats: counts, suites: [{ specs }] }));
        write(
          "run.json",
          JSON.stringify({
            schemaVersion: 1,
            exitCode: failing ? 1 : 0,
            provenance: {
              site: "/nix/store/site",
              source: "/nix/store/source",
              dependencies: "/nix/store/dependencies",
              browsers: "/nix/store/browsers",
              node: "/nix/store/node",
              system,
              config,
              projects: projects.join(","),
              trace: "retain-on-failure",
              evidenceEpoch: "0",
            },
          }),
        );
      '';

      variants = [
        "passing"
        "steady"
        "failing"
        "traversal"
        "absolute"
        "symlink"
        "not-png"
        "darwin"
        "negative-config"
        "invalid"
      ];
      reports = lib.genAttrs variants (
        variant:
        pkgs.runCommand "vanixiets-docs-e2e-report-${variant}" {
          nativeBuildInputs = [ pkgs.nodejs_24 ];
        } "node ${fixture} ${variant} $out"
      );

      # The stub's S3 endpoint stands in for R2 at a path prefix: it accepts
      # only requests SigV4-signed with a temporary credential whose session
      # token is an HS256 JWT signed by the parent secret, with the claims
      # authenticate-r2-temp-credentials.mdx sets, and refuses (403) keys
      # outside the token's prefixPaths and writes (PUT, DELETE) under an
      # object-read-only scope, as R2 does. Every S3 request is logged with
      # the scope and prefixPaths of its credential (null when refused
      # before the claims are known). A `fail` file holding `<METHOD> <key>`
      # makes that request return 500.
      server = pkgs.writeText "publish-evidence-stub-server.py" ''
        import base64
        import hashlib
        import hmac
        import json
        import os
        import pathlib
        import time
        import urllib.parse
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        state = pathlib.Path(os.environ["STUB_STATE"])
        account = os.environ["STUB_ACCOUNT_ID"]
        access_key_id = os.environ["STUB_ACCESS_KEY_ID"]
        parent_secret = os.environ["STUB_PARENT_SECRET"].encode()
        task_token = os.environ["STUB_TASK_TOKEN"]
        repo = "/api/repos/github/cameronraysmith/vanixiets/builds"
        s3 = "/s3/"


        def b64url(data):
            return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))


        def sha256(data):
            return hashlib.sha256(data).hexdigest()


        def append(name, entry):
            with (state / name).open("a") as log:
                log.write(json.dumps(entry) + "\n")


        class Refused(Exception):
            pass


        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def reply(self, status, body=b"", content_type="application/json"):
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def handle_any(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                # Every byte the stub receives, for the parent-secret check.
                with (state / "raw.log").open("ab") as raw:
                    raw.write(self.requestline.encode() + b"\n" + bytes(self.headers) + body + b"\n")
                append("requests.jsonl", {"method": self.command, "path": self.path})
                url = urllib.parse.urlsplit(self.path)
                if url.path.startswith(s3):
                    return self.s3(url, body)
                if self.command == "POST" and url.path == "/api/v1/pr-comment":
                    return self.pr_comment(body)
                if self.command != "GET":
                    return self.reply(405)
                if url.path == repo and url.query:
                    commit = urllib.parse.parse_qs(url.query).get("commit", [""])[0]
                    fixture = state / "commits" / (commit + ".json")
                    if commit.isalnum() and fixture.is_file():
                        return self.reply(200, fixture.read_bytes())
                    return self.reply(200, b'{"items": [], "page": 1, "has_next": false}')
                if url.path.startswith(repo + "/"):
                    fixture = state / "builds" / (url.path[len(repo) + 1:] + ".json")
                    if fixture.is_file():
                        return self.reply(200, fixture.read_bytes())
                self.reply(404)

            do_GET = do_PUT = do_POST = do_HEAD = do_DELETE = handle_any

            def pr_comment(self, body):
                payload = json.loads(body)
                authorization = self.headers.get("Authorization", "")
                append("comments.jsonl", {
                    "authorization": authorization,
                    "contentType": self.headers.get("Content-Type"),
                    "body": payload.get("body"),
                    "marker": payload.get("marker"),
                })
                if authorization != "Bearer " + task_token:
                    return self.reply(401, b'{"detail": "invalid task token"}')
                self.reply(200, b"{}")

            def verify(self, path, query, body):
                """The JWT claims, or Refused: the temporary credential and
                the SigV4 signature it keys."""
                token = self.headers.get("x-amz-security-token")
                authorization = self.headers.get("Authorization", "")
                scheme = "AWS4-HMAC-SHA256 "
                if not token or not authorization.startswith(scheme):
                    raise Refused("no temporary credential")
                decoded = base64.b64decode(token, validate=True).decode()
                if not decoded.startswith("jwt/"):
                    raise Refused("session token is not jwt/<jwt>")
                jwt = decoded[len("jwt/"):]
                header, payload, signature = jwt.split(".")
                expected = hmac.new(parent_secret, f"{header}.{payload}".encode(), hashlib.sha256).digest()
                if not hmac.compare_digest(b64url(signature), expected):
                    raise Refused("JWT not signed by the parent secret")
                if json.loads(b64url(header)) != {"alg": "HS256", "typ": "JWT"}:
                    raise Refused("JWT header")
                claims = json.loads(b64url(payload))
                now = time.time()
                if not (
                    claims.get("bucket") == "sciexp"
                    and claims.get("scope") in ("object-read-only", "object-read-write")
                    and claims.get("sub") == account
                    and claims.get("iss") == access_key_id
                    and claims.get("aud") == self.headers.get("Host")
                    and claims.get("exp", 0) - claims.get("iat", 0) == 900
                    and claims["iat"] - 60 <= now <= claims["exp"]
                    and set(claims.get("paths", {})) == {"prefixPaths", "objectPaths"}
                ):
                    raise Refused("JWT claims " + json.dumps(claims))
                fields = dict(part.split("=", 1) for part in authorization[len(scheme):].split(", "))
                credential = fields["Credential"].split("/")
                if credential[0] != access_key_id or credential[2:] != ["auto", "s3", "aws4_request"]:
                    raise Refused("credential scope " + fields["Credential"])
                signed = fields["SignedHeaders"].split(";")
                if not {"host", "x-amz-date", "x-amz-security-token"} <= set(signed):
                    raise Refused("unsigned headers " + fields["SignedHeaders"])
                payload_hash = self.headers.get("x-amz-content-sha256") or sha256(body)
                if payload_hash not in ("UNSIGNED-PAYLOAD", sha256(body)):
                    raise Refused("payload hash")
                canonical = "\n".join([
                    self.command,
                    path,
                    query,
                    "".join(name + ":" + " ".join(self.headers.get(name, "").split()) + "\n" for name in signed),
                    ";".join(signed),
                    payload_hash,
                ])
                string_to_sign = "\n".join([
                    "AWS4-HMAC-SHA256",
                    self.headers["x-amz-date"],
                    "/".join(credential[1:]),
                    sha256(canonical.encode()),
                ])
                key = ("AWS4" + sha256(jwt.encode())).encode()
                for part in credential[1:]:
                    key = hmac.new(key, part.encode(), hashlib.sha256).digest()
                if not hmac.compare_digest(
                    hmac.new(key, string_to_sign.encode(), hashlib.sha256).hexdigest(), fields["Signature"]
                ):
                    raise Refused("SigV4 signature")
                return claims

            def s3(self, url, body):
                bucket, _, key = url.path[len(s3):].partition("/")
                entry = {
                    "method": self.command,
                    "key": key,
                    "contentType": self.headers.get("Content-Type"),
                    "ifNoneMatch": self.headers.get("If-None-Match"),
                    "scope": None,
                    "prefix": None,
                }
                try:
                    claims = self.verify(url.path, url.query, body)
                except (Refused, KeyError, ValueError) as e:
                    append("s3.jsonl", {**entry, "status": 403, "refused": str(e)})
                    return self.reply(403, b"AccessDenied", "application/xml")
                paths = claims["paths"]
                entry.update(scope=claims["scope"], prefix=paths["prefixPaths"])
                if bucket != "sciexp" or not (
                    any(key.startswith(p) for p in paths["prefixPaths"]) or key in paths["objectPaths"]
                ):
                    append("s3.jsonl", {**entry, "status": 403, "refused": "outside the token paths"})
                    return self.reply(403, b"AccessDenied", "application/xml")
                if claims["scope"] == "object-read-only" and self.command in ("PUT", "DELETE"):
                    append("s3.jsonl", {**entry, "status": 403, "refused": "read-only scope"})
                    return self.reply(403, b"AccessDenied", "application/xml")
                fail = state / "fail"
                if fail.is_file() and fail.read_text().split() == [self.command, key]:
                    append("s3.jsonl", {**entry, "status": 500})
                    return self.reply(500, b"InternalError", "application/xml")
                obj = state / "objects" / key
                if self.command in ("GET", "HEAD"):
                    status = 200 if obj.is_file() else 404
                    append("s3.jsonl", {**entry, "status": status})
                    if status == 200:
                        return self.reply(200, obj.read_bytes(), "application/octet-stream")
                    return self.reply(404, b"NoSuchKey", "application/xml")
                if self.command == "DELETE":
                    obj.unlink(missing_ok=True)
                    append("s3.jsonl", {**entry, "status": 204})
                    return self.reply(204)
                if self.command != "PUT":
                    append("s3.jsonl", {**entry, "status": 405})
                    return self.reply(405)
                if self.headers.get("If-None-Match") == "*" and obj.exists():
                    status = 412
                else:
                    status = 200
                    obj.parent.mkdir(parents=True, exist_ok=True)
                    obj.write_bytes(body)
                append("s3.jsonl", {**entry, "status": status})
                self.reply(status, b"", "application/xml")


        httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        (state / "port.tmp").write_text(str(httpd.server_port))
        (state / "port.tmp").rename(state / "port")
        httpd.serve_forever()
      '';

      # python3 client.py <method> <url> <scope> <prefix>: one S3 request
      # signed exactly as the publisher's, with a temporary credential this
      # client mints from CLIENT_PARENT_SECRET for <scope> on <prefix>; prints
      # the HTTP status. The negative controls use it to show the stub
      # enforces what the publisher's credentials claim.
      client = pkgs.writeText "publish-evidence-s3-client.py" ''
        import base64
        import hashlib
        import hmac
        import json
        import os
        import sys
        import time
        import urllib.error
        import urllib.parse
        import urllib.request

        method, url, scope, prefix = sys.argv[1:5]
        secret = os.environ["CLIENT_PARENT_SECRET"].encode()
        account = os.environ["CLIENT_ACCOUNT_ID"]
        access_key_id = os.environ["CLIENT_ACCESS_KEY_ID"]


        def b64url(data):
            return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


        parts = urllib.parse.urlsplit(url)
        iat = int(time.time())
        claims = {
            "bucket": "sciexp",
            "scope": scope,
            "paths": {"prefixPaths": [prefix], "objectPaths": []},
            "sub": account,
            "iss": access_key_id,
            "aud": parts.netloc,
            "iat": iat,
            "exp": iat + 900,
        }
        signing_input = b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode()) + "." + b64url(json.dumps(claims).encode())
        jwt = signing_input + "." + b64url(hmac.new(secret, signing_input.encode(), hashlib.sha256).digest())
        body = b"negative control" if method == "PUT" else b""
        amz_date = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
        scope_path = amz_date[:8] + "/auto/s3/aws4_request"
        headers = {
            "host": parts.netloc,
            "x-amz-content-sha256": hashlib.sha256(body).hexdigest(),
            "x-amz-date": amz_date,
            "x-amz-security-token": base64.b64encode(("jwt/" + jwt).encode()).decode(),
        }
        signed = sorted(headers)
        canonical = "\n".join([
            method,
            parts.path,
            parts.query,
            "".join(name + ":" + headers[name] + "\n" for name in signed),
            ";".join(signed),
            headers["x-amz-content-sha256"],
        ])
        string_to_sign = "\n".join([
            "AWS4-HMAC-SHA256",
            amz_date,
            scope_path,
            hashlib.sha256(canonical.encode()).hexdigest(),
        ])
        key = ("AWS4" + hashlib.sha256(jwt.encode()).hexdigest()).encode()
        for part in scope_path.split("/"):
            key = hmac.new(key, part.encode(), hashlib.sha256).digest()
        signature = hmac.new(key, string_to_sign.encode(), hashlib.sha256).hexdigest()
        request_headers = {
            "Host": parts.netloc,
            "x-amz-content-sha256": headers["x-amz-content-sha256"],
            "x-amz-date": amz_date,
            "x-amz-security-token": headers["x-amz-security-token"],
            "Authorization": "AWS4-HMAC-SHA256 Credential=" + access_key_id + "/" + scope_path
            + ", SignedHeaders=" + ";".join(signed) + ", Signature=" + signature,
        }
        if method == "PUT":
            request_headers["Content-Type"] = "application/octet-stream"
        request = urllib.request.Request(
            url, data=body if method == "PUT" else None, method=method, headers=request_headers
        )
        try:
            with urllib.request.urlopen(request) as response:
                print(response.status)
        except urllib.error.HTTPError as e:
            print(e.code)
      '';
    in
    {
      checks.publish-evidence-rehearsal =
        pkgs.runCommand "publish-evidence-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.findutils
              pkgs.gnugrep
              pkgs.jq
              pkgs.nix
              pkgs.nodejs_24
              pkgs.python3
            ];
            # The loopback API needs local networking in the darwin sandbox.
            __darwinAllowLocalNetworking = true;
            meta.description = "behavioural check: publish-evidence build-finished against a loopback nixbot API and chroot store";
          }
          ''
            set -euo pipefail

            # The fixtures the publisher's own checks reject are otherwise
            # valid evidence; the invalid one fails the validator itself.
            for report in ${
              lib.concatMapStringsSep " " (v: reports.${v}) [
                "passing"
                "steady"
                "failing"
                "traversal"
                "symlink"
                "not-png"
                "darwin"
                "negative-config"
              ]
            }; do
              node ${reportTools}/validate-report.ts validate "$report" > /dev/null \
                || { echo "control: fixture $report is not valid evidence" >&2; exit 1; }
            done
            for report in ${reports.invalid} ${reports.absolute}; do
              status=0
              node ${reportTools}/validate-report.ts validate "$report" > /dev/null 2>&1 || status=$?
              [ "$status" = 2 ] || { echo "control: validator exited $status for $report, expected 2" >&2; exit 1; }
            done

            export HOME=$TMPDIR
            export NIX_REMOTE="local?root=$TMPDIR/store-root"
            export NIX_CONFIG="substituters ="
            for report in ${lib.concatMapStringsSep " " (v: reports.${v}) variants}; do
              mkdir -p "$TMPDIR/store-root$report"
              printf '%s\n\n0\n' "$report" | nix-store --register-validity
              nix-store --realise "$report" > /dev/null
            done
            if nix-store --realise ${unrealisable} > /dev/null 2>&1; then
              echo "control: the chroot store realised an unregistered path" >&2
              exit 1
            fi

            export STUB_STATE=$TMPDIR/stub
            mkdir -p "$STUB_STATE/builds" "$STUB_STATE/commits" "$STUB_STATE/objects"
            touch "$STUB_STATE/raw.log"
            STUB_ACCOUNT_ID=${accountId} STUB_ACCESS_KEY_ID=${accessKeyId} \
              STUB_PARENT_SECRET=${parentSecret} STUB_TASK_TOKEN=${taskToken} \
              python3 ${server} &
            server_pid=$!
            # Teardown never decides the verdict: the rows do. The server may
            # already be gone, so neither kill nor wait may fail the trap.
            trap 'kill "$server_pid" 2> /dev/null || :; wait "$server_pid" 2> /dev/null || :' EXIT
            for _ in $(seq 600); do
              [ -f "$STUB_STATE/port" ] && break
              kill -0 "$server_pid" 2> /dev/null \
                || { echo "control: the stub API server exited before listening" >&2; exit 1; }
              sleep 0.1
            done
            [ -f "$STUB_STATE/port" ] || { echo "control: the stub API server did not listen within 60s" >&2; exit 1; }
            port="$(cat "$STUB_STATE/port")"

            export NIXBOT_API_URL="http://127.0.0.1:$port"
            export NIXBOT_EVENT_KIND=build_finished
            export NIXBOT_EVENT_JSON=$TMPDIR/event.json
            export NIXBOT_API_TOKEN=${taskToken}
            export R2_EVIDENCE_ACCESS_KEY_ID=${accessKeyId}
            export R2_EVIDENCE_SECRET_ACCESS_KEY=${parentSecret}
            export CLOUDFLARE_ACCOUNT_ID=${accountId}
            export PUBLISH_EVIDENCE_S3_ENDPOINT="http://127.0.0.1:$port/s3"
            pub=$TMPDIR/pub
            mkdir "$pub"

            fail() {
              echo "row '$name': $*" >&2
              exit 1
            }
            # reset: fresh request, S3 and comment logs for the next row.
            reset() {
              : > "$STUB_STATE/requests.jsonl"
              : > "$STUB_STATE/s3.jsonl"
              : > "$STUB_STATE/comments.jsonl"
            }
            # run <name> <program args...>: runs publish-evidence with fresh
            # logs and records the exit status. Each row's S3 requests are
            # also kept, tagged with the row, for assertions across rows.
            run() {
              name=$1
              shift
              echo "--- $name"
              reset
              output="$TMPDIR/rows/$name"
              mkdir -p "$(dirname "$output")"
              status=0
              ${publishEvidenceProgram} "$@" > "$output" 2>&1 || status=$?
              cat "$output"
              jq -c --arg row "$name" '. + {row: $row}' "$STUB_STATE/s3.jsonl" >> "$TMPDIR/s3-rows.jsonl"
            }
            expect_status() {
              [ "$status" = "$1" ] || fail "exit status $status, expected $1"
            }
            expect_line() {
              grep -qxF -- "$1" "$output" || fail "missing output line: $1"
            }
            # expect_lines <line...>: exactly these PUBLISH-EVIDENCE lines, in
            # order (none when called without arguments).
            expect_lines() {
              local actual expected
              actual="$(grep '^PUBLISH-EVIDENCE:' "$output" || :)"
              expected="$(printf '%s\n' "$@")"
              [ "$actual" = "$expected" ] \
                || fail "PUBLISH-EVIDENCE lines $(jq -Rsc . <<< "$actual"), expected $(jq -Rsc . <<< "$expected")"
            }
            # expect_build_requests <build number|none>: the requests made.
            expect_build_requests() {
              local expected='[]'
              [ "$1" = none ] || expected="$(jq -nc --arg path "/api/repos/github/cameronraysmith/vanixiets/builds/$1" '[{method: "GET", path: $path}]')"
              jq -se --argjson expected "$expected" '. == $expected' "$STUB_STATE/requests.jsonl" > /dev/null \
                || fail "requests $(jq -sc . "$STUB_STATE/requests.jsonl"), expected $expected"
            }
            # rejected <build number|none> <message> <out>: exit 1 with the
            # message, and no publication at <out>.
            rejected() {
              expect_status 1
              expect_line "error: $2"
              expect_build_requests "$1"
              [ ! -e "$3" ] || fail "rejected run created $3"
            }

            # build <number> <aggregate status> <commit> <attributes json>
            build() {
              jq -n --argjson n "$1" --arg status "$2" --arg rev "$3" --argjson attributes "$4" \
                '{build: {number: $n, status: $status, commit_sha: $rev}, attributes: $attributes}' \
                > "$STUB_STATE/builds/$1.json"
            }
            # attr <name> <status> <out> [<cached>]: one attribute entry.
            attr() {
              jq -nc --arg attr "$1" --arg status "$2" --arg out "$3" --argjson cached "''${4:-false}" \
                '{attr: $attr, system: "x86_64-linux", status: $status, cached: $cached, outputs: {out: $out}}'
            }
            report() {
              attr ${reportAttr} "$@"
            }
            # event <number json> [<status> [<rev> [<pull request number>]]]:
            # the build_finished payload, with a pullRequest when numbered.
            event() {
              jq -n --argjson n "$1" --arg status "''${2:-succeeded}" --arg rev "''${3:-${rev}}" --arg pr "''${4:-}" \
                '{build: {number: $n, url: "https://nixbot.example/builds/\($n)", status: $status,
                  branch: "main", rev: $rev, previousStatus: "succeeded", failedAttrs: []}}
                + if $pr == "" then {} else {pullRequest: {number: ($pr | tonumber), title: "evidence",
                  url: "https://github.com/cameronraysmith/vanixiets/pull/\($pr)"}} end' \
                > "$NIXBOT_EVENT_JSON"
            }
            other="$(attr checks.x86_64-linux.other succeeded /nix/store/00000000000000000000000000000000-other)"

            # obs <report>: the contract's <obs>, the first 32 hex of the
            # SHA-256 of the compact identity [attribute, outPath] (no
            # newline), computed here independently of the publisher.
            obs() {
              printf '["%s","%s"]' ${reportAttr} "$1" | sha256sum | cut -c1-32
            }

            # expect_receipt <receipt> <report> <passed> <counts json>
            # <destination json|null> <file...>: the exact schemaVersion 3
            # receipt of <report>'s bundle <file...>: content only, nothing
            # of the build that carried the report.
            expect_receipt() {
              local receipt=$1 report=$2 passed=$3 counts=$4 destination=$5
              shift 5
              local files
              files="$(for file in "$@"; do
                jq -nc --arg path "$file" --arg sha256 "$(sha256sum "$report/$file" | cut -d' ' -f1)" \
                  --argjson bytes "$(wc -c < "$report/$file")" '{path: $path, sha256: $sha256, bytes: $bytes}'
              done | jq -sc .)"
              jq -e \
                --arg report "$report" \
                --arg obs "$(obs "$report")" \
                --argjson passed "$passed" \
                --argjson counts "$counts" \
                --argjson files "$files" \
                --argjson destination "$destination" \
                --slurpfile run "$report/run.json" \
                '({
                  schemaVersion: 3,
                  identity: {attribute: "${reportAttr}", outPath: $report},
                  obs: $obs,
                  attribute: "${reportAttr}",
                  outPath: $report,
                  reportProvenance: $run[0].provenance,
                  verdict: {passed: $passed, counts: $counts},
                  files: $files
                } + if $destination == null then {} else {destination: $destination} end) as $expected
                | . == $expected and keys_unsorted == ($expected | keys_unsorted)' "$receipt" > /dev/null \
                || fail "unexpected receipt: $(cat "$receipt")"
            }

            # expect_published <dir> <report> <build> <passed> <counts json>
            # <file...>: the exact bundle and receipt.
            expect_published() {
              local dir=$1 report=$2 number=$3 passed=$4 counts=$5
              shift 5
              expect_status 0
              expect_lines "PUBLISH-EVIDENCE: published (report $(obs "$report"), passed=$passed)"
              expect_build_requests "$number"
              expect_bundle "$dir" "$report" "$@"
              expect_receipt "$dir/receipt.json" "$report" "$passed" "$counts" null "$@"
            }
            # expect_bundle <dir> <report> <file...>: <dir> holds exactly the
            # report's <file...> and a receipt, all regular files.
            expect_bundle() {
              local dir=$1 report=$2
              shift 2
              (cd "$dir" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort) > "$TMPDIR/bundle"
              printf '%s\n' "$@" receipt.json | LC_ALL=C sort | diff - "$TMPDIR/bundle" \
                || fail "unexpected bundle contents"
              find "$dir" -type l | grep -q . && fail "bundle holds a symlink"
              for file in "$@"; do
                cmp "$report/$file" "$dir/$file" || fail "$file differs from the report"
              done
            }
            bundle=(playwright-report/completion.json run.json ${screenshot})
            steady_bundle=(playwright-report/completion.json run.json)
            passing_counts='{"expected": 29, "unexpected": 0, "skipped": 0, "flaky": 1}'
            failing_counts='{"expected": 29, "unexpected": 1, "skipped": 0, "flaky": 0}'
            steady_counts='{"expected": 30, "unexpected": 0, "skipped": 0, "flaky": 0}'
            p_obs="$(obs ${reports.passing})"
            f_obs="$(obs ${reports.failing})"
            s_obs="$(obs ${reports.steady})"

            # --- publication

            build 21 succeeded ${rev} "[$other, $(report succeeded ${reports.passing})]"
            event 21
            run passing build-finished --out "$pub/passing"
            expect_published "$pub/passing" ${reports.passing} 21 true "$passing_counts" "''${bundle[@]}"
            cp -a "$pub/passing" "$TMPDIR/passing.snapshot"

            run repeat build-finished --out "$pub/passing"
            expect_status 0
            expect_lines "PUBLISH-EVIDENCE: unchanged (report $p_obs, passed=true)"
            diff -r "$TMPDIR/passing.snapshot" "$pub/passing" || fail "repeat changed the publication"

            # An empty destination is accepted, and a fresh publication of the
            # same report reproduces the bytes.
            mkdir "$pub/fresh"
            run fresh build-finished --out "$pub/fresh"
            expect_status 0
            expect_lines "PUBLISH-EVIDENCE: published (report $p_obs, passed=true)"
            diff -r "$TMPDIR/passing.snapshot" "$pub/fresh" || fail "republication is not byte-identical"

            # A completed product failure is evidence, also from a failed
            # aggregate build (the verdict attribute failed alongside it).
            build 22 failed ${rev} "[$(report succeeded ${reports.failing})]"
            event 22 failed
            run failing build-finished --out "$pub/failing"
            expect_published "$pub/failing" ${reports.failing} 22 false "$failing_counts" "''${bundle[@]}"

            # Another build of the same report, even a skipped_local
            # attribute's cached one, reproduces the receipt byte for byte.
            build 23 succeeded ${rev} "[$(report skipped_local ${reports.passing} true)]"
            event 23
            run skipped-local-cached build-finished --out "$pub/cached"
            expect_published "$pub/cached" ${reports.passing} 23 true "$passing_counts" "''${bundle[@]}"
            diff -r "$TMPDIR/passing.snapshot" "$pub/cached" || fail "another build's publication of the report differs"

            # --- destinations

            build 24 succeeded ${rev} "[$(report succeeded ${reports.passing})]"
            event 24
            run other-build-same-report build-finished --out "$pub/passing"
            expect_status 0
            expect_lines "PUBLISH-EVIDENCE: unchanged (report $p_obs, passed=true)"
            diff -r "$TMPDIR/passing.snapshot" "$pub/passing" || fail "another build of the report changed the publication"

            build 37 succeeded ${rev} "[$(report succeeded ${reports.failing})]"
            event 37
            run other-identity build-finished --out "$pub/passing"
            expect_status 1
            expect_line "error: --out $pub/passing holds the receipt of another publication [\"${reportAttr}\",\"${reports.passing}\"]; refusing to overwrite it"
            diff -r "$TMPDIR/passing.snapshot" "$pub/passing" || fail "the existing publication changed"

            # The same identity with other bytes is never overwritten either.
            cp -a "$TMPDIR/passing.snapshot" "$pub/tampered"
            jq '.verdict.passed = false' "$TMPDIR/passing.snapshot/receipt.json" > "$pub/tampered/receipt.json"
            cp -a "$pub/tampered" "$TMPDIR/tampered.snapshot"
            event 21
            run out-same-report-differs build-finished --out "$pub/tampered"
            expect_status 1
            expect_line "error: --out $pub/tampered holds a different publication of report $p_obs; refusing to overwrite it"
            diff -r "$TMPDIR/tampered.snapshot" "$pub/tampered" || fail "the tampered publication changed"

            mkdir "$pub/occupied"
            touch "$pub/occupied/unrelated"
            run occupied build-finished --out "$pub/occupied"
            expect_status 1
            expect_line "error: --out $pub/occupied is neither empty nor a publication; refusing to overwrite it"
            [ "$(ls -A "$pub/occupied")" = unrelated ] || fail "the occupied destination changed"

            run missing-out build-finished
            expect_status 2
            expect_line "error: one of --out or --upload is required"
            expect_build_requests none

            # --- unavailable evidence: reported, never rebuilt

            build 25 succeeded ${rev} "[$other]"
            event 25
            run missing-attr build-finished --out "$pub/missing-attr"
            rejected 25 "evidence unavailable: nixbot build 25 has no attribute ${reportAttr}" "$pub/missing-attr"

            build 26 failed ${rev} "[$(report failed ${reports.passing})]"
            event 26 failed
            run failed-attr build-finished --out "$pub/failed-attr"
            rejected 26 "evidence unavailable: nixbot build 26 attribute ${reportAttr} is \"failed\"" "$pub/failed-attr"

            build 27 succeeded ${rev} "[$(report succeeded ${unrealisable})]"
            event 27
            run unrealisable build-finished --out "$pub/unrealisable"
            rejected 27 "evidence unavailable: cannot realise ${unrealisable}" "$pub/unrealisable"

            event 28
            run build-not-found build-finished --out "$pub/not-found"
            rejected 28 "evidence unavailable: cannot fetch nixbot build 28 from $NIXBOT_API_URL/api/repos/github/cameronraysmith/vanixiets/builds/28" "$pub/not-found"

            # --- rejected evidence

            # reject <name> <build> <report> <message>: publishing <report>
            # from build <build> is rejected with <message>.
            reject() {
              build "$2" succeeded ${rev} "[$(report succeeded "$3")]"
              event "$2"
              run "$1" build-finished --out "$pub/$1"
              rejected "$2" "evidence rejected: $4" "$pub/$1"
            }
            reject traversal 29 ${reports.traversal} \
              'attachment path is not normalised "test-results/reader-journey-chromium/../reader-journey-chromium/test-failed-1.png"'
            reject absolute 30 ${reports.absolute} \
              'absolute attachment path "${reports.absolute}/${screenshot}"'
            reject symlink 31 ${reports.symlink} "symlink in the report: ${screenshot}"
            reject not-png 32 ${reports.not-png} 'attachment is not PNG data "${screenshot}"'
            reject system-mismatch 33 ${reports.darwin} \
              'report provenance {"system":"aarch64-darwin","config":"playwright.config.ts"} does not match ${reportAttr} {"system":"x86_64-linux","config":"playwright.config.ts"}'
            reject config-mismatch 34 ${reports.negative-config} \
              'report provenance {"system":"x86_64-linux","config":"playwright.negative.config.ts"} does not match ${reportAttr} {"system":"x86_64-linux","config":"playwright.config.ts"}'
            reject invalid-evidence 35 ${reports.invalid} \
              "invalid report: Invalid Playwright evidence: runner infrastructure error"

            build 36 succeeded ${otherRev} "[$(report succeeded ${reports.passing})]"
            event 36
            run rev-mismatch build-finished --out "$pub/rev-mismatch"
            rejected 36 "evidence rejected: nixbot build 36 is {\"number\":36,\"rev\":\"${otherRev}\"}, not the event's build 36 at ${rev}" "$pub/rev-mismatch"

            # --- events rejected before any request

            event 21
            NIXBOT_EVENT_KIND=pull_request
            run wrong-kind build-finished --out "$pub/wrong-kind"
            rejected none "expected a build_finished event, got pull_request" "$pub/wrong-kind"
            NIXBOT_EVENT_KIND=build_finished

            event '"21; touch pwned"'
            run malformed-number build-finished --out "$pub/malformed-number"
            rejected none "malformed event (build=\"21; touch pwned\" rev=\"${rev}\")" "$pub/malformed-number"

            event 21 succeeded 0123456
            run malformed-rev build-finished --out "$pub/malformed-rev"
            rejected none "malformed event (build=21 rev=\"0123456\")" "$pub/malformed-rev"

            # --- upload: the stub's S3 endpoint and nixbot's pr-comment API

            objects=$STUB_STATE/objects
            ttl90=${evidenceKeyRoot}/ttl-90d
            ttl30=${evidenceKeyRoot}/ttl-30d

            # Control (unsigned-put): the stub refuses a request without the
            # temporary credential, so the accepted uploads below were signed.
            python3 -c 'import sys, urllib.request, urllib.error
            try:
                urllib.request.urlopen(urllib.request.Request(sys.argv[1], data=b"x", method="PUT"))
            except urllib.error.HTTPError as e:
                sys.exit(e.code != 403)
            sys.exit(1)' "$PUBLISH_EVIDENCE_S3_ENDPOINT/sciexp/$ttl30/v1/unsigned" \
              || { echo "control: the stub S3 endpoint accepted an unsigned PUT" >&2; exit 1; }
            [ ! -e "$objects/$ttl30/v1/unsigned" ] \
              || { echo "control: the stub stored an unsigned PUT" >&2; exit 1; }

            # req <method> <status> <credential> <key> [<content type>
            # [<If-None-Match>]]: one S3 request as the stub logs it, signed by
            # credential ro (object-read-only on ttl-90d/), rw30 or rw90
            # (object-read-write on ttl-30d/ or ttl-90d/).
            req() {
              jq -nc --arg method "$1" --argjson status "$2" --arg credential "$3" --arg key "$4" \
                --arg type "''${5:-}" --arg inm "''${6:-}" --arg root ${evidenceKeyRoot} '
                {method: $method, key: $key,
                  contentType: (if $type == "" then null else $type end),
                  ifNoneMatch: (if $inm == "" then null else $inm end),
                  status: $status}
                + ({
                  ro: {scope: "object-read-only", prefix: ["\($root)/ttl-90d/"]},
                  rw30: {scope: "object-read-write", prefix: ["\($root)/ttl-30d/"]},
                  rw90: {scope: "object-read-write", prefix: ["\($root)/ttl-90d/"]}
                } | .[$credential])'
            }
            s3_log() {
              jq -sc '[.[] | {method, key, contentType, ifNoneMatch, status, scope, prefix}]' "$STUB_STATE/s3.jsonl"
            }
            # expect_s3 <requests...>: exactly these S3 requests (JSON lines,
            # several per argument allowed), in order; none without arguments.
            expect_s3() {
              local expected
              expected="$(printf '%s\n' "$@" | jq -sc .)"
              [ "$(s3_log)" = "$expected" ] || fail "S3 requests $(s3_log), expected $expected"
            }
            # upload <credential> <prefix> <file...>: the requests of an
            # upload to an empty prefix: the receipt read, every file, the
            # receipt last and conditional.
            upload() {
              local credential=$1 prefix=$2 file type
              shift 2
              req GET 404 "$credential" "$prefix/receipt.json"
              for file in "$@"; do
                case "$file" in
                  *.png) type=image/png ;;
                  *) type=application/json ;;
                esac
                req PUT 200 "$credential" "$prefix/$file" "$type"
              done
              req PUT 200 "$credential" "$prefix/receipt.json" application/json '*'
            }
            # destination <tier> <obs>: the receipt's destination object.
            destination() {
              jq -nc --arg prefix "${evidenceKeyRoot}/$1/v1/$2/" --arg tier "$1" --arg url "${evidenceOrigin}/$1/v1/$2/" \
                '{bucket: "sciexp", prefix: $prefix, tier: $tier, url: $url}'
            }
            # expect_api <request...>: the nixbot API requests ({method, path}),
            # S3 aside, in order.
            expect_api() {
              local expected
              expected="$(printf '%s\n' "$@" | jq -sc .)"
              jq -se --argjson expected "$expected" '[.[] | select(.path | startswith("/s3/") | not)] == $expected' \
                "$STUB_STATE/requests.jsonl" > /dev/null \
                || fail "requests $(jq -sc . "$STUB_STATE/requests.jsonl"), expected $expected"
            }
            api_build() {
              jq -nc --arg path "/api/repos/github/cameronraysmith/vanixiets/builds/$1" '{method: "GET", path: $path}'
            }
            api_comment='{"method": "POST", "path": "/api/v1/pr-comment"}'
            # expect_comments <count>: exactly <count> pr-comment requests, each
            # with the task token, as JSON, upserting the evidence marker.
            expect_comments() {
              jq -se --argjson n "$1" 'length == $n and all(.[];
                  .authorization == "Bearer ${taskToken}"
                  and .contentType == "application/json"
                  and .marker == "vanixiets-browser-evidence")' "$STUB_STATE/comments.jsonl" > /dev/null \
                || fail "comments $(jq -sc . "$STUB_STATE/comments.jsonl"), expected $1"
            }
            expect_no_comment() {
              expect_comments 0
            }
            # expect_comment_has <needle...>: the row's one comment body holds
            # every needle.
            expect_comment_has() {
              printf '%s\n' "$@" | jq -nRe --slurpfile comments "$STUB_STATE/comments.jsonl" \
                'all(inputs; . as $needle | $comments[0].body | contains($needle))' > /dev/null \
                || fail "comment body lacks one of $(printf '%s\n' "$@" | jq -Rsc .): $(jq -sc . "$STUB_STATE/comments.jsonl")"
            }
            # marker_key <pr>: the pull request's marker object.
            marker_key() {
              echo "$ttl30/pr/$1.json"
            }
            # marker <pr> <state> <obs> <build> <rev>: a marker's exact bytes.
            marker() {
              jq -nc --argjson pr "$1" --arg state "$2" --arg obs "$3" --argjson build "$4" --arg rev "$5" \
                '{schemaVersion: 1, pr: $pr, state: $state, obs: $obs, build: $build, rev: $rev}'
            }
            expect_marker() {
              local key
              key="$objects/$(marker_key "$1")"
              marker "$@" | cmp -s - "$key" \
                || fail "marker $(cat "$key" 2> /dev/null || echo absent), expected $(marker "$@")"
            }
            expect_no_marker() {
              [ ! -e "$objects/$(marker_key "$1")" ] || fail "marker #$1 exists: $(cat "$objects/$(marker_key "$1")")"
            }
            # seed <key>: stores stdin as object <key>, as an earlier run (or
            # a corruption) would have left it.
            seed() {
              mkdir -p "$(dirname "$objects/$1")"
              cat > "$objects/$1"
            }
            # client <method> <scope> <prefix> <key>: the status of one request
            # signed with a credential minted here, not by the publisher.
            client() {
              CLIENT_PARENT_SECRET=${parentSecret} CLIENT_ACCOUNT_ID=${accountId} CLIENT_ACCESS_KEY_ID=${accessKeyId} \
                python3 ${client} "$1" "$PUBLISH_EVIDENCE_S3_ENDPOINT/sciexp/$4" "$2" "$3"
            }

            # pr-credential-confinement, the stub's half: credentials minted
            # as the publisher mints its own. The read-only one reads ttl-90d
            # but can neither write nor delete there; the ttl-30d read-write
            # one writes and deletes ttl-30d and nothing outside it.
            name=pr-credential-confinement
            echo "--- $name (stub)"
            reset
            control=v1/0000000000000000000000000000000c/receipt.json
            statuses="$(
              client HEAD object-read-only "$ttl90/" "$ttl90/$control"
              client PUT object-read-only "$ttl90/" "$ttl90/$control"
              client DELETE object-read-only "$ttl90/" "$ttl90/$control"
              client PUT object-read-write "$ttl30/" "$ttl90/$control"
              client DELETE object-read-write "$ttl30/" "$ttl90/$control"
              client PUT object-read-write "$ttl30/" "$ttl30/$control"
              client DELETE object-read-write "$ttl30/" "$ttl30/$control"
            )"
            [ "$statuses" = "$(printf '%s\n' 404 403 403 403 403 200 204)" ] \
              || fail "statuses $(jq -Rsc . <<< "$statuses")"
            expect_s3 \
              "$(req HEAD 404 ro "$ttl90/$control")" \
              "$(req PUT 403 ro "$ttl90/$control" application/octet-stream)" \
              "$(req DELETE 403 ro "$ttl90/$control")" \
              "$(req PUT 403 rw30 "$ttl90/$control" application/octet-stream)" \
              "$(req DELETE 403 rw30 "$ttl90/$control")" \
              "$(req PUT 200 rw30 "$ttl30/$control" application/octet-stream)" \
              "$(req DELETE 204 rw30 "$ttl30/$control")"
            jq -se '[.[].refused] == [null, "read-only scope", "read-only scope",
                "outside the token paths", "outside the token paths", null, null]' "$STUB_STATE/s3.jsonl" > /dev/null \
              || fail "refusals $(jq -sc '[.[].refused]' "$STUB_STATE/s3.jsonl")"
            [ -z "$(find "$objects" -type f -print -quit)" ] || fail "the controls left objects: $(find "$objects" -type f)"

            # 1 main-upload: main --rev resolves the newest build of exactly
            # that commit (the API filters by prefix) and uploads to ttl-90d
            # with a ttl-90d credential, receipt last, without a comment.
            jq -n '{items: [
                {number: 45, commit_sha: "${mainRev}ff", status: "succeeded"},
                {number: 44, commit_sha: "${mainRev}", status: "succeeded"},
                {number: 43, commit_sha: "${mainRev}", status: "failed"}
              ], page: 1, has_next: false}' > "$STUB_STATE/commits/${mainRev}.json"
            build 44 succeeded ${mainRev} "[$(report succeeded ${reports.passing})]"
            build 43 failed ${mainRev} "[$(report succeeded ${reports.failing})]"
            unset NIXBOT_EVENT_KIND NIXBOT_EVENT_JSON
            run main-upload main --rev ${mainRev} --upload
            p90=$ttl90/v1/$p_obs
            expect_status 0
            expect_lines \
              "PUBLISH-EVIDENCE: uploaded ${evidenceOrigin}/ttl-90d/v1/$p_obs/" \
              "PUBLISH-EVIDENCE: published (report $p_obs, passed=true)"
            jq -se '.[0:2] == [
                {method: "GET", path: "/api/repos/github/cameronraysmith/vanixiets/builds?commit=${mainRev}"},
                {method: "GET", path: "/api/repos/github/cameronraysmith/vanixiets/builds/44"}
              ] and all(.[2:][]; .path | startswith("/s3/sciexp/"))' "$STUB_STATE/requests.jsonl" > /dev/null \
              || fail "requests $(jq -sc . "$STUB_STATE/requests.jsonl")"
            expect_s3 "$(upload rw90 "$p90" "''${bundle[@]}")"
            expect_bundle "$objects/$p90" ${reports.passing} "''${bundle[@]}"
            expect_receipt "$objects/$p90/receipt.json" ${reports.passing} true "$passing_counts" \
              "$(destination ttl-90d "$p_obs")" "''${bundle[@]}"
            expect_no_comment
            [ -z "$(find "$objects/$ttl30" -type f -print -quit 2> /dev/null)" ] || fail "main wrote under ttl-30d"
            cp -a "$objects" "$TMPDIR/objects.main"

            # 2 main-repeat-other-build: another main build at another rev
            # with the same report reads the receipt and writes nothing.
            jq -n '{items: [{number: 46, commit_sha: "${mainRev2}", status: "succeeded"}], page: 1, has_next: false}' \
              > "$STUB_STATE/commits/${mainRev2}.json"
            build 46 succeeded ${mainRev2} "[$(report succeeded ${reports.passing})]"
            run main-repeat-other-build main --rev ${mainRev2} --upload
            expect_status 0
            expect_lines "PUBLISH-EVIDENCE: unchanged (report $p_obs, passed=true)"
            expect_api \
              '{"method": "GET", "path": "/api/repos/github/cameronraysmith/vanixiets/builds?commit=${mainRev2}"}' \
              "$(api_build 46)"
            expect_s3 "$(req GET 200 rw90 "$p90/receipt.json")"
            expect_no_comment
            diff -r "$TMPDIR/objects.main" "$objects" || fail "another build of the report changed the bucket"

            run main-no-build main --rev ${otherRev} --upload
            expect_status 1
            expect_line "error: evidence unavailable: nixbot has no build of ${otherRev}"
            expect_s3

            api_url=$NIXBOT_API_URL
            unset NIXBOT_API_URL
            run main-no-api-url main --rev ${mainRev} --upload
            export NIXBOT_API_URL=$api_url
            expect_status 1
            expect_line "error: NIXBOT_API_URL is not set: main resolves the build of --rev through nixbot's build API, which nixbot exposes to an effect only with its task token"
            expect_build_requests none

            run main-missing-rev main --upload
            expect_status 2
            expect_line "error: main requires --rev"
            expect_build_requests none
            export NIXBOT_EVENT_KIND=build_finished NIXBOT_EVENT_JSON=$TMPDIR/event.json

            run rev-outside-main build-finished --rev ${mainRev} --upload
            expect_status 2
            expect_line "error: --rev is only valid for main"
            expect_build_requests none

            # 3 pr-unaffected: main already published this report, so the
            # read-only probe finds it; nothing is uploaded, and without a
            # marker no comment was ever posted, so none is.
            build 50 succeeded ${prRev} "[$(report succeeded ${reports.passing})]"
            event 50 succeeded ${prRev} 7
            run pr-unaffected build-finished --upload
            expect_status 0
            expect_lines "PUBLISH-EVIDENCE: unaffected (report $p_obs already published from main)"
            expect_api "$(api_build 50)"
            expect_s3 "$(req HEAD 200 ro "$p90/receipt.json")" "$(req GET 404 rw30 "$(marker_key 7)")"
            expect_no_comment
            expect_no_marker 7
            diff -r "$TMPDIR/objects.main" "$objects" || fail "an unaffected build changed the bucket"

            # 4 pr-affected: no baseline, so ttl-30d with the ttl-30d
            # credential, receipt last, one comment linking the Worker URLs,
            # then the marker `current`.
            build 51 failed ${affectedRev} "[$(report succeeded ${reports.failing})]"
            event 51 failed ${affectedRev} 7
            run pr-affected build-finished --upload
            f30=$ttl30/v1/$f_obs
            f_url="${evidenceOrigin}/ttl-30d/v1/$f_obs/"
            expect_status 0
            expect_lines \
              "PUBLISH-EVIDENCE: uploaded $f_url" \
              "PUBLISH-EVIDENCE: published (report $f_obs, passed=false)" \
              "PUBLISH-EVIDENCE: commented #7"
            expect_api "$(api_build 51)" "$api_comment"
            expect_s3 \
              "$(req HEAD 404 ro "$ttl90/v1/$f_obs/receipt.json")" \
              "$(upload rw30 "$f30" "''${bundle[@]}")" \
              "$(req PUT 200 rw30 "$(marker_key 7)" application/json)"
            expect_bundle "$objects/$f30" ${reports.failing} "''${bundle[@]}"
            expect_receipt "$objects/$f30/receipt.json" ${reports.failing} false "$failing_counts" \
              "$(destination ttl-30d "$f_obs")" "''${bundle[@]}"
            expect_comments 1
            expect_comment_has \
              "### Browser evidence: failed" \
              "This pull request changes the docs site's browser evidence." \
              "[build 51](https://nixbot.example/builds/51) at \`${lib.substring 0 12 affectedRev}\`" \
              "29 expected, 1 unexpected, 0 flaky, 0 skipped" \
              "[${screenshot}](''${f_url}${screenshot})" \
              "[receipt.json](''${f_url}receipt.json)" \
              'No report identical to this one has been published from `main` in the last 90 days, so it is shown here.' \
              "kept 30 days"
            jq -se '.[0].body | contains("](https://evidence.vanixiets.net/vanixiets/browser-evidence/ttl-30d/v1/")
                and (contains("ttl-90d") or contains("scientistexperience") | not)' \
              "$STUB_STATE/comments.jsonl" > /dev/null \
              || fail "comment links: $(jq -sc . "$STUB_STATE/comments.jsonl")"
            expect_marker 7 current "$f_obs" 51 ${affectedRev}
            cp -a "$objects" "$TMPDIR/objects.affected"
            cp "$STUB_STATE/comments.jsonl" "$TMPDIR/comments.affected"

            # 5 pr-affected-retry: the same build again finds its receipt,
            # writes no evidence, upserts the same comment and rewrites the
            # same marker bytes.
            run pr-affected-retry build-finished --upload
            expect_status 0
            expect_lines \
              "PUBLISH-EVIDENCE: unchanged (report $f_obs, passed=false)" \
              "PUBLISH-EVIDENCE: commented #7"
            expect_s3 \
              "$(req HEAD 404 ro "$ttl90/v1/$f_obs/receipt.json")" \
              "$(req GET 200 rw30 "$f30/receipt.json")" \
              "$(req PUT 200 rw30 "$(marker_key 7)" application/json)"
            expect_comments 1
            cmp "$TMPDIR/comments.affected" "$STUB_STATE/comments.jsonl" || fail "the retry's comment differs"
            expect_marker 7 current "$f_obs" 51 ${affectedRev}
            diff -r "$TMPDIR/objects.affected" "$objects" || fail "the retry changed the bucket"

            # 6 pr-second-build-same-report: a new build of the same report
            # writes no new objects; its comment and marker name the build.
            build 52 failed ${laterRev} "[$(report succeeded ${reports.failing})]"
            event 52 failed ${laterRev} 7
            run pr-second-build-same-report build-finished --upload
            expect_status 0
            expect_lines \
              "PUBLISH-EVIDENCE: unchanged (report $f_obs, passed=false)" \
              "PUBLISH-EVIDENCE: commented #7"
            expect_api "$(api_build 52)" "$api_comment"
            expect_s3 \
              "$(req HEAD 404 ro "$ttl90/v1/$f_obs/receipt.json")" \
              "$(req GET 200 rw30 "$f30/receipt.json")" \
              "$(req PUT 200 rw30 "$(marker_key 7)" application/json)"
            expect_comments 1
            expect_comment_has \
              "[build 52](https://nixbot.example/builds/52) at \`${lib.substring 0 12 laterRev}\`" \
              "[receipt.json](''${f_url}receipt.json)"
            expect_marker 7 current "$f_obs" 52 ${laterRev}
            diff -r -x pr "$TMPDIR/objects.affected" "$objects" || fail "a later build of the report wrote new objects"
            cmp "$TMPDIR/objects.affected/$f30/receipt.json" "$objects/$f30/receipt.json" || fail "the receipt changed"
            cp -a "$objects" "$TMPDIR/objects.later"

            # A refused comment fails the run after the (unchanged) upload,
            # and the marker is not advanced.
            NIXBOT_API_TOKEN=not-the-task-token
            run pr-comment-refused build-finished --upload
            NIXBOT_API_TOKEN=${taskToken}
            expect_status 1
            expect_lines "PUBLISH-EVIDENCE: unchanged (report $f_obs, passed=false)"
            expect_line "error: comment on #7 failed: HTTP 401"
            expect_s3 "$(req HEAD 404 ro "$ttl90/v1/$f_obs/receipt.json")" "$(req GET 200 rw30 "$f30/receipt.json")"
            diff -r "$TMPDIR/objects.later" "$objects" || fail "a refused comment changed the bucket"

            # A different receipt at the report's key (a corruption, or
            # another schema) conflicts and writes nothing.
            jq '.schemaVersion = 2' "$TMPDIR/objects.later/$f30/receipt.json" | seed "$f30/receipt.json"
            run pr-receipt-conflict build-finished --upload
            cp "$TMPDIR/objects.later/$f30/receipt.json" "$objects/$f30/receipt.json"
            expect_status 1
            expect_lines
            expect_line "error: conflict: sciexp/$f30/receipt.json holds a different receipt than this publication's; refusing to overwrite it"
            expect_s3 "$(req HEAD 404 ro "$ttl90/v1/$f_obs/receipt.json")" "$(req GET 200 rw30 "$f30/receipt.json")"
            expect_no_comment
            diff -r "$TMPDIR/objects.later" "$objects" || fail "the conflict changed the bucket"

            # 11 pr-probe-500: a baseline probe that is neither 200 nor 404
            # names its key; nothing is uploaded or commented.
            echo "HEAD $ttl90/v1/$f_obs/receipt.json" > "$STUB_STATE/fail"
            run pr-probe-500 build-finished --upload
            rm "$STUB_STATE/fail"
            expect_status 1
            expect_lines
            expect_line "error: baseline probe failed: HEAD sciexp/$ttl90/v1/$f_obs/receipt.json returned HTTP 500"
            expect_api "$(api_build 52)"
            expect_s3 "$(req HEAD 500 ro "$ttl90/v1/$f_obs/receipt.json")"
            expect_no_comment
            diff -r "$TMPDIR/objects.later" "$objects" || fail "a failed probe changed the bucket"

            # Reverted to main's report with a current marker but no task
            # token: noted, and the marker stays current.
            build 53 succeeded ${revertedRev} "[$(report succeeded ${reports.passing})]"
            event 53 succeeded ${revertedRev} 7
            unset NIXBOT_API_TOKEN
            run pr-reverted-no-token build-finished --upload
            export NIXBOT_API_TOKEN=${taskToken}
            expect_status 0
            expect_lines \
              "PUBLISH-EVIDENCE: unaffected (report $p_obs already published from main)" \
              "PUBLISH-EVIDENCE: no comment on #7: NIXBOT_API_TOKEN is not set"
            expect_s3 "$(req HEAD 200 ro "$p90/receipt.json")" "$(req GET 200 rw30 "$(marker_key 7)")"
            expect_no_comment
            diff -r "$TMPDIR/objects.later" "$objects" || fail "a run without a token changed the bucket"

            # 7 pr-reverted: the current comment is superseded once, without
            # links, and the marker records it; a further run does nothing.
            run pr-reverted build-finished --upload
            expect_status 0
            expect_lines \
              "PUBLISH-EVIDENCE: unaffected (report $p_obs already published from main)" \
              "PUBLISH-EVIDENCE: superseded #7"
            expect_api "$(api_build 53)" "$api_comment"
            expect_s3 \
              "$(req HEAD 200 ro "$p90/receipt.json")" \
              "$(req GET 200 rw30 "$(marker_key 7)")" \
              "$(req PUT 200 rw30 "$(marker_key 7)" application/json)"
            expect_comments 1
            printf '### Browser evidence: superseded\n\nThe latest build of this pull request produces the same docs report as `main` (report `%s`), so the evidence previously linked here no longer describes a change. Build 53, rev `%s`.\n' \
              "$p_obs" ${lib.substring 0 12 revertedRev} > "$TMPDIR/superseded.md"
            jq -se --rawfile expected "$TMPDIR/superseded.md" '.[0].body == $expected' "$STUB_STATE/comments.jsonl" > /dev/null \
              || fail "superseded body $(jq -sc '.[0].body' "$STUB_STATE/comments.jsonl"), expected $(jq -Rsc . "$TMPDIR/superseded.md")"
            expect_marker 7 superseded "$p_obs" 53 ${revertedRev}
            diff -r -x pr "$TMPDIR/objects.later" "$objects" || fail "superseding wrote evidence objects"
            cp -a "$objects" "$TMPDIR/objects.superseded"

            run pr-reverted-again build-finished --upload
            expect_status 0
            expect_lines "PUBLISH-EVIDENCE: unaffected (report $p_obs already published from main)"
            expect_s3 "$(req HEAD 200 ro "$p90/receipt.json")" "$(req GET 200 rw30 "$(marker_key 7)")"
            expect_no_comment
            diff -r "$TMPDIR/objects.superseded" "$objects" || fail "a superseded marker changed again"

            # A marker the publisher did not write fails the run untouched.
            build 54 succeeded ${revertedRev} "[$(report succeeded ${reports.passing})]"
            event 54 succeeded ${revertedRev} 8
            echo '{"schemaVersion":1,"pr":8,"state":"stale"}' | seed "$(marker_key 8)"
            cp -a "$objects" "$TMPDIR/objects.malformed"
            run pr-marker-malformed build-finished --upload
            expect_status 1
            grep -q '^error: ' "$output" || fail "no error line"
            grep -qE '^PUBLISH-EVIDENCE: (superseded|commented|published|uploaded)' "$output" && fail "acted on a malformed marker"
            expect_s3 "$(req HEAD 200 ro "$p90/receipt.json")" "$(req GET 200 rw30 "$(marker_key 8)")"
            expect_no_comment
            diff -r "$TMPDIR/objects.malformed" "$objects" || fail "a malformed marker changed the bucket"

            # 8 pr-credential-confinement, the program's half: across every
            # pull request row, ttl-90d was only probed (HEAD) and only with
            # the read-only credential, every other request used the ttl-30d
            # read-write one, and ttl-90d still holds exactly main's objects.
            name=pr-credential-confinement
            jq -se --arg ttl90 "$ttl90/" --arg ttl30 "$ttl30/" '
              [.[] | select(.row | startswith("pr-"))]
              | length > 0 and all(.[];
                  if .key | startswith($ttl90)
                  then .method == "HEAD" and .scope == "object-read-only" and .prefix == [$ttl90]
                  else .scope == "object-read-write" and .prefix == [$ttl30] end)' \
              "$TMPDIR/s3-rows.jsonl" > /dev/null \
              || fail "pull request S3 requests $(jq -sc '[.[] | select(.row | startswith("pr-"))]' "$TMPDIR/s3-rows.jsonl")"
            diff -r "$TMPDIR/objects.main/$ttl90" "$objects/$ttl90" || fail "a pull request row changed ttl-90d"

            # A failed PUT names its key, and no receipt follows it.
            s90=$ttl90/v1/$s_obs
            build 41 succeeded ${prRev} "[$(report succeeded ${reports.steady})]"
            event 41 succeeded ${prRev}
            echo "PUT $s90/run.json" > "$STUB_STATE/fail"
            run upload-500 build-finished --upload
            rm "$STUB_STATE/fail"
            expect_status 1
            expect_lines
            expect_line "error: upload failed: PUT sciexp/$s90/run.json returned HTTP 500"
            expect_s3 \
              "$(req GET 404 rw90 "$s90/receipt.json")" \
              "$(req PUT 200 rw90 "$s90/playwright-report/completion.json" application/json)" \
              "$(req PUT 500 rw90 "$s90/run.json" application/json)"
            [ ! -e "$objects/$s90/receipt.json" ] || fail "a receipt exists after a failed upload"
            expect_no_comment

            # 9 non-pr-build-finished: a build without a pull request (another
            # build of the same report) completes the publication in ttl-90d
            # with no probe and no comment; with --out too, the local receipt
            # is the uploaded one.
            build 42 succeeded ${prRev} "[$(report succeeded ${reports.steady})]"
            event 42 succeeded ${prRev}
            run non-pr-build-finished build-finished --out "$pub/non-pr" --upload
            expect_status 0
            expect_lines \
              "PUBLISH-EVIDENCE: uploaded ${evidenceOrigin}/ttl-90d/v1/$s_obs/" \
              "PUBLISH-EVIDENCE: published (report $s_obs, passed=true)"
            expect_api "$(api_build 42)"
            expect_s3 "$(upload rw90 "$s90" "''${steady_bundle[@]}")"
            expect_bundle "$objects/$s90" ${reports.steady} "''${steady_bundle[@]}"
            expect_bundle "$pub/non-pr" ${reports.steady} "''${steady_bundle[@]}"
            expect_receipt "$objects/$s90/receipt.json" ${reports.steady} true "$steady_counts" \
              "$(destination ttl-90d "$s_obs")" "''${steady_bundle[@]}"
            cmp "$objects/$s90/receipt.json" "$pub/non-pr/receipt.json" || fail "the local receipt differs"
            expect_no_comment
            [ -z "$(find "$objects/$ttl30/v1/$s_obs" -type f -print -quit 2> /dev/null)" ] || fail "a non-PR build wrote under ttl-30d"

            # Missing upload credentials stop the run before any request.
            event 50 succeeded ${prRev} 7
            unset R2_EVIDENCE_SECRET_ACCESS_KEY
            run missing-r2-env build-finished --upload
            export R2_EVIDENCE_SECRET_ACCESS_KEY=${parentSecret}
            expect_status 1
            expect_line "error: R2_EVIDENCE_SECRET_ACCESS_KEY is not set (required by --upload)"
            expect_build_requests none
            expect_no_comment

            # Over every row without a pull request: one ttl-90d read-write
            # credential, never a probe or the read-only credential.
            name=non-pr-rows
            jq -se --arg ttl90 "$ttl90/" '
              [.[] | select(.row | startswith("pr-") | not)]
              | length > 0 and all(.[];
                  .method != "HEAD" and .scope == "object-read-write" and .prefix == [$ttl90])' \
              "$TMPDIR/s3-rows.jsonl" > /dev/null \
              || fail "S3 requests $(jq -sc '[.[] | select(.row | startswith("pr-") | not)]' "$TMPDIR/s3-rows.jsonl")"

            # 10: over every row, requests carried the parent's access key
            # id, never the parent secret.
            grep -aqF "Credential=${accessKeyId}/" "$STUB_STATE/raw.log" \
              || { echo "no request carried the parent access key id" >&2; exit 1; }
            if grep -aqF ${parentSecret} "$STUB_STATE/raw.log"; then
              echo "a request carried the parent secret" >&2
              exit 1
            fi

            [ -z "$(find "$pub" -maxdepth 1 -name '.publish-evidence.*' -print -quit)" ] \
              || { echo "a staging directory outlived its run" >&2; exit 1; }

            touch $out
          '';
    };
}
