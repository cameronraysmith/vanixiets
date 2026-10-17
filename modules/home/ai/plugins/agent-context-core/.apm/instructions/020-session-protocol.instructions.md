---
description: Pre-action assessment checklist for non-trivial requests covering workflow-DAG readiness, ambiguity, local source resolution, and decomposition approval.
---

## Session protocol

Before acting on any non-trivial request, pause to assess:

1. Is my context optimally primed to design a workflow DAG of subagent Tasks?
2. Are there ambiguities requiring clarification before I proceed?
3. Would local access to external source code or documentation improve this work?
   Whenever a repository is named, resolve it to a local path before reasoning about it: resolve the org first, then route by authorship — repositories we maintain live under `~/projects/<repo>/`, repositories we only read live under `$(ghq root)/<host>/<org>/<repo>/`, which is `~/ghq` by default; on a host with a shared reference tree `~/ghq` links to that tree, so `ghq list -p` prints the shared root.
   A reference copy may be read-only: update it with `ghq-sync -u <path-or-name>` (add `--tags` for every tag), never with git inside it, and clone it into `~/projects` to change it.
   The full lookup procedure, on-miss acquisition, and the `(see local)` marker directive live in the `dependency-source-acquisition` skill.
4. Should I present my task decomposition for approval before dispatching?

If any answer is "yes" or "uncertain," pause and ask rather than proceeding with assumptions.

Before working in a directory, or before asserting how a directory or its subtree behaves, read the nearest enclosing `README.md`.
It carries that directory's contract and hazards, and a branch-level one indexes its children.
We keep no separate agent-facing documentation: there is user-facing documentation, development documentation, and this local tier, and everything an agent needs is therefore something a human reads.
Do not create per-directory agent instruction files; a stub existing only for agents is the thing that arrangement avoids.

When Session Protocol is invoked explicitly, externalize your assessment proportional to what you find.
If the task is straightforward with no ambiguities, a brief acknowledgment suffices.
If any question surfaces considerations, state them and how they affect your approach.
The goal is surfacing substance, not merely demonstrating procedure.
