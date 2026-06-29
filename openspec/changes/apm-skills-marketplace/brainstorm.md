<!--
Raw capture of the apm-skills-marketplace design exploration.
Decision-log format: background -> decision chain Q1-Qn -> design trade-offs.
design.md reorganizes this content into structured sections; do not copy this file into design.md.
-->

# Brainstorm: apm-skills-marketplace

## Background

The fleet's first-party AI-agent skills (~104 total: 93 under `modules/home/ai/skills/src/core`, 11 under `src/claude`) are managed as a flat tree.
Nix builds that tree into the store and symlinks it into each harness: `~/.claude/skills`, `~/.factory/skills`, `~/.config/opencode/skill`, `~/.hermes/skills`, and `~/.agents/skills` for codex (via a real-file copy, because codex skips symlinked `SKILL.md` leaves).
Third-party plugins are partially vendored via store-pinned Claude marketplaces in `pkgs/by-name/agent-plugins/`.

The harness-native plugin managers (Claude Code's marketplace) are not reproducible when they fetch unpinned github refs at runtime.

The goal is to make this repo a self-sovereign apm (Agent Package Manager) marketplace and refactor the first-party skills into apm packages.
This gains (a) ecosystem-standard modularization, (b) a lockable dependency graph where first-party packages can depend on upstream plugins (e.g. superpowers) with per-file content hashes, and (c) forward-compatibility with the agentskills/agent-plugins/apm standards through one interface.
This must happen WITHOUT giving up nix's two load-bearing properties: immutable store-symlinked skill files and fully-declarative, always-succeeds activation.

## Decision chain

### Q1 — When does apm run: at activation or at build time?

Two candidate execution models were considered.

Option A: run apm install at ACTIVATION. Home-manager generates `~/.apm/{marketplaces.json,apm.yml,config.json}` and an activation hook runs `apm install -g`.
REJECTED for three independent reasons.
First, `apm install --global` writes real files into client dirs but hard-ERRORS when a skill destination is a symlink or resolves outside `$HOME` (`skill_integrator` `PathTraversalError`) — which is exactly what our home-manager store-symlinks are.
Second, an imperative install at activation can fail on network outage or apm-schema churn, regressing the always-succeeds `darwin-rebuild` invariant.
Third, it yields mutable copies, losing immutability.

Option B1: apm as a BUILD-time composer that nix consumes. apm runs only inside a nix derivation; nix store-pins the output and symlinks it; apm never runs at activation.
CHOSEN.
This preserves immutability and always-succeeds activation while gaining apm's dependency graph, lock file, and multi-harness fan-out.

Decision: B1 (build-time composer).

### Q2 — Skill namespacing: flat names or runtime plugin:skill?

apm has two output modes.
`apm install` deploys skills FLAT / merged (bare names, no `plugin:` prefix).
A Claude `marketplace.json` plus Claude's native loader yields runtime `plugin:skill` namespacing, but it is Claude-only and carries no apm dependency graph.

Decision: choose FLAT (the `apm install` path).
Skills stay at flat `~/.claude/skills/<name>`, which requires NO rework of the ~70 absolute `@`-autoload skill references in `modules/home/tools/agents-md.nix`.
Runtime `plugin:skill` namespacing is explicitly DEFERRED — a separate Claude-only marketplace layer if ever wanted.

### Q3 — Who owns the upstream version pins: nix or apm?

Option B1: nix owns upstream version pins via `fetchFromGitHub` rev+hash recorded in `flake.lock`.
Option B2: `apm.yml` carries `#commit` pins resolved by a fixed-output derivation.

Decision: nix owns the pins (B1).
`apm.lock` records per-file content hashes; `flake.lock` owns the upstream SHAs.

## Design trade-offs and consequences

The chosen architecture (build-time apm compose, flat namespacing, nix-owned pins) trades away two things relative to the rejected activation-time model: runtime `plugin:skill` namespacing and apm's own imperative client integration.
In exchange it keeps both load-bearing nix properties intact.

The compose runs fully offline and deterministically: local-path dependencies skip apm's git-fetch code path, so no git tag is required and the resolve+compose has no network dependency.
The only nondeterminism is `apm.lock`'s `generated_at` timestamp, which is stripped / not harvested.

"Extending" an upstream plugin like superpowers is additive co-shipping (same-name collisions resolved by precedence / `--force`), because apm has no patch/override mechanism — declarative layering is not available.

Known constraints surfaced during exploration, to be carried into design:
- Only the ROOT manifest may declare local-path deps; a remotely-fetched parent's local-path dep is rejected — so the compose must happen at the root consumer manifest.
- superpowers (`obra/superpowers`) is auto-detected by apm as a `MARKETPLACE_PLUGIN` via its `.claude-plugin/` — no fork needed.
- The `openspec-schemas-superpowers-bridge` fork is NOT apm-installable as-is (schema.yaml + templates/ only, no `SKILL.md` / `.claude-plugin/` / `apm.yml`); the fork must add ONE packaging signal.
- droid/factory is NOT an apm target (the targets enum lacks it).
- Hooks are NOT supported at user scope for opencode/openclaw/hermes (supported for claude/codex/gemini), so hooks stay in the existing agent-specific home-manager modules and are out of scope for this skills-only change.
