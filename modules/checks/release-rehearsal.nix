# Behavioural check: release-packages cuts a real release of packages/docs.
#
# The release-packages effect only runs on main, so nothing before a merge
# otherwise exercises the program with the production semantic-release plugin
# set. This check runs the same release-packages program the effect runs,
# with the production release block from packages/docs/package.json, against
# a fixture that stands in for GitHub: a bare repo the program clones through
# RELEASE_PACKAGES_REPO_URL and semantic-release pushes to through git's
# url.insteadOf, and a stub of the REST endpoints @semantic-release/github
# calls. No secret or network is involved; the token is a fixed dummy the stub
# never checks.
#
# The release-packages effect entry lists this check in its rehearsals, so the
# gated `nix build <effect>^*` on pull requests and merge-queue batches runs it.
#
# Asserted: a missing GITHUB_TOKEN fails before any clone; a rev main has moved
# past is skipped as superseded and a rev outside main's history is refused,
# neither touching tags or releases; the feat commit releases
# @vanixiets/docs-v0.8.0 with the floating docs-v0 / docs-v0.8 tags that
# ADR-0006 mandates (semantic-release-major-tag), with exactly one GitHub
# release; a second run with no new commits releases nothing.
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
      token = "rehearsal-dummy-token";

      # Answers exactly the requests a release makes; anything else is a 404 so
      # an unexpected call fails the run. Every request is appended to
      # requests.jsonl for the assertions below.
      githubStub = pkgs.writeText "github-api-stub.py" ''
        import json, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer

        REPO = "/repos/cameronraysmith/vanixiets"
        log_path, port_path = sys.argv[1], sys.argv[2]

        class Handler(BaseHTTPRequestHandler):
            def _handle(self):
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length) or b"null")
                with open(log_path, "a") as log:
                    log.write(json.dumps({"method": self.command, "path": self.path, "body": body}) + "\n")
                if self.command == "GET" and self.path == REPO:
                    status, reply = 200, {
                        "full_name": "cameronraysmith/vanixiets",
                        "clone_url": "${repoUrl}.git",
                        "permissions": {"push": True},
                    }
                elif self.command == "POST" and self.path == REPO + "/releases":
                    status, reply = 201, {
                        "id": 1,
                        "html_url": "${repoUrl}/releases/tag/" + body["tag_name"],
                        "upload_url": "",
                    }
                else:
                    status, reply = 404, {"message": "Not Found"}
                data = json.dumps(reply).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = do_POST = do_PATCH = do_PUT = do_DELETE = _handle

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
            meta.description = "behavioural check: release-packages cuts a docs release against a local GitHub stand-in";
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

            python3 ${githubStub} "$TMPDIR/requests.jsonl" "$TMPDIR/port" &
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
                (.method == "GET" and .path == "/repos/cameronraysmith/vanixiets")
                or (.method == "POST" and .path == "/repos/cameronraysmith/vanixiets/releases")
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

            touch $out
          '';
    };
}
