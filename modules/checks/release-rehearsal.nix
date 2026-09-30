# Behavioural check: release-packages cuts a real release of packages/docs,
# and `release-packages plan` forecasts a pull request's release without one.
#
# The release-packages effect only runs on main, so nothing before a merge
# otherwise exercises the program with the production semantic-release plugin
# set. This check runs the same release-packages program the effect runs,
# with the production release block from packages/docs/package.json, against
# a fixture that stands in for GitHub: a bare repo the program clones through
# RELEASE_PACKAGES_REPO_URL and semantic-release pushes to through git's
# url.insteadOf, and a stub of the REST endpoints @semantic-release/github
# and github-check-run call. No secret or network is involved; the tokens are
# fixed dummies. The stub answers as GitHub does for each: the release PAT
# has push permission, the forge token is an App installation token
# (permissions.push false, HEAD /installation/repositories 200).
#
# The release-packages effect entry lists this check in its rehearsals, so the
# gated `nix build <effect>^*` on pull requests and merge-queue batches runs it.
#
# Asserted for `--rev`: a missing GITHUB_TOKEN fails before any clone; a rev
# main has moved past is skipped as superseded and a rev outside main's
# history is refused, neither touching tags or releases; the feat commit
# releases @vanixiets/docs-v0.8.0 with the floating docs-v0 / docs-v0.8 tags
# that ADR-0006 mandates (semantic-release-major-tag), with exactly one GitHub
# release; a second run with no new commits releases nothing.
#
# Asserted for `plan`, against a second bare remote carrying refs/pull/<N>/head:
# a missing forge token or a head that disagrees with the event or with
# refs/pull/<N>/head exits 1; a feat PR forecasts 0.7.0 -> 0.8.0 and a
# `feat!:` PR 1.0.0 (the production conventionalcommits preset is in force),
# a chore-only PR no release, each with a successful release-plan check run;
# a PR that rewrites the release config and adds a plugin still gets main's
# forecast and its plugin never runs; a PR conflicting with main completes the
# check run as a failure. Every plan row leaves the remote's refs untouched,
# publishes no release, and authenticates every API call with the forge token
# although a release PAT sits in the environment. The stub reports each of
# those pull requests open at the event's head; one closed, or open at another
# head, skips with a neutral check run and never clones, and a failed state
# request fails the check run without cloning.
#
# The floating tags depend on `"success": {}` in that release block. Without
# it semantic-release-monorepo's wrapped success step runs instead, which
# never finds major-tag's CJS `success` export and would hand it the git tag
# rather than the version; `{}` restores the plain per-plugin success steps.
{ ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      releasePackagesProgram = config.apps.release-packages.program;

      repoUrl = "https://github.com/cameronraysmith/vanixiets";
      repoApi = "/repos/cameronraysmith/vanixiets";
      token = "rehearsal-dummy-token";
      forgeToken = "rehearsal-forge-token";
      checkRunId = "42";

      # Answers exactly the requests a release, a plan and a check run make;
      # anything else is a 404 so an unexpected call fails the run. Every
      # request is appended to requests.jsonl, with the bearer token it
      # carried, for the assertions below.
      githubStub = pkgs.writeText "github-api-stub.py" ''
        import json, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from urllib.parse import urlsplit

        REPO = "${repoApi}"
        FORGE = "${forgeToken}"
        log_path, port_path, pull_path = sys.argv[1], sys.argv[2], sys.argv[3]

        class Handler(BaseHTTPRequestHandler):
            def _handle(self):
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length) or b"null")
                path = urlsplit(self.path).path
                auth = self.headers.get("Authorization") or ""
                token = auth.split()[-1] if auth else None
                with open(log_path, "a") as log:
                    log.write(json.dumps({"method": self.command, "path": path, "token": token, "body": body}) + "\n")
                if self.command == "GET" and path == REPO:
                    status, reply = 200, {
                        "full_name": "cameronraysmith/vanixiets",
                        "clone_url": "${repoUrl}.git",
                        "permissions": {"push": token != FORGE},
                    }
                elif self.command == "HEAD" and path == "/installation/repositories":
                    status, reply = (200, {}) if token == FORGE else (401, {"message": "Bad credentials"})
                elif self.command == "POST" and path == REPO + "/releases":
                    status, reply = 201, {
                        "id": 1,
                        "html_url": "${repoUrl}/releases/tag/" + body["tag_name"],
                        "upload_url": "",
                    }
                elif self.command == "POST" and path == REPO + "/check-runs":
                    status, reply = 201, {"id": ${checkRunId}}
                elif self.command == "PATCH" and path == REPO + "/check-runs/${checkRunId}":
                    status, reply = 200, {"id": ${checkRunId}}
                elif self.command == "GET" and path.startswith(REPO + "/pulls/"):
                    with open(pull_path) as f:
                        status, reply = json.load(f)
                else:
                    status, reply = 404, {"message": "Not Found"}
                data = json.dumps(reply).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(data)

            do_GET = do_HEAD = do_POST = do_PATCH = do_PUT = do_DELETE = _handle

        server = HTTPServer(("127.0.0.1", 0), Handler)
        with open(port_path, "w") as f:
            f.write(str(server.server_port))
        server.serve_forever()
      '';
    in
    {
      checks.release-rehearsal =
        pkgs.runCommand "release-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.git
              pkgs.jq
              pkgs.python3
              pkgs.coreutils
              pkgs.gnugrep
            ];
            # The stub listens on loopback, which the darwin sandbox otherwise denies.
            __darwinAllowLocalNetworking = true;
            meta.description = "behavioural check: release-packages cuts a docs release and plans a PR's release against a local GitHub stand-in";
          }
          ''
            set -euo pipefail

            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export GIT_CONFIG_NOSYSTEM=1
            export GIT_CONFIG_GLOBAL="$TMPDIR/gitconfig"
            export GIT_AUTHOR_NAME=rehearsal GIT_AUTHOR_EMAIL=rehearsal@vanixiets.local
            export GIT_COMMITTER_NAME=rehearsal GIT_COMMITTER_EMAIL=rehearsal@vanixiets.local

            # The bare remote stands in for GitHub. release-packages clones it
            # through RELEASE_PACKAGES_REPO_URL; the plain URL and the oauth2
            # credential URL semantic-release derives from GIT_CREDENTIALS both
            # resolve to it, so every fetch and push lands here.
            remote="$TMPDIR/vanixiets.git"
            git init --quiet --bare -b main "$remote"
            git config --global url."file://$TMPDIR/vanixiets".insteadOf ${repoUrl}
            git config --global --add url."file://$TMPDIR/vanixiets".insteadOf \
              "https://oauth2:${token}@github.com/cameronraysmith/vanixiets"

            # History: the last docs release, then a feat commit under
            # packages/docs on main, and a side branch that diverges from main.
            seed="$TMPDIR/seed"
            git init --quiet -b main "$seed"
            mkdir -p "$seed/packages/docs/src"
            cp ${../../packages/docs/package.json} "$seed/packages/docs/package.json"
            echo "# docs" > "$seed/packages/docs/src/index.md"
            git -C "$seed" add -A
            git -C "$seed" commit --quiet -m "chore(docs): initial"
            git -C "$seed" tag @vanixiets/docs-v0.7.0
            initial_sha="$(git -C "$seed" rev-parse HEAD)"
            echo "new page" > "$seed/packages/docs/src/feature.md"
            git -C "$seed" add -A
            git -C "$seed" commit --quiet -m "feat(docs): add feature page"
            feat_sha="$(git -C "$seed" rev-parse HEAD)"
            git -C "$seed" checkout --quiet -b side "$initial_sha"
            echo "side page" > "$seed/packages/docs/src/side.md"
            git -C "$seed" add -A
            git -C "$seed" commit --quiet -m "feat(docs): add side page"
            side_sha="$(git -C "$seed" rev-parse HEAD)"
            git -C "$seed" push --quiet ${repoUrl}.git main side --tags

            # Plan history, on its own remote so the releases above never
            # shift a forecast: main is the 0.7.0 release plus a chore that
            # rewrites index.md, and each pull request sits at
            # refs/pull/<N>/head as on GitHub. PR 5 branches from the release
            # and rewrites index.md too, so it conflicts with main.
            plan_remote="$TMPDIR/plan.git"
            git init --quiet --bare -b main "$plan_remote"
            git -C "$seed" checkout --quiet -b plan-main "$initial_sha"
            echo "# docs on main" > "$seed/packages/docs/src/index.md"
            git -C "$seed" commit --quiet -am "chore(docs): retitle index"
            plan_main_sha="$(git -C "$seed" rev-parse HEAD)"

            pr_commit() { # <base> <message> <edit command...>
              local base=$1 message=$2
              shift 2
              git -C "$seed" checkout --quiet --detach "$base"
              (cd "$seed" && "$@")
              git -C "$seed" add -A
              git -C "$seed" commit --quiet -m "$message"
              git -C "$seed" rev-parse HEAD
            }
            feat_pr="$(pr_commit "$plan_main_sha" "feat(docs): add plan page" \
              sh -c 'echo plan > packages/docs/src/plan.md')"
            major_pr="$(pr_commit "$plan_main_sha" "feat(docs)!: drop the index page" \
              rm packages/docs/src/index.md)"
            chore_pr="$(pr_commit "$plan_main_sha" "chore(docs): tidy index" \
              sh -c 'echo "# docs, tidied" > packages/docs/src/index.md')"
            # Rewrites main's release config: every fix becomes a major, and a
            # plugin that records it ran. The plugin is referenced by absolute
            # path because semantic-release-monorepo resolves relative plugin
            # paths against its own directory, not the package's.
            sentinel="$TMPDIR/plugin-ran"
            printf '%s\n' "module.exports = { verifyConditions() { require('fs').writeFileSync('$sentinel', 'ran'); } };" \
              > "$TMPDIR/sentinel-plugin.cjs"
            injection_pr="$(pr_commit "$plan_main_sha" "fix(docs): tune release config" \
              sh -c "
                jq --arg plugin '$TMPDIR/sentinel-plugin.cjs' \
                  '.release.plugins[0][1].releaseRules = [{type: \"fix\", release: \"major\"}]
                  | .release.plugins += [\$plugin]' packages/docs/package.json > package.json.new
                mv package.json.new packages/docs/package.json
              ")"
            conflict_pr="$(pr_commit "$initial_sha" "feat(docs): rewrite index" \
              sh -c 'echo "# docs on the PR" > packages/docs/src/index.md')"
            git -C "$seed" push --quiet "$plan_remote" \
              "$plan_main_sha:refs/heads/main" refs/tags/@vanixiets/docs-v0.7.0 \
              "$feat_pr:refs/pull/1/head" "$major_pr:refs/pull/2/head" \
              "$chore_pr:refs/pull/3/head" "$injection_pr:refs/pull/4/head" \
              "$conflict_pr:refs/pull/5/head"
            plan_refs="$(git -C "$plan_remote" for-each-ref)"

            python3 ${githubStub} "$TMPDIR/requests.jsonl" "$TMPDIR/port" "$TMPDIR/pull.json" &
            stub_pid=$!
            trap 'kill "$stub_pid"' EXIT
            for _ in $(seq 100); do [ -s "$TMPDIR/port" ] && break; sleep 0.1; done
            [ -s "$TMPDIR/port" ] || { echo "github stub did not start" >&2; exit 1; }
            touch "$TMPDIR/requests.jsonl"

            fail() { echo "release-rehearsal: $*" >&2; exit 1; }

            release_packages() {
              GITHUB_TOKEN=${token} \
              GITHUB_API_URL="http://127.0.0.1:$(cat "$TMPDIR/port")" \
              RELEASE_PACKAGES_REPO_URL="file://$remote" \
                ${releasePackagesProgram} --rev "$1"
            }

            # Runs a command, keeping its exit status in $rc and its output in
            # $TMPDIR/stdout and $TMPDIR/stderr (echoed for the build log).
            capture() {
              rc=0
              "$@" > "$TMPDIR/stdout" 2> "$TMPDIR/stderr" || rc=$?
              cat "$TMPDIR/stdout" "$TMPDIR/stderr" >&2
            }

            remote_tags() { git -C "$remote" tag --list | sort; }
            release_posts() {
              jq -c 'select(.method == "POST" and (.path | endswith("/releases")))' "$TMPDIR/requests.jsonl"
            }
            assert_untouched() {
              [ "$(remote_tags)" = @vanixiets/docs-v0.7.0 ] \
                || fail "$1 changed remote tags: $(remote_tags)"
              [ ! -s "$TMPDIR/requests.jsonl" ] \
                || fail "$1 called the API: $(cat "$TMPDIR/requests.jsonl")"
            }

            echo "--- missing GITHUB_TOKEN: fails before any clone"
            capture env -u GITHUB_TOKEN RELEASE_PACKAGES_REPO_URL="file://$TMPDIR/absent.git" \
              ${releasePackagesProgram} --rev "$feat_sha"
            [ "$rc" = 1 ] || fail "missing token exited $rc, expected 1"
            grep -q "GITHUB_TOKEN is required" "$TMPDIR/stderr" \
              || fail "missing token did not report GITHUB_TOKEN"
            ! grep -q RELEASE-CLONE-START "$TMPDIR/stdout" \
              || fail "missing token still started a clone"
            assert_untouched "missing token"

            echo "--- superseded: main has moved past the rev"
            capture release_packages "$initial_sha"
            [ "$rc" = 0 ] || fail "superseded run exited $rc, expected 0"
            grep -qxF "RELEASE-PACKAGES-ACTION: superseded (main moved to $feat_sha)" "$TMPDIR/stdout" \
              || fail "superseded run did not report superseded"
            assert_untouched "superseded run"

            echo "--- diverged: rev outside main's history"
            capture release_packages "$side_sha"
            [ "$rc" = 1 ] || fail "diverged run exited $rc, expected 1"
            grep -q "refusing to release a rev outside main's history" "$TMPDIR/stderr" \
              || fail "diverged run did not report the refusal"
            assert_untouched "diverged run"

            echo "--- first run: feat commit releases 0.8.0"
            capture release_packages "$feat_sha"
            [ "$rc" = 0 ] || fail "first run exited $rc"
            grep -qxF "RELEASE-PACKAGE-OK: packages/docs" "$TMPDIR/stdout" \
              || fail "first run did not release packages/docs"

            for tag in @vanixiets/docs-v0.8.0 docs-v0 docs-v0.8; do
              sha="$(git -C "$remote" rev-parse --verify --quiet "refs/tags/$tag^{commit}")" \
                || fail "remote is missing tag $tag"
              [ "$sha" = "$feat_sha" ] || fail "tag $tag is at $sha, expected $feat_sha"
            done

            posts="$(release_posts)"
            [ "$(printf '%s\n' "$posts" | grep -c .)" = 1 ] \
              || fail "expected one release POST, got: $posts"
            [ "$(printf '%s\n' "$posts" | jq -r .body.tag_name)" = @vanixiets/docs-v0.8.0 ] \
              || fail "release POST has the wrong tag_name: $posts"

            if jq -e 'select(
                (.method == "GET" and .path == "${repoApi}")
                or (.method == "POST" and .path == "${repoApi}/releases")
                | not)' "$TMPDIR/requests.jsonl" > /dev/null; then
              fail "unexpected API request: $(cat "$TMPDIR/requests.jsonl")"
            fi

            echo "--- second run: no new commits, no release"
            tags_before="$(remote_tags)"
            release_packages "$feat_sha" || fail "second run exited $?"
            [ "$(remote_tags)" = "$tags_before" ] \
              || fail "second run changed remote tags: $(remote_tags)"
            [ "$(release_posts)" = "$posts" ] \
              || fail "second run published a release: $(release_posts)"

            # Plan runs see the environment nixbot gives a pullRequest trigger,
            # plus a release PAT that must go unused. Their global git config
            # sends the GitHub URL to the plan remote, so a push that escaped
            # the program's own redirection would show in its refs. Extra
            # arguments are env(1) operands overriding that environment.
            printf '%s\n' \
              "[url \"file://$TMPDIR/plan\"]" \
              "  insteadOf = ${repoUrl}" \
              "  insteadOf = https://oauth2:${forgeToken}@github.com/cameronraysmith/vanixiets" \
              "  insteadOf = https://x-access-token:${forgeToken}@github.com/cameronraysmith/vanixiets" \
              "  insteadOf = https://${forgeToken}@github.com/cameronraysmith/vanixiets" \
              > "$TMPDIR/plan-gitconfig"
            # pull_reply, when set, is the stub's [status, body] for the pull
            # request; by default it is open at the event's head.
            plan() { # <number> <head> [env operands...]
              local number=$1 head=$2
              shift 2
              : > "$TMPDIR/requests.jsonl"
              rm -f "$sentinel"
              jq -n --argjson n "$number" --arg h "$head" \
                '{pullRequest: {number: $n, headRev: $h}}' > "$TMPDIR/event.json"
              if [ -n "''${pull_reply:-}" ]; then
                printf '%s\n' "$pull_reply" > "$TMPDIR/pull.json"
              else
                jq -n --arg h "$head" '[200, {state: "open", head: {sha: $h}}]' > "$TMPDIR/pull.json"
              fi
              capture env \
                GIT_CONFIG_GLOBAL="$TMPDIR/plan-gitconfig" \
                GITHUB_TOKEN=rehearsal-release-pat \
                GITHUB_FORGE_TOKEN=${forgeToken} \
                GITHUB_API_URL="http://127.0.0.1:$(cat "$TMPDIR/port")" \
                RELEASE_PACKAGES_REPO_URL="file://$plan_remote" \
                NIXBOT_EVENT_KIND=pull_request \
                NIXBOT_EVENT_JSON="$TMPDIR/event.json" \
                NIXBOT_PR_NUMBER="$number" \
                NIXBOT_PR_HEAD="$head" \
                env "$@" ${releasePackagesProgram} plan
            }
            assert_plan_harmless() {
              [ "$(git -C "$plan_remote" for-each-ref)" = "$plan_refs" ] \
                || fail "$1 wrote to the remote: $(git -C "$plan_remote" for-each-ref)"
              [ -z "$(release_posts)" ] || fail "$1 published a release: $(release_posts)"
              if jq -e 'select(.token != "${forgeToken}")' "$TMPDIR/requests.jsonl" > /dev/null; then
                fail "$1 authenticated without the forge token: $(cat "$TMPDIR/requests.jsonl")"
              fi
              if jq -e 'select(
                  (.method == "GET" and .path == "${repoApi}")
                  or (.method == "HEAD" and .path == "/installation/repositories")
                  or (.method == "GET" and (.path | test("^${repoApi}/pulls/[0-9]+$")))
                  or (.method == "POST" and .path == "${repoApi}/check-runs")
                  or (.method == "PATCH" and .path == "${repoApi}/check-runs/${checkRunId}")
                  | not)' "$TMPDIR/requests.jsonl" > /dev/null; then
                fail "$1 made an unexpected API request: $(cat "$TMPDIR/requests.jsonl")"
              fi
            }
            check_run_created() { # <label> <head>
              jq -e --arg h "$2" 'select(.method == "POST" and .path == "${repoApi}/check-runs"
                  and .body.name == "release-plan" and .body.head_sha == $h)' \
                "$TMPDIR/requests.jsonl" > /dev/null \
                || fail "$1 created no release-plan check run on $2: $(cat "$TMPDIR/requests.jsonl")"
            }
            check_run_completion() {
              jq -c 'select(.method == "PATCH" and .path == "${repoApi}/check-runs/${checkRunId}") | .body' \
                "$TMPDIR/requests.jsonl"
            }
            assert_check_run() { # <label> <head> <conclusion>
              check_run_created "$1" "$2"
              completion="$(check_run_completion)"
              [ "$(printf '%s\n' "$completion" | grep -c .)" = 1 ] \
                || fail "$1 expected one check run completion, got: $completion"
              [ "$(printf '%s\n' "$completion" | jq -r '.status + " " + .conclusion')" = "completed $3" ] \
                || fail "$1 completed the check run as: $completion"
            }
            assert_forecast() { # <label> <head> <next>
              [ "$rc" = 0 ] || fail "$1 exited $rc, expected 0"
              grep -qxF "RELEASE-PLAN: docs 0.7.0 -> $3" "$TMPDIR/stdout" \
                || fail "$1 did not forecast docs 0.7.0 -> $3"
              assert_check_run "$1" "$2" success
              [ "$(printf '%s\n' "$completion" | jq -r .output.title)" = "Release plan" ] \
                || fail "$1 check run has the wrong title: $completion"
              assert_plan_harmless "$1"
            }
            assert_skipped() { # <label> <number> <head> <state>
              [ "$rc" = 0 ] || fail "$1 exited $rc, expected 0"
              grep -qxF "RELEASE-PLAN: skipped ($4)" "$TMPDIR/stdout" \
                || fail "$1 did not report RELEASE-PLAN: skipped ($4)"
              ! grep -q RELEASE-PLAN-CLONE-START "$TMPDIR/stdout" \
                || fail "$1 cloned the repository"
              jq -e --arg p "${repoApi}/pulls/$2" 'select(.method == "GET" and .path == $p)' \
                "$TMPDIR/requests.jsonl" > /dev/null \
                || fail "$1 did not ask for pull request #$2: $(cat "$TMPDIR/requests.jsonl")"
              assert_check_run "$1" "$3" neutral
              [ "$(printf '%s\n' "$completion" | jq -r '.output.title + ": " + .output.summary')" \
                = "Release plan skipped: pull request #$2 is $4; no forecast" ] \
                || fail "$1 check run has the wrong output: $completion"
              assert_plan_harmless "$1"
            }

            echo "--- plan: missing forge token fails before any network"
            plan 1 "$feat_pr" -u GITHUB_FORGE_TOKEN RELEASE_PACKAGES_REPO_URL="file://$TMPDIR/absent.git"
            [ "$rc" = 1 ] || fail "plan without forge token exited $rc, expected 1"
            grep -q GITHUB_FORGE_TOKEN "$TMPDIR/stderr" \
              || fail "plan without forge token did not report GITHUB_FORGE_TOKEN"
            [ ! -s "$TMPDIR/requests.jsonl" ] \
              || fail "plan without forge token called the API: $(cat "$TMPDIR/requests.jsonl")"

            echo "--- plan: NIXBOT_PR_HEAD disagrees with the event"
            plan 1 "$feat_pr" NIXBOT_PR_HEAD="$major_pr"
            [ "$rc" = 1 ] || fail "plan with disagreeing NIXBOT_PR_HEAD exited $rc, expected 1"
            assert_plan_harmless "plan with disagreeing NIXBOT_PR_HEAD"

            echo "--- plan: refs/pull/1/head is not the event's head"
            plan 1 "$major_pr"
            [ "$rc" = 1 ] || fail "plan with a stale head exited $rc, expected 1"
            assert_plan_harmless "plan with a stale head"
            assert_check_run "plan with a stale head" "$major_pr" failure

            echo "--- plan: feat PR forecasts 0.8.0"
            plan 1 "$feat_pr"
            assert_forecast "feat plan" "$feat_pr" 0.8.0
            printf '%s\n' "$completion" | jq -r .output.summary \
              | grep -qE '^\|.*docs.*\|.*0\.7\.0.*\|.*0\.8\.0.*\|.*minor' \
              || fail "feat plan check run summary lacks the docs row: $completion"

            echo "--- plan: breaking PR forecasts 1.0.0"
            plan 2 "$major_pr"
            assert_forecast "breaking plan" "$major_pr" 1.0.0

            echo "--- plan: chore PR releases nothing"
            plan 3 "$chore_pr"
            assert_forecast "chore plan" "$chore_pr" "no release"

            echo "--- plan: PR release config and plugins are ignored"
            plan 4 "$injection_pr"
            [ ! -e "$sentinel" ] || fail "injection plan ran the PR's plugin"
            assert_forecast "injection plan" "$injection_pr" 0.7.1

            echo "--- plan: PR conflicting with main fails its check run"
            plan 5 "$conflict_pr"
            [ "$rc" = 1 ] || fail "conflict plan exited $rc, expected 1"
            assert_check_run "conflict plan" "$conflict_pr" failure
            printf '%s\n' "$completion" | grep -qF "conflicts with main" \
              || fail "conflict plan check run does not report the conflict: $completion"
            assert_plan_harmless "conflict plan"

            # The clone URL is absent, so a fetch the skip failed to prevent
            # would fail the row as well as print RELEASE-PLAN-CLONE-START.
            echo "--- plan: closed PR skips without cloning"
            pull_reply="$(jq -nc --arg h "$feat_pr" '[200, {state: "closed", merged: true, head: {sha: $h}}]')" \
              plan 1 "$feat_pr" RELEASE_PACKAGES_REPO_URL="file://$TMPDIR/absent.git"
            assert_skipped "closed plan" 1 "$feat_pr" closed

            echo "--- plan: PR moved to a newer head skips without cloning"
            pull_reply="$(jq -nc --arg h "$major_pr" '[200, {state: "open", head: {sha: $h}}]')" \
              plan 1 "$feat_pr" RELEASE_PACKAGES_REPO_URL="file://$TMPDIR/absent.git"
            assert_skipped "superseded plan" 1 "$feat_pr" superseded

            echo "--- plan: pull request state unavailable fails its check run"
            pull_reply='[404, {"message": "Not Found"}]' \
              plan 1 "$feat_pr" RELEASE_PACKAGES_REPO_URL="file://$TMPDIR/absent.git"
            [ "$rc" = 1 ] || fail "plan without pull request state exited $rc, expected 1"
            ! grep -q RELEASE-PLAN-CLONE-START "$TMPDIR/stdout" \
              || fail "plan without pull request state cloned the repository"
            assert_check_run "plan without pull request state" "$feat_pr" failure
            printf '%s\n' "$completion" | grep -qF "cannot read the state of pull request #1" \
              || fail "plan without pull request state check run does not report it: $completion"
            assert_plan_harmless "plan without pull request state"

            touch $out
          '';
    };
}
