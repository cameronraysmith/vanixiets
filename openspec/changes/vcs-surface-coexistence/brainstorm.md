# Decision capture: coexisting version-control surfaces on one repository

The operator stated the requirements below in conversation on 2026-11-14, after a read-only survey of every surface that creates or uses a working tree of this repository.
This file records them as given; the `superpowers:brainstorming` dialogue was not rerun, matching the decision-capture form of `workstation-parity`.
Status words: DECIDED for what the operator settled, OPEN for everything else, and [INFERENCE] for claims nobody has verified yet.
Only C9 and C10 are DECIDED.

## Background

This repository is a colocated jj repository whose primary checkout keeps a detached git `HEAD` on the development join.
Five programs create further working trees on the same git common directory, each with its own defaults and its own cleanup, and none consults the others.
The evidence is the survey `logs/parity/vcs-surface-survey.md` (sections cited below as survey §N), read together with the fleet fragments under `modules/home/ai/plugins/agent-context-vcs*/.apm/instructions/`, the repository fragment `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/10-repository-overview.instructions.md`, the skills named in the contradictions below, and the devshell entry in `modules/devshells/default.nix:57-102`.

Observations made for this capture on 2026-11-14, read-only:

- `jj --ignore-working-copy workspace list` in the primary lists `default` only, so the thirteen names in `.jj/repo/workspace_store/index` that the survey could not resolve (survey §7, question 2) are forgotten workspaces, not live registrations.
- `../vanixiets-wv-preview-port` and `../vanixiets-wv-webkit-screenshot` (dated 2026-10-01) each hold a `.git` file naming an admin directory under `.git/worktrees/` that no longer exists, and each holds an independent `.jj/repo` directory (own `op_store` and `op_heads`) whose `store/git_target` is `../../../.git`; the survey missed both.
  The `deploy` worktree's independent jj repository the survey found has since been retired; its `.git` file remains and it has no `.jj`.
- A linked worktree's `git config --local` writes the common `.git/config`, and git 2.56.0 refuses a config write with exit 255 after about one second while another writer holds `config.lock`; 600 concurrent short writes from two trees produced no error (`logs/vcs-git-config-lock-20261114-145437.log`).

## Operator requirements

1. Keep working on a machine through a herdr server in a single jj workspace; multiple jj workspaces only in rare situations.
2. An omnigent-based omp agent must never hit a significant compatibility bug when it creates a git worktree and runs `direnv allow` in it to generate the repository-local agent context.
3. ovnfs stays packaged but is not enabled in the near term.

## Contingencies

### C1 One primary jj workspace per machine — OPEN as practice, given as requirement 1

The primary checkout is the only jj workspace in use on stibnite today (observation above).
Extra jj workspaces are rare and short-lived; the forgotten index entries show they have been made and forgotten.

### C2 Omnigent worktree plus `direnv allow` must just work — OPEN as to mechanism, given as requirement 2

Every devshell write is either per-tree (the generated `AGENTS.md`, `CLAUDE.md` and `.agents/` under the tree's own root, found by walking up to `apm.yml` beside `.git`, `default.nix:58-65`) or identical from every tree (the absolute common-dir `core.hooksPath`, `default.nix:97-98`).
Unverified edges: concurrent devshell entry from two trees racing the `.git/config` lock, since the `git config` call is unguarded (`default.nix:98`) and the git-hooks.nix shellHook that runs first writes its own relative value; and the context tier test `[[ -e $HOME/.claude/CLAUDE.md ]]` (`default.nix:66`), which selects the full composition for an account whose private home lacks a user-level context file, as an Omnigent worker account's may [INFERENCE].
Omnigent workers with private homes cannot reach `/Users/crs58/projects/vanixiets` (survey §4), so today only an omnigent host running as `crs58` creates worktrees here [INFERENCE].

### C3 Shared settings and hooks are identical from every tree — OPEN as to mechanism

`git config --local` from any linked worktree writes the one common config (observation above), and `mergify stack setup` installs hooks into the one common hooks directory, so a tree-specific value written there breaks every other tree.
The current hook path is written absolute for exactly this reason (`default.nix:89-96`).

### C4 Five tree creators share one git common directory — OPEN

wt, omnigent, Claude Code's `jj-worktree-create` hook, Google Antigravity and ovnfs (survey §2, §7).
Any rule must hold at the git-ref level, not per tool (survey constraint 1).

### C5 Global `fetch.prune=true` — OPEN

`git config --global --get fetch.prune` returns `true`, so every plain `git fetch` prunes, which `jj-version-control` names destructive against a jj primary (survey §1).
Omnigent's `_ensure_base_resolvable` runs a plain `git fetch` (survey §4).
No damage was found on 2026-11-14.

### C6 Every creator's default base is the primary's join — OPEN

Claude's hook, omnigent with no base and ovnfs's jj workspace all start from the primary's `HEAD` or the parents of `@`, which is the development join, so a new tree carries other chains' unpublished work (survey constraint 6).

### C7 jj sees worktree commits only on import — OPEN

git-worktree and omnigent commits enter jj only when the primary imports refs, as bookmarks; ovnfs git commits never enter until applied or fetched (survey constraint 2).
Ownership must therefore be expressible both as jj changes and as git branches.

### C8 Non-colocated jj workspaces are invalid in a flake repository — OPEN as assumption

Flake evaluation resolves the root through git, and a non-colocated jj workspace loses the revision (fleet fragment 040 l.11).
ovnfs creates exactly such workspaces (survey §3), with a private gitdir that may still save evaluation [INFERENCE: untested].

### C9 ovnfs is never enabled in the near term — DECIDED 2026-11-14

`programs.omp.ovnfs.enable` stays `false` everywhere and `pkgs/by-name/ovnfs` stays packaged.
The omp ovnfs prompt that tells agents to use `ovnfs new` never reaches an agent while the option is off (survey §3).

### C10 Rebase policy — DECIDED 2026-11-14

Unpublished chains are rebased freely.
A chain is rebased onto `main` once before its first push.
A published chain is rebased only when it conflicts with `main` or the merge queue fails it.
Rationale: gitea-mq tests every pull request on the tip of `main` and skips that run only when the pull request already contains the tip (`skipQueueIfUpToDate = true`, `git-stacked-pr-integration` l.41; gitea-mq `README.md:29-36`), so rebasing a published chain only to stay current buys nothing and churns review and CI.

### C11 Stray independent jj repositories must be detected — OPEN as to mechanism

One was found in the `deploy` worktree and retired; two more are recorded above.
An independent jj repository on the shared git directory keeps its own operation log while sharing refs, so each repository imports the other's exports as foreign moves or deletions (survey constraint 4) [INFERENCE].

## Contradictions between instruction sources

The survey found six (survey §6); the recommended winner is recorded, none is decided.

1. omp's ovnfs prompt says agents MUST use `ovnfs new`; the fleet fragment says stay on the join and ask first, and calls non-colocated jj workspaces never valid. Recommended winner: the fleet fragment, already moot under C9.
2. `wt-switch-create` says Worktrunk's `WorktreeCreate` hook runs `wt switch --create`; the live hook is `jj-worktree-create`, which makes `.claude/worktrees/<name>` on branch `worktree-<name>`, and the skill's `git stash push -u` advice breaks the no-stash rule. Recommended winner: the live hook and the fleet fragment.
3. `using-git-worktrees` creates `.worktrees/` trees with plain `git worktree add`; the fleet fragment requires `wt switch --create`. Recommended winner: the fleet fragment.
4. The git-worktree gate hook says jj is unavailable inside a worktree, yet independent jj repositories have been found inside worktrees. Recommended winner: neither text; the gate's claim must become true (detection, C11) or be reworded.
5. `mergify-stack` tells authors to `mergify stack sync` before new work and to `git stash -u`; the fleet forbids stash in a jj working copy and, under C10, rebasing published chains to stay current. Recommended winner: C10 and the fleet fragment.
6. The diamond remote-advance recipe rebases every chain root in `roots(<base>@origin..@)`, published chains included. Recommended winner: C10, which excludes published chains.

## Gaps

- Keeping unpublished work current exists only as the jj recipe; nothing covers git worktrees, omnigent worktrees or ovnfs checkouts.
- First-push timing exists only as role contracts; nothing says when an independent git-worktree author pushes (C10 now says: after one rebase onto `main`).
- Nothing excludes published or remote-tracked bookmarks from the remote-advance recipe (C10 now does, in policy only).
- No ownership rule forbids rewriting another agent's commits, deleting another agent's branch (omnigent session delete runs `git branch -D`), or a pruning fetch.
- No single tool enumerates every tree: `git worktree list`, `jj workspace list`, `ovnfs ls`, omnigent's session records and a scan for stray `.jj/repo` directories are all needed (survey constraint 11), and the orphaned `vanixiets-wv-*` trees appear in none of the first four.

## Scope notes

This change is discovery only: it records assumptions, requirements and the tests to write first.
No guidance or tooling changes until those tests exist and fail where expected.
