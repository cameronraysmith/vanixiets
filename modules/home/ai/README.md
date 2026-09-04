---
title: AI agent configuration
created: 2026-08-25
---

## AI agent configuration

Home-manager aspects for AI coding agents: the harnesses themselves, the skill corpus they load, and the context files they read.

Two boundaries here account for most wrong edits in this subtree, and neither is visible from a directory listing.

**Generated outputs versus their generators.** `../tools/agents-md.nix` is the single source for every user-level agent context file — `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, and the rest, plus pi's `context` option, which is also what serves atomic through its legacy scan. Those destination files are nix-managed outputs. Edit the generator, never the generated file.

**Source versus delivered.** Skills are authored under `plugins/<group>/.apm/skills/<skill>/`.
Claude Code, OpenCode, Droid, and Hermes receive read-only nix-store symlinks.
Codex and Pi consume writable real-file copies under `~/.agents/skills`, which are materialized because Codex v0.135.0 skips symlinked skill-file leaves.
Delivered content changes only after a build, so it can retain pre-change content indefinitely after the source is edited, and a nix store path reports a 1970 mtime whatever it contains.
Verify an edit against the source tree and treat delivered content as generated output.

## Children

- `plugins/` — the first-party skill corpus, eighteen apm packages; indexed by its own README.
- `skills/` — composition and delivery of the corpus to each harness's skill directory.
- `openspec/` — the OpenSpec CLI, its schema bundles, and vendored artifact refresh.
- `agent-settings.nix` — settings shared across harnesses.

Harness-specific modules, each configuring one agent's settings, hooks, MCP servers, and wrappers: `atomic/`, `claude-code/`, `codex/`, `firstmate/`, `omp/`, `opencode/`, `pi/`.

Supporting tools these harnesses invoke: `cognee/` (memory layer), `moshi/` (session multiplexing), `hunk/` and `tuicr/` (interactive diff review), `worktrunk/` (worktree management).
