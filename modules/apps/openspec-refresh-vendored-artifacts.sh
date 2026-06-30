#!/usr/bin/env bash
#
# regenerate the vendored openspec claude assets under assets/.
#
# openspec stores its skill bodies as compiled javascript, not as static files,
# so the markdown payloads must be produced by running `openspec init`. this
# script captures that generated output so it can be committed and injected at
# the user level without a per-project init. delivery=skills emits only the 11
# openspec-* skills and no commands/ tree (the /opsx:* commands were 1:1 skill
# duplicates).
#
# the generated skills are version-portable: no working directory
# or absolute path is embedded. the only dynamic field is the `generatedBy`
# frontmatter line on each SKILL.md, which records the openspec version.
#
# regenerate after an `llm-agents` flake input bump (which is the source of the
# pinned openspec version) so the committed assets track the cli on path.
#
# the script is idempotent: it runs `openspec init` in a fully sandboxed temp
# directory (no real $HOME is touched), then replaces the contents of assets/.
#
set -euo pipefail

# locate the repo via git so the script is location-independent: it can be
# embedded into a nix store path (the openspec-refresh-vendored-artifacts flake
# app) and still rewrite the committed assets in the user's worktree.
repo_root="$(git rev-parse --show-toplevel)"
assets_dir="${repo_root}/modules/home/ai/openspec/assets"

# the pinned openspec version is injected by the flake app via runtimeEnv; when
# running this script standalone, set it explicitly, e.g.
#   OPENSPEC_VERSION=1.4.1 bash modules/apps/openspec-refresh-vendored-artifacts.sh
ver="${OPENSPEC_VERSION:?set OPENSPEC_VERSION (injected by the flake app)}"
echo "openspec version: ${ver}"

# generate into a sandboxed temp dir; HOME is redirected so nothing escapes.
work="$(mktemp -d "${TMPDIR:-/tmp}/openspec-gen.XXXXXX")"
trap 'rm -rf "${work}"' EXIT
proj="${work}/proj"
home="${work}/home"
mkdir -p "${proj}" "${home}"

# `openspec init` defaults to the `core` profile (4 workflows). the full set of
# 11 workflows requires a global config selecting profile=custom plus the
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
  "workflows": ["propose","explore","new","continue","apply","ff","sync","archive","bulk-archive","verify","onboard"]
}
JSON

(
  cd "${proj}" && HOME="${home}" XDG_CONFIG_HOME="${xdg}" CI=true OPENSPEC_TELEMETRY=0 \
    OPENSPEC_NO_COMPLETIONS=1 DO_NOT_TRACK=1 \
    bunx "@fission-ai/openspec@${ver}" init --tools claude --force --profile custom </dev/null
)

# verify the expected layout before clobbering the committed assets.
generated_skills="${proj}/.claude/skills"
if [[ ! -d "${generated_skills}" ]]; then
  echo "error: expected .claude/skills in generated output" >&2
  exit 1
fi

# assert the full custom-profile set was generated, so a silent core-profile
# fallback (4 workflows) or partial generation fails loudly here.
skill_count=$(fd -t d -d 1 . "${generated_skills}" | wc -l | tr -d ' ')
if [[ "${skill_count}" -ne 11 ]]; then
  echo "error: expected 11 skills, got ${skill_count} skills" >&2
  exit 1
fi

# replace the committed asset tree.
rm -rf "${assets_dir}/skills"
mkdir -p "${assets_dir}/skills"
cp -R "${generated_skills}/." "${assets_dir}/skills/"

# portability guard: fail if any sandbox path leaked into the assets.
if rg -q -e "${proj}" -e "/tmp/openspec-gen" "${assets_dir}"; then
  echo "error: sandbox path leaked into generated assets" >&2
  exit 1
fi

# summary.
echo ""
echo "regenerated openspec assets (version ${ver}):"
fd -H -t f . "${assets_dir}" | sort | sed "s#${assets_dir}/#  #"
echo ""
echo "generatedBy frontmatter:"
rg -n 'generatedBy' "${assets_dir}/skills"
