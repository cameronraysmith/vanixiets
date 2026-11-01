---
description: Task-dispatch isolation defaults to the diamond join; worktree creation is ask-gated with exclusive branch ownership and return-by-ref, and jj-state-protecting prohibitions on force-checkout, branch deletion, prune, and stash.
---

## Worktree interop and external frameworks

Subagent dispatch in jj-mode repositories omits the `isolation` parameter by default, because the diamond development join already supplies the isolation; setting `isolation: "worktree"` raises an ask and is warranted only when the subagent genuinely needs its own filesystem tree.
This default overrides the worktrunk skill's recipe of one worktree per parallel subagent.

Worktree creation is ask-gated: answer affirmatively only when a separate filesystem tree is itself the point, including a tree pinned at a base to show one change failing there and passing with it while other work sits in the join; otherwise stay on the development join.
In a flake repository that tree is a colocated jj workspace when the work will be committed with jj, and a git worktree when it will be committed with git; a non-colocated jj workspace is never valid there, because flake evaluation in it loses the revision.
Create the jj workspace with `jj workspace add --name <name> --revision 'trunk()' <path>` (jj 0.46.0 or later colocates it by default) and never pass it `--ignore-working-copy`; remove it with `jj workspace forget <name>` and then delete the directory, never with `wt remove`.
Create the git worktree with `wt switch --create <branch> --no-cd`, never a detached `git worktree add`, so the tree has a named branch that `wt list` ties to its pull request and `wt remove` cleans up with the branch.
The discipline is exclusive branch ownership — a branch belongs to the jj primary or to one worktree, never both — and return-by-ref: commit in the worktree, integrate by ref in the primary.
The primary's HEAD stays detached throughout; never reattach it, force-checkout, delete branches, `git fetch --prune`, or `git stash` in a jj working copy.
An external agent framework such as firstmate gets its own clone rather than a symlink to a working copy we also use, because its fleet-sync runs exactly the operations forbidden above.
Full mechanics and recovery: the `jj-version-control` skill §"Worktree interop".
