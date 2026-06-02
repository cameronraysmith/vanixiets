# HIL apply-phase isolation under jj mode

The HIL mode delegates to opsx and superpowers via the superpowers-bridge.
The bridge apply node reaches superpowers:using-git-worktrees, which resolves to a raw git worktree add.
In this jj-mode environment that surface is hook-blocked, so the router carries isolation guidance rather than assuming git worktree add succeeds.

This file owns the isolation guidance for the HIL apply phase.
The board states and gates live in references/board-and-gates.md; the per-mode entry criteria live in references/execution-modes.md.

## Why git worktree add does not apply here

The repository runs jujutsu in colocated mode.
The harness denies the worktree-creating tool surfaces under jj: EnterWorktree and ExitWorktree are denied, Task dispatches requesting worktree isolation are denied, and the raw git worktree add is denied unconditionally.
superpowers:using-git-worktrees already prefers the harness's native worktree tool over git worktree add and its step 0 detects existing isolation, so under jj the git-worktree path does not apply and the reader is directed to the jj substitute.

## The jj diamond development join as the worktree substitute

The jj diamond development join is the worktree substitute.
Parallel chains of work share a single working copy rather than separate worktrees: a multi-parent working-copy commit merges the active chains, edits route as new commits onto a chain, and jj auto-rebases the join and the working-copy commit after each routed commit.
Where the superpowers worktree skill would create an isolated worktree per task, the diamond routes the unit of work onto its chain inside the one working copy, so isolation is achieved without any worktree creation.

## The CLAUDE_JJ_WORKSPACE_ISOLATION hatch

An env-gated hatch exists as an alternative to the diamond.
With CLAUDE_JJ_WORKSPACE_ISOLATION set, the worktree-create hook early-exits to allow before the deny branch, making the parent directory and adding an in-tree jj workspace rather than a git worktree.
This is the jj-workspace escape for a unit of work that genuinely warrants its own checkout, a tangling-writers situation, a long build, or an independent stream, where the diamond join is the wrong tool.
The diamond join and the jj workspace nest: the workspace is for an isolated checkout, the diamond is for integrating chains.

## The reconciliation is an apply-gate open point

The choice between the diamond development join and the CLAUDE_JJ_WORKSPACE_ISOLATION jj-workspace hatch is not decided in this skill.
It is confirmed at the apply gate per the change's Risks and Open Questions, and it is input to a separate jj-policy follow-up.
The router bakes in no git worktree add and asserts no single isolation mechanism; it names both candidates and directs the apply executor to confirm the choice at the apply gate.

## Orchestrator-routed commits and no autonomous PR

Commits during the HIL apply phase are orchestrator-routed onto the chain.
The orchestrator routes each commit as a new commit onto the unit's chain inside the shared working copy, rather than the bridge's subagent-driven auto-commit-and-PR flow running unattended.

Integration is jj-native and user-gated.
The bridge's finishing-a-development-branch step would open a PR; under jj the chain is instead linearized onto main by sequential rebase at completion, and that integration is a user-gated decision.
There is no autonomous PR: the router does not open a pull request as a side effect of the apply phase.
A PR into the monorepo remains one realization of the terminal artifact when the human elects the PR-when-warranted path, but it is never an automatic consequence of reaching In Review.
