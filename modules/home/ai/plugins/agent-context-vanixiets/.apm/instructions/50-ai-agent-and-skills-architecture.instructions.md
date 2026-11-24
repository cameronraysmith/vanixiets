---
description: vanixiets AI agent skills architecture — apm packaging, the compose-and-deliver pipeline, and where issue tracking actually lives.
---

## Skills architecture

Agent skills are packaged as apm marketplace plugins.
The source of truth for every first-party skill is `modules/home/ai/plugins/<group>/.apm/skills/<skill>/SKILL.md`.
The corpus size is computed, not maintained as a number in prose: a hand-written count has already drifted across this repository's own documents more than once, so treat any specific figure you read as a snapshot, not a fact, and recompute it with a glob such as `fd --hidden SKILL.md modules/home/ai/plugins/*/.apm/skills` when you need a current total.
Each `<group>/` carries an `apm.yml` beside its `.apm/` tree and no other manifest; `.github/plugin/marketplace.json` (apm), `.claude-plugin/marketplace.json` (Claude) and `skills.sh.json` (`npx skills`) are generated from the `apm.yml` files by `just agents-marketplace`, never edited by hand, and the `skills-marketplace-drift` check fails until the committed three match the generator.
The marketplace supports apm 0.38 and later only; older apm may install a group yet deploy none of its skills.

At build time `pkgs/by-name/apm-skills-compose/` composes those packages, plus remote apm dependencies resolved offline, into a flat skill tree, and checks it against the committed index `skills.json`.
After a deliberate remote ref, pin or apm bump the build fails naming each remote skill whose hash moved; review those skills, then `just agents-skills-index` regenerates the index.
`modules/home/ai/skills/{compose.nix,default.nix}` re-globs that tree and delivers it through home-manager symlinks to each harness's skills directory.
The delivered `~/.claude/skills/<skill>/SKILL.md` is a read-only Nix store symlink, so edits belong in the plugins source in this repository.

`modules/home/ai/` also holds per-harness home-manager modules for hooks, MCP servers, settings, and wrappers, one directory per agent tool.
Diff review uses tuicr (`modules/home/ai/tuicr/` and the `tuicr` skill); hunk and its `hunk-review` skill were removed, and jj diffs page through delta.
Claude Code cloud sessions are created and steered with `nix run .#claude-cloud-session` and the `sandbox-claude-cloud` skill; `modules/home/users/claude-sandbox/README.md` covers this repository's environments and setup step, and why transcript publishing is disabled (the repository is public).
Past agent sessions are queryable read-only: `nix run .#obs-query` for SQL and full-text search over the `agent` database on magnetite, and `nix run .#langfuse-query` for trace trees, sessions and cost in Langfuse Cloud; "Querying agent sessions" in `packages/docs/src/content/docs/development/operations/fleet-observability.md` says which to use.

## Instructions packages are a separate primitive

The `agent-context-*` packages, this one included, ship only `.apm/instructions/*.instructions.md` fragments and carry no `.apm/skills/` directory.
apm discovers and renders these into a compiled `AGENTS.md` independently of the skills pipeline described above.
See "Agent context composition" in this package for how these fragments reach both the repository-root `AGENTS.md` and the user-level harness surfaces.

## Issue tracking

Issue tracking for this repository runs through Linear and OpenSpec, not a local database: there is no `.beads/` directory in this tree, so a `bd status` invocation has nothing to read.
The `beads-issue-tracking-and-session-workflow` apm package still exists and still ships its session-workflow skills (`session-orient`, `session-plan`, `session-checkpoint`, `session-review`, `stigmergic-convention`); only the dolt-backed issue database it once also covered is gone.
