---
description: vanixiets AI agent skills architecture — apm packaging, the compose-and-deliver pipeline, and where issue tracking actually lives.
---

## Skills architecture

Agent skills are packaged as apm marketplace plugins.
The source of truth for every first-party skill is `modules/home/ai/plugins/<group>/.apm/skills/<skill>/SKILL.md`.
The corpus size is computed, not maintained as a number in prose: a hand-written count has already drifted across this repository's own documents more than once, so treat any specific figure you read as a snapshot, not a fact, and recompute it with a glob such as `fd --hidden SKILL.md modules/home/ai/plugins/*/.apm/skills` when you need a current total.
Each `<group>/` carries an `apm.yml` and a `plugin.json` manifest beside its `.apm/skills/` tree, and the marketplace manifest is `.github/plugin/marketplace.json`.

At build time `pkgs/by-name/apm-skills-compose/` composes those packages, plus remote apm dependencies resolved offline, into a flat skill tree.
`modules/home/ai/skills/{compose.nix,default.nix}` re-globs that tree and delivers it through home-manager symlinks to each harness's skills directory.
The delivered `~/.claude/skills/<skill>/SKILL.md` is a read-only Nix store symlink, so edits belong in the plugins source in this repository.

`modules/home/ai/` also holds per-harness home-manager modules for hooks, MCP servers, settings, and wrappers, one directory per agent tool.
Claude Code cloud sessions are created and steered with `nix run .#claude-cloud-session` and the `sandbox-claude-cloud` skill; `modules/home/users/claude-sandbox/README.md` covers this repository's environments and setup step, and why transcript publishing is disabled (the repository is public).

## Instructions packages are a separate primitive

The `agent-context-*` packages, this one included, ship only `.apm/instructions/*.instructions.md` fragments and carry no `.apm/skills/` directory.
apm discovers and renders these into a compiled `AGENTS.md` independently of the skills pipeline described above; a package that mixed both primitives would still need the skills declaration in `plugin.json` for its skills half.
See "Agent context composition" in this package for how these fragments reach both the repository-root `AGENTS.md` and the user-level harness surfaces.

## Issue tracking

Issue tracking for this repository runs through Linear and OpenSpec, not a local database: there is no `.beads/` directory in this tree, so a `bd status` invocation has nothing to read.
The `beads-issue-tracking-and-session-workflow` apm package still exists and still ships its session-workflow skills (`session-orient`, `session-plan`, `session-checkpoint`, `session-review`, `stigmergic-convention`); only the dolt-backed issue database it once also covered is gone.
