# openspec vendored claude assets

This directory holds the vendored OpenSpec (`@fission-ai/openspec`) Claude assets and the home-manager module that installs them.
The `assets/skills/` tree, plus the `assets/schemas/superpowers-bridge` schema bundle, are committed generated output, produced by running `openspec init --tools claude` against the version pinned by the `llm-agents` flake input.
OpenSpec runs under `delivery=skills`, which emits only the 11 `openspec-*` skills and no `commands/opsx/` tree; the `/opsx:*` slash commands were 1:1 duplicates of the skills, redundant for the non-Claude harnesses that consume skills, not commands.
They are installed at the user level by the opt-in `programs.openspec` module in `default.nix`: a user opts in with `programs.openspec.enable = true` (crs58 does), which wires the skills via `aiSkills.extraSkillDirs`, the schema bundle user-global, and the global `config.json` (custom profile, 11 workflows).
The assets are version-portable; the only dynamic field is the `generatedBy` frontmatter line on each `SKILL.md`.
Do not hand-edit these files; regenerate them with `nix run .#openspec-refresh-vendored-artifacts` (or `just openspec-regen`) after an `llm-agents` input bump instead.
The regeneration script is the flake app's sidecar at `modules/apps/openspec-refresh-vendored-artifacts.sh`.
