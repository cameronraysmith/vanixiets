# Tiered ceremony in jj mode

This document establishes the three-tier ceremony model that governs how much version-control apparatus a given jj-mode workstream warrants.
The doctrine is monotonic escalation: stay at the lowest tier that satisfies the work's verification needs, ascend only when a concrete trigger fires, and descend back once the trigger resolves.
Most jj work is tier 1.
Bookmark creation has a specific operational trigger (engaging the nix-flake-pr-cycle workflow with CI as the severity-raising mechanism), not a general "this work is important" intuition.
The diamond workflow is reserved for genuine multi-stream parallel work, not for solo single-stream development that happens to span several commits.

For the theoretical treatment of the diamond workflow (lattice theory, event structures, VSM mapping, four-phase recipe), see `diamond-workflow.md` in this directory.
For the operational reference on the development join entity (edit-route cycle, conflict behavior, join + wip structure, composite maintenance invariant), see `SKILL.md` in this directory.
For mode-detection context (when this document applies versus git-native or GitButler), see `~/.claude/skills/preferences-git-version-control/03-jj-mode.md`.

## Tier 1: anonymous chain on `@`

What it is: commits accumulate on `@` as an anonymous chain descending from the repository's default trunk bookmark (typically `main`).
No bookmark beyond the trunk one is created.
When the chain is ready, the trunk bookmark advances to the chain tip and gets pushed directly.

Trigger to be in this tier: default state.
Routine repo maintenance, small fixes, atomic commits each individually safe to land on the trunk, work where local `just check-fast` provides adequate verification severity.

Cost: zero ceremony.
No bookmark management, no PR, no buildbot wait, no Mergify.
Verification severity is bounded by what local checks can establish on `currentSystem`.

Operations: regular `jj describe -m "..."` + `jj new` cycle as documented in `SKILL.md`.
Push via `jj bookmark move main --to @-` then `jj git push --bookmark main`.

## Tier 2: single named bookmark

What it is: one bookmark created at a specific change on an existing anonymous chain (or at `@-`), pushed to the remote to engage the nix-flake-pr-cycle workflow.
Buildbot picks up the bookmark, runs flake checks across the declared system matrix, and the resulting PR becomes the merge gateway.
CI validation is the severity-raising mechanism — it exercises fleet coverage that local `currentSystem` checks cannot.

Trigger to enter: the work's verification severity needs exceed what local `just check-fast` provides.
Concretely, this fires when the change touches multi-platform artifacts, when the change is large enough that human review would benefit from a unified PR view, or when the change must clear the fleet-wide check matrix before reaching the trunk.
The bookmark exists *for* the PR/CI gateway, not for any other reason.

Cost: one bookmark name, one push, one PR open/monitor/ready/merge cycle.
The agent must monitor buildbot, address failures, and either trigger Mergify auto-merge or merge manually when checks pass.

Operations to enter (retroactive bookmark creation on an existing anonymous chain):

```bash
jj bookmark create <name> -r <change-id>   # or -r @- for the chain tip
jj git push --bookmark <name> --allow-new
```

Then follow `~/.claude/skills/nix-flake-pr-cycle/SKILL.md` for the canonical draft-PR / buildbot-monitor / ready / Mergify sequence.

Operations to integrate: rebase the bookmark onto trunk when ready, then either let Mergify FF-merge the PR or perform the FF merge directly.
After merge, delete the bookmark and return to tier 1 for subsequent work.

## Tier 3: diamond workflow with development join

What it is: two or more bookmarks active simultaneously, with a multi-parent `[merge]` commit merging all active chain tips and a `[wip]` commit on top where `@` resides — the canonical two-commit development join.
Per Krycho's canonical model, `[wip]` sits on top of `[merge]` so that `[merge]` stays frozen and `[wip]` serves as scratch space; see `docs/notes/development/version-control/references/krycho-jujutsu-megamerges-and-jj-absorb.md` for the canonical structure and routing recipe.
Edits in `@` (which is `[wip]`) are routed to the correct chain via `jj squash --from @ --into <chain-tip> --keep-emptied` (amend an existing chain commit), the route-and-extend recipe (`jj new -A <tip> --no-edit -m "..."` then `jj squash --from @ --into <new-change-id> --keep-emptied` then `jj bookmark move <name> --to <new-change-id>`), or `jj absorb` (auto-route by blame, preserves `[wip]` automatically).
`[merge]` is never touched by any routing operation, and `[wip]`'s description is ephemeral so no description-recovery step is required after a squash.
Each chain becomes its own PR via FF merge.
Integration is sequential rebase linearization in phase 4 (serialize).

Trigger to enter: two or more independent work streams in the same repo concurrently.
Examples include multiple beads issues within an epic being worked in parallel, a vocab refactor running alongside a peer agent's separate workstream, or parallel experiments that should compose into a coherent integrated state for validation.
A single workstream that happens to span several commits does not trigger tier 3 — that is still tier 1 or tier 2 depending on the verification needs.

Cost: routing discipline (every edit must be intentionally routed to the right chain before yielding control), editor-hang avoidance vigilance (every commit-boundary subcommand needs `-m`; see the editor-hang reference in vanixiets memory), careful bookmark and development-join maintenance per the composite maintenance invariant in `SKILL.md`.

Operations to enter (promote from tier 2 by adding a second parent to `@` and layering `[wip]` on top):

```bash
# If the new bookmark already exists at some change:
jj new <existing-bookmark> <new-bookmark> -m "join N=2: <alphabetical bookmarks, comma-separated>"
jj new @ -m "wip"   # layer [wip] on top of [merge]; @ is now [wip]

# If the new bookmark doesn't exist yet, seed it first:
jj new main -m "wip(<name>): seed chain"
jj bookmark create <new-bookmark> -r @
# then promote @ to a development join over both bookmarks, layering [wip] on top:
jj new <existing-bookmark> <new-bookmark> -m "join N=2: <alphabetical bookmarks, comma-separated>"
jj new @ -m "wip"
```

Describe `[merge]` once with the state-based convention `join N=<cardinality>: <alphabetical, comma-separated parent chain bookmarks>` (unbookmarked parents render as backtick-wrapped short change_ids), per the join + wip structure documented in `SKILL.md`; do not re-describe `[merge]` after creation, and rewrite the description in full whenever parents change so it always declares the current state.

Operations to dissolve (phase 4 serialize): each chain rebases onto an updated trunk in dependency order.

```bash
# For each chain, in dependency order:
jj rebase -b <bookmark> -d main
# Then FF-merge each PR sequentially.
```

Once all chains are linearized to the trunk and bookmarks are deleted, `@` returns to a single-parent state on the trunk — back to tier 1.

For the four-phase theoretical treatment and lattice-theoretic foundation, see `diamond-workflow.md`.
For the operational entity-level reference of the development join, see `SKILL.md`.

## Transition recipes

Tier 1 → tier 2 (retroactive bookmark on an existing anonymous chain):

```bash
jj bookmark create <name> -r <change-id>   # or -r @- for the chain tip
jj git push --bookmark <name> --allow-new
```

Tier 2 → tier 3 (add a second parent to create `[merge]`, then layer `[wip]` on top):

```bash
jj new <existing-bookmark> <new-bookmark> -m "join N=2: <alphabetical bookmarks, comma-separated>"
jj new @ -m "wip"
```

Tier 3 → tier 1 (after the diamond completes and all chains merge to trunk):

```bash
# For each chain, in dependency order:
jj rebase -b <bookmark> -d main
# FF-merge each PR, then delete the bookmark:
jj bookmark delete <bookmark>
# When all chains are integrated, @ descends from a single trunk parent — tier 1 resumes.
```

Descent is always available once the tier's trigger resolves.
Do not stay at a higher tier than the work currently warrants; ceremony has a real coordination cost.

## Workspaces are not a tier

In jj mode, jj workspaces (and equivalently git worktrees) are NOT a tier in this model.
They are not used for parallelizing related work — that is the diamond workflow's role at tier 3, accomplished via the development join in a single working copy.
Workspaces are reserved for cases the user explicitly requests workspace isolation by name in-session, with utterances naming `worktree`, `workspace`, `isolate`, `separate working copy`, or path forms like `.worktrees/X`.
Without an explicit request, all parallel work in jj mode uses the diamond workflow's development join.
See `jj-workflow/SKILL.md` "Workspace creation (explicit user request only)" for the workspace mechanics when the user does request them.
