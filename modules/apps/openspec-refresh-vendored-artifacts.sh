#!/usr/bin/env bash
#
# regenerate the vendored openspec claude skills into the planning-and-development
# apm package.
#
# openspec stores its skill bodies as compiled javascript, not as static files,
# so the markdown payloads must be produced by running openspec's own code.
# `openspec init` and `openspec update` install every file of each skill from
# the package's `expectedSkillFiles`; this script calls that function from the
# pinned package directly, through modules/home/ai/openspec/generate-skills.mjs,
# so it needs no network and produces the bytes init would install. the
# openspec-vendored-skills check uses the same generator, so the two can never
# disagree.
#
# the generated skills are version-portable: no working directory or absolute
# path is embedded, and since 2.1 they carry no `generatedBy` line. upstream's
# `metadata.author: openspec` frontmatter marks them as generated.
#
# regenerate after an `llm-agents` flake input bump (which is the source of the
# pinned openspec version) so the committed skills track the cli on path; the
# openspec-vendored-skills check fails until they do.
#
# the script is idempotent: it generates in a sandboxed temp directory (HOME,
# every XDG base directory and TMPDIR point inside it, and the run fails if
# anything under the real home's openspec folders changed), then replaces ONLY
# the generated openspec-* skills in the package, per-skill, leaving the
# hand-authored skills in the same directory untouched.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: openspec-refresh-vendored-artifacts [-h|--help]

Regenerates the vendored OpenSpec skills (openspec and openspec-*) in
modules/home/ai/plugins/planning-and-development/.apm/skills offline from the
flake-pinned openspec package, in a sandboxed temp directory.
Hand-authored skills in that directory are left untouched.

Options:
  -h, --help  show this help and exit.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# locate the repo via git so the script is location-independent: it can be
# embedded into a nix store path (the openspec-refresh-vendored-artifacts flake
# app) and still rewrite the committed skills in the user's worktree.
repo_root="$(git rev-parse --show-toplevel)"
generator="${repo_root}/modules/home/ai/openspec/generate-skills.mjs"

# the generated openspec skills are vendored into the planning-and-development
# apm package so they ship through apm-skills-compose; this directory ALSO holds
# four hand-authored skills (agentic-planning-development-workflow,
# openspec-bdd-bridge, openspec-linear-sync, linear-project-management) which this script
# must never touch.
skills_target="${repo_root}/modules/home/ai/plugins/planning-and-development/.apm/skills"

# the flake app puts the flake-pinned openspec (the llm-agents package that
# programs.openspec installs) on PATH, so the vendored skills come from the same
# artifact the fleet runs. standalone runs use whichever openspec is on PATH.
ver="$(openspec --version)"
package_root="$(dirname "$(dirname "$(realpath "$(command -v openspec)")")")/lib/node_modules/@fission-ai/openspec"
echo "openspec version: ${ver}"
echo "openspec package: ${package_root}"

# generate into a sandboxed temp dir. HOME, every XDG base directory and TMPDIR
# point inside it: an inherited XDG_DATA_HOME once let 2.1's known-projects list
# (src/core/known-projects.ts) land in the real ~/.local/share/openspec/.
work="$(mktemp -d "${TMPDIR:-/tmp}/openspec-gen.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
work="$(realpath "${work}")"
real_home="${HOME}"
generated_skills="${work}/skills"
sandbox_env=(
  "HOME=${work}/home"
  "XDG_CONFIG_HOME=${work}/xdg/config"
  "XDG_DATA_HOME=${work}/xdg/data"
  "XDG_CACHE_HOME=${work}/xdg/cache"
  "XDG_STATE_HOME=${work}/xdg/state"
  "TMPDIR=${work}/tmp"
)
for assignment in "${sandbox_env[@]}"; do
  dir="${assignment#*=}"
  mkdir -p "${dir}"
  if [[ "$(realpath "${dir}")" != "${work}"/* ]]; then
    echo "error: ${assignment%%=*} resolves outside the sandbox: ${dir}" >&2
    exit 1
  fi
done

# the folders under the real home that openspec writes to when unsandboxed;
# none may change during the run.
watched=(
  "${real_home}/.agents"
  "${real_home}/.config/openspec"
  "${real_home}/.local/share/openspec"
  "${real_home}/.local/state/openspec"
  "${real_home}/.cache/openspec"
  "${real_home}/.claude/skills"
)
run_start="${work}/run-start"
touch "${run_start}"

(
  cd "${work}" && env "${sandbox_env[@]}" OPENSPEC_TELEMETRY=0 DO_NOT_TRACK=1 \
    node "${generator}" "${package_root}" "${generated_skills}" "${ver}"
)

escaped=()
for dir in "${watched[@]}"; do
  [[ -e "${dir}" ]] || continue
  while IFS= read -r path; do
    escaped+=("${path}")
  done < <(find "${dir}" -newer "${run_start}" -print)
done
if [[ ${#escaped[@]} -gt 0 ]]; then
  echo "error: files under the real home changed during the sandboxed generation:" >&2
  printf '  %s\n' "${escaped[@]}" >&2
  exit 1
fi

# assert the full set was generated, so a partial generation or a change in the
# number of upstream skills fails loudly here rather than vendoring a subset.
skill_count=$(fd -t d -d 1 . "${generated_skills}" | wc -l | tr -d ' ')
if [[ "${skill_count}" -ne 13 ]]; then
  echo "error: expected 13 skills, got ${skill_count} skills" >&2
  exit 1
fi

# replace ONLY the generated openspec-* skills in the target package, per-skill.
# iterate over the names this run actually produced (never a static `openspec-*`
# glob against the package) so the hand-authored skills sharing this directory are
# never removed or overwritten. openspec-bdd-bridge and openspec-linear-sync are
# hand-authored despite their openspec- prefix and are not produced by openspec,
# so they never appear in ${generated_skills} and are therefore never members of
# this loop.
generated_names=()
for skill_path in "${generated_skills}"/*/; do
  skill_name="$(basename "${skill_path}")"
  generated_names+=("${skill_name}")
  rm -rf "${skills_target:?}/${skill_name}"
  cp -R "${skill_path%/}" "${skills_target}/${skill_name}"
done

# portability guard: fail if any sandbox path leaked into the regenerated skills.
for skill_name in "${generated_names[@]}"; do
  if rg -q -F -e "${work}" -e "openspec-gen." "${skills_target}/${skill_name}"; then
    echo "error: sandbox path leaked into ${skill_name}" >&2
    exit 1
  fi
done

# summary.
echo ""
echo "regenerated ${#generated_names[@]} openspec skills (version ${ver}) into ${skills_target}:"
for skill_name in "${generated_names[@]}"; do
  fd -H -t f . "${skills_target}/${skill_name}" | sort | sed "s#${skills_target}/#  #"
done
