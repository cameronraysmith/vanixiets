# Behavioural check: the deploy-docs program drives wrangler as intended.
#
# The deploy-docs and deploy-docs-preview effects only run after a merge or on
# a pull request event with the Cloudflare token, so nothing before a merge
# otherwise runs deploy.sh. This check runs the same deploy-docs program the
# effects run, against the real docs payload and small fixture payloads, with
# a stub standing in for wrangler. No secret or network is involved: the
# Cloudflare values are fixed dummies, and main's head is a file:// URL.
#
# Both effects list this check in their inputs, so the gated
# `nix build <effect>^*` on pull requests and merge-queue batches runs it.
#
# The stub records each invocation's argv, working directory, env file and
# parsed --config, emits the NDJSON event and stdout line deploy.sh parses,
# and, like wrangler, runs the config's build command.
#
# Asserted: production deploys the payload's own config as infra-docs from an
# empty directory and cross-checks the deployments list; a superseded run
# deploys nothing; a version not at 100% fails the run. Preview uploads with a
# config synthesized from a fixed shape, refuses a payload holding a symlink
# before wrangler runs, and never carries a payload's build command.
{ ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      deployDocsProgram = config.apps.deploy-docs.program;
      payload = config.packages.vanixiets-docs;

      rev = "0123456789abcdef0123456789abcdef01234567";
      otherRev = "fedcba9876543210fedcba9876543210fedcba98";
      versionId = "11111111-2222-4333-8444-555555555555";

      wranglerStub = pkgs.writeText "wrangler-stub.js" ''
        "use strict";
        const fs = require("fs");
        const path = require("path");
        const { execSync } = require("child_process");

        const VERSION = "${versionId}";
        const args = process.argv.slice(2);
        const flag = (name) => {
          const i = args.indexOf(name);
          return i < 0 ? null : args[i + 1];
        };
        const rest = [];
        for (let i = 0; i < args.length; i++) {
          if (args[i] === "--config" || args[i] === "--env-file") i++;
          else rest.push(args[i]);
        }

        const configPath = flag("--config");
        const envFile = flag("--env-file");
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
        }) + "\n");

        if (config?.build?.command) execSync(config.build.command, { stdio: "inherit" });

        const emit = (event) =>
          fs.appendFileSync(process.env.WRANGLER_OUTPUT_FILE_PATH, JSON.stringify(event) + "\n");
        const command = rest.slice(0, 2).join(" ");
        if (rest[0] === "deploy") {
          emit({ type: "deploy", version_id: VERSION });
          console.log(`Current Version ID: ''${VERSION}`);
        } else if (command === "versions upload") {
          emit({ type: "version-upload", version_id: VERSION });
          console.log(`Worker Version ID: ''${VERSION}`);
        } else if (command === "deployments list") {
          const percentage = Number(process.env.STUB_PERCENTAGE ?? 100);
          console.log(JSON.stringify([{ versions: [{ version_id: VERSION, percentage }] }]));
        } else {
          console.error(`wrangler stub: unexpected command: ''${rest.join(" ")}`);
          process.exit(1);
        }
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
            meta.description = "behavioural check: deploy-docs against a wrangler stub";
          }
          ''
            set -euo pipefail

            export WRANGLER=${wranglerStub}
            export CLOUDFLARE_API_TOKEN=rehearsal-dummy-token
            export CLOUDFLARE_ACCOUNT_ID=rehearsal-dummy-account
            export GIT_REV=${rev}
            export GIT_REV_SHORT=${builtins.substring 0 7 rev}
            export GIT_REV_SHORT12=${builtins.substring 0 12 rev}
            export GIT_BRANCH=main
            export GIT_COMMIT_MSG=rehearsal
            export GIT_WORKTREE_STATUS=clean
            export DEPLOY_DEPLOYER=rehearsal
            export DEPLOY_HOST=sandbox
            export DEPLOY_DOCS_MAIN_SHA_URL="file://$TMPDIR/main.json"
            export STUB_LOG

            fail() {
              echo "row '$name': $*" >&2
              exit 1
            }
            main_is() {
              printf '{"sha":"%s"}' "$1" > "$TMPDIR/main.json"
            }
            # run <name> <payload> <program args...>: runs deploy-docs with
            # its own stub log and records the exit status in $status.
            run() {
              name=$1
              local payload=$2
              shift 2
              echo "--- $name"
              row="$TMPDIR/rows/$name"
              mkdir -p "$row"
              STUB_LOG="$row/wrangler.ndjson"
              status=0
              DOCS_PAYLOAD="$payload" ${deployDocsProgram} "$@" > "$row/output" 2>&1 || status=$?
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

            # Control: the stub runs a build command handed to it, so the
            # sentinel's absence below means deploy.sh did not pass it on.
            name=stub-runs-build-command
            STUB_LOG="$TMPDIR/control.ndjson" WRANGLER_OUTPUT_FILE_PATH="$TMPDIR/control-events.ndjson" \
              node "$WRANGLER" --config "$TMPDIR/fixtures/build-command/dist/client/wrangler.json" \
              --env-file /dev/null versions upload > /dev/null
            [ -e "$sentinel" ] || fail "stub did not run the build command"
            rm "$sentinel"

            main_is ${rev}
            run production-current ${payload} production
            expect_status 0
            expect_line "deployed nix-built payload to production"
            expect_line "  Worker Version ID: ${versionId}"
            expect_calls 2
            expect "deploy runs as infra-docs" \
              '.[0].args | index(["deploy", "--name", "infra-docs"]) != null'
            expect "deploy uses the payload's config" \
              '.[0].config == $config[0] and (.[0].configPath | endswith("/payload/dist/client/wrangler.json"))' \
              --slurpfile config ${payload}/dist/client/wrangler.json
            expect "deployments list is cross-checked" \
              '.[1].args | index(["deployments", "list", "--name", "infra-docs", "--json"]) != null'
            expect "wrangler runs isolated" "$isolated"

            main_is ${otherRev}
            run production-superseded ${payload} production
            expect_status 0
            expect_line "DEPLOY-DOCS-ACTION: superseded (main is ${otherRev})"
            expect_calls 0

            main_is ${rev}
            STUB_PERCENTAGE=50 run production-partial ${payload} production
            expect_failure
            expect_line "error: version ${versionId} is not at 100% in deployments list"
            expect_calls 2

            run preview ${payload} preview pr-7
            expect_status 0
            expect_line "  Preview URL: https://b-pr-7-infra-docs.sciexp.workers.dev"
            expect_calls 1
            expect "preview uploads as infra-docs with alias b-pr-7 and the commit tag" \
              '.[0].args | index(["versions", "upload", "--name", "infra-docs", "--preview-alias", "b-pr-7", "--tag", $tag]) != null' \
              --arg tag ${builtins.substring 0 12 rev}
            expect "preview config has only the fixed shape" \
              ".[0].config | (keys - $preview_keys) == [] and (.assets | keys) == [\"directory\"]"
            expect "preview config is an assets-only infra-docs preview" \
              '.[0].config | .name == "infra-docs" and .workers_dev == false and .preview_urls == true'
            expect "preview config keeps the payload's compatibility settings" \
              '.[0].config | .compatibility_date == $config[0].compatibility_date and .compatibility_flags == $config[0].compatibility_flags' \
              --slurpfile config ${payload}/dist/client/wrangler.json
            expect "preview assets are the payload's client build" '.[0].assetsIndex'
            expect "wrangler runs isolated" "$isolated"

            run preview-symlink "$TMPDIR/fixtures/symlink" preview pr-7
            expect_failure
            expect_line "error: payload entry is neither a regular file nor a directory: $TMPDIR/fixtures/symlink/dist/client/leak"
            expect_calls 0

            run preview-build-command "$TMPDIR/fixtures/build-command" preview pr-7
            expect_status 0
            expect_calls 1
            expect "preview config drops the payload's build, main, routes and bindings" \
              ".[0].config | (keys - $preview_keys) == [] and .name == \"infra-docs\""
            [ ! -e "$sentinel" ] || fail "the payload's build command ran"

            touch $out
          '';
    };
}
