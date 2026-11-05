---
description: vanixiets agent context composition — how the generated AGENTS.md and CLAUDE.md come to exist, and where to actually make an edit.
---

## Agent context composition

The repository-root `AGENTS.md` and `CLAUDE.md` are generated files, git-ignored, and not committed.
The source of truth for their content is the committed instruction fragments under `modules/home/ai/plugins/agent-context-*/.apm/instructions/` — this package's own fragments plus its sibling `agent-context-core`, `agent-context-vcs`, and `agent-context-vcs-jj` packages.
Editing the generated `AGENTS.md` directly is pointless: the next composition run overwrites it, discarding the edit without warning.
The generated file carries a source comment above each section identifying the exact fragment that section came from, so the correction always belongs in that fragment, not in the generated output.

Two `just` recipes drive the two consumers of these same fragments.
`just agents-context` composes the instruction fragments into the repository-root `AGENTS.md` (and the `CLAUDE.md` pointer alongside it).
You rarely need to run it: entering the devshell (direnv or `nix develop`) recomposes both files whenever `AGENTS.md` or `CLAUDE.md` is missing or the composition inputs changed since the last run, so a fresh clone or jj workspace gets them on first entry and a fragment edit reaches them on the next.
The inputs are this tier's fragments, the `compilation:` block of the root `apm.yml`, and the compiler's own store path, recorded as a content hash in the git-ignored `.agents/.context-inputs-sha256`; an unchanged entry runs only shell builtins, and a failed compile prints a warning instead of failing the shell.
`just agents-install` materializes this repository's own apm skill packages from the committed `apm.lock.yaml` into a git-ignored `.agents/skills/` tree, for clones on machines without the home-manager profile.
Where home-manager already delivers the skills, it refuses unless given `--shadow-user-skills`, because agents prefer the repo-local tree: a tree installed from a 19-day-old lock once shadowed the current Nix-delivered skills and agents followed an outdated `jj-version-control`.

The same fragments are also composed a second way, by Nix, into the eight user-level harness surfaces (`~/.claude/CLAUDE.md` and its counterparts for the other agent tools); that composition is unrelated to this repository's own `AGENTS.md` and is documented in `agent-context-core`, not here.
