---
linear_story_id: CAM-102
linear_story_identifier: CAM-102
linear_story_title: "Make jj workspaces, git worktrees and ovnfs checkouts coexist safely"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-102/make-jj-workspaces-git-worktrees-and-ovnfs-checkouts-coexist-safely
linear_story_state: In Progress
linear_team: CAM
linear_project: pi-agent-environment
last_synced_state: In Progress
last_synced_at: "2026-11-14T22:30:44Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-14T20:08:59Z", transition: "Backlog->Todo", outcome: "posted", note: "Project d7d743a19249 renamed to Agent environment; issue CAM-102 created in Todo with description seeded from proposal.md; state, project and labels confirmed by read-only view" }
  - { at: "2026-11-14T22:30:44Z", transition: "Todo->In Progress", outcome: "posted", note: "apply gate: tasks 1.1, 1.2 and 1.7 checked; state confirmed by read-only view" }
---

## Why

Five programs create working trees on this repository's one git common directory (wt, omnigent, Claude Code's `jj-worktree-create` hook, Google Antigravity and ovnfs), each with its own default base, cleanup and fetch behaviour, while the operator integrates every chain in one jj primary.
The survey of 2026-11-14 (`logs/parity/vcs-surface-survey.md`) found six contradictions between the instruction sources agents read, four guidance gaps, a pruning global fetch setting, default bases that leak unpublished work, and independent jj repositories sharing the git directory unnoticed.
Before any guidance or tooling changes, the fleet needs the assumptions and requirements written down with their evidence, and tests that show where today's behaviour breaks them.

## What Changes

This change is discovery: it records world assumptions, requirements and the tests to write first, and decides only the two items the operator settled.

**Recorded contingencies**
- From: the constraints live in a survey log, in conversation, and implicitly in a devshell hook.
- To: C1 to C11 are world assumptions with evidence and violation conditions, or requirements with the tests that would show them failing.
- Reason: guidance and tooling written later must cite what they rely on.
- Impact: documentation only.

**Rebase policy (DECIDED)**
- From: the diamond remote-advance recipe rebases every chain root, published ones included, and `mergify-stack` advises syncing before new work.
- To: unpublished chains rebase freely, once onto `main` before the first push, and published chains only on conflict or merge-queue failure.
- Reason: the merge queue tests every pull request on the tip of `main`, so a rebase only to stay current buys nothing.
- Impact: guidance only, applied by later tasks.

**ovnfs stays off (DECIDED)**
- From: ovnfs is packaged and its omp option defaults to off, with nothing recording that this is intended.
- To: ovnfs stays packaged and is enabled nowhere in the near term.
- Reason: its checkouts are non-colocated jj workspaces with private refs, which the fleet treats as invalid in a flake repository.
- Impact: none to any closure.

## Capabilities

### New Capabilities

- `vcs-surface-coexistence` [behavioral]: the operator works from one primary working tree per host; an agent that creates a working tree and allows its devshell gets working agent context without breaking any other tree; shared repository state reads the same from every tree; unpublished work is owned by one agent and expressible both as jj changes and as git branch names; stray history stores are detected; and chains are rebased under the decided policy.
- `vcs-surface-coexistence-interface` [interface]: ovnfs is packaged and its omp option is enabled in no evaluated home.

Trust boundary of `vcs-surface-coexistence-interface`: its property holds of evaluated home-manager configurations.
It does not establish that no person runs the packaged `ovnfs` binary by hand, or that no ovnfs checkout exists on a host.

### Modified Capabilities

- `world-assumptions` [world]: adds designations for the vocabulary of working trees (working tree, primary working tree, tree creator, shared repository state, agent context, devshell entry, chain, development join, base, main, unpublished work, published work, rebase, conflict, pruning fetch, history store, stray history store, drift report) and adds A96 (one primary working tree per host), A97 (five tree creators share one git common directory), A98 (the global fetch setting prunes), A99 (every creator's default base is the development join), A100 (jj learns of worktree commits only on import), A101 (a non-colocated jj workspace loses the revision flake evaluation needs), A102 (an independent jj repository can share the git directory unnoticed), A103 (a linked worktree's local config write lands in the shared config, and a held config lock fails it), and A104 (the merge queue tests on the tip of the target and skips only when already up to date).

## Impact

Documentation only: `openspec/changes/vcs-surface-coexistence/`.
Later tasks name the code they would touch: the fleet fragments under `modules/home/ai/plugins/agent-context-vcs*/.apm/instructions/`, the repository fragment `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/10-repository-overview.instructions.md`, the first-party skills `jj-version-control`, `git-stacked-pr-integration` and `worktree-sparsity-eval`, composition-time overrides for the vendored skills `using-git-worktrees`, `mergify-stack`, `worktrunk` and `wt-switch-create`, `modules/devshells/default.nix`, and new read-only tooling.
No host's closure changes, and no Linear binding is created.
