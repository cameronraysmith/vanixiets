## 1. Tests first, against today's tree

Each test is written and run before any guidance or tooling change, and records whether today's behaviour passes or fails it; a test expected to fail is shown failing first.
Tests that create trees do so in a scratch clone with its own git common directory, never in `/Users/crs58/projects/vanixiets`.

- [ ] 1.1 Script a worktree creation and devshell entry as an Omnigent worker account: create a git worktree of a scratch clone the way omnigent's `_create_worktree` does (`git worktree add -b <branch> <path>` under `<repo>-worktrees/`), run `direnv allow` and enter, under an account whose private home has no `~/.claude/CLAUDE.md` and under one that has it — verify: the script's log shows, for both accounts, the tree's own `AGENTS.md`, `CLAUDE.md` and `.agents/.context-compile-key` with the expected tier, `git config --show-origin core.hooksPath` naming the common-dir hooks path, a git commit there running the prek hooks and gaining a `Change-Id` trailer, and the primary tree's generated files byte-identical before and after.
- [ ] 1.2 Script concurrent devshell entry in two linked worktrees of a scratch clone, including a run with `config.lock` held for longer than git's one-second wait (A103) — verify: the log records each entry's exit status and stderr, and the final `core.hooksPath`; the held-lock run is shown leaving `core.hooksPath` at a value from which git in one tree runs no hooks, or shown not to, and either outcome is recorded against design D9.
- [ ] 1.3 Write a read-only detector test for stale joins: given a scratch repository with a worktree whose branch is based on a development join containing another chain, and one whose branch is behind `origin/main`, the detector names both — verify: the test fails against an empty detector stub, passes against the detector of 4.1, and a before-and-after listing of refs, `.git/worktrees/`, `.jj/repo/op_heads` and every tree's files is identical.
- [ ] 1.4 Write a read-only detector test for stray history stores and orphaned trees: a scratch linked worktree with `jj git init --colocate` run in it, and a sibling directory whose `.git` file names a missing admin directory, as found on 2026-11-14 in `../vanixiets-wv-preview-port` — verify: the detector names both, fails against the stub first, and changes nothing by the same listing as 1.3.
- [ ] 1.5 Run the detector tests' fixtures against a jj-workspace record whose directory is gone and a forgotten workspace — verify: the detector names the first as stale and does not report forgotten workspaces as live, matching `jj workspace list` in the fixture.
- [ ] 1.6 Run 1.3 to 1.5 read-only against `/Users/crs58/projects/vanixiets` itself — verify: the report names `../vanixiets-wv-preview-port` and `../vanixiets-wv-webkit-screenshot` (or records that they were retired), and the before-and-after listing is identical.
- [ ] 1.7 Write a test that a pruning fetch from a linked worktree deletes a remote-tracking name the jj primary tracks, in a scratch colocated clone with `fetch.prune = true` — verify: the test shows the bookmark's remote side gone after `jj git import` in the primary, recorded as the baseline for design D8.

## 2. Decisions to take, informed by section 1

- [ ] 2.1 Decide design D5 (new trees' base) — verify: D5 marked DECIDED in design.md with the rejected option and the 1.3 evidence.
- [ ] 2.2 Decide design D6 (how ownership is recorded) — verify: D6 marked DECIDED, with an example chain readable as jj changes and as a branch.
- [ ] 2.3 Decide design D8 (`fetch.prune`) — verify: D8 marked DECIDED with the 1.7 evidence.
- [ ] 2.4 Decide design D9 (devshell shared-state writes and the tier test) — verify: D9 marked DECIDED with the 1.1 and 1.2 evidence.
- [ ] 2.5 Settle the contradiction table in design D4 — verify: each row marked with its winner and the override's location.
- [ ] 2.6 Ask the operator to dispose of the stray history stores and orphaned trees 1.6 reports, and of the Antigravity worktree — verify: the operator's disposition recorded in design.md Open Questions.

## 3. Guidance, per level

Each guidance change is evaluation-only and is verified by `nix eval` of the delivered file's text, or by inspecting the delivered path after activation; the verify column says which.

- [ ] 3.1 User-level fleet fragments under `modules/home/ai/plugins/agent-context-vcs-jj/.apm/instructions/`: in `040-worktree-interop-and-external-frameworks`, state the rebase policy (D1), the base rule (D5), the ownership rule (D6) and the prohibition of plain `git fetch` while `fetch.prune` holds (D8); in `030-working-copy-hazards`, add stray history stores and orphaned trees as a hazard headline — verify: `nix eval` of the composed user-level context for `crs58@aarch64-darwin` contains each new sentence once.
- [ ] 3.2 User-level fragment `agent-context-vcs/.apm/instructions/030-stacked-landing-protocol`: state first-push timing (one rebase onto `main` before the first push) and that published chains rebase only on conflict or queue failure — verify: as 3.1.
- [ ] 3.3 Repository fragment `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/10-repository-overview.instructions.md`: state what devshell entry writes per tree and to shared repository state, and that Omnigent worker trees enter the devshell the same way — verify: `apm-context-compile` output for this repository contains the text once, and the 1.1 script still passes.
- [ ] 3.4 First-party skill `jj-version-control`: restrict the diamond remote-advance recipe's source set to unpublished chains (exclude remote-tracked bookmarks from `roots(<base>@origin..@)`), and add stray history stores to `hazards.md` — verify: the delivered skill text after activation, and a scratch-repository run of the amended revset that leaves a published bookmark's commit hash unchanged.
- [ ] 3.5 First-party skills `git-stacked-pr-integration` and `worktree-sparsity-eval`: align first-push timing and branch ownership with 3.1 and 3.2 — verify: the delivered skill text after activation.
- [ ] 3.6 Vendored skills `using-git-worktrees`, `mergify-stack`, `worktrunk` and `wt-switch-create`: add first-party overrides where they are composed, for the D4 rows they lose, without editing the vendored source — verify: the composed text an agent loads names the override, and the vendored source's hash is unchanged.
- [ ] 3.7 Correct the claim in `modules/home/tools/hooks/gate-git-worktree.sh` that jj is unavailable inside a worktree, per D4 row 4 — verify: the delivered hook text after activation.

## 4. Tooling

- [ ] 4.1 A read-only drift detector over `git worktree list --porcelain`, `jj workspace list`, `.git/worktrees/`, every tree's `.jj/repo`, orphaned sibling `.git` files and each worktree branch against `origin/main` — verify: tests 1.3 to 1.6 pass, and their before-and-after listings show no write.
- [ ] 4.2 A foreground, idempotent restack command that rebases only the invoking agent's own unpublished chains under D1 and D6 — verify: in a scratch colocated clone with two agents' chains in a development join and one published bookmark, a run rebases only the invoker's unpublished chains, a second run with `main` unchanged reports no change, and the published bookmark's and the other agent's commit hashes are unchanged.
- [ ] 4.3 If D9 calls for it, change the devshell's shared-state write in `modules/devshells/default.nix` — verify: tests 1.1 and 1.2 pass on the changed devshell, built from the working copy for x86_64-linux on magnetite.

## 5. Integration Verification

- [ ] 5.1 An Omnigent worker on a host that reaches a checkout of this repository creates a worktree, enters the devshell, commits and returns its branch, while the operator works in the primary working tree — verify: the primary's development join is unchanged, the worker's tree has its own agent context, the drift report run before and after names the worker's tree and nothing new besides, and its commit carries a `Change-Id` trailer.
- [ ] 5.2 After `main` advances, the restack of 4.2 runs in the primary — verify: published pull requests' head commits are unchanged, and the merge queue tests them on the tip of `main`.
- [ ] 5.3 Strict OpenSpec validation of this change — verify: `openspec validate vcs-surface-coexistence --strict` exits 0.
