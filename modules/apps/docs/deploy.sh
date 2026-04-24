#!/usr/bin/env bash
# shellcheck shell=bash
# Docs deployment dispatcher invoked via `nix run .#deploy-docs`.
#
# Env-var contract (per ADR-002 / env-var-contract-design.md §2.1, extended
# by the m4-deploy-docs-git-env-contract feature to ALL host-PATH binary
# dependencies). 12 caller-overridable variables: 4 secret tokens (the
# closed effects bundle), 6 GIT_*, 2 DEPLOY_*. Symmetric env-first /
# shelled-fallback shape across all four caller contexts (effect preamble,
# sops exec-env, direnv, GHA env, local shell).
#
#   Required (secret, provided by caller from the closed 4-key effects
#   bundle — see modules/effects/vanixiets/secrets.nix):
#     CLOUDFLARE_API_TOKEN     wrangler auth token (CONSUMED by this
#                              script; required at runtime).
#     CLOUDFLARE_ACCOUNT_ID    Cloudflare account id (CONSUMED; wrangler
#                              requires this for account-scoped ops such
#                              as `versions upload` on a Worker attached
#                              to an account-level resource).
#     GITHUB_TOKEN             not consumed by deploy.sh; documented as
#                              part of the canonical effects bundle for
#                              homogeneity (consumed by release.sh).
#     SOPS_AGE_KEY             not consumed by deploy.sh; documented as
#                              part of the canonical effects bundle for
#                              homogeneity (consumed by
#                              k3d-bootstrap-secrets.sh). Per ADR-002,
#                              this script does NOT shell out to sops.
#   Required (config, injected by deploy.nix):
#     DOCS_PAYLOAD             store path of the vanixiets-docs derivation
#                              ($out/{dist/, .wrangler/, wrangler.jsonc})
#     DOCS_NODE_MODULES        store path of vanixiets-docs-deps node_modules
#                              tree (runtimeEnv of deploy.nix)
#
#   Optional (git metadata; env-first with git-fallback). Extended in the
#   m4-deploy-docs-git-env-contract feature to let the script run inside
#   the buildbot-effects bwrap sandbox which does NOT bind-mount the
#   working tree (upstream-by-design). Every GIT_* consumer below is
#   expressed as `${GIT_X:-$(git … 2>/dev/null || true)}` so the three
#   supported caller contexts all work: effect preamble (env pre-populated,
#   no .git reachable), local shell from a git worktree (env unset, git
#   fallback), and GHA after checkout (env unset, git fallback).
#     GIT_REV                  40-char commit SHA (fallback: git rev-parse HEAD)
#     GIT_REV_SHORT            7-ish-char short SHA (fallback: git rev-parse --short HEAD)
#     GIT_REV_SHORT12          12-char short SHA used for wrangler --tag /
#                              workers/tag cross-check (fallback:
#                              git rev-parse --short=12 HEAD). VAL-WRITESHELL-DOCS-010
#                              commit_tag invariant sources from here.
#     GIT_BRANCH               current branch name (fallback: git branch --show-current)
#     GIT_COMMIT_MSG           HEAD subject line used in the version-message
#                              annotation (fallback: git log -1 --pretty=format:'%s')
#     GIT_WORKTREE_STATUS      literal "clean" or "dirty" (fallback:
#                              git diff-index --quiet HEAD -- && echo clean || echo dirty)
#
#   Optional (deploy-context metadata; env-first with bash-builtin /
#   shelled-fallback). Generalisation of the same pattern to ALL host-PATH
#   binary dependencies, fixing the second-bug-class regression where the
#   bwrap sandbox lacks `hostname`/`whoami` on PATH (only /nix/store
#   ro-bind + writeShellApplication runtimeInputs are available). The
#   bash builtin `$HOSTNAME` is populated from gethostname(2) at shell
#   startup — no external binary required in any context.
#     DEPLOY_HOST              short hostname for the production deploy
#                              message. Fallback: ${HOSTNAME%%.*}
#                              (bash builtin parameter expansion; trims
#                              the first dot-suffix to mimic `hostname -s`
#                              without shelling out).
#     DEPLOY_DEPLOYER          actor identity for deploy/version messages.
#                              Fallback chain: GITHUB_ACTOR (GHA context)
#                              → `whoami 2>/dev/null` (local shell with
#                              /etc/passwd available) → "unknown".
#
#   Optional (caller debugging / overrides):
#     WRANGLER                 override binary path for test harnesses; default
#                              $DOCS_NODE_MODULES/.bin/wrangler
#     DEPLOY_DOCS_DEBUG        preserve tmpdir on exit when set
#     GITHUB_ACTIONS / GITHUB_ACTOR / GITHUB_WORKFLOW
#                              when GITHUB_ACTIONS is set, the production
#                              deploy message uses GITHUB_WORKFLOW (default
#                              "CI") as the deploy context instead of
#                              DEPLOY_HOST. GITHUB_ACTOR participates in
#                              the DEPLOY_DEPLOYER fallback chain.
#
# Caller mechanisms (satisfy each contract slot via one of):
#   - Local dev:    caller-side sops wrapper (justfile `docs-deploy-*`
#                   recipes wrap with `sops` to decrypt secrets/shared.yaml
#                   and export the Cloudflare env before the nested nix run)
#                   OR direnv dotenv (.envrc loads .env with the Cloudflare
#                   env vars already exported). DEPLOY_HOST / DEPLOY_DEPLOYER
#                   left unset → bash-builtin / whoami fallback.
#   - GHA env:      deploy-docs.yaml step wraps the nix run with the same
#                   caller-side sops decrypt inside a nix-develop wrapper;
#                   the age key is provided via the step `env:` block from
#                   the repo secrets (see deploy-docs.yaml). GIT_* / DEPLOY_*
#                   left unset → git/bash-builtin/GITHUB_ACTOR fallback.
#   - M4 effect:    the deploy-docs dispatcher effect preamble extracts
#                   CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID from
#                   $HERCULES_CI_SECRETS_JSON, exports the six GIT_*
#                   variables interpolated from herculesCI.config.repo.*
#                   (via lib.escapeShellArg + builtins.substring at eval
#                   time), AND exports DEPLOY_DEPLOYER=hercules-ci-effects
#                   and DEPLOY_HOST=magnetite before invoking the embedded
#                   store path ${config.apps.deploy-docs.program}. The
#                   bwrap sandbox does not bind-mount the working tree
#                   and provides no host-PATH binaries beyond /nix/store
#                   ro-bind + runtimeInputs PATH, so every git/hostname/
#                   whoami consumer in this script is env-first with
#                   bash-builtin or error-tolerant shelled fallback.
#
# Secret passing rule (per ADR-002): wrangler authentication flows ONLY
# through inherited env vars; no authentication CLI flags are used.
# No caller-side sops wrappers inside this script (the caller wraps if
# their mechanism is sops-based).
#
# Usage:
#   deploy-docs preview <branch>
#   deploy-docs production
#   deploy-docs --help
set -euo pipefail

usage() {
  cat <<'EOF'
usage: deploy-docs preview <branch>
       deploy-docs production
       deploy-docs --help

Deploy the nix-built vanixiets-docs payload to Cloudflare Workers.

Subcommands:
  preview <branch>   Upload a Cloudflare Workers preview version tagged with
                     the current HEAD short SHA, aliased at b-<sanitized-branch>.
                     <branch> defaults to `git branch --show-current`; explicit
                     value required when HEAD is detached.
  production         Promote the existing preview version matching the current
                     HEAD short SHA to 100% production traffic, or fall back
                     to a direct deploy of the nix-built payload when no
                     matching preview exists.

Flags:
  --help, -h         Print this usage and exit 0.

Environment contract (see top-of-file header for full details):
  Required (secret, caller-provided from the closed 4-key effects bundle):
    CLOUDFLARE_API_TOKEN   wrangler auth token (CONSUMED)
    CLOUDFLARE_ACCOUNT_ID  Cloudflare account id (CONSUMED; account-scoped ops)
    GITHUB_TOKEN           bundle homogeneity (not consumed by deploy.sh)
    SOPS_AGE_KEY           bundle homogeneity (not consumed by deploy.sh)
  Required (config, injected by deploy.nix):
    DOCS_PAYLOAD           path to the vanixiets-docs derivation output
    DOCS_NODE_MODULES      path to vanixiets-docs-deps node_modules tree
  Optional (env-first with shelled-fallback):
    GIT_REV, GIT_REV_SHORT, GIT_REV_SHORT12, GIT_BRANCH,
    GIT_COMMIT_MSG, GIT_WORKTREE_STATUS
                     git metadata; supplied by effect preamble when no
                     .git is reachable; otherwise resolved via `git ...`.
    DEPLOY_HOST      short hostname; fallback `${HOSTNAME%%.*}` (bash
                     builtin, no external binary).
    DEPLOY_DEPLOYER  actor identity; fallback chain GITHUB_ACTOR →
                     `whoami 2>/dev/null` → "unknown".
  Optional (caller debugging / overrides):
    WRANGLER, DEPLOY_DOCS_DEBUG
    GITHUB_ACTIONS / GITHUB_ACTOR / GITHUB_WORKFLOW
                     When GITHUB_ACTIONS is set, the production deploy
                     message uses the GitHub Actions context (workflow
                     name) instead of DEPLOY_HOST.

Examples:
  nix run .#deploy-docs -- preview my-feature-branch
  nix run .#deploy-docs -- production
EOF
}

mode="${1:-}"
case "$mode" in
  -h | --help)
    usage
    exit 0
    ;;
esac

if [[ -z "$mode" ]]; then
  echo "error: missing subcommand" >&2
  echo "usage: deploy-docs preview <branch> | deploy-docs production" >&2
  echo "(run with --help for full usage and env-var contract)" >&2
  exit 2
fi
shift

# Env-var contract guards (per ADR-002 / env-var-contract-design.md §2.1.2).
# Fail fast before any wrangler / filesystem work if the contract is unmet.
: "${DOCS_PAYLOAD:?DOCS_PAYLOAD not set; deploy.nix must pass the nix-built payload}"
[[ -d "$DOCS_PAYLOAD" ]] || { echo "error: DOCS_PAYLOAD=$DOCS_PAYLOAD is not a directory" >&2; exit 1; }
: "${DOCS_NODE_MODULES:?DOCS_NODE_MODULES not set; deploy.nix must expose vanixiets-docs-deps via runtimeEnv}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required (see deploy.sh header for caller mechanisms: effect preamble, direnv, caller-side sops wrapper, or GHA env)}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is required (see deploy.sh header for caller mechanisms: effect preamble, direnv, caller-side sops wrapper, or GHA env)}"

# Hermetic wrangler via bun-managed node_modules (vanixiets-docs-deps derivation).
# The `${WRANGLER:-...}` fallback allows test harnesses (e.g. the no-op wrangler stub
# used to exercise the post-condition error paths for VAL-WRITESHELL-DOCS-010) to
# override the hermetic binary without rewriting this script.
export WRANGLER="${WRANGLER:-$DOCS_NODE_MODULES/.bin/wrangler}"

# Invoke wrangler via real node, not the .bin/wrangler shebang:
# bun's .bin wrappers point at bun-with-fake-node/bin/node (bun in node-
# compat mode), but bun's fetch() on linux-x64 silently hangs on keep-
# alive connection reuse to api.cloudflare.com — wrangler `versions
# upload` / `versions deploy` exit 0 with no Worker Version ID produced
# and no error. Prefixing `node` forces real-node (undici) runtime.
# Matches pkgs/by-name/vanixiets-docs/package.nix:141 (astro) and :248
# (playwright) precedent for tools with known bun incompatibilities.
# Empirical: diagnosed 2026-04-22 via magnetite linux-x64 reproducer;
# same machine + wrangler runs fine under real node, hangs under bun.

# Git metadata is resolved below via env-first / git-fallback (see top-of-
# file env-var contract for GIT_*). Wrangler is invoked with absolute
# `--config "$WRANGLER_CONFIG"`, so CWD is immaterial — no `cd` into the
# worktree is required (and would fail inside the buildbot-effects bwrap
# sandbox, which does not bind-mount the working tree).

# Materialise a writable copy of the nix payload. wrangler reads
# .wrangler/deploy/config.json whose configPath ("../../dist/server/wrangler.json")
# resolves against the config file's location, and wrangler may write state to
# .wrangler/ during deploy — both require a writable tree outside /nix/store.
tmpdir=$(mktemp -d -t deploy-docs.XXXXXX)
if [[ -n "${DEPLOY_DOCS_DEBUG:-}" ]]; then
  echo "[deploy-docs] DEBUG: preserving tmpdir at $tmpdir" >&2
  trap 'echo "[deploy-docs] DEBUG: tmpdir preserved at '\''$tmpdir'\''" >&2' EXIT
else
  trap 'rm -rf "$tmpdir"' EXIT
fi
cp -R "$DOCS_PAYLOAD"/. "$tmpdir/"
chmod -R u+w "$tmpdir"

# Astro generates dist/server/wrangler.json with real resolved relative paths
# (main: "entry.mjs", assets.directory: "../client") during build.
# .wrangler/deploy/config.json in the payload explicitly references this as the
# deploy-time config. Use it directly — no jq rewrite needed, and no dependency
# on node_modules to resolve the @astrojs/cloudflare/entrypoints/server specifier
# present in the source wrangler.jsonc.
wrangler_config="$tmpdir/dist/server/wrangler.json"

# Commit metadata shared by preview and production subcommands. Env-first /
# git-fallback per the GIT_* env-var contract (see top-of-file header).
# All `git` invocations are guarded by `2>/dev/null || true` so that a
# missing .git (e.g. buildbot-effects bwrap sandbox, no bind-mounted worktree)
# surfaces as empty strings rather than a non-zero exit; the env-first path
# supplies the authoritative values in that context.
commit_sha="${GIT_REV:-$(git rev-parse HEAD 2>/dev/null || true)}"
commit_tag="${GIT_REV_SHORT12:-$(git rev-parse --short=12 HEAD 2>/dev/null || true)}"
commit_short="${GIT_REV_SHORT:-$(git rev-parse --short HEAD 2>/dev/null || true)}"
current_branch="${GIT_BRANCH:-$(git branch --show-current 2>/dev/null || true)}"

# Resolve deployer / deploy_host with env-first / bash-builtin / shelled-fallback
# per the DEPLOY_* env-var contract (see top-of-file header). The bwrap
# sandbox provides no host-PATH binaries beyond /nix/store ro-bind +
# runtimeInputs PATH, so unconditional `hostname -s` / `whoami` would fail
# with `command not found` (exit 127). Bash builtin `$HOSTNAME` is populated
# from gethostname(2) at shell startup and requires no external binary in
# any context; `${HOSTNAME%%.*}` mimics `hostname -s` via parameter
# expansion. `whoami` is retained as a final fallback for local shells where
# DEPLOY_DEPLOYER and GITHUB_ACTOR are both unset; it is error-tolerant
# (`2>/dev/null || echo unknown`) so a missing /etc/passwd entry surfaces
# as "unknown" rather than a non-zero exit.
deploy_host="${DEPLOY_HOST:-${HOSTNAME%%.*}}"
deployer="${DEPLOY_DEPLOYER:-${GITHUB_ACTOR:-$(whoami 2>/dev/null || echo unknown)}}"

# Compose deploy message (prefer GitHub Actions context, fall back to local).
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  deploy_context="${GITHUB_WORKFLOW:-CI}"
  deploy_msg="Deployed by ${deployer} from ${current_branch} via ${deploy_context}"
else
  deploy_msg="Deployed by ${deployer} from ${current_branch} on ${deploy_host}"
fi

case "$mode" in
  preview)
    branch="${1:-${current_branch:-}}"
    if [[ -z "$branch" ]]; then
      echo "error: preview requires a <branch> argument" >&2
      echo "usage: deploy-docs preview <branch>" >&2
      exit 2
    fi

    # Sanitize branch name for Cloudflare alias (valid subdomain component):
    #   replace / with -, collapse runs, strip leading/trailing -, cap at 40 chars.
    safe_branch=$(echo "$branch" \
      | tr '/' '-' \
      | tr -c 'a-zA-Z0-9-' '-' \
      | sed 's/--*/-/g; s/^-//; s/-$//' \
      | cut -c1-40)

    # Env-first / git-fallback — see top-of-file GIT_* env-var contract.
    # `git log` / `git diff-index` are error-tolerant so a missing .git
    # (buildbot-effects bwrap) leaves commit_msg empty; the effect preamble
    # supplies GIT_COMMIT_MSG and GIT_WORKTREE_STATUS=clean in that case.
    commit_msg="${GIT_COMMIT_MSG:-$(git log -1 --pretty=format:'%s' 2>/dev/null || true)}"
    if [[ -n "${GIT_WORKTREE_STATUS:-}" ]]; then
      git_status="$GIT_WORKTREE_STATUS"
    elif git diff-index --quiet HEAD -- 2>/dev/null; then
      git_status="clean"
    else
      # Non-zero from `git diff-index` covers both "dirty worktree" and
      # "not a git repository" — collapse both to "dirty" so downstream
      # version_message is always well-formed.
      git_status="dirty"
    fi
    version_message="[${branch}] ${commit_msg} (${commit_tag}, ${git_status})"

    echo "Deploying preview for branch: ${branch}"
    echo "Sanitized alias: b-${safe_branch}"
    echo "Commit: ${commit_short} (${git_status})"
    echo "Full SHA: ${commit_sha}"
    echo "Tag: ${commit_tag}"
    echo "Message: ${commit_msg}"
    echo ""

    export VERSION_TAG="$commit_tag"
    export VERSION_MESSAGE="$version_message"
    export SAFE_BRANCH="$safe_branch"
    export WRANGLER_CONFIG="$wrangler_config"

    # Capture wrangler's machine-readable NDJSON event log via
    # WRANGLER_OUTPUT_FILE_PATH (supported by wrangler >= 3.x; confirmed on
    # 4.84.1 by grepping `WRANGLER_OUTPUT_FILE_PATH` + `type: "version-upload"`
    # in packages/docs/node_modules/wrangler/wrangler-dist/cli.js). The
    # previous revision of this script used `--json` on `wrangler versions
    # upload`, but wrangler 4.84.x does NOT accept `--json` on that subcommand
    # (GHA re-run against cd-via-effects @ 6ce9fca2 exited 1 with "Unknown
    # argument: json"); `--json` is only supported on the `versions list` and
    # `deployments list` subcommands. The NDJSON stream is emitted to the file
    # named by WRANGLER_OUTPUT_FILE_PATH; each line is a JSON object with a
    # `type` discriminator. For `versions upload` we look for the
    # `version-upload` event, which carries `version_id`, `worker_tag`,
    # `preview_url`, and `preview_alias_url`.
    #
    # Three post-conditions enforce the no-silent-success invariant
    # (VAL-WRITESHELL-DOCS-010):
    #   (a) the NDJSON event log contains a `type == "version-upload"` entry
    #       with a non-empty `version_id` (primary authoritative source)
    #   (b) `wrangler versions list --json` contains an entry whose
    #       annotations["workers/tag"] matches $commit_tag (server-side
    #       persistence cross-check)
    #   (c) only then is the user-visible success block echoed, including the
    #       authoritative Worker Version ID parsed from (a).
    wrangler_upload_ndjson="$tmpdir/wrangler-versions-upload.ndjson"
    wrangler_upload_stdout="$tmpdir/wrangler-versions-upload.stdout"
    wrangler_upload_stderr="$tmpdir/wrangler-versions-upload.stderr"
    : > "$wrangler_upload_ndjson"
    : > "$wrangler_upload_stdout"
    : > "$wrangler_upload_stderr"
    export WRANGLER_OUTPUT_FILE_PATH="$wrangler_upload_ndjson"
    # Note: WRANGLER_LOG=debug was observed to deterministically terminate
    # wrangler 4.84.1 mid-fetch (process exits 0 after POST
    # /assets-upload-session request, before response; on GHA similar early
    # termination at GET /workers/services/<name>). Upload then never
    # completes. Do NOT re-enable without gating it to a retry-only code
    # path. Wrangler's internal log file at ~/.wrangler/logs/wrangler-*.log
    # is written at default level regardless and is captured on failure.

    # Tee stdout so we both display wrangler output live AND parse it as a
    # fallback version_id source when the NDJSON event stream from
    # WRANGLER_OUTPUT_FILE_PATH doesn't produce the expected
    # `type:"version-upload"` event. Retained as defense-in-depth against
    # future wrangler silent-success regressions. See top-of-file rationale
    # (lines ~101-110) for the diagnostic history.
    #
    # Diagnostic: echo the exact upload command line to stderr so the GHA log
    # shows what the shell is about to invoke (CLOUDFLARE_API_TOKEN and
    # CLOUDFLARE_ACCOUNT_ID are expected in the inherited env per the
    # env-var contract; never printed on argv).
    printf '>> wrangler upload command: node %s --config %s versions upload --preview-alias %s --tag %s --message %q\n' \
      "$WRANGLER" "$WRANGLER_CONFIG" "b-${SAFE_BRANCH}" "$VERSION_TAG" "$VERSION_MESSAGE" >&2

    set +e
    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions upload \
        --preview-alias "b-${SAFE_BRANCH}" \
        --tag "$VERSION_TAG" \
        --message "$VERSION_MESSAGE" \
      > >(tee "$wrangler_upload_stdout") \
      2> >(tee "$wrangler_upload_stderr" >&2)
    wrangler_upload_rc=$?
    set -e

    unset WRANGLER_OUTPUT_FILE_PATH

    # Post-condition (a): extract a non-empty Worker Version ID.
    #   Primary source:   NDJSON `version-upload` event (Option A)
    #   Fallback source:  stdout line `Worker Version ID: <uuid>` (Option B)
    # The cross-check in post-condition (b) below guarantees the version
    # actually persisted server-side regardless of which source produced it.
    version_id=""
    if [[ -s "$wrangler_upload_ndjson" ]]; then
      version_id=$(
        jq -rs '
          map(select(type == "object" and (.type // "") == "version-upload"))
          | .[0].version_id // empty
        ' "$wrangler_upload_ndjson" 2>/dev/null || true
      )
    fi
    if [[ -z "$version_id" ]]; then
      version_id=$(
        grep -oE 'Worker Version ID: [a-f0-9-]+' "$wrangler_upload_stdout" 2>/dev/null \
          | awk '{print $NF}' \
          | head -1 || true
      )
    fi
    if [[ -z "$version_id" ]]; then
      # Relax errexit for the entire diagnostic dump block. grep/sed/cat/head
      # failures here (missing stdout match, empty NDJSON, nonexistent log
      # file) must not abort before every dump section fires — the script's
      # fail contract is satisfied by the explicit `exit 1` at the end of
      # this block, not by intermediate pipeline exit codes.
      set +e
      echo "" >&2
      echo "error: wrangler exited 0 but produced no Worker Version ID" >&2
      echo "  post-condition (a) failed: neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
      echo "                              event log nor wrangler stdout contained" >&2
      echo "                              a recognizable Worker Version ID" >&2
      echo "  wrangler exit code:    $wrangler_upload_rc" >&2
      echo "  raw wrangler event log: $wrangler_upload_ndjson" >&2
      echo "  raw wrangler stdout:   $wrangler_upload_stdout" >&2
      echo "  raw wrangler stderr:   $wrangler_upload_stderr" >&2
      echo "  hints:" >&2
      echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
      echo "      the caller (see deploy.sh env-var contract header for caller mechanisms)" >&2
      echo "    - if linux-x64 regression, confirm wrangler invoked under real node and" >&2
      echo "      not bun-fake-node (see top-of-file rationale at lines ~101-110)" >&2
      echo "    - inspect the wrangler internal log dumped below / raw NDJSON and stdout paths above for any output" >&2
      echo "" >&2
      # Locate wrangler's internal log file by glob + newest mtime across
      # platform-specific candidate locations. Avoids depending on wrangler's
      # stdout `Writing logs to "..."` announcement (only printed under
      # WRANGLER_LOG=debug, which we no longer set). The log file contains
      # full HTTP request/response bodies and any internal stack traces that
      # are otherwise destroyed with the GHA runner — dump it first as the
      # most informative diagnostic source when NDJSON/stdout/stderr are
      # empty or truncated.
      wrangler_log_path=""
      for candidate_dir in "$HOME/.wrangler/logs" "$HOME/.config/.wrangler/logs"; do
        if [[ -d "$candidate_dir" ]]; then
          # Filename format is `wrangler-YYYY-MM-DD_HH-MM-SS_mmm.log` — the
          # embedded timestamp is zero-padded and lexicographically sortable,
          # so `sort | tail -1` selects the newest without needing ls -t.
          newest=$(find "$candidate_dir" -maxdepth 1 -type f -name 'wrangler-*.log' 2>/dev/null | sort | tail -1 || true)
          if [[ -n "$newest" ]]; then
            wrangler_log_path="$newest"
            break
          fi
        fi
      done
      if [[ -n "$wrangler_log_path" && -f "$wrangler_log_path" ]]; then
        echo "--- begin wrangler internal log ($wrangler_log_path) ---" >&2
        cat "$wrangler_log_path" >&2 || true
        echo "--- end wrangler internal log ---" >&2
      else
        echo "wrangler internal log: no file found under \$HOME/.wrangler/logs or \$HOME/.config/.wrangler/logs" >&2
      fi
      echo "--- begin raw wrangler NDJSON ($wrangler_upload_ndjson) ---" >&2
      cat "$wrangler_upload_ndjson" >&2 || true
      echo "--- end raw wrangler NDJSON ---" >&2
      echo "--- begin raw wrangler stdout ($wrangler_upload_stdout) ---" >&2
      cat "$wrangler_upload_stdout" >&2 || true
      echo "--- end raw wrangler stdout ---" >&2
      echo "--- begin raw wrangler stderr ($wrangler_upload_stderr) ---" >&2
      cat "$wrangler_upload_stderr" >&2 || true
      echo "--- end raw wrangler stderr ---" >&2
      set -e
      exit 1
    fi

    # Post-condition (b): cross-check via versions list that the upload landed
    # server-side with the expected commit tag annotation. The `| cat` pipe
    # ensures wrangler's stdout is delivered through a pipe-shaped fd before
    # being redirected to disk (observed empirically: `wrangler ... --json >
    # file` intermittently produces zero bytes whereas `wrangler ... --json |
    # cat > file` reliably produces the full JSON output, which suggests
    # wrangler inspects stdout before emitting when the fd points directly at
    # a file).
    wrangler_list_json="$tmpdir/wrangler-versions-list.json"

    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json \
      | cat > "$wrangler_list_json"

    matched_count=$(jq --arg tag "$commit_tag" \
      '[.[] | select(.annotations["workers/tag"] == $tag)] | length' \
      "$wrangler_list_json" 2>/dev/null || echo 0)
    if [[ "$matched_count" -lt 1 ]]; then
      echo "" >&2
      echo "error: uploaded version with tag ${commit_tag} not found in versions list" >&2
      echo "  post-condition (b) failed: wrangler versions list returned no entries" >&2
      echo "                              with annotations[\"workers/tag\"] == ${commit_tag}" >&2
      echo "  raw versions list output: $wrangler_list_json" >&2
      echo "  hint: wrangler reported a version_id locally but the Cloudflare API did" >&2
      echo "        not persist it; inspect the raw versions list for surrounding entries" >&2
      exit 1
    fi

    # Post-condition (c): authoritative success echo with parsed Worker Version ID.
    echo ""
    echo "Version uploaded successfully"
    echo "  Worker Version ID: ${version_id}"
    echo "  Tag: ${commit_tag}"
    echo "  Full SHA: ${commit_sha}"
    echo "  Message: ${version_message}"
    echo "  Preview URL: https://b-${safe_branch}-infra-docs.sciexp.workers.dev"
    ;;

  production)
    echo "Deploying to production from branch: ${current_branch}"
    echo "Current commit: ${commit_short}"
    echo "Full SHA: ${commit_sha}"
    echo "Looking for existing version with tag: ${commit_tag}"
    echo "Deployment message: ${deploy_msg}"
    echo ""

    export WRANGLER_CONFIG="$wrangler_config"

    # Query for an existing version uploaded from this commit (via preview).
    # Capture versions list to a tempfile so post-condition verification below
    # can reuse it (avoids a second API call purely for the existing-version
    # lookup) and any diagnostic error messages can reference the raw JSON.
    # `| cat >` is used instead of `>` to route wrangler's stdout through a
    # pipe-shaped fd; see the preview subcommand's equivalent comment for the
    # empirical rationale.
    wrangler_list_json="$tmpdir/wrangler-versions-list.json"

    node "$WRANGLER" --config "$WRANGLER_CONFIG" versions list --json \
      | cat > "$wrangler_list_json"

    existing_version=$(jq -r --arg tag "$commit_tag" \
      '.[] | select(.annotations["workers/tag"] == $tag) | .id' \
      "$wrangler_list_json" 2>/dev/null | head -1 || true)

    if [[ -n "$existing_version" ]]; then
      echo "found existing version: ${existing_version}"
      echo "  this version was already built and tested in preview"
      echo "  promoting to 100% production traffic..."
      echo ""

      export DEPLOYMENT_MESSAGE="$deploy_msg"
      export EXISTING_VERSION="$existing_version"

      # Post-condition verification mirrors the preview path: capture
      # wrangler's NDJSON event log via WRANGLER_OUTPUT_FILE_PATH, assert a
      # non-empty deployment_id on the `version-deploy` event, then cross-check
      # via `wrangler deployments list --json` before declaring success. Like
      # `versions upload`, `versions deploy` does NOT accept `--json` on
      # wrangler 4.84.x — the event log is the authoritative machine-readable
      # output channel. Detects wrangler's silent-exit failure mode
      # (VAL-WRITESHELL-DOCS-010 + diagnostic session 45961bc9) when the
      # CI-detection branch exits 0 without actually performing the promotion.
      deploy_ndjson="$tmpdir/wrangler-versions-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-versions-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" versions deploy \
          "${EXISTING_VERSION}@100%" \
          --yes \
          --message "$DEPLOYMENT_MESSAGE" \
        | tee "$deploy_stdout"

      unset WRANGLER_OUTPUT_FILE_PATH

      # Post-condition (a): extract a non-empty Deployment ID. Primary source
      # is the NDJSON `version-deploy` event (Option A); fallback is stdout
      # parsing for a recognizable deployment identifier (Option B).
      deployment_id=""
      if [[ -s "$deploy_ndjson" ]]; then
        deployment_id=$(
          jq -rs '
            map(select(type == "object" and (.type // "") == "version-deploy"))
            | .[0].deployment_id // empty
          ' "$deploy_ndjson" 2>/dev/null || true
        )
      fi
      if [[ -z "$deployment_id" ]]; then
        # stdout fallback: match patterns like "Deployment ID: <uuid>" or
        # "deployment_id: <uuid>" that wrangler prints on the console.
        deployment_id=$(
          grep -oiE '(Deployment ID|deployment_id)[[:space:]]*:[[:space:]]*[a-f0-9-]+' \
            "$deploy_stdout" 2>/dev/null \
            | awk '{print $NF}' \
            | head -1 || true
        )
      fi
      if [[ -z "$deployment_id" ]]; then
        echo "" >&2
        echo "error: wrangler exited 0 but produced no Deployment ID" >&2
        echo "  post-condition (a) failed: neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
        echo "                              event log nor wrangler stdout contained" >&2
        echo "                              a recognizable Deployment ID" >&2
        echo "  raw wrangler event log: $deploy_ndjson" >&2
        echo "  raw wrangler stdout:   $deploy_stdout" >&2
        echo "  hints:" >&2
        echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
        echo "      the caller (see deploy.sh env-var contract header for caller mechanisms)" >&2
        echo "    - if linux-x64 regression, confirm wrangler invoked under real node and" >&2
        echo "      not bun-fake-node (see top-of-file rationale at lines ~101-110)" >&2
        echo "    - inspect the wrangler internal log dumped below / raw capture paths above for any output" >&2
        exit 1
      fi

      # Post-condition (b): cross-check via deployments list that the deploy
      # landed server-side. `| cat >` empirically required — see preview path
      # comment for the rationale.
      deployments_list_json="$tmpdir/wrangler-deployments-list.json"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json \
        | cat > "$deployments_list_json"

      found_count=$(jq --arg did "$deployment_id" --arg vid "$existing_version" \
        '[.[] | select(
           .id == $did
           or .deployment_id == $did
           or ((.versions // []) | map(.version_id // .id // "") | index($vid) != null)
         )] | length' \
        "$deployments_list_json" 2>/dev/null || echo 0)
      if [[ "$found_count" -lt 1 ]]; then
        echo "" >&2
        echo "error: deployment ${deployment_id} (version ${existing_version}) not found in deployments list" >&2
        echo "  post-condition (b) failed: wrangler deployments list returned no" >&2
        echo "                              entries matching the just-deployed id/version" >&2
        echo "  raw deployments list output: $deployments_list_json" >&2
        echo "  hint: wrangler reported a deployment locally but the Cloudflare API did" >&2
        echo "        not persist it; inspect the raw deployments list for surrounding entries" >&2
        exit 1
      fi

      # Post-condition (c): authoritative success echo with parsed Deployment ID.
      echo ""
      echo "successfully promoted version ${existing_version} to production"
      echo "  Deployment ID: ${deployment_id}"
      echo "  tag: ${commit_tag}"
      echo "  full SHA: ${commit_sha}"
      echo "  deployed by: ${deploy_msg}"
      echo "  production URL: https://infra.cameronraysmith.net"
    else
      echo "warning: no existing version found with tag: ${commit_tag}"
      echo "  this should only happen if:"
      echo "    - this is the first deployment"
      echo "    - commit was made directly on main (not recommended)"
      echo "    - version was cleaned up (retention policy)"
      echo ""
      echo "  falling back to direct deploy of the nix-built payload..."
      echo ""

      export DEPLOYMENT_MESSAGE="$deploy_msg"

      # Fallback direct-deploy: same post-condition pattern, but the relevant
      # NDJSON event is `type == "deploy"` which carries `version_id` (no
      # deployment_id field on this event type — see wrangler cli.js
      # writeOutput block for `deploy`). `wrangler deploy` does NOT accept
      # `--json` on wrangler 4.84.x; WRANGLER_OUTPUT_FILE_PATH is the
      # authoritative machine-readable channel.
      deploy_ndjson="$tmpdir/wrangler-deploy.ndjson"
      deploy_stdout="$tmpdir/wrangler-deploy.stdout"
      : > "$deploy_ndjson"
      : > "$deploy_stdout"
      export WRANGLER_OUTPUT_FILE_PATH="$deploy_ndjson"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" deploy \
          --message "$DEPLOYMENT_MESSAGE" \
        | tee "$deploy_stdout"

      unset WRANGLER_OUTPUT_FILE_PATH

      # Post-condition (a): extract the just-deployed version_id. Primary
      # source: NDJSON `deploy` event (Option A). Fallback: stdout grep
      # (Option B) for the "Current Version ID: <uuid>" or similar line
      # wrangler prints on direct deploy.
      deploy_version_id=""
      if [[ -s "$deploy_ndjson" ]]; then
        deploy_version_id=$(
          jq -rs '
            map(select(type == "object" and (.type // "") == "deploy"))
            | .[0].version_id // empty
          ' "$deploy_ndjson" 2>/dev/null || true
        )
      fi
      if [[ -z "$deploy_version_id" ]]; then
        deploy_version_id=$(
          grep -oiE '(Current Version ID|Worker Version ID|version_id)[[:space:]]*:[[:space:]]*[a-f0-9-]+' \
            "$deploy_stdout" 2>/dev/null \
            | awk '{print $NF}' \
            | head -1 || true
        )
      fi
      if [[ -z "$deploy_version_id" ]]; then
        echo "" >&2
        echo "error: wrangler exited 0 but produced no Deployment Version ID (fallback direct deploy)" >&2
        echo "  post-condition (a) failed: neither WRANGLER_OUTPUT_FILE_PATH NDJSON" >&2
        echo "                              event log nor wrangler stdout contained" >&2
        echo "                              a recognizable version_id" >&2
        echo "  raw wrangler event log: $deploy_ndjson" >&2
        echo "  raw wrangler stdout:   $deploy_stdout" >&2
        echo "  hints:" >&2
        echo "    - confirm CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are exported by" >&2
        echo "      the caller (see deploy.sh env-var contract header for caller mechanisms)" >&2
        echo "    - if linux-x64 regression, confirm wrangler invoked under real node and" >&2
        echo "      not bun-fake-node (see top-of-file rationale at lines ~101-110)" >&2
        echo "    - inspect the wrangler internal log dumped below / raw capture paths above for any output" >&2
        exit 1
      fi
      # Reuse deployment_id slot below (it now holds the just-deployed version_id
      # since `wrangler deploy` emits no server-assigned deployment id directly).
      deployment_id="$deploy_version_id"

      deployments_list_json="$tmpdir/wrangler-deployments-list.json"

      node "$WRANGLER" --config "$WRANGLER_CONFIG" deployments list --json \
        | cat > "$deployments_list_json"

      found_count=$(jq --arg vid "$deploy_version_id" \
        '[.[] | select(
           .id == $vid
           or .deployment_id == $vid
           or ((.versions // []) | map(.version_id // .id // "") | index($vid) != null)
         )] | length' \
        "$deployments_list_json" 2>/dev/null || echo 0)
      if [[ "$found_count" -lt 1 ]]; then
        echo "" >&2
        echo "error: deployment for version ${deploy_version_id} not found in deployments list (fallback direct deploy)" >&2
        echo "  post-condition (b) failed: wrangler deployments list returned no" >&2
        echo "                              entries matching the just-deployed version_id" >&2
        echo "  raw deployments list output: $deployments_list_json" >&2
        echo "  hint: wrangler reported a deployment locally but the Cloudflare API did" >&2
        echo "        not persist it; inspect the raw deployments list for surrounding entries" >&2
        exit 1
      fi

      echo ""
      echo "deployed nix-built payload directly to production"
      echo "  Deployment Version ID: ${deployment_id}"
      echo "  tag: ${commit_tag}"
      echo "  full SHA: ${commit_sha}"
      echo "  deployed by: ${deploy_msg}"
      echo "  production URL: https://infra.cameronraysmith.net"
      echo "  warning: this version was not tested in preview first"
    fi
    ;;

  *)
    echo "error: unknown subcommand '$mode'" >&2
    echo "usage: deploy-docs preview <branch> | deploy-docs production" >&2
    echo "(run with --help for full usage and env-var contract)" >&2
    exit 2
    ;;
esac
