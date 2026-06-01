#!/usr/bin/env bash
#
# regenerate the vendored openspec claude assets under assets/.
#
# openspec stores its skill and slash-command bodies as compiled javascript,
# not as static files, so the markdown payloads must be produced by running
# `openspec init`. this script captures that generated output so it can be
# committed and injected at the user level without a per-project init.
#
# the generated skills and commands are version-portable: no working directory
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

# resolve this script's directory so the script works from any cwd.
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
assets_dir="$script_dir/assets"

# derive the pinned openspec version from the flake rather than hardcoding, so
# this stays in sync with the llm-agents input on every regeneration.
#
# use the git+file:// flake form rather than a bare path: flake. a path: flake
# copies the entire working tree including .git, which fails on the fsmonitor
# socket (.git/fsmonitor--daemon.ipc, "unsupported type"). git+file:// excludes
# .git entirely, evaluating cleanly while still reading the pinned input.
ver="$(nix eval --raw --impure --expr \
  "let f = builtins.getFlake \"git+file://${repo_root}\"; in f.inputs.llm-agents.packages.\${builtins.currentSystem}.openspec.version")"
echo "openspec version (from flake): ${ver}"

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
  "delivery": "both",
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
generated_commands="${proj}/.claude/commands/opsx"
if [[ ! -d "${generated_skills}" || ! -d "${generated_commands}" ]]; then
  echo "error: expected .claude/skills and .claude/commands/opsx in generated output" >&2
  exit 1
fi

# assert the full custom-profile set was generated, so a silent core-profile
# fallback (4 workflows) or partial generation fails loudly here.
skill_count=$(fd -t d -d 1 . "${generated_skills}" | wc -l | tr -d ' ')
cmd_count=$(fd -t f -e md . "${generated_commands}" | wc -l | tr -d ' ')
if [[ "${skill_count}" -ne 11 || "${cmd_count}" -ne 11 ]]; then
  echo "error: expected 11 skills and 11 commands, got ${skill_count} skills / ${cmd_count} commands" >&2
  exit 1
fi

# replace the committed asset trees.
rm -rf "${assets_dir}/skills" "${assets_dir}/commands"
mkdir -p "${assets_dir}/skills" "${assets_dir}/commands"
cp -R "${generated_skills}/." "${assets_dir}/skills/"
cp -R "${generated_commands}" "${assets_dir}/commands/opsx"

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
