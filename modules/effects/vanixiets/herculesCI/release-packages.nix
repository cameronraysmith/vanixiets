# herculesCI effect: semantic-release per-package dispatcher (dry-run vs release).
{
  config,
  inputs,
  lib,
  withSystem,
  ...
}:
{
  herculesCI =
    herculesCI:
    let
      # Nullable: null on tag pushes (no branch).
      branch = herculesCI.config.repo.branch;
      shortRev = herculesCI.config.repo.shortRev;
      rev = herculesCI.config.repo.rev;

      isMain = branch == "main";

      # builtins.match returns null on no-match, list of captures on success; null-guard keeps the eval pure for non-PR pushes.
      prMergeMatch = if branch == null then null else builtins.match "^refs/pull/([0-9]+)/merge$" branch;
      isPrMerge = prMergeMatch != null;
      prNumber = if isPrMerge then builtins.head prMergeMatch else null;

      actionBanner = if isMain then "release" else "dry-run";
    in
    {
      onPush.default.outputs.effects.release-packages = withSystem "x86_64-linux" (
        { config, pkgs, ... }:
        let
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

          # release.sh --dry-run short-circuits on in-tree branches:["main"]; preview-version is the non-main path.
          listPackagesProgram = config.apps.list-packages-json.program;
          releaseProgram = config.apps.release.program;
          previewVersionProgram = config.apps.preview-version.program;
        in
        hci-effects.mkEffect {
          name = "release-packages";

          # Why: mkEffect's defaultInputs do not include git; clone preamble below requires it.
          inputs = [ pkgs.git ];

          effectScript = ''
            set -euo pipefail

            echo "=== effects.release-packages (semantic-release per-package dispatcher) ==="
            echo "branch:   ${lib.escapeShellArg (toString branch)}"
            echo "rev:      ${lib.escapeShellArg (toString rev)}"
            echo "shortRev: ${lib.escapeShellArg (toString shortRev)}"
            echo "isMain:   ${if isMain then "true" else "false"}"

            echo "RELEASE-PACKAGES-ACTION: ${actionBanner}"

            export GITHUB_TOKEN="$(jq -r '.GITHUB_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"

            if [ -z "''${GITHUB_TOKEN:-}" ] || [ "$GITHUB_TOKEN" = "null" ]; then
              echo "error: GITHUB_TOKEN missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi

            # Why: do not use config.repo.remoteHttpUrl — buildbot-nix bakes
            # the App installation token into it; would leak via banner echo.
            clone_url="https://github.com/cameronraysmith/vanixiets.git"

            clone_dir="$(mktemp -d -t release-packages-clone.XXXXXX)"

            trap 'rm -rf "$clone_dir"' EXIT

            GIT_REV=${lib.escapeShellArg (toString rev)}
            GIT_BRANCH=${lib.escapeShellArg (if branch == null then "" else toString branch)}
            ${
              if isPrMerge then
                ''
                  git clone "$clone_url" "$clone_dir"
                  git -C "$clone_dir" fetch --tags origin

                  # `git fetch origin refs/pull/<N>/head` alone updates
                  # FETCH_HEAD but does NOT auto-create the remote-tracking
                  # ref; the explicit `+ref:remote-tracking-ref` mapping
                  # closes that gap.
                  git -C "$clone_dir" fetch origin \
                    "+refs/pull/${toString prNumber}/head:refs/remotes/origin/pr-${toString prNumber}-head"
                  head_sha="$(git -C "$clone_dir" rev-parse origin/pr-${toString prNumber}-head)"

                  echo "RELEASE-CLONE-PR-HEAD: ${toString prNumber} $head_sha"
                  echo "RELEASE-CLONE-PR-DISPATCH: ${toString prNumber} buildbot-rev=$GIT_REV head=$head_sha"

                  echo "RELEASE-CLONE-START: $clone_url $GIT_REV $GIT_BRANCH"

                  git -C "$clone_dir" checkout -B "pr-${toString prNumber}-head" "$head_sha"
                  echo "RELEASE-CLONE-CHECKOUT: $head_sha"

                  # Trivially true post-fetch unless force-push race lost the head ref; set -e propagates abort.
                  git -C "$clone_dir" rev-parse --verify origin/pr-${toString prNumber}-head >/dev/null
                ''
              else
                ''
                  echo "RELEASE-CLONE-START: $clone_url $GIT_REV $GIT_BRANCH"

                  git clone "$clone_url" "$clone_dir"
                  git -C "$clone_dir" fetch --tags origin

                  if [ -n "$GIT_BRANCH" ]; then
                    checkout_branch="$GIT_BRANCH"
                  else
                    checkout_branch="release-packages-detached"
                  fi
                  git -C "$clone_dir" checkout -B "$checkout_branch" "$GIT_REV"
                  echo "RELEASE-CLONE-CHECKOUT: $GIT_REV"

                  if [ -n "$GIT_BRANCH" ]; then
                    git -C "$clone_dir" fetch origin "$GIT_BRANCH"
                    head_rev="$(git -C "$clone_dir" rev-parse HEAD)"
                    remote_rev="$(git -C "$clone_dir" rev-parse "origin/$GIT_BRANCH")"
                    if [ "$head_rev" != "$remote_rev" ]; then
                      echo "RELEASE-CLONE-STALE: expected $head_rev remote $remote_rev" >&2
                      exit 1
                    fi
                  fi
                ''
            }

            echo "RELEASE-CLONE-READY: $clone_dir"

            # semantic-release's get-git-auth-url.js treats GIT_CREDENTIALS as user:password and constructs the authenticated URL in-process. The vanixiets-effects-secrets PAT (Read+Write) is the canonical authority — the buildbot-nix App installation token (Read-only) is NOT reused for release mutation.
            export GIT_CREDENTIALS="x-access-token:''${GITHUB_TOKEN}"

            # CI=true bypasses semantic-release's env-ci abort. GIT_AUTHOR/COMMITTER are honoured natively without writing .git/config (which the bwrap /nix/store ro-bind would block).
            export CI=true
            export GIT_BRANCH
            export RELEASE_REPO_ROOT="$clone_dir"
            export GIT_AUTHOR_NAME=semantic-release
            export GIT_AUTHOR_EMAIL=semantic-release@vanixiets.local
            export GIT_COMMITTER_NAME=semantic-release
            export GIT_COMMITTER_EMAIL=semantic-release@vanixiets.local

            # Why: bwrap sandbox does not bind working tree; .# cannot resolve. Use eval-time /nix/store paths.
            LIST_PACKAGES=${listPackagesProgram}
            RELEASE=${releaseProgram}
            PREVIEW=${previewVersionProgram}

            # list-packages-json calls `git rev-parse --show-toplevel`
            # which must resolve to $clone_dir (the only real git tree).
            cd "$clone_dir"

            packages_json="$("$LIST_PACKAGES")"
            echo "packages discovered: $packages_json"

            failed_packages=()

            while IFS= read -r pkg_path; do
              [ -z "$pkg_path" ] && continue

              echo "RELEASE-PACKAGE-ITERATION: $pkg_path"

              # CLI grammars differ — release <pkg-path> [--dry-run] vs preview-version [target-branch] [pkg-path] — so a single shared dispatch line cannot work.
              set +e
              ${if isMain then ''"$RELEASE" "$pkg_path"'' else ''"$PREVIEW" main "$pkg_path"''}
              rc=$?
              set -e

              if [ "$rc" -eq 0 ]; then
                echo "RELEASE-PACKAGE-OK: $pkg_path"
              else
                echo "RELEASE-PACKAGE-FAILURE: $pkg_path (exit $rc)"
                failed_packages+=("$pkg_path")
              fi
            done < <(printf '%s\n' "$packages_json" | jq -r '.[].path')

            if [ "''${#failed_packages[@]}" -gt 0 ]; then
              echo "error: ''${#failed_packages[@]} package(s) failed: ''${failed_packages[*]}" >&2
              exit 1
            fi

            echo "=== release-packages effect complete (exit 0) ==="
          '';
        }
      );
    };
}
