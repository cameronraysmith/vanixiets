#!/usr/bin/env bash
# shellcheck shell=bash
#
# producer-path materialization for the vanixiets apm skills marketplace.
#
# materializes the marketplace this repo publishes back into the repo it is
# published from: the 18 packages under modules/home/ai/plugins/ are declared
# as apm.yml `dependencies.apm` entries pointing at
# cameronraysmith/vanixiets/modules/home/ai/plugins/<group>#main, so a run of
# this script resolves them from github `main` rather than the local
# worktree. that makes the committed apm.lock.yaml reproduce identically in
# any environment (ephemeral dev shells included), independent of what the
# local checkout happens to contain at run time.
#
# `apm init` and positional-argument `apm install <pkg>` are never invoked
# here: both write apm.yml back through apm's ruamel-based writer, which
# would reflow the over-80-column `source:` values in the existing
# `marketplace:` publishing block or, in `apm init`'s case, overwrite the
# whole manifest. `apm compile` is never invoked either: it replaces the
# `AGENTS.md` path with a fresh regular file via `os.replace`, which would
# sever the repo's existing symlink to the planning-repo context file.
#
# unlike apm-marketplace-validate.sh, this script deliberately does NOT
# isolate $HOME or override APM_CACHE_DIR: it targets the shared warm apm
# git cache at the platform cache dir, which is what lets a lock-honoring
# `apm install --frozen` succeed without network access; validate isolates
# because it is exercising the cold consumer path instead.
#
# two mutually exclusive modes:
#   (default)  apm install --frozen   materialize from the committed lockfile.
#   --relock   apm install --update    re-solve the graph in place so a
#              newly appeared transitive dependency is discovered.
#
# refuses by default on a host where home-manager already delivers the same
# skills at user level (modules/home/ai/skills/default.nix): agent harnesses
# prefer the project-level .agents/skills/ over the user-level directories,
# so a repo-local tree materialized from the committed lock silently shadows
# the current Nix-delivered skills and goes stale as the lock ages. That
# happened: a tree from a 19-day-old lock shadowed the user-level skills and
# agents followed an outdated jj-version-control. See
# home_manager_skills_present below for the detection rule;
# --shadow-user-skills overrides it for deliberate use (for example a relock
# on a home-manager host).
#
# grep-able marker: APM-SKILLS-INSTALL-OK
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: apm-skills-install [--relock] [--shadow-user-skills] [-h|--help]

Materializes this repo's own 18 apm skill packages (declared in apm.yml
`dependencies.apm`, resolved from github cameronraysmith/vanixiets `main`)
into .agents/skills/, using the shared warm apm git cache. Never isolates
$HOME or APM_CACHE_DIR.

Refuses when home-manager already delivers skills at user level, because
the repo-local .agents/skills/ would shadow them for agents run in this
repository.

Modes:
  (default)  apm install --frozen  — install strictly from the committed
             apm.lock.yaml; fails if manifest and lock disagree.
  --relock   apm install --update — re-solve the graph in place so a
             newly appeared transitive dependency is discovered.

Options:
  --shadow-user-skills  install even though home-manager delivers skills
                        at user level; the result shadows them until
                        .agents/skills/ is removed.
  -h, --help            show this help and exit.
EOF
}

# True when any user-level skill directory that modules/home/ai/skills/
# populates via home.file holds a SKILL.md symlink into home-manager's
# generation tree. home-manager links every home.file entry through one
# derivation it always names "home-manager-files" (runCommandLocal in
# home-manager's modules/files.nix), and programs.claude-code.skills,
# programs.opencode.skills and the .factory/.hermes home.file entries all
# deploy SKILL.md as such a link. A clone, a manual copy, or another tool
# produces regular files or links elsewhere, so the test does not fire
# there. ~/.agents/skills is not tested: its activation script copies real
# files, which carry no provenance. Cost: one glob and at most one readlink
# per directory.
home_manager_skills_present() {
  local dir leaf target
  for dir in "${HOME}/.claude/skills" "${HOME}/.config/opencode/skills" \
    "${HOME}/.factory/skills" "${HOME}/.hermes/skills"; do
    for leaf in "${dir}"/*/SKILL.md; do
      [ -L "${leaf}" ] || continue
      target="$(readlink "${leaf}")"
      case "${target}" in
        /nix/store/*-home-manager-files/*)
          echo "${leaf} -> ${target}"
          return 0
          ;;
      esac
      break
    done
  done
  return 1
}

mode=frozen
shadow_user_skills=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --relock) mode=refresh ;;
    --shadow-user-skills) shadow_user_skills=1 ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

repo_root="$(git rev-parse --show-toplevel)"
cd "${repo_root}"

# guard: refuse to run against anything but this repository's producer
# manifest, so a misplaced invocation cannot install into an unrelated
# project's apm_modules/.
if [ ! -f apm.yml ]; then
  echo "apm-skills-install: no apm.yml at repo root ${repo_root}" >&2
  exit 1
fi
manifest_output="$(yq -r '.marketplace.output' apm.yml)"
if [ "${manifest_output}" != ".github/plugin/marketplace.json" ]; then
  echo "apm-skills-install: apm.yml at ${repo_root} is not the vanixiets producer manifest (marketplace.output=${manifest_output})" >&2
  exit 1
fi

if hm_evidence="$(home_manager_skills_present)"; then
  if [ "${shadow_user_skills}" -eq 0 ]; then
    cat >&2 <<EOF
apm-skills-install: refusing: home-manager already delivers agent skills on
  this host (${hm_evidence}).
  A repo-local .agents/skills/ would shadow those user-level skills for
  every agent run in this repository and drift from them as apm.lock.yaml
  ages. Use the home-manager-delivered skills instead.
  To install anyway (for example to relock), pass --shadow-user-skills:
    nix run .#apm-skills-install -- --shadow-user-skills
    just agents-install --shadow-user-skills
  and remove .agents/skills/ afterwards unless the shadowing is intended.
EOF
    exit 3
  fi
  echo "apm-skills-install: --shadow-user-skills: installing over home-manager-delivered skills (${hm_evidence})" >&2
fi

echo "=== apm-skills-install (mode=${mode}) ==="
echo "repo_root: ${repo_root}"
apm --version | head -1 || true
echo ""

if [ "${mode}" = frozen ]; then
  if [ ! -f apm.lock.yaml ]; then
    echo "apm-skills-install: apm.lock.yaml is missing; run 'just agents-relock' first" >&2
    exit 1
  fi
  apm install --frozen
else
  # Relock re-solves the dependency graph with --update rather than --refresh.
  # --refresh only re-resolves pins that are ALREADY in the lockfile and
  # silently ignores a transitive dependency that has since appeared in a
  # package's own manifest. That is not hypothetical: a mergify-stack
  # dependency added upstream stayed invisible across a --refresh whose diff
  # was pure substitution, 57 insertions and 57 deletions with no additions.
  #
  # --update restructures the lockfile in place, so the path is never absent.
  # That matters beyond tidiness: removing the file would make jj see a fresh
  # 400KiB-plus path and refuse to snapshot it under
  # snapshot.max-new-file-size, because that limit applies only to paths jj
  # does not already track.
  #
  # Relock starts from an empty apm_modules/ cache. In apm 0.32.0, an existing
  # install path under --update is re-fetched only for semver refs
  # (should_force_ref_recheck, src/apm_cli/drift.py:174-193): a literal commit
  # pin that changed in a dependency's own manifest reuses the cached checkout
  # and writes the old resolved_commit back. Plain install catches that drift;
  # --update does not. Observed when version-control-and-forge/apm.yml moved
  # its worktrunk and mergify-cli refs and the relock kept both old commits.
  # apm_modules/ is git-ignored materialization only, and the lockfile ledger
  # carries ownership of deployed files, so removing it costs one re-fetch.
  rm -rf "${repo_root}/apm_modules"
  relock_log="$(mktemp)"
  if ! apm install --update 2>&1 | tee "${relock_log}"; then
    rm -f "${relock_log}"
    exit 1
  fi

  # A skipped file means apm found deployed content it does not own and left it
  # alone, and a skipped deployment is never recorded in the lockfile ledger.
  # The lockfile would then describe this machine rather than the pinned
  # sources, so fail rather than let a contaminated ledger be committed
  # unnoticed. Deleting the named file and rerunning lets apm redeploy and
  # record it.
  if grep -q 'not managed by APM' "${relock_log}"; then
    echo "" >&2
    echo "apm-skills-install: apm skipped deployed files it does not own, so the" >&2
    echo "  regenerated lockfile omits them. Do not commit it. Remove the files" >&2
    echo "  apm reported under .agents/skills/ and rerun this relock." >&2
    rm -f "${relock_log}"
    exit 1
  fi
  rm -f "${relock_log}"
fi
echo ""

mapfile -t skill_files < <(find "${repo_root}/.agents/skills" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sort)
skill_count="${#skill_files[@]}"

echo "deployed skill count: ${skill_count}"
echo "paths written:"
echo "  ${repo_root}/.agents/skills"
if [ -d "${repo_root}/apm_modules" ]; then
  echo "  ${repo_root}/apm_modules"
fi

if [ "${mode}" = refresh ]; then
  echo ""
  echo "apm.lock.yaml diff:"
  git diff --stat -- apm.lock.yaml || true
fi

echo ""
echo "APM-SKILLS-INSTALL-OK: ${skill_count} skill(s) deployed to .agents/skills/"
