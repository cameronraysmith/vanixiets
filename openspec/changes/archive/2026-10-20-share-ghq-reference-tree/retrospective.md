# Retrospective: share-ghq-reference-tree

> Written: 2026-10-21 (after verify passed and the change merged as PR #3548)
> Commit range: `1c993d45..009d411c`
> Worktree: merged to main

---

## 0. Evidence

- **Commit range**: `1c993d45..009d411c` (29 commits), merged by fast-forward at 2026-10-21T03:24:54Z
- **Diff size**: +4425 / -18 lines across 42 files
- **Tasks done**: 39/40; 9.4 (deleting stibnite's empty `~/ghq.pre-shared-20261017` and the migration records) stays open and operator-gated; 6.3, 6.4 and 9.5 are checked as dropped by the decision of 2026-10-17
- **Active hours**: about 5 days of wall clock, 2026-10-16 to 2026-10-21, across activation, four code-review rounds and a confirmation round
- **Subagent dispatches**: 3 fix agents in code-review round 1 (migrate, handler and wrapper, nix assertions); every later round was done in one session
- **New external dependencies**: none outside nixpkgs (`acl` for `getfacl` on Linux, already in nixpkgs)
- **Bugs encountered post-merge**: none; one deploy incident before merge (a plain-main deploy to magnetite removed the writer, verify.md §5)
- **OpenSpec validate state at archive**: pass (`openspec validate --all`)
- **Test coverage signal**: `vmTests.x86_64-linux.shared-reference-tree` with two must-fail mutations; `package-ghq-shared-test-{acl,handler,wrapper}` on aarch64-darwin and x86_64-linux; evaluation mutations for every module assertion

Commit chain (chronological):

```
a20c42eb openspec(share-ghq-reference-tree): propose shared ghq reference tree
fbc7e720 feat(shared-reference-tree): declare per-host participation
a31d7d48 feat(shared-reference-tree): add the NixOS writer account and reader group
f3611cd0 feat(ghq-shared): add the read-only ghq wrapper, writer client and request handler
92b39687 feat(shared-reference-tree): add the NixOS socket-activated writer service
829445ab test(shared-reference-tree): add the executed NixOS test with negative controls
ad1ed427 feat(ghq-shared): add ghq-shared-migrate to move per-account trees into the shared tree
1b69b082 feat(shared-reference-tree): add the darwin writer _ghq (460) and keep worker secrets on their own group
ea53270f feat(shared-reference-tree): add the darwin socket-activated writer daemon
98722f87 feat(ghq-shared): fetch tags on update without moving a shallow boundary
d7e6ca4b feat(direnv): keep layouts under the account's cache
663bde04 docs(agent-context): route reference repositories through ghq root and say they may be read-only
009d411c docs(openspec): verify share-ghq-reference-tree
<archive> chore(openspec): archive share-ghq-reference-tree and sync its specs
```

---

## 1. Wins

- The threat demonstration in the NixOS test (a writer-planted `core.fsmonitor` runs as a reader) and the `broken-control` and `group-writable` mutations kept every "readers cannot write" assertion from being vacuous through five rounds of change.
- The single-writer model held on all three hosts after deployment: every participating account read the tree, every write and refusal behaved as specified, and `nobody` was refused at the root and the socket (verify.md §5).
- stibnite's 557 repositories moved by one rename, with no refetch, as the user required.
- Routing each fix into the commit that owned its file kept the 29-commit chain reviewable and rebased three times without a conflict in this change's files.

## 2. Misses

- [high] [blocking | evidence: code review rounds 1–4, verify.md §5a–5d] Sanitising other accounts' trees in place was built through two review rounds and kept failing review on new bypasses (nested `.git` files, `commondir`, ACLs, races against the walk); it was replaced by the administrator-only rule only after the third round.
- [med] [painful | evidence: verify.md §5d, I1] Dropping the staging directory with the sanitiser reopened a window in which another account could write an administrator's tree while it moved; round 4 caught it.
- [med] [painful | evidence: verify.md §5, magnetite incident] A deploy of main before the merge removed the writer from magnetite and orphaned the tree; nothing marked the host as depending on an unmerged change.
- [low] [nit | evidence: world-assumptions delta] The MODIFIED vocabulary block was built from a pre-S1 corpus and would have deleted 73 rows at archive; it was rebuilt against main only at pre-push.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 1.x / D1 | the darwin root moved from `/Users/Shared/ghq` to `/var/lib/ghq` | `/Users/Shared` trips the Omnigent worker guard (user decision 2026-10-17) |
| 4.6, 4.7, 7.4–7.6 | path targets, tags, wrapper delegation, direnv layouts and the always-loaded context added after first activation | gaps found by use on the hosts |
| 6.1 → 6.3, 6.4 | sanitisation hardened twice, then dropped | code review rounds 1–3 |
| 6.5–6.7 | administrator-only in-place migration, set-aside for every other account, up-front exposure refusals, closed window, stopped writer | user decision 2026-10-17 and review round 4 |
| 9.5 | dropped | `--sanitise-existing` was removed with sanitisation |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes  |
| superpowers:writing-plans                        | yes  |
| superpowers:using-git-worktrees                  | no   |
| superpowers:subagent-driven-development          | yes  |
| (transitive) superpowers:test-driven-development | yes  |
| (transitive) superpowers:requesting-code-review  | yes  |
| superpowers:finishing-a-development-branch       | yes  |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill; the chain was built as jj commits in the shared working copy.
  - **Why this cycle**: the working copy was shared with a concurrently running observability session, and the orchestrator required path-scoped `jj squash --from @` into chain commits with `jj new --no-edit -A … -B <join>`, so a separate worktree would have split the chain from the join it is merged through.
  - **How to prevent recurrence**: `scope-judgment rule` — in a jj repository whose chains are joined under one working copy, the jj workspace and join commit play the worktree's role; the next cycle should record that equivalence in the plan instead of listing the git-worktree skill as skipped.

## 5. Surprises

- An administrator can already act as every account, so cleaning its tree defends against nothing; but whether only that administrator could have written its tree still has to be checked, through ownership, permission bits, hard links and ACLs.
- On darwin, group membership is not visible in `gr_mem` for nested groups such as `everyone`; only `getgrouplist` gives the real answer.
- git's `safe.bareRepository` can only be set globally, so the protection for the shared tree changes every participant's git use.
- NixOS's uid map kept the writer's uid across its removal and re-creation, which is what made the magnetite incident recoverable without touching data.

## 6. Promote candidates → long-term learning

- [ ] [high] **Check who could have written a tree before trusting it by its owner's authority** → **Promote to memory** (type: feedback)
  > **Why**: the administrator-only rule was sound only once ownership, permission bits, hard links and ACLs were refused up front (review round 4, I1).
  > **How to apply**: whenever a design moves or trusts content because of who owns it.
- [ ] [med] **Stop sanitising untrusted trees once a second review round finds a new bypass class; narrow the trust boundary instead** → **Promote to memory** (type: feedback)
  > **Why**: two hardening rounds on the sanitiser each found new bypasses before the user replaced it with a boundary decision.
  > **How to apply**: at the second review round that finds a bypass in a cleaning or filtering mechanism.
- [ ] [med] **Rebuild MODIFIED requirement blocks against main's current text before push** → **Promote to schema** (verify or archive guidance)
  > **Why**: the world-assumptions block was based on a corpus 73 rows old and would have deleted other changes' rows.
  > **How to apply**: at verify and again before push for any change that MODIFIES a shared requirement.
- [ ] [low] **A host deployed from an unmerged chain needs a marker** → **One-off**
  > **Why**: magnetite lost the writer when main was deployed before the merge; the merge ends that exposure for this change.
  > **How to apply**: record in the deploy notes which hosts run an unmerged chain.
