## Context

This repository is a colocated jj repository.
The primary checkout at `/Users/crs58/projects/vanixiets` keeps a detached git `HEAD` on the development join, and the operator and agents working through a herdr server integrate every active chain there.
Five tree creators share its git common directory (survey §2, §7):

- wt: `wt switch --create <branch>`, default path `../vanixiets.<branch>`, `wt remove` deletes merged branches and `-D` force-deletes.
- omnigent: `git worktree add -b <branch> <path> [base]` under `../vanixiets-worktrees/`, base defaulting to `HEAD`, a plain `git fetch` when the base is missing, and `git branch -D` on session delete with `delete_branch=true`.
- Claude Code: the `WorktreeCreate` hook `jj-worktree-create` makes `.claude/worktrees/<name>` on branch `worktree-<name>` from the primary's `HEAD`.
- Google Antigravity: `~/.gemini/antigravity/worktrees/vanixiets/<name>`, one live today.
- ovnfs: a private gitdir with private copies of refs plus a non-colocated jj workspace, packaged and off.

The devshell entry (`modules/devshells/default.nix:57-102`) runs on `direnv allow` in any tree.
It writes per-tree outputs (`AGENTS.md`, `CLAUDE.md`, `.agents/`) under the tree's own root, picks the context tier from `$HOME/.claude/CLAUDE.md`, writes `core.hooksPath` as the absolute common-dir hooks path with `git config --local` (which lands in the shared `.git/config` from every tree, A103), and runs `mergify stack setup`, which installs hooks into the shared hooks directory.

Global `fetch.prune = true` makes every plain `git fetch` prune (A98).
gitea-mq tests every pull request on the tip of `main` (A104).

The contingencies, contradictions and gaps are captured in `brainstorm.md`; this document organizes them.

## Goals / Non-Goals

**Goals:**

- Record C1 to C11 as world assumptions with evidence, or as requirements with failing-first tests.
- Settle the rebase policy (C10) and the ovnfs disposition (C9).
- Name the tests to write before any guidance or tooling changes, and the guidance and tooling changes per level that follow them.

**Non-Goals:**

- Changing any guidance, skill, devshell code or global git setting in this change.
- Enabling, removing or reconfiguring ovnfs.
- Retiring the stray history stores found on 2026-11-14; detection comes first, and their disposition is the operator's.
- Supporting multiple jj workspaces as a routine way to work.

## Decisions

### D1: rebase policy — DECIDED 2026-11-14 (C10)

- **Choice**: Unpublished chains are rebased freely.
  A chain is rebased onto `main` once before its first push.
  A published chain is rebased only when it conflicts with `main` or the merge queue fails it.
- **Rationale**: A104: the queue already tests the merge onto the tip, so a currency-only rebase of a published chain changes nothing the queue checks, while it churns review state and repeats CI.
- **Alternatives considered**: rebasing every chain root on each remote advance, as the diamond recipe's `roots(<base>@origin..@)` does today, rewrites published pull requests for no gain; never rebasing before the first push publishes a chain onto a stale base, so the first queue run is the first time anyone sees its conflicts.
- **Boundary**: first-party guidance (`jj-version-control` diamond-workflow and the fleet fragments) against the vendored `mergify-stack` advice to sync before new work, which needs a composition-time override, not an upstream edit.

### D2: ovnfs stays packaged and off — DECIDED 2026-11-14 (C9)

- **Choice**: `pkgs/by-name/ovnfs` stays, `programs.omp.ovnfs.enable` stays `false` in every home, and no guidance tells agents to use ovnfs.
- **Rationale**: ovnfs checkouts are non-colocated jj workspaces with private ref copies (A101 relies on the fleet's own finding that such a workspace loses the revision flake evaluation needs); the private gitdir may compensate, but nobody has tested it here.
- **Alternatives considered**: enabling it for isolated agent work now would add a sixth surface with frozen refs before the five existing ones are governed; removing the package would discard a working build the operator wants kept.
- **Boundary**: vendored ovnfs source and omp's vendored prompt stay unmodified; the first-party omp module's option is the only control.

### D3: tests before guidance and tooling — OPEN, recommended

- **Choice (recommended)**: write the tests in tasks §1 first and show each failing, or recording the defect, on today's tree; change guidance (tasks §3) and tooling (tasks §4) only after.
- **Rationale**: several requirements rest on unverified edges (concurrent devshell entry, the tier test for worker accounts); guidance written before they are measured would encode guesses.

### D4: which instruction source wins each contradiction — OPEN, recommendations recorded

| # | Sources | Recommended winner |
|---|---|---|
| 1 | omp's ovnfs prompt vs fleet fragment 040 | fleet fragment; moot under D2 |
| 2 | `wt-switch-create` vs the live `jj-worktree-create` hook and the no-stash rule | live hook and fleet fragment |
| 3 | `using-git-worktrees` (`.worktrees/`, plain `git worktree add`) vs fleet fragment l.14 | fleet fragment |
| 4 | gate-hook text "jj is unavailable inside it" vs independent jj repositories found in worktrees | neither; detection (D7) makes it true or the text is reworded |
| 5 | `mergify-stack` sync-before-work and `git stash -u` vs the fleet's no-stash rule | D1 and the fleet fragment |
| 6 | diamond remote-advance recipe rebasing published chains vs D1 | D1 |

Rows 5 and 6 follow from D1 and so are settled in substance; the wording of the overrides is open.
Rows 2, 3 and 5 sit on the vendored-versus-first-party boundary: the remedy is a first-party override where the vendored text is composed, never an edit to the vendored skill.

### D5: new trees' base — OPEN (C6)

Options: require `trunk()`/`origin/main` as the base and have each creator's wrapper pass it (wt, the Claude hook and omnigent take a base argument); or keep the join base and accept that a tree carries unpublished work it must not push.
No recommendation yet; the test in tasks 1.3 measures how often the join base leaks into a pushed branch.

### D6: ownership expressed twice (C7) — OPEN

A chain is owned by one agent, recorded as jj change ids in the primary and as `refs/heads/<branch>` for a git worktree.
Candidate mechanisms: a naming convention on branches and bookmarks, the Change-Id trailer already shared by jj and mergify, or an ownership file under the git common directory.
Deleting a ref one does not own must be refused or guarded wherever it can happen (omnigent session delete, `wt remove -D`, pruning fetch).

### D7: detection is read-only; restack is foreground and scoped — OPEN, shape recommended

- A drift detector reads `git worktree list --porcelain`, `jj workspace list`, the `.git/worktrees/` admin directories, every tree's `.jj/repo` (a directory there is a stray history store), sibling directories whose `.git` file names a missing admin directory, and each worktree's branch against `origin/main`, and writes nothing.
- A restack command rebases only the invoking agent's own unpublished chains under D1, runs in the foreground, and is idempotent: a second run on an unchanged `main` is a no-op.
- Whether either becomes a flake check, a `just` recipe or a devshell hook is open; a check that reads live host state cannot be a pure flake check.

### D8: `fetch.prune` — OPEN (C5)

Options: drop the global `fetch.prune = true`; keep it and rely on guidance forbidding plain `git fetch` in a jj primary; or set `fetch.prune = false` locally in this repository's shared config, which every tree then reads (A103).
The detector in D7 can report a pruned tracked ref after the fact; it cannot prevent one.
Baseline (tasks 1.7, `logs/vcs-1.7-prune-baseline-20261114-172309.log`): after the forge deletes a tracked branch, a plain `git fetch` from a linked worktree under `fetch.prune = true` deletes `refs/remotes/origin/feature`. The primary's next jj command then abandons the chain's commit, rebases the working-copy commit off it, and deletes the local bookmark as well as `feature@origin`. With `fetch.prune = false` nothing is lost.

### D9: shared-state writes from devshell entry (C2, C3) — OPEN

The absolute `core.hooksPath` already satisfies C3.
Open: whether the unguarded `git config` call (`default.nix:98`) needs a retry or a compare-before-write to survive the lock contention A103 describes, and whether the context tier test needs to change for worker accounts; tasks 1.1 and 1.2 decide by measurement.
Evidence (tasks 1.1, 1.2; recorded, not decided):
- The tier test reads only the entering account's own `$HOME/.claude/CLAUDE.md`. Both Omnigent workers on magnetite have one from home-manager and get tier `default`; with it absent the tier is `full` and the tree's context is still complete. Neither case reads another account's home (`logs/vcs-1.1-worker-*-20261114-1723*.log`).
- Six concurrent entries in pairs of fresh linked worktrees produced no lock error and left the absolute value.
- A `config.lock` held across a whole entry fails all three writes with an `error: could not lock config file` line each, while the entry still exits 0; the earlier absolute value survives and hooks still run.
- A lock held from just after git-hooks.nix's relative `.git/hooks` write, during primary entry with a stale hook link, leaves `core.hooksPath = .git/hooks`. From then on, commits in every linked worktree exit 0 with no hook run and no `Change-Id`, and nothing reports it (`logs/vcs-1.2-concurrent-entry-20261114-172506.log`).
- Ordinary concurrent entries never held `config.lock` past git's one-second wait in these runs; the hold was produced deliberately. [INFERENCE: outside a test, such a hold would come from a stale lock left by a killed git process.]

## Risks / Trade-offs

- [Risk] A pruning fetch by an omnigent host or an agent deletes a remote-tracking ref jj tracks, and the next import abandons commits → Mitigation now: none beyond the fleet's prohibition; D7 reports it, D8 would prevent it.
- [Risk] A new tree based on the join pushes another chain's unpublished commits → Mitigation: D5 once decided; until then, tasks 1.3 detects it.
- [Risk] A stray history store imports the primary's exports as foreign moves and exports its own → Mitigation: D7 detection; the two found on 2026-11-14 stay untouched until the operator decides.
- [Risk] Two devshell entries contend for `.git/config.lock` and one leaves `core.hooksPath` at the relative value git-hooks.nix wrote, so git commits in that tree silently run no hooks → Mitigation: tasks 1.2 measures it; D9 decides a remedy.
- [Trade-off] D1 leaves published chains on old bases until they conflict → accepted; the queue tests the real merge.
- [Trade-off] Overriding vendored skills at composition time leaves their upstream text contradicting the fleet → accepted; the override is where agents read it.

## Migration Plan

No migration in this change.
Later changes land in the order of tasks.md: tests first, then guidance per level, then tooling, each as its own pull request.
Rollback of any later guidance change is reverting its pull request; nothing here alters a closure.

## Open Questions

- D3 to D9 above.
- Who created `../vanixiets-wv-preview-port` and `../vanixiets-wv-webkit-screenshot` on 2026-10-01, and should their independent jj repositories and orphaned `.git` files be retired as the `deploy` one was?
- Should Antigravity be governed as a fifth managed creator or kept out of this repository?
- Does any Omnigent worker account on a host other than stibnite reach a checkout of this repository, given that dedicated workers have private homes (survey §4)?
- The `.delta/worktrees/` and `.delta/clones/` orphans (survey §7): which tool made them?
