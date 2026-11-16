# openspec vendored claude assets

This directory holds the vendored OpenSpec (`@fission-ai/openspec`) Claude assets and the home-manager module that installs them.
The schema bundles under `assets/schemas/` are hand-maintained, not generated (see `assets/schemas/README.md`); the refresh generates only the 12 `openspec-*` skills, by running `openspec init --tools claude` with the version pinned by the `llm-agents` flake input.
Since OpenSpec 2.0 (Fission-AI/OpenSpec#2223), `openspec init` emits only the 12 `openspec-*` skills, written once to a shared `.agents/skills/` folder and symlinked from each tool's own skills folder such as `.claude/skills/`; the `/opsx:*` commands and the `delivery` setting are retired, so the refresh script reads `.agents/skills/` and vendors those skills into the planning-and-development apm package.
Never run `openspec init` or `openspec update` in this repository or in any repository whose `.agents/` is apm-managed: 2.0 writes its skills into `.agents/skills/`, the tree apm regenerates from its manifest and lock, and links each tool's skills folder (such as `.claude/skills/`) into it.
The schema bundles and config are installed at the user level by the opt-in `programs.openspec` module in `default.nix`: setting `programs.openspec.enable = true` in a home configuration, as each user home that uses OpenSpec and every Omnigent worker does, delivers the schema bundles user-global and writes the global `config.json` (custom profile, 12 workflows); the 12 `openspec-*` skills ship separately through the planning-and-development apm package.
The generated skills are version-portable; the only dynamic field is the `generatedBy` frontmatter line on each `SKILL.md`.
Do not hand-edit the generated skills; regenerate them with `nix run .#openspec-refresh-vendored-artifacts` (or `just openspec-regen`) after an `llm-agents` input bump instead.
The regeneration script is the flake app's sidecar at `modules/apps/openspec-refresh-vendored-artifacts.sh`.
