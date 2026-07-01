---
name: preferences-comment-cleanup
description: Uncomment-driven workflow for auditing and removing noise comments while preserving load-bearing markers, as the operational arm of the code-comments policy. Load when you remove comments, strip comments, uncomment or declutter code, run a comment cleanup, or systematically prune noise comments across a subtree.
---

# Comment cleanup

## Scope

This skill is the operational enforcement arm of the code-comments policy defined in `~/.claude/skills/preferences-style-and-conventions/SKILL.md` §"Code comments"; it does not restate that policy but drives it over real trees.
It is a workflow sibling to `preferences-git-history-cleanup`, and like it, a comment-only cleanup is a legitimate standalone change.

## The tool: uncomment

The workflow is built on this repository's `uncomment-bin` package (`pkgs/by-name/uncomment-bin`), a tree-sitter comment remover that is deny-by-default: it removes every configured comment node unless a preservation rule matches.
It offers `--dry-run` and `--dry-run --diff` (no writes), a `~keep` always-preserve escape hatch, case-sensitive substring `preserve_patterns` (global merges into per-language), and it emits a "removed N potentially important comment(s)" warning on each run.

## Why uncomment is never run unattended

uncomment cannot be a repo-wide mutation engine: it intrinsically deletes hand-written "why" prose — the exact rationale category the policy protects — and misses `# SAFETY:`, `# -*- coding: -*-`, and any license or managed-block marker past the first few lines.
Its language list is not an allowlist (shell, yaml, hcl, make all get processed), and there is no ignore-glob config key, so committed-but-generated or vendored trees must be excluded by path, one subtree at a time, with a human-plus-agent classification gate between census and apply.

## The workflow

Operate on one subdirectory tree at a time rather than the whole repository, e.g. `uncomment modules/apps --dry-run --diff`.

### 1. Census

Take a complete candidate-removal inventory without touching files, and note the reported "potentially important" count as the seed for classification.

```bash
uncomment modules/apps --dry-run --diff
```

### 2. Classify

Fan out the candidate removals across parallel agents, sorting each into `mandatory-keep`, `essential-keep`, or `slop-cut`, seeded by uncomment's important-warnings and the `preferences-style-and-conventions` §"Code comments" load-bearing carve-out list.
Adversarially verify every proposed cut before applying, treating a wrong deletion of a rationale comment as high-severity.

### 3. Apply

Delete only confirmed slop, in place; essential and mandatory comments never move, so there is no lossy strip-then-restore round trip.

### 4. Commit

Group the applied cuts by subsystem into a small number of atomic commits; never commit one comment per commit.

## Safety gates

Exclude vendored, generated, and upstream-mirrored trees by path, since uncomment has no ignore-glob and its language list is not an allowlist.
Watch for cross-branch file collisions with any active VCS chains, and keep dry-run-first discipline before every apply.
A hardened starting config ships beside this skill at `~/.claude/skills/preferences-comment-cleanup/uncommentrc.toml`; it preserves the license/SPDX headers, linter and formatter pragmas, code-generation markers, and `SAFETY:` comments that uncomment's built-ins miss past the first few lines.
Copy it to the target repository root as `.uncommentrc.toml` and treat it as a targeted-assist config for a specific run, not a standing repo-wide policy.

## Cross-links

The owning policy this skill enforces is `~/.claude/skills/preferences-style-and-conventions/SKILL.md` §"Code comments".
For the sibling cleanup workflow see `preferences-git-history-cleanup`; for severity grading and adversarial verification of proposed cuts see `preferences-validation-assurance`; for the classification fan-out see `dispatching-parallel-agents` and `preferences-workflow-orchestration-algebra`; and the tool itself is this repository's `uncomment-bin` package at `pkgs/by-name/uncomment-bin`.
