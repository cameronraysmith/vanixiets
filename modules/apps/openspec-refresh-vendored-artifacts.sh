#!/usr/bin/env bash
#
# regenerate the vendored openspec claude skills into the planning-and-development
# apm package.
#
# openspec stores its skill bodies as compiled javascript, not as static files,
# so the markdown payloads must be produced by running `openspec init`. this
# script captures that generated output so it can be committed and shipped through
# apm-skills-compose without a per-project init. delivery=skills emits only the 12
# openspec-* skills and no commands/ tree (the /opsx:* commands were 1:1 skill
# duplicates).
#
# the generated skills are version-portable: no working directory
# or absolute path is embedded. the only dynamic field is the `generatedBy`
# frontmatter line on each SKILL.md, which records the openspec version.
#
# regenerate after an `llm-agents` flake input bump (which is the source of the
# pinned openspec version) so the committed skills track the cli on path.
#
# the script is idempotent: it runs `openspec init` in a fully sandboxed temp
# directory (no real $HOME is touched), then replaces ONLY the generated
# openspec-* skills in the package, per-skill, leaving the hand-authored skills
# in the same directory untouched.
set -euo pipefail

# locate the repo via git so the script is location-independent: it can be
# embedded into a nix store path (the openspec-refresh-vendored-artifacts flake
# app) and still rewrite the committed skills in the user's worktree.
repo_root="$(git rev-parse --show-toplevel)"

# the 12 generated openspec-* skills are vendored into the planning-and-development
# apm package so they ship through apm-skills-compose; this directory ALSO holds
# four hand-authored skills (agentic-planning-development-workflow,
# openspec-bdd-bridge, openspec-linear-sync, project-management) which this script
# must never touch. the openspec module's assets/ tree now holds only the
# superpowers-bridge schema bundle (no skills/).
skills_target="${repo_root}/modules/home/ai/plugins/planning-and-development/.apm/skills"

# the pinned openspec version is injected by the flake app via runtimeEnv; when
# running this script standalone, set it explicitly, e.g.
#   OPENSPEC_VERSION=1.5.0 bash modules/apps/openspec-refresh-vendored-artifacts.sh
ver="${OPENSPEC_VERSION:?set OPENSPEC_VERSION (injected by the flake app)}"
echo "openspec version: ${ver}"

# generate into a sandboxed temp dir; HOME is redirected so nothing escapes.
work="$(mktemp -d "${TMPDIR:-/tmp}/openspec-gen.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
proj="${work}/proj"
home="${work}/home"
mkdir -p "${proj}" "${home}"

# `openspec init` defaults to the `core` profile (4 workflows). the full set of
# 12 workflows requires a global config selecting profile=custom plus the
# explicit workflows array; init exposes no --workflows flag, so the array can
# only come from the config file. point XDG_CONFIG_HOME at an isolated dir so
# this config never touches the real environment.
xdg="${work}/xdg"
mkdir -p "${xdg}/openspec"
cat > "${xdg}/openspec/config.json" <<'JSON'
{
  "featureFlags": {},
  "profile": "custom",
  "delivery": "skills",
  "workflows": ["propose","explore","new","continue","apply","update","ff","sync","archive","bulk-archive","verify","onboard"]
}
JSON

(
  cd "${proj}" && HOME="${home}" XDG_CONFIG_HOME="${xdg}" CI=true OPENSPEC_TELEMETRY=0 \
    OPENSPEC_NO_COMPLETIONS=1 DO_NOT_TRACK=1 \
    bunx "@fission-ai/openspec@${ver}" init --tools claude --force --profile custom </dev/null
)

# verify the expected layout before clobbering the committed skills.
generated_skills="${proj}/.claude/skills"
if [[ ! -d "${generated_skills}" ]]; then
  echo "error: expected .claude/skills in generated output" >&2
  exit 1
fi

# assert the full custom-profile set was generated, so a silent core-profile
# fallback (4 workflows) or partial generation fails loudly here.
skill_count=$(fd -t d -d 1 . "${generated_skills}" | wc -l | tr -d ' ')
if [[ "${skill_count}" -ne 12 ]]; then
  echo "error: expected 12 skills, got ${skill_count} skills" >&2
  exit 1
fi

# replace ONLY the generated openspec-* skills in the target package, per-skill.
# iterate over the names this run actually produced (never a static `openspec-*`
# glob against the package) so the hand-authored skills sharing this directory are
# never removed or overwritten. openspec-bdd-bridge and openspec-linear-sync are
# hand-authored despite their openspec- prefix and are not produced by
# `openspec init`, so they never appear in ${generated_skills} and are therefore
# never members of this loop.
generated_names=()
for skill_path in "${generated_skills}"/*/; do
  skill_name="$(basename "${skill_path}")"
  generated_names+=("${skill_name}")
  rm -rf "${skills_target:?}/${skill_name}"
  cp -R "${skill_path%/}" "${skills_target}/${skill_name}"
done

# portability guard: fail if any sandbox path leaked into the regenerated skills.
for skill_name in "${generated_names[@]}"; do
  if rg -q -e "${proj}" -e "/tmp/openspec-gen" "${skills_target}/${skill_name}"; then
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
echo ""
echo "generatedBy frontmatter:"
for skill_name in "${generated_names[@]}"; do
  rg -n 'generatedBy' "${skills_target}/${skill_name}"
done
