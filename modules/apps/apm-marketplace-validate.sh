#!/usr/bin/env bash
# shellcheck shell=bash
#
# consumer-path validation for the vanixiets apm skills marketplace.
#
# proves an apm-native CONSUMER can register the marketplace this repo publishes
# and install every package into a throwaway root, in a fully isolated
# environment that never reads or writes the real $HOME / ~/.claude / ~/.config.
#
# two source modes:
#   --local  (default) register the worktree as a kind=local marketplace and
#            validate the about-to-be-published content. apm reads local
#            git-backed marketplaces via `git show <ref>:<file>`, so the
#            marketplace manifest must be reachable at the chosen ref. --ref
#            defaults to HEAD (the current integrated checkout) rather than git
#            `main`, where the marketplace manifests do not yet live. the
#            first-party packages resolve with zero network; the lone remote
#            transitive dep (planning-and-development -> obra/superpowers) still
#            fetches from github over https, which is why cacert +
#            GIT_SSL_CAINFO are provided on PATH/env.
#   --remote register OWNER/REPO from github (default cameronraysmith/vanixiets).
#            requires the publishing branch pushed; --ref selects it. exercises
#            the real fetch path and is not run until the branch is pushed.
#
# grep-able markers: APM-VALIDATE-MARKETPLACE-ADDED, APM-VALIDATE-COVERAGE-{OK,DRIFT},
# APM-VALIDATE-PKG-{OK,FAIL}, APM-VALIDATE-SUMMARY.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: apm-marketplace-validate [--local | --remote] [--repo OWNER/REPO] [--ref REF] [-h|--help]

Registers the vanixiets apm skills marketplace in a throwaway, fully isolated
environment (overrides $HOME and every XDG dir) and installs each published
package the way an external apm consumer would, asserting a SKILL.md lands per
package. Never touches the real $HOME / ~/.claude / ~/.config.

Modes:
  --local   (default) register the worktree as a kind=local marketplace. apm
            reads local git-backed marketplaces with `git show <ref>:<file>`, so
            --ref must name a ref carrying the marketplace manifests; the default
            HEAD is the current integrated checkout (the manifests are not on git
            `main` until this change merges). First-party packages resolve
            offline; planning-and-development's superpowers dep fetches from
            github over https.
  --remote  register OWNER/REPO from github (default cameronraysmith/vanixiets);
            requires the publishing branch pushed. --ref selects it (default main).

Options:
  --repo OWNER/REPO  override the remote source repo (used by --remote).
  --ref REF          git ref carrying the marketplace manifests. Default: HEAD
                     for --local, main for --remote.
  -h, --help         show this help and exit.

Exits nonzero if marketplace coverage drifts or any package fails to install.
EOF
}

mode=local
repo_override=""
ref_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --local) mode=local ;;
    --remote) mode=remote ;;
    --repo)
      repo_override="${2:?--repo needs OWNER/REPO}"
      shift
      ;;
    --ref)
      ref_override="${2:?--ref needs a git ref}"
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# resolve the repo before redirecting $HOME so git config still reads normally.
repo_root="$(git rev-parse --show-toplevel)"

# fully isolated throwaway environment. the real $HOME / ~/.claude / ~/.config
# are never read or written: apm install writes apm.yml + .gitignore into $PWD
# (so the per-package loop runs from a scratch project dir, never $repo_root) and
# registry state into $HOME/.apm. the trap restores write permission before
# removal because apm install deploys read-only store-symlinked trees under
# --root.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/apm-validate.XXXXXX")"
trap 'chmod -R u+w "$SCRATCH" 2>/dev/null || true; rm -rf "$SCRATCH"' EXIT
export HOME="$SCRATCH/home"
export XDG_CONFIG_HOME="$SCRATCH/config"
export XDG_DATA_HOME="$SCRATCH/data"
export XDG_STATE_HOME="$SCRATCH/state"
export XDG_CACHE_HOME="$SCRATCH/cache"
export APM_CACHE_DIR="$SCRATCH/apm-cache"
export APM_E2E_TESTS=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" \
  "$XDG_CACHE_HOME" "$APM_CACHE_DIR"

echo "=== apm-marketplace-validate (mode=${mode}) ==="
echo "repo_root: ${repo_root}"
echo "scratch:   ${SCRATCH}"
apm --version | head -1 || true
echo ""

# published package set (producer manifest) cross-checked against the
# marketplace.json apm registers. the worktree files faithfully reflect the
# --local ref (HEAD) for these committed manifests.
mapfile -t published < <(yq -r '.marketplace.packages[].name' "${repo_root}/apm.yml" | sort)
mapfile -t served < <(jq -r '.plugins[].name' "${repo_root}/.claude-plugin/marketplace.json" | sort)
echo "published packages (apm.yml):          ${#published[@]}"
echo "served plugins (marketplace.json):     ${#served[@]}"
if [ "${#published[@]}" -eq 0 ]; then
  echo "error: no packages enumerated from ${repo_root}/apm.yml" >&2
  exit 1
fi

# register the marketplace.
if [ "${mode}" = local ]; then
  source_arg="${repo_root}"
  ref="${ref_override:-HEAD}"
else
  source_arg="${repo_override:-cameronraysmith/vanixiets}"
  ref="${ref_override:-main}"
fi
echo "marketplace source: ${source_arg} @ ${ref}"
echo ""

set +e
add_out="$(apm marketplace add "${source_arg}" --ref "${ref}" 2>&1)"
add_rc=$?
set -e
echo "${add_out}"
if [ "${add_rc}" -ne 0 ]; then
  echo "APM-VALIDATE-MARKETPLACE-ADD-FAILED: ${source_arg} @ ${ref} (rc=${add_rc})" >&2
  exit 1
fi

# show the registry for the human log, but derive the alias programmatically.
apm marketplace list || true
echo ""

# derive the registered alias rather than hardcoding it: apm derives the alias
# from the manifest `name` field ("vanixiets-skills-marketplace"), not the
# apm.yml top-level `name` ("vanixiets"). parse the human-facing success line
# (`Marketplace '<alias>' registered`) which the `apm marketplace list` table
# would otherwise truncate with an ellipsis; fall back to the registry JSON.
alias_line="$(printf '%s\n' "${add_out}" | grep -o "Marketplace '[^']*' registered" | head -1 || true)"
alias_name="${alias_line#Marketplace \'}"
alias_name="${alias_name%\' registered}"
if [ -z "${alias_name}" ] && [ -f "${HOME}/.apm/marketplaces.json" ]; then
  alias_name="$(jq -r '.marketplaces[-1].name // empty' "${HOME}/.apm/marketplaces.json")"
fi
if [ -z "${alias_name}" ] || [ "${alias_name}" = null ]; then
  echo "error: could not derive registered marketplace alias from apm output" >&2
  exit 1
fi
echo "APM-VALIDATE-MARKETPLACE-ADDED: ${alias_name}"

# coverage: the registered marketplace must serve exactly the published set.
missing="$(comm -23 <(printf '%s\n' "${published[@]}") <(printf '%s\n' "${served[@]}"))"
extra="$(comm -13 <(printf '%s\n' "${published[@]}") <(printf '%s\n' "${served[@]}"))"
coverage_ok=1
if [ -n "${missing}" ] || [ -n "${extra}" ]; then
  coverage_ok=0
  missing_flat="$(printf '%s' "${missing}" | tr '\n' ' ')"
  extra_flat="$(printf '%s' "${extra}" | tr '\n' ' ')"
  echo "APM-VALIDATE-COVERAGE-DRIFT: missing=[${missing_flat}] extra=[${extra_flat}]" >&2
else
  echo "APM-VALIDATE-COVERAGE-OK: ${#published[@]} packages served"
fi
echo ""

# per-package install loop. collect failures; never abort on first failure so a
# single broken manifest does not mask the rest of the set.
declare -a status
passed=0
failed=0
for i in "${!published[@]}"; do
  pkg="${published[$i]}"
  proj="${SCRATCH}/proj/${pkg}"
  root="${SCRATCH}/root/${pkg}"
  mkdir -p "${proj}" "${root}"

  echo "--- installing ${pkg}@${alias_name} ---"
  # cd into the throwaway project dir: apm install writes apm.yml + .gitignore
  # into $PWD. the subshell keeps the cwd change local. `-t agent-skills,claude`
  # is required — without a target apm aborts pre-resolve with "No harness
  # detected".
  set +e
  (cd "${proj}" && apm install "${pkg}@${alias_name}" --root "${root}" -t agent-skills,claude) \
    >"${proj}/install.log" 2>&1
  rc=$?
  set -e

  shopt -s nullglob
  claude_skills=("${root}"/.claude/skills/*/SKILL.md)
  agents_skills=("${root}"/.agents/skills/*/SKILL.md)
  shopt -u nullglob

  if [ "${rc}" -eq 0 ] && { [ "${#claude_skills[@]}" -gt 0 ] || [ "${#agents_skills[@]}" -gt 0 ]; }; then
    status[i]=OK
    passed=$((passed + 1))
    echo "APM-VALIDATE-PKG-OK: ${pkg} (claude_skills=${#claude_skills[@]} agents_skills=${#agents_skills[@]})"
  else
    status[i]=FAIL
    failed=$((failed + 1))
    echo "APM-VALIDATE-PKG-FAIL: ${pkg} (rc=${rc})" >&2
    if [ "${rc}" -eq 0 ]; then
      echo "    install succeeded but no SKILL.md landed under ${root}" >&2
    fi
    while IFS= read -r line; do
      echo "    ${line}" >&2
    done < <(tail -20 "${proj}/install.log")
  fi
  echo ""
done

# summary table + machine-readable line.
echo "=== apm-marketplace-validate summary (mode=${mode}, alias=${alias_name}) ==="
printf '  %-55s %s\n' "PACKAGE" "RESULT"
for i in "${!published[@]}"; do
  printf '  %-55s %s\n' "${published[$i]}" "${status[$i]}"
done
echo ""
echo "APM-VALIDATE-SUMMARY: passed=${passed} failed=${failed} total=${#published[@]}"

if [ "${coverage_ok}" -ne 1 ] || [ "${failed}" -gt 0 ]; then
  exit 1
fi
echo "APM-VALIDATE-OK: all ${passed} package(s) installed in isolation; coverage intact"
