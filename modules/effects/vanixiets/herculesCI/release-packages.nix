# effects.release-packages — semantic-release per-package dispatcher
# (M4 feature `m4-release-packages`). Consolidates three pre-consolidation
# jobs (preview-release-version, production-release-packages-dryrun,
# production-release-packages-cutover) into a single herculesCI effect
# that iterates every package discovered under `packages/*` and dispatches
# `semantic-release` with branch-aware behaviour.
#
# Design contract (see mission AGENTS.md "ADR-002 locked decisions" and
# `.factory/validation-contract.md` VAL-EFFECT-RELEASEPACKAGES-*):
#
#   Option Gamma store-path embedding:
#     The effect body invokes both the `list-packages-json` and `release`
#     flake apps via the nix-eval-time resolved store paths
#     `${config.apps.x86_64-linux.list-packages-json.program}` and
#     `${config.apps.x86_64-linux.release.program}`. The effect never
#     dispatches via a flake-app shell-out (`nix run`); bwrap does not
#     bind the working tree, so the .# syntax cannot resolve.
#
#   Branch dispatch (exact string equality):
#     Selection is driven by `primaryRepo.branch == "main"`, surfaced
#     through `herculesCI.config.repo.branch` which hercules-ci-effects
#     populates from the primaryRepo record at flake.herculesCI entry.
#     * primaryRepo.branch == "main"  → real semantic-release per package
#         (semantic-release's per-package commit-analyzer decides whether
#         to cut a release; tag push + GitHub Release published when so;
#         npmPublish stays false — never overridden).
#     * any other branch (or null)    → per-package `--dry-run`
#         (semantic-release prints the next-version preview only; no git
#         tags pushed, no GitHub Release created, no remote git mutation).
#
#   Pattern C'-refined secrets preamble:
#     Extracts GITHUB_TOKEN ONLY from $HERCULES_CI_SECRETS_JSON at the
#     `.GITHUB_TOKEN.data.value` envelope (see
#     modules/effects/vanixiets/secrets.nix for the generator that emits
#     this shape). Per ADR-002 §5.3 exclusivity audit, this effect MUST
#     NOT consume SOPS_AGE_KEY (load-bearing only for k3d-bootstrap-secrets)
#     and MUST NOT reference NPM_TOKEN (not part of the closed 4-key
#     bundle; npmPublish=false invariant means no npm publish surface).
#
#   ADR-003 Option α clone preamble (m5-01a-release-packages-clone-internally-implement):
#     The buildbot-effects bwrap sandbox does NOT bind-mount the worker's
#     git checkout (`mkEffect` only seeds `HOME=/build/home`); the previous
#     iteration of this effect failed with `fatal: not a git repository`
#     because semantic-release ran against an empty $PWD. Per ADR-003
#     "release-packages clone-and-push" (Option α, locked 2026-04-24;
#     mission-internal note kept under repo-local `.factory/library/`,
#     git-ignored via `.git/info/exclude`),
#     the preamble below performs an in-sandbox clone of
#     the canonical GitHub URL, checks out the exact triggering rev,
#     verifies branch-tip freshness, exports `GIT_CREDENTIALS` for
#     semantic-release's auth-URL builder, and points the existing
#     env-var contract's `RELEASE_REPO_ROOT` at the clone (not `$PWD`).
#
#     Six normative phases (ADR-003 §Architecture):
#       1. URL canonicalization — literal `https://github.com/cameronraysmith/vanixiets.git`
#          (NOT `herculesCI.config.repo.remoteHttpUrl`, which bakes the
#          buildbot-nix GitHub App installation token at clone time).
#       2. Full clone (no shallow / since-date / blob-filter flags):
#          semantic-release needs the full tag list, full commit log
#          since `lastRelease.gitHead`, and per-commit `git diff-tree`
#          changed-file lookups (semantic-release-monorepo path filter).
#       3. Exact-rev checkout via `git checkout -B "$GIT_BRANCH" "$GIT_REV"` —
#          force-push and rapid-merge events become deterministic; the
#          effect releases what buildbot-master's nix-eval ran against.
#       4. Single freshness check before the package loop (invariant #11):
#          `git fetch origin "$GIT_BRANCH"` + `rev-parse HEAD == origin/$GIT_BRANCH`;
#          stale runs emit `RELEASE-CLONE-STALE` and exit non-zero.
#       5. Sanitized structured banners — `RELEASE-CLONE-{START,CHECKOUT,READY,STALE}`.
#          NEVER echo a token-baked URL (invariant #9); only the
#          canonicalized GitHub URL appears in any banner.
#       6. `GIT_CREDENTIALS=x-access-token:${GITHUB_TOKEN}` export for
#          semantic-release's `get-git-auth-url.js` URL builder
#          (in-process; no host credential helper, no ~/.git-credentials
#          write per invariants #5 / VAL-RELEASE-α-AUTH-003 / -004).
#
#     Helper extraction (ADR-003 §D3): the inline preamble lands at ~35
#     bash lines; well under the ~60-line threshold for factoring into
#     `modules/effects/lib/mkMutatingEffect.nix`. Future PR-creating
#     mutating effects (security-update-pr, dep-bump) should prefer
#     upstream `hci-effects.git-update`/`flakeUpdate`, NOT a local helper.
#
#   Symmetric env-var contract (CI + GIT_AUTHOR/COMMITTER + RELEASE_REPO_ROOT)
#   (m4-release-packages-runtime-deps-contract; extended in m5-01a):
#     Exports CI=true, GIT_BRANCH (from herculesCI.config.repo.branch at
#     eval time via lib.escapeShellArg), RELEASE_REPO_ROOT=$clone_dir
#     (the in-sandbox clone created by the ADR-003 preamble; previously
#     "$PWD", which referred to the empty mkEffect cwd that triggered
#     the `fatal: not a git repository` failure mode), and the
#     GIT_AUTHOR_NAME/EMAIL + GIT_COMMITTER_NAME/EMAIL identity quartet.
#     Required because the buildbot-effects bwrap sandbox does not
#     bind-mount the worker's checkout AND provides no host-PATH binaries
#     beyond /nix/store ro-bind + writeShellApplication runtimeInputs
#     PATH (upstream-by-design across all 3 reference effect
#     implementations); release.sh's `git config user.{name,email} "…"`
#     writes would fail with `error: could not lock config file
#     .git/config`, and semantic-release would abort with `running on a
#     CI environment is required` (env-ci default) without these
#     exports. Symmetric to the deploy-docs env-var contract (GIT_* +
#     DEPLOY_*) precedent.
#
#   Per-package atomicity (NOT fail-fast):
#     If package A fails, the loop continues to package B. Each
#     per-package failure is recorded; the dispatcher exits non-zero at
#     the end iff ANY package failed. Successful per-package tags +
#     GitHub Releases persist (semantic-release's own per-package
#     mutations are atomic per-package); failures surface via the
#     RELEASE-PACKAGE-FAILURE banners for manual re-trigger.
#
#   Posture A outer gate:
#     Fork-PR exposure is blocked by `effects_on_pull_requests = false`
#     in `buildbot-nix.toml`, which precedes this inner branch-dispatch.
#     The dispatcher logic runs only after the outer gate has passed.
#
#   Structured banners (RP-05 / RP-06 / RP-19 log-grep anchors):
#     * `RELEASE-PACKAGES-ACTION: dry-run|release` emitted exactly once
#       per run, identifying the dispatcher path taken (analogous to the
#       deploy-docs DEPLOY-DOCS-ACTION banner).
#     * `RELEASE-PACKAGE-ITERATION: <pkg-path>` emitted before each
#       per-package release invocation (count must equal
#       `just list-packages-json | jq length`).
#     * `RELEASE-PACKAGE-OK: <pkg-path>` emitted on per-package success.
#     * `RELEASE-PACKAGE-FAILURE: <pkg-path> (exit <rc>)` emitted on
#       per-package failure; the loop continues regardless.
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
      # primaryRepo.branch (exposed as config.repo.branch by
      # hercules-ci-effects' paramModule, populated from primaryRepo.branch
      # at flake.herculesCI entry). Type: nullable string — null on tag
      # pushes where branch is not populated.
      branch = herculesCI.config.repo.branch;
      shortRev = herculesCI.config.repo.shortRev;
      rev = herculesCI.config.repo.rev;

      # Branch dispatch: exact string equality. null == "main" is false
      # in Nix, so tag pushes naturally fall through to the dry-run path.
      isMain = branch == "main";

      # Action banner emitted once per run (RP-05 log-grep anchor).
      actionBanner = if isMain then "release" else "dry-run";

      # Eval-time --dry-run flag injection. Empty on main, "--dry-run"
      # otherwise. Ordered AFTER the package-path positional arg per
      # release.sh's CLI grammar (`release <package-path> [--dry-run]`).
      dryRunFlag = if isMain then "" else "--dry-run";
    in
    {
      onPush.default.outputs.effects.release-packages = withSystem "x86_64-linux" (
        { config, pkgs, ... }:
        let
          hci-effects = inputs.hercules-ci-effects.lib.withPkgs pkgs;

          # Option Gamma: resolved at nix eval time to /nix/store paths
          # that the bwrap sandbox can execute without a working-tree or
          # nix-daemon lookup.
          listPackagesProgram = config.apps.list-packages-json.program;
          releaseProgram = config.apps.release.program;
        in
        hci-effects.mkEffect {
          name = "release-packages";

          # Runtime PATH inputs for the effectScript body (m5-01d-release-packages-runtimeinputs-fix).
          # mkEffect's defaultInputs (cacert + curl + jq + effectSetupHook) plus stdenvNoCC's
          # bundled coreutils/bash/gnused/gnugrep/gawk/gnutar cover every directly-invoked binary
          # in the effectScript EXCEPT `git`, which the ADR-003 Option α clone preamble calls
          # via `git clone`, `git fetch`, `git checkout -B`, and `git rev-parse`. The flake apps
          # invoked downstream (`${listPackagesProgram}`, `${releaseProgram}`) carry their own
          # writeShellApplication-baked runtimeInputs PATH so internal tool resolution is
          # self-contained. Adding `pkgs.git` here closes the m5-01c Phase 1 dry-run regression
          # where the bwrap sandbox emitted RELEASE-CLONE-START correctly and then failed with
          # `git: command not found` from stdenv-linux/setup line 1842 (`git clone "$clone_url" …`).
          # `cacert` is already in defaultInputs, so HTTPS clone CA-trust resolution is unaffected.
          inputs = [ pkgs.git ];

          effectScript = ''
            set -euo pipefail

            echo "=== effects.release-packages (semantic-release per-package dispatcher) ==="
            echo "branch:   ${lib.escapeShellArg (toString branch)}"
            echo "rev:      ${lib.escapeShellArg (toString rev)}"
            echo "shortRev: ${lib.escapeShellArg (toString shortRev)}"
            echo "isMain:   ${if isMain then "true" else "false"}"

            # Structured banner (RP log-grep anchor): emitted once per run
            # so log-grep can distinguish dry-run vs release dispatch path.
            echo "RELEASE-PACKAGES-ACTION: ${actionBanner}"

            # Secrets preamble — Pattern C'-refined (ADR-002):
            # extract GITHUB_TOKEN ONLY from $HERCULES_CI_SECRETS_JSON
            # at the .data.value envelope. The other bundle keys are
            # intentionally NOT extracted here — exclusivity rules and
            # the npm-publish-never invariant are documented in the
            # outer-module doc-comments (kept out of the rendered
            # effectScript to satisfy VAL-EFFECT-RELEASEPACKAGES-22 /
            # -24's `rg -c` zero-match contract on effectScript output).
            export GITHUB_TOKEN="$(jq -r '.GITHUB_TOKEN.data.value' "$HERCULES_CI_SECRETS_JSON")"

            # Env-var-contract guard: fail fast if the secrets bundle is
            # missing GITHUB_TOKEN. Message excludes the value; only key
            # name is echoed.
            if [ -z "''${GITHUB_TOKEN:-}" ] || [ "$GITHUB_TOKEN" = "null" ]; then
              echo "error: GITHUB_TOKEN missing from \$HERCULES_CI_SECRETS_JSON" >&2
              exit 1
            fi

            # === ADR-003 Option α clone preamble ===========================
            # Phases 1–6 per ADR-003 §Architecture and the file-header
            # doc-comment. All token-leak / freshness / authority invariants
            # (#1, #2, #3, #5, #9, #11, #12) are codified here.

            # Canonicalized clone URL (ADR-003 §Architecture step 1,
            # invariant #1). Hard-coded GitHub URL — NEVER derived from
            # `herculesCI.config.repo.remoteHttpUrl`, which buildbot-nix
            # populates with `https://git:<App-installation-token>@github.com/...`
            # for GitHub-App-backed repos. Reusing that URL would bake the
            # buildbot-nix App's `Contents: Read-only` token into local git
            # config — exactly the wrong authority for a release mutation
            # and a clear-text token-leak risk in any subsequent banner echo.
            clone_url="https://github.com/cameronraysmith/vanixiets.git"

            # mkEffect's $TMPDIR is /tmp (tmpfs); mktemp here keeps the
            # clone inside the bwrap-managed tmpfs which is reaped on
            # sandbox exit regardless of the trap below.
            clone_dir="$(mktemp -d -t release-packages-clone.XXXXXX)"

            # Single-step EXIT trap (invariant #12). Defensive hygiene only;
            # the bwrap tmpfs is ephemeral. Do NOT add multi-step traps.
            trap 'rm -rf "$clone_dir"' EXIT

            # Pre-compute git refs as nix-eval-time literals. Bash captures
            # them as local vars so the freshness-check / checkout / banner
            # phases share one canonicalized value without re-shelling-out.
            GIT_REV=${lib.escapeShellArg (toString rev)}
            GIT_BRANCH=${lib.escapeShellArg (if branch == null then "" else toString branch)}

            # RELEASE-CLONE-START banner (invariants #9, #10): emitted
            # BEFORE the clone with the sanitized public URL. Token never
            # appears in this output even though GIT_CREDENTIALS is set
            # later in this effect — the URL string is the canonical one.
            echo "RELEASE-CLONE-START: $clone_url $GIT_REV $GIT_BRANCH"

            # Full clone (ADR-003 §Architecture step 2, invariant #2):
            # NO shallow flag, NO since-date flag, NO blob-filter flag.
            # semantic-release requires `git tag --merged <branch>`
            # (lib/git.js:24-31), the full unshallowed tag fetch
            # (lib/git.js:106-132), notes refs (lib/git.js:144-154), and
            # the full commit log since lastRelease.gitHead
            # (lib/get-commits.js:7-25); semantic-release-monorepo
            # additionally needs per-commit changed-file lookups
            # (src/git-utils.js:16-24). Pack size (~21.5 MiB) does not
            # warrant shallow optimization at this scale.
            git clone "$clone_url" "$clone_dir"
            git -C "$clone_dir" fetch --tags origin

            # Exact-rev checkout (ADR-003 §Architecture step 3, invariant
            # #3). When GIT_BRANCH is empty (tag-push events: hercules-ci-
            # effects models tag checkouts as `branch = null`), use a
            # synthetic local branch name. The dry-run gate (isMain ==
            # false) ensures no production push attempts in that case;
            # see ADR-003 §"Tag-push event handling".
            if [ -n "$GIT_BRANCH" ]; then
              checkout_branch="$GIT_BRANCH"
            else
              checkout_branch="release-packages-detached"
            fi
            git -C "$clone_dir" checkout -B "$checkout_branch" "$GIT_REV"
            echo "RELEASE-CLONE-CHECKOUT: $GIT_REV"

            # Freshness check (ADR-003 §Architecture step 4, invariant
            # #11). Single check after checkout, before the package loop.
            # Per-package re-checks are NOT added (see ADR-003 §11). On
            # tag-push events (GIT_BRANCH empty) there is no branch tip
            # to compare against, so the check is structurally
            # inapplicable; the ADR-003 §"Tag-push event handling" gate
            # forces dry-run for those runs anyway.
            if [ -n "$GIT_BRANCH" ]; then
              git -C "$clone_dir" fetch origin "$GIT_BRANCH"
              head_rev="$(git -C "$clone_dir" rev-parse HEAD)"
              remote_rev="$(git -C "$clone_dir" rev-parse "origin/$GIT_BRANCH")"
              if [ "$head_rev" != "$remote_rev" ]; then
                echo "RELEASE-CLONE-STALE: expected $head_rev remote $remote_rev" >&2
                exit 1
              fi
            fi

            echo "RELEASE-CLONE-READY: $clone_dir"

            # Token authentication (ADR-003 §Architecture step 6,
            # invariants #4, #5). semantic-release's get-git-auth-url.js
            # treats GIT_CREDENTIALS as a pre-baked `user:password` pair
            # and constructs the authenticated URL in-process — NO host
            # credential helper installation, NO write to ~/.git-
            # credentials. The PAT held in `vanixiets-effects-secrets`
            # (Contents: Read+Write) is the canonical authority; the
            # buildbot-nix GitHub App installation token (Contents:
            # Read-only) is intentionally NOT reused for release
            # mutation. The shell variable is only consumed by
            # semantic-release's URL builder; it is never echoed.
            export GIT_CREDENTIALS="x-access-token:''${GITHUB_TOKEN}"

            # === existing m4-release-packages env-var contract =============
            # (extended for m5-01a: RELEASE_REPO_ROOT now points at the
            # in-sandbox clone, not the empty mkEffect $PWD that previously
            # caused `fatal: not a git repository`).
            #
            # CI is set so env-ci recognises the run as non-interactive CI,
            # bypassing semantic-release's `running on a CI environment is
            # required` abort. GIT_BRANCH is the eval-time literal value
            # already captured above (re-exported for child processes).
            # GIT_AUTHOR_*/GIT_COMMITTER_* are hard-coded identities for the
            # semantic-release CHANGELOG-prepare phase; git honours these
            # env vars natively without writing to .git/config (which the
            # bwrap /nix/store ro-bind would block anyway).
            export CI=true
            export GIT_BRANCH
            export RELEASE_REPO_ROOT="$clone_dir"
            export GIT_AUTHOR_NAME=semantic-release
            export GIT_AUTHOR_EMAIL=semantic-release@vanixiets.local
            export GIT_COMMITTER_NAME=semantic-release
            export GIT_COMMITTER_EMAIL=semantic-release@vanixiets.local

            # Option Gamma store-path dispatch — both flake apps' /nix/store
            # paths are embedded at eval time via the perSystem
            # config.apps.<name>.program attributes. No flake-app shell-out
            # (bwrap would not resolve .#).
            LIST_PACKAGES=${listPackagesProgram}
            RELEASE=${releaseProgram}

            # cd into the clone before invoking list-packages-json: that
            # script calls `git rev-parse --show-toplevel`, which must
            # resolve to $clone_dir (the only real git tree in this
            # sandbox). release.sh's own RELEASE_REPO_ROOT consumer also
            # picks up the same clone via the env export above.
            cd "$clone_dir"

            # Discover packages under packages/* (jq-driven enumeration of
            # the list-packages-json output).
            packages_json="$("$LIST_PACKAGES")"
            echo "packages discovered: $packages_json"

            # Per-package failure tracker — populated inside the loop;
            # used at end-of-loop to set the aggregate exit code.
            failed_packages=()

            # Per-package atomicity loop: iterate every {name, path}
            # entry. Read paths into the loop via process substitution
            # over `jq -r '.[].path'` (one path per line, robust to
            # paths-with-spaces unlike `for pkg in $(...)`).
            while IFS= read -r pkg_path; do
              [ -z "$pkg_path" ] && continue

              echo "RELEASE-PACKAGE-ITERATION: $pkg_path"

              # Disable -e for the per-package invocation so a single
              # package's failure does not abort the loop. We capture
              # the exit code, log appropriately, and continue.
              set +e
              "$RELEASE" "$pkg_path" ${dryRunFlag}
              rc=$?
              set -e

              if [ "$rc" -eq 0 ]; then
                echo "RELEASE-PACKAGE-OK: $pkg_path"
              else
                echo "RELEASE-PACKAGE-FAILURE: $pkg_path (exit $rc)"
                failed_packages+=("$pkg_path")
              fi
            done < <(printf '%s\n' "$packages_json" | jq -r '.[].path')

            # Aggregate exit code: OR of all per-package results. Zero
            # iff every package's invocation exited zero (or zero
            # packages were discovered, which is itself a degenerate
            # success). Non-zero iff any package failed; the failed
            # set is enumerated in stderr for operator triage.
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
