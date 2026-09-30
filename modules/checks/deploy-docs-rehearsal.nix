# Behavioural check: the deploy-docs program drives wrangler as intended.
#
# The effects that run deploy-docs only run after a merge or on a pull request
# event with the Cloudflare token, so nothing before a merge otherwise runs
# deploy.sh. This check runs the same deploy-docs program the effects run,
# through its flag interface, against the built-in docs payload and small
# fixture payloads, with a stub standing in for wrangler. No secret or network
# is involved: the Cloudflare values are fixed dummies, and main's head is a
# file:// URL.
#
# The effects list this check as a rehearsal in their inputs, so the gated
# `nix build <effect>^*` on pull requests and merge-queue batches runs it.
#
# The stub records each invocation's argv, working directory, env file,
# parsed --config and asset marker, then holds deploy.sh to wrangler's own
# grammar: it runs the pinned real wrangler with the identical argv in the
# same directory, as a --dry-run for `deploy` and `versions upload` (which
# also runs the config's build command), and fails the call when that run
# fails. Only then does it emit the NDJSON event and stdout line deploy.sh
# parses. `deployments list` has no dry run, and --help skips argument
# validation, so the real wrangler runs it for real against a loopback
# Cloudflare API serving the canned deployments.
#
# Asserted: production deploys the built-in payload's own config as
# infra-docs from an empty directory, cross-checks the deployments list and
# reports the deployed version; a superseded run deploys nothing; a version
# not at 100% fails the run. Preview uploads with a config synthesized from a
# fixed shape, uploads a --payload build when given one, prints exactly one
# DEPLOY-DOCS-PREVIEW-URL line, refuses a payload holding a symlink before
# wrangler runs, and never carries a payload's build command. A missing or
# malformed --rev, an empty --alias, --payload on production, or a missing
# Cloudflare secret fails before wrangler or main's head is consulted.
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
      otherRev = "fedcba9876543210fedcba9876543210fedcba98";
      versionId = "11111111-2222-4333-8444-555555555555";

      wranglerStub = pkgs.writeText "wrangler-stub.js" ''
        "use strict";
        const fs = require("fs");
        const http = require("http");
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
        const command = has("versions", "upload") ? "versions upload"
          : has("deployments", "list") ? "deployments list"
          : has("deploy") ? "deploy"
          : null;

        const configPath = option("--config");
        const envFile = option("--env-file");
        const config = configPath === null ? null : JSON.parse(fs.readFileSync(configPath, "utf8"));
        const assetsDir = config?.assets?.directory == null
          ? null
          : path.resolve(path.dirname(configPath), config.assets.directory);

        fs.appendFileSync(process.env.STUB_LOG, JSON.stringify({
          args,
          cwdEntries: fs.readdirSync(process.cwd()),
          envFileBytes: envFile === null ? null : fs.statSync(envFile).size,
          configPath,
          config,
          assetsIndex: assetsDir !== null && fs.existsSync(path.join(assetsDir, "index.html")),
          assetsMarker: assetsDir !== null && fs.existsSync(path.join(assetsDir, "marker.txt"))
            ? fs.readFileSync(path.join(assetsDir, "marker.txt"), "utf8")
            : null,
        }) + "\n");

        // A loopback Cloudflare API: the deployments list is the canned
        // answer, anything else is an error, so a dry run that reaches for
        // the API fails.
        const api = http.createServer((req, res) => {
          res.setHeader("content-type", "application/json");
          if (req.method === "GET" && req.url.endsWith("/workers/scripts/infra-docs/deployments")) {
            const percentage = Number(process.env.STUB_PERCENTAGE ?? 100);
            res.end(JSON.stringify({ success: true, errors: [], messages: [], result: {
              deployments: [{ id: "rehearsal", versions: [{ version_id: VERSION, percentage }] }],
            } }));
          } else {
            res.statusCode = 500;
            res.end(JSON.stringify({ success: false, errors: [{ code: 1, message: `rehearsal API: unexpected ''${req.method} ''${req.url}` }], messages: [], result: null }));
          }
        });

        // Runs the real wrangler with deploy.sh's argv in deploy.sh's cwd,
        // resolving to its exit status and output. HOME is private because
        // the sandbox's is unwritable; the hidden banner skips the npm update
        // check. A .wrangler state directory it leaves in the cwd is removed
        // so the next call's record shows only what deploy.sh put there.
        const real = (extraArgs) => new Promise((resolve) => {
          const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "wrangler-real-"));
          const hadState = fs.existsSync(".wrangler");
          const env = {
            ...process.env,
            HOME: path.join(scratch, "home"),
            WRANGLER_SEND_METRICS: "false",
            WRANGLER_HIDE_BANNER: "true",
            WRANGLER_OUTPUT_FILE_PATH: path.join(scratch, "events.ndjson"),
            CLOUDFLARE_API_BASE_URL: `http://127.0.0.1:''${api.address().port}/client/v4`,
          };
          const child = spawn(process.execPath, [REAL_WRANGLER, ...args, ...extraArgs(scratch)], { env });
          let stdout = "", stderr = "";
          child.stdout.on("data", (d) => (stdout += d));
          child.stderr.on("data", (d) => (stderr += d));
          child.on("close", (status) => {
            if (!hadState) fs.rmSync(".wrangler", { recursive: true, force: true });
            fs.rmSync(scratch, { recursive: true, force: true });
            if (status !== 0) stderr += `wrangler stub: the real wrangler rejected ''${args.join(" ")}\n`;
            resolve({ status, stdout, stderr });
          });
        });

        const emit = (event) =>
          fs.appendFileSync(process.env.WRANGLER_OUTPUT_FILE_PATH, JSON.stringify(event) + "\n");

        const dryRun = (scratch) => ["--dry-run", "--outdir", path.join(scratch, "out")];
        const main = async () => {
          if (command === "deploy" || command === "versions upload") {
            const run = await real(dryRun);
            if (run.status !== 0) return run;
            if (command === "deploy") {
              emit({ type: "deploy", version_id: VERSION });
              console.log(`Current Version ID: ''${VERSION}`);
            } else {
              emit({ type: "version-upload", version_id: VERSION });
              console.log(`Worker Version ID: ''${VERSION}`);
            }
            return { status: 0, stdout: "", stderr: "" };
          }
          if (command === "deployments list") return real(() => []);
          return { status: 1, stdout: "", stderr: `wrangler stub: unexpected command: ''${args.join(" ")}\n` };
        };

        api.listen(0, "127.0.0.1", async () => {
          const { status, stdout, stderr } = await main();
          api.close();
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
              pkgs.nodejs_24
            ];
            # The loopback Cloudflare API needs local networking in the
            # darwin sandbox.
            __darwinAllowLocalNetworking = true;
            meta.description = "behavioural check: deploy-docs against a wrangler stub";
          }
          ''
            set -euo pipefail

            export WRANGLER=${wranglerStub}
            export CLOUDFLARE_API_TOKEN=rehearsal-dummy-token
            export CLOUDFLARE_ACCOUNT_ID=rehearsal-dummy-account
            export DEPLOY_DOCS_MAIN_SHA_URL="file://$TMPDIR/main.json"
            export STUB_LOG

            fail() {
              echo "row '$name': $*" >&2
              exit 1
            }
            main_is() {
              printf '{"sha":"%s"}' "$1" > "$TMPDIR/main.json"
            }
            # run <name> <program args...>: runs deploy-docs with its own
            # stub log and records the exit status in $status.
            run() {
              name=$1
              shift
              echo "--- $name"
              row="$TMPDIR/rows/$name"
              mkdir -p "$row"
              STUB_LOG="$row/wrangler.ndjson"
              status=0
              ${deployDocsProgram} "$@" > "$row/output" 2>&1 || status=$?
              cat "$row/output"
            }
            expect_status() {
              [ "$status" = "$1" ] || fail "exit status $status, expected $1"
            }
            expect_failure() {
              [ "$status" != 0 ] || fail "exit status 0, expected a failure"
            }
            expect_line() {
              grep -qxF -- "$1" "$row/output" || fail "missing output line: $1"
            }
            expect_calls() {
              local calls=0
              [ ! -f "$STUB_LOG" ] || calls="$(wc -l < "$STUB_LOG")"
              [ "$calls" = "$1" ] || fail "wrangler invoked $calls times, expected $1"
            }
            # expect <description> <jq filter over the invocation array> [jq args...]
            expect() {
              local description=$1 filter=$2
              shift 2
              jq -se "$@" "$filter" "$STUB_LOG" > /dev/null || fail "$description"
            }

            # Every invocation runs from an empty directory with an empty env
            # file, so no .env can redirect wrangler's API base or token.
            isolated='all(.[]; .cwdEntries == [] and .envFileBytes == 0)'
            preview_keys='["assets","compatibility_date","compatibility_flags","name","observability","preview_urls","workers_dev"]'

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
              kv_namespaces: [{ binding: "KV", id: "0" }]
            }')"

            # Control: the real wrangler behind the stub runs a build command
            # handed to it, then rejects the config's missing entry point, so
            # the sentinel's absence below means deploy.sh did not pass it on.
            name=stub-runs-build-command
            STUB_LOG="$TMPDIR/control.ndjson" WRANGLER_OUTPUT_FILE_PATH="$TMPDIR/control-events.ndjson" \
              node "$WRANGLER" versions upload --config="$TMPDIR/fixtures/build-command/dist/client/wrangler.json" \
              --env-file=/dev/null > /dev/null 2>&1 || true
            [ -e "$sentinel" ] || fail "stub did not run the build command"
            rm "$sentinel"

            main_is ${rev}
            run production-current production --rev ${rev}
            expect_status 0
            expect_line "deployed nix-built payload to production"
            expect_line "  Worker Version ID: ${versionId}"
            expect_line "DEPLOY-DOCS-ACTION: deploy (version ${versionId})"
            expect_calls 2
            expect "deploy runs as infra-docs with a message naming the deployer" \
              '.[0].args | index(["deploy", "--name", "infra-docs", "--message", "Deployed by nixbot from main at ${builtins.substring 0 7 rev}"]) != null'
            expect "deploy uses the payload's config" \
              '.[0].config == $config[0] and (.[0].configPath | endswith("/payload/dist/client/wrangler.json"))' \
              --slurpfile config ${payload}/dist/client/wrangler.json
            expect "deployments list is cross-checked" \
              '.[1].args | index(["deployments", "list", "--name", "infra-docs", "--json"]) != null'
            expect "wrangler runs isolated" "$isolated"

            main_is ${otherRev}
            run production-superseded production --rev ${rev}
            expect_status 0
            expect_line "DEPLOY-DOCS-ACTION: superseded (main is ${otherRev})"
            expect_calls 0

            main_is ${rev}
            STUB_PERCENTAGE=50 run production-partial production --rev ${rev}
            expect_failure
            expect_line "error: version ${versionId} is not at 100% in deployments list"
            expect_calls 2

            run preview preview --rev ${rev} --alias pr-7 --deployed-by rehearsal
            expect_status 0
            expect_line "  Preview URL: https://b-pr-7-infra-docs.sciexp.workers.dev"
            [ "$(grep -c '^DEPLOY-DOCS-PREVIEW-URL: ' "$row/output")" = 1 ] \
              || fail "expected exactly one DEPLOY-DOCS-PREVIEW-URL line"
            expect_line "DEPLOY-DOCS-PREVIEW-URL: https://b-pr-7-infra-docs.sciexp.workers.dev"
            expect_calls 1
            expect "preview uploads as infra-docs with alias b-pr-7, the commit tag and the deployer" \
              '.[0].args | index(["versions", "upload", "--name", "infra-docs", "--preview-alias", "b-pr-7", "--tag", $tag, "--message", "[b-pr-7] \($tag) deployed by rehearsal"]) != null' \
              --arg tag ${builtins.substring 0 12 rev}
            expect "preview config has only the fixed shape" \
              ".[0].config | (keys - $preview_keys) == [] and (.assets | keys) == [\"directory\"]"
            expect "preview config is an assets-only infra-docs preview" \
              '.[0].config | .name == "infra-docs" and .workers_dev == false and .preview_urls == true'
            expect "preview config keeps the payload's compatibility settings" \
              '.[0].config | .compatibility_date == $config[0].compatibility_date and .compatibility_flags == $config[0].compatibility_flags' \
              --slurpfile config ${payload}/dist/client/wrangler.json
            expect "preview assets are the built-in payload's client build" '.[0].assetsIndex and .[0].assetsMarker == null'
            expect "wrangler runs isolated" "$isolated"

            run preview-override preview --rev ${rev} --alias feature/Some_Branch --payload "$TMPDIR/fixtures/override"
            expect_status 0
            expect_line "DEPLOY-DOCS-PREVIEW-URL: https://b-feature-Some-Branch-infra-docs.sciexp.workers.dev"
            expect_calls 1
            expect "preview uploads the --payload build" '.[0].assetsMarker == "override"'

            run preview-symlink preview --rev ${rev} --alias pr-7 --payload "$TMPDIR/fixtures/symlink"
            expect_failure
            expect_line "error: payload entry is neither a regular file nor a directory: $TMPDIR/fixtures/symlink/dist/client/leak"
            expect_calls 0

            run preview-build-command preview --rev ${rev} --alias pr-7 --payload "$TMPDIR/fixtures/build-command"
            expect_status 0
            expect_calls 1
            expect "preview config drops the payload's build, main, routes and bindings" \
              ".[0].config | (keys - $preview_keys) == [] and .name == \"infra-docs\""
            [ ! -e "$sentinel" ] || fail "the payload's build command ran"

            run production-missing-rev production
            expect_status 2
            expect_line "error: --rev is required"
            expect_calls 0

            run preview-missing-rev preview --alias pr-7
            expect_status 2
            expect_line "error: --rev is required"
            expect_calls 0

            run production-short-rev production --rev ${builtins.substring 0 12 rev}
            expect_status 2
            expect_line "error: --rev must be a full 40-hex commit SHA, got '${builtins.substring 0 12 rev}'"
            expect_calls 0

            run preview-uppercase-rev preview --rev ${lib.toUpper rev} --alias pr-7
            expect_status 2
            expect_calls 0

            run preview-empty-alias preview --rev ${rev} --alias ""
            expect_status 2
            expect_line "error: preview requires a non-empty --alias"
            expect_calls 0

            run production-rejects-payload production --rev ${rev} --payload "$TMPDIR/fixtures/override"
            expect_status 2
            expect_line "error: --payload is only valid for preview"
            expect_calls 0

            # main is elsewhere, so a secret check placed after main's head
            # fetch would exit 0 as superseded instead of failing.
            main_is ${otherRev}
            for secret in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID; do
              saved="''${!secret}"
              unset "$secret"
              run "production-without-$secret" production --rev ${rev}
              export "$secret=$saved"
              expect_failure
              grep -qF "$secret is required" "$row/output" || fail "missing error naming $secret"
              ! grep -q '^DEPLOY-DOCS-ACTION' "$row/output" || fail "ran past the secret check"
              expect_calls 0
            done

            touch $out
          '';
    };
}
