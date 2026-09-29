# herculesCI effect: semantic-release for every monorepo package, on main only.
#
# One program, one path. effectRunContext.mainOnlyGuard refuses to run outside
# a push to main before the GITHUB_TOKEN secret is read, so the token is only
# ever held by code from main. Pull requests and merge-queue batches build this
# effect's dependencies without running it.
#
# Merge-queue batches land by fast-forwarding main, possibly several in quick
# succession, so by the time this effect runs main may have moved past the rev
# it was evaluated at. The `lock` orders runs across builds; a run whose rev is
# an ancestor of origin/main skips with exit 0 and leaves the release to the
# run for the newer rev, which sees the same commits.
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
      shortRev = herculesCI.config.repo.shortRev;
      rev = herculesCI.config.repo.rev;

      # Captured under the outer `config` (this file's flake-parts config)
      # before `withSystem` rebinds `config` to the per-system config below.
      runContext = config.flake.lib.effectRunContext;
    in
    {
      onPush.default.outputs.effects.release-packages = withSystem "x86_64-linux" (
        { config, pkgs, ... }:
        let
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

          listPackagesProgram = config.apps.list-packages-json.program;
          releaseProgram = config.apps.release.program;
        in
        hci-effects.mkEffect {
          name = "release-packages";

          # nixbot extension (passes through mkEffect): serialises runs of this
          # effect across builds so successive main pushes release in order.
          lock = "release-packages";

          # nixbot mints a runtime token carrying event/ref claims only for
          # audiences the effect declares; mainOnlyGuard requests this
          # audience. Must be a JSON array string: a bare nix list serialises
          # space-separated into the derivation environment, and nixbot's
          # parser rejects that before the sandbox starts.
          idTokenAudiences = builtins.toJSON [ runContext.audience ];

          # See deploy-docs.nix for why this map is required under nixbot.
          # GITHUB_TOKEN is the only entry this effect reads; the composed
          # file also carries CLOUDFLARE_*, which this effect has no use for.
          secretsMap.GITHUB_TOKEN = "GITHUB_TOKEN";

          # Why: mkEffect's defaultInputs do not include git; the clone below
          # requires it. curl, jq and coreutils (base64, cut, tr) back
          # mainOnlyGuard's runtime token exchange.
          inputs = [
            pkgs.git
            pkgs.curl
            pkgs.jq
            pkgs.coreutils
            # Not used at run time: listing the rehearsal makes the gated
            # `nix build <effect>^*` on PRs and batches run it before merge.
            config.checks.release-rehearsal
          ];

          effectScript = ''
            set -euo pipefail

            ${runContext.mainOnlyGuard}

            echo "=== effects.release-packages (semantic-release per package) ==="
            echo "rev:      ${lib.escapeShellArg (toString rev)}"
            echo "shortRev: ${lib.escapeShellArg (toString shortRev)}"

            export GITHUB_TOKEN="$(jq -r '.GITHUB_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"

            if [ -z "''${GITHUB_TOKEN:-}" ] || [ "$GITHUB_TOKEN" = "null" ]; then
              echo "error: GITHUB_TOKEN missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi

            # Why: do not use config.repo.remoteHttpUrl — it may carry the
            # forge installation token, which would leak via banner echo.
            clone_url="https://github.com/cameronraysmith/vanixiets.git"

            clone_dir="$(mktemp -d -t release-packages-clone.XXXXXX)"

            trap 'rm -rf "$clone_dir"' EXIT

            GIT_REV=${lib.escapeShellArg (toString rev)}
            GIT_BRANCH="$CI_BRANCH"

            echo "RELEASE-CLONE-START: $clone_url $GIT_REV $GIT_BRANCH"

            git clone "$clone_url" "$clone_dir"
            git -C "$clone_dir" fetch --tags origin

            git -C "$clone_dir" checkout -B "$GIT_BRANCH" "$GIT_REV"
            echo "RELEASE-CLONE-CHECKOUT: $GIT_REV"

            git -C "$clone_dir" fetch origin "$GIT_BRANCH"
            head_rev="$(git -C "$clone_dir" rev-parse HEAD)"
            remote_rev="$(git -C "$clone_dir" rev-parse "origin/$GIT_BRANCH")"
            if [ "$head_rev" != "$remote_rev" ]; then
              if git -C "$clone_dir" merge-base --is-ancestor "$head_rev" "$remote_rev"; then
                echo "RELEASE-PACKAGES-ACTION: superseded (main moved to $remote_rev)"
                exit 0
              fi
              echo "error: $head_rev is not on origin/$GIT_BRANCH ($remote_rev); refusing to release a rev outside main's history" >&2
              exit 1
            fi

            echo "RELEASE-PACKAGES-ACTION: release"
            echo "RELEASE-CLONE-READY: $clone_dir"

            # semantic-release's get-git-auth-url.js treats GIT_CREDENTIALS as user:password and constructs the authenticated URL in-process. The vanixiets-effects-secrets PAT (Read+Write) is the release authority; no forge installation token is reused for release mutation.
            # Username MUST NOT be `x-access-token` here: that string is reserved for GitHub App installation tokens (ghs_*) and routes fine-grained PATs (github_pat_*) into the wrong credential validator, surfacing as "Invalid username or token. Password authentication is not supported for Git operations." at git push despite Bearer-auth (API) succeeding. `oauth2` is the conventional username for fine-grained and classic PATs over HTTPS Basic auth.
            export GIT_CREDENTIALS="oauth2:''${GITHUB_TOKEN}"

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

            # list-packages-json calls `git rev-parse --show-toplevel`
            # which must resolve to $clone_dir (the only real git tree).
            cd "$clone_dir"

            packages_json="$("$LIST_PACKAGES")"
            echo "packages discovered: $packages_json"

            failed_packages=()

            while IFS= read -r pkg_path; do
              [ -z "$pkg_path" ] && continue

              echo "RELEASE-PACKAGE-ITERATION: $pkg_path"

              set +e
              "$RELEASE" "$pkg_path"
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
