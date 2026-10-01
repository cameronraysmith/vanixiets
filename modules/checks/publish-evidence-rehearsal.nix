# Behavioural check: the publish-evidence program's build-finished mode,
# which otherwise only runs from a default-branch build_finished effect that
# is not registered yet.
#
# A python server stands in for nixbot's build API, serving fixture files and
# logging every request as JSONL. nix-store is the real one against a chroot
# store in $TMPDIR holding the report fixtures, which are sandbox inputs and
# so readable at their real store paths.
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
# receipt, also from a failed aggregate build and a skipped_local attribute,
# whose cached field is copied verbatim. A repeat run is a byte-identical
# no-op, and a fresh destination receives byte-identical bytes. Every
# rejected run exits 1 with its exact message and leaves no receipt or
# staging directory behind: another publication's --out, a missing, failed,
# unfetchable or unrealisable report, traversal, absolute, symlinked or
# non-PNG attachments, build/report identity mismatches, a wrong event kind,
# malformed events and invalid evidence. Rows rejected from the event alone
# make no API request.
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

      # node fixture.mjs <variant> <out>: one synthetic report. The reader
      # journey of the first project carries the failed attempt, retried to
      # a pass (flaky) in `passing` and final everywhere else it fails.
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

      server = pkgs.writeText "publish-evidence-stub-server.py" ''
        import json
        import os
        import pathlib
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        state = pathlib.Path(os.environ["STUB_STATE"])
        builds = "/api/repos/github/cameronraysmith/vanixiets/builds/"


        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                with (state / "requests.jsonl").open("a") as log:
                    log.write(json.dumps({"method": self.command, "path": self.path}) + "\n")
                if self.path.startswith(builds):
                    fixture = state / "builds" / (self.path[len(builds):] + ".json")
                    if fixture.is_file():
                        body = fixture.read_bytes()
                        self.send_response(200)
                        self.send_header("Content-Type", "application/json")
                        self.send_header("Content-Length", str(len(body)))
                        self.end_headers()
                        self.wfile.write(body)
                        return
                self.send_error(404)


        httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        (state / "port.tmp").write_text(str(httpd.server_port))
        (state / "port.tmp").rename(state / "port")
        httpd.serve_forever()
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
            mkdir -p "$STUB_STATE/builds"
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
            pub=$TMPDIR/pub
            mkdir "$pub"

            fail() {
              echo "row '$name': $*" >&2
              exit 1
            }
            # run <name> <program args...>: runs publish-evidence with a fresh
            # request log and records the exit status.
            run() {
              name=$1
              shift
              echo "--- $name"
              : > "$STUB_STATE/requests.jsonl"
              output="$TMPDIR/rows/$name"
              mkdir -p "$(dirname "$output")"
              status=0
              ${publishEvidenceProgram} "$@" > "$output" 2>&1 || status=$?
              cat "$output"
            }
            expect_status() {
              [ "$status" = "$1" ] || fail "exit status $status, expected $1"
            }
            expect_line() {
              grep -qxF -- "$1" "$output" || fail "missing output line: $1"
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
            # event <number json> [<status> [<rev>]]: the build_finished payload.
            event() {
              jq -n --argjson n "$1" --arg status "''${2:-succeeded}" --arg rev "''${3:-${rev}}" \
                '{build: {number: $n, url: "https://nixbot.example/builds/\($n)", status: $status,
                  branch: "main", rev: $rev, previousStatus: "succeeded", failedAttrs: []}}' \
                > "$NIXBOT_EVENT_JSON"
            }
            other="$(attr checks.x86_64-linux.other succeeded /nix/store/00000000000000000000000000000000-other)"

            # expect_published <dir> <report> <build> <build status> <cached>
            # <passed> <counts json> <file...>: the exact bundle and receipt.
            expect_published() {
              local dir=$1 report=$2 number=$3 build_status=$4 cached=$5 passed=$6 counts=$7
              shift 7
              expect_status 0
              expect_line "PUBLISH-EVIDENCE: published (build $number, passed=$passed)"
              expect_build_requests "$number"
              (cd "$dir" && find . -mindepth 1 \( -type f -o -type l \) -printf '%P\n' | LC_ALL=C sort) > "$TMPDIR/bundle"
              printf '%s\n' "$@" receipt.json | LC_ALL=C sort | diff - "$TMPDIR/bundle" \
                || fail "unexpected bundle contents"
              find "$dir" -type l | grep -q . && fail "bundle holds a symlink"
              for file in "$@"; do
                cmp "$report/$file" "$dir/$file" || fail "$file differs from the report"
              done
              local files
              files="$(for file in "$@"; do
                jq -nc --arg path "$file" --arg sha256 "$(sha256sum "$dir/$file" | cut -d' ' -f1)" \
                  --argjson bytes "$(wc -c < "$dir/$file")" '{path: $path, sha256: $sha256, bytes: $bytes}'
              done | jq -sc .)"
              jq -e \
                --argjson number "$number" \
                --arg status "$build_status" \
                --arg report "$report" \
                --argjson cached "$cached" \
                --argjson passed "$passed" \
                --argjson counts "$counts" \
                --argjson files "$files" \
                --slurpfile run "$report/run.json" \
                '. == {
                  schemaVersion: 1,
                  build: {number: $number, rev: "${rev}", status: $status, url: "https://nixbot.example/builds/\($number)"},
                  attribute: "${reportAttr}",
                  outPath: $report,
                  cached: $cached,
                  reportProvenance: $run[0].provenance,
                  verdict: {passed: $passed, counts: $counts},
                  files: $files
                } and (keys_unsorted == ["schemaVersion", "build", "attribute", "outPath", "cached",
                  "reportProvenance", "verdict", "files"])' "$dir/receipt.json" > /dev/null \
                || fail "unexpected receipt: $(cat "$dir/receipt.json")"
            }
            bundle=(playwright-report/completion.json run.json ${screenshot})

            # --- publication

            build 21 succeeded ${rev} "[$other, $(report succeeded ${reports.passing})]"
            event 21
            run passing build-finished --out "$pub/passing"
            expect_published "$pub/passing" ${reports.passing} 21 succeeded false true \
              '{"expected": 29, "unexpected": 0, "skipped": 0, "flaky": 1}' "''${bundle[@]}"
            cp -a "$pub/passing" "$TMPDIR/passing.snapshot"

            run repeat build-finished --out "$pub/passing"
            expect_status 0
            expect_line "PUBLISH-EVIDENCE: unchanged (build 21, passed=true)"
            diff -r "$TMPDIR/passing.snapshot" "$pub/passing" || fail "repeat changed the publication"

            # An empty destination is accepted, and a fresh publication of the
            # same identity reproduces the bytes.
            mkdir "$pub/fresh"
            run fresh build-finished --out "$pub/fresh"
            expect_status 0
            expect_line "PUBLISH-EVIDENCE: published (build 21, passed=true)"
            diff -r "$TMPDIR/passing.snapshot" "$pub/fresh" || fail "republication is not byte-identical"

            # A completed product failure is evidence, also from a failed
            # aggregate build (the verdict attribute failed alongside it).
            build 22 failed ${rev} "[$(report succeeded ${reports.failing})]"
            event 22 failed
            run failing build-finished --out "$pub/failing"
            expect_published "$pub/failing" ${reports.failing} 22 failed false false \
              '{"expected": 29, "unexpected": 1, "skipped": 0, "flaky": 0}' "''${bundle[@]}"

            build 23 succeeded ${rev} "[$(report skipped_local ${reports.passing} true)]"
            event 23
            run skipped-local-cached build-finished --out "$pub/cached"
            expect_published "$pub/cached" ${reports.passing} 23 succeeded true true \
              '{"expected": 29, "unexpected": 0, "skipped": 0, "flaky": 1}' "''${bundle[@]}"

            # --- destinations

            build 24 succeeded ${rev} "[$(report succeeded ${reports.passing})]"
            event 24
            run other-identity build-finished --out "$pub/passing"
            expect_status 1
            expect_line "error: --out $pub/passing holds the receipt of another publication [21,\"${rev}\",\"${reportAttr}\",\"${reports.passing}\"]; refusing to overwrite it"
            diff -r "$TMPDIR/passing.snapshot" "$pub/passing" || fail "the existing publication changed"

            mkdir "$pub/occupied"
            touch "$pub/occupied/unrelated"
            run occupied build-finished --out "$pub/occupied"
            expect_status 1
            expect_line "error: --out $pub/occupied is neither empty nor a publication; refusing to overwrite it"
            [ "$(ls -A "$pub/occupied")" = unrelated ] || fail "the occupied destination changed"

            run missing-out build-finished
            expect_status 2
            expect_line "error: --out is required"
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

            [ -z "$(find "$pub" -maxdepth 1 -name '.publish-evidence.*' -print -quit)" ] \
              || { echo "a staging directory outlived its run" >&2; exit 1; }

            touch $out
          '';
    };
}
