---
linear_story_id: CAM-30
linear_story_identifier: CAM-30
linear_story_title: "Self-sovereign apm skill marketplace + reproducible nix distribution"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-30/self-sovereign-apm-skill-marketplace-reproducible-nix-distribution
linear_story_state: In Progress
linear_team: CAM
last_synced_state: In Progress
last_synced_at: 2026-06-29T18:29:04Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-06-29T16:29:00Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind" }
  - { at: "2026-06-29T18:29:04Z", transition: "Todo->In Progress", outcome: "posted", note: "T2 apply gate (first tasks.md [x]); Phase 1 spike built+verified" }
---

## Why

First-party AI-agent skills (~104) live in a flat nix-built tree symlinked into each harness, and third-party plugins are only partially vendored.
Harness-native plugin managers fetch unpinned github refs at runtime, so they are not reproducible.
Adopting apm (Agent Package Manager) as the marketplace and package format gains ecosystem-standard modularization, a lockable dependency graph with per-file content hashes, and forward-compatibility with the agentskills/agent-plugins/apm standards — without surrendering nix's immutable store-symlinked skills or its always-succeeds activation.

## What Changes

**First-party skill authoring and distribution**
- From: skills live as a flat tree under `modules/home/ai/skills/src/{core,claude}`; nix builds the tree and symlinks it into each harness.
- To: skills are authored as apm packages under `modules/home/ai/plugins/<pkg>/`; a nix derivation runs `apm install` at build time to compose them into per-harness flat trees, which nix store-pins and symlinks.
- Reason: gain apm's lockable dependency graph and ecosystem-standard packaging while retaining immutable store-symlinks and always-succeeds activation.
- Impact: non-breaking for skill consumers — flat skill names are preserved, so the ~70 `@`-autoload references in `modules/home/tools/agents-md.nix` are unchanged.

**Upstream plugin dependencies**
- From: third-party plugins are partially vendored via store-pinned Claude marketplaces in `pkgs/by-name/agent-plugins/`.
- To: first-party apm packages may declare apm dependencies on upstream plugins (e.g. superpowers), pinned by nix `fetchFromGitHub` and composed offline at the root consumer manifest, with `apm.lock` recording per-file content hashes.
- Reason: a single lockable interface for first-party + third-party composition.
- Impact: additive; the existing store-pinned marketplaces keep working until cutover.

This change is skills-only.
Hooks remain in the existing agent-specific home-manager modules; runtime `plugin:skill` namespacing is deferred; droid/factory apm-targeting is out of scope (handled via `~/.agents/skills` or retained nix fan-out).

## Capabilities

### New Capabilities

- `first-party-skill-distribution`: how first-party skills are authored as apm packages and composed by nix at build time into immutable, store-symlinked, per-harness flat trees with always-succeeds activation.
- `third-party-plugin-dependency`: how first-party apm packages declare dependencies on upstream plugins pinned by nix and composed offline at the root consumer manifest, recording per-file content hashes in `apm.lock`.

### Modified Capabilities

<!-- No existing openspec/specs/ capabilities; the change to nix's current flat-tree behavior is captured as a requirement within first-party-skill-distribution. -->

## Impact

- New source tree: `modules/home/ai/plugins/<pkg>/` (apm packages: `apm.yml`, `plugin.json`, `.apm/skills/<skill>/`), plus a committed ROOT producer `apm.yml` with a `marketplace:` block.
- Rewritten: `modules/home/ai/skills/default.nix` consumes the apm-composed `$out` per harness, preserving the codex real-file-copy workaround.
- New nix compose derivation generating a ROOT consumer `apm.yml` and running `apm install --root $out` offline (HOME/`APM_CACHE_DIR` isolated, `APM_E2E_TESTS=1`).
- New typed home-manager module (options: packages, upstream deps, targets).
- Upstream deps: superpowers (`obra/superpowers`) consumed without a fork; `openspec-schemas-superpowers-bridge` fork must add one packaging signal (`SKILL.md`/`apm.yml`).
- `flake.lock` gains/owns upstream SHAs; new `apm.lock` records content hashes; `apm_modules/` and `build/` are gitignored.
- Unchanged: `modules/home/tools/agents-md.nix` `@`-autoload references (flat names preserved); hooks in agent-specific HM modules.
