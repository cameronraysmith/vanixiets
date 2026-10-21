# Verification Report

**Change**: `share-ghq-reference-tree`
**Verified at**: `2026-10-21 02:55` (post-deploy checks at the CAM-77 tip `c703a7ec`)
**Verifier**: `ShareGhqTreeProposal` (delegated agent, openspec-verify-change)

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items report `"valid": true`

**Result**:

```text
totals: 33 items, 33 passed, 0 failed (18 changes, 15 specs)
```

| Item | Type | Issues |
|---|---|---|
| — | — | — |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

39 of 40 tasks are checked; 6.3, 6.4 and 9.5 are checked as dropped by the user's decision of 2026-10-17 (design D10), 6.5 records the simplification, 6.6 the ACL refusal and 6.7 the round-4 fixes.

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 9.4 Delete pre-shared copies and sidecars | Human-gated: each deletion waits for the operator's explicit authorization per account per host. Pyrite and magnetite set nothing aside; on stibnite `/Users/crs58/ghq.pre-shared-20261017` is empty and `/var/lib/ghq-migration/crs58` holds the rollback sidecar. | No: deletion removes only the rollback path, and keeping it costs disk, not correctness. |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `shared-reference-tree` | pending sync | New capability; no main spec yet. |
| `shared-reference-tree-interface` | pending sync | New capability; no main spec yet. |
| `world-assumptions` | pending sync | Adds A34, A35 and A36 (numbers unused in the corpus, which holds A1–A33 and A37–A42 at main `1c993d45`, and in other active changes) and modifies `Grounded vocabulary for behavioral requirements`. The modified block was rebuilt on 2026-10-21 from main's block at `1c993d45` (128 rows): every main row is kept except `person` and `writer`, which become two senses each (main's text kept as `person \| service` and `writer \| database`, this change's as `person \| account` and `writer \| reference tree`), plus 11 new rows; the two-senses sentence names eighteen terms (main's fifteen plus `person`, `writer` and `account`). Comparison: `cam77-wa-compare-*.log`. |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 root | `/var/lib/ghq` on every sharing host | interface `The shared root is owned by the writer…` names `/var/lib/ghq` | none |
| D3 single writer | `ghq`/`_ghq`, readers through the writer's group, `safe.directory = <root>/*` | behavioral `Only the writer changes the reference tree`; interface `Readers trust the writer's tree…` | none |
| D5 transport and requests | socket-activated writer, fixed action set, unknown fields refused, tags in two batches | interface `Acquisition is delegated…` and `The writer accepts only constrained requests` | none: the requirement names the `tags` field, the full-clone tag fetch and the shallow two-batch rule, with a scenario |
| D10 migration | administrators only: rename or copy, chown and masked modes, deeper clone kept, rollback; other accounts set aside and reacquired through the writer | behavioral `Moving per-account copies…`; interface `Migration moves only administrators' trees in place…` | none |
| D7/D8 evidence | module assertions, VM test with negative controls | interface `Each property is backed by evidence that can fail` | none |

**Drift warnings** (non-blocking):

- none.
  The interface requirement `The writer accepts only constrained requests` predated task 4.7 and omitted `tags`; it now names the field, the full-clone tag fetch, the shallow two-batch rule and the refusal to force a moved tag, with the scenario `A request asks for every tag in a shallow clone`, which the VM test's tags subtest exercises.
  The stibnite tree migrated before task 6.2's fix held entries with permission bits for others; the operator ran `chmod o-rwx` over them, and `sudo -n find /var/lib/ghq ! -type l -perm +o=rwx | wc -l` reads 0.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree belonging to this change (the working copy holds another session's files, which this change does not touch)
- [ ] All related commits have been pushed — not pushed, by instruction; one pull request for the whole chain follows review

**Commit range** (if known): `kmusvmpr .. mrwxxnlm` (29 commits on bookmark `cam-77-share-ghq-reference-tree`, on main `096e494e`); code checked at `2660ecc6565e`.

Runtime evidence (log paths under `logs/`, gitignored), at `a783db847a50` (`ghq-round5-verify-*.log`), and for the follow-ups at `2660ecc6565e` (`ghq-round6-verify-*.log`: the three package tests on both systems, the three evaluations, the VM test and `openspec validate`, all passing):

- `vmTests.x86_64-linux.shared-reference-tree` passes (`ghq-round5-verify-*-vm.log`).
  Its migration subtest covers: a dry run listing an administrator's planned move and refusing the non-administrator with its reacquisition commands; `--apply` naming a non-administrator refused with every tree, the root and the record directory unchanged; a standing manifest refused; an entry writable by every account, an entry owned by `omnigent-cameron` and a hard link to a file outside the tree listed by the plan and refused by `--apply` with the tree, the root and the record directory unchanged; an ACL granting `omnigent-cameron` write on the administrator's `.git` listed by the plan and refused by `--apply` with the tree, the root and the record directory unchanged; the administrator `cameron` (in `wheel`) moved whole, with a hook run mid-apply finding the writer's socket inactive and the shared root mode `0700` and unreadable by `nobody`, and the writer active again afterwards, writer-owned, no group write or access for others, a setuid file without its bit, its hook unchanged; `--set-aside` of the non-administrator `omnigent-cameron`, whose tree stays its own, whose credential-bearing upstream URL is printed without its credential, and whose printed `ghq-sync` commands, run as it, reacquire each repository through the writer; a writer clone before rollback; a rollback that fails on an immutable file and completes when run again; and records holding the earlier tool's `sanitise` steps (a rewritten configuration and a removed hook), which roll back exactly.
  The round-2 tool fails the dry-run, refusal and unchanged-tree checks and has no `--set-aside` (`cam77-r3-vm-red-20261018-011227.log`), so the later cases, which need `--set-aside`, are not reached by it.
  The tool at `cd54e01d7dcc` fails the three ACL checks (`cam77-r4-vm-red-20261018-014528.log`): the plan does not list the entry, apply moves the tree, and the tree and root change.
  The tool at `549321670bbe` fails the round-4 checks (`cam77-r5-vm-red-20261018-024622.log`): the plan does not list the world-writable, foreign-owned and outside-hard-link entries and apply moves the tree; the writer runs and the root is reachable mid-apply; set-aside prints `git://user:secret@…` and the command it prints fails at the writer.
- `mutations.group-writable` and `mutations.broken-control` fail at their intended subtests.
- `package-ghq-shared-test-acl`, `-handler` and `-wrapper` pass on aarch64-darwin and x86_64-linux.
  On aarch64-darwin the ACL test plants ACLs on a directory, a file whose name has a space and a symlink, and checks the probe lists exactly those; the tool at `cd54e01d7dcc` has no probe (`cam77-r4-acl-local-*.log`).
  The Linux build sandbox has no POSIX ACLs, so on x86_64-linux it checks that their absence is reported as none; the VM test covers a Linux ACL being refused.
  Gap: the darwin refusal is exercised through its probe, not through a darwin `--apply`, which needs root and a second account.
- `checks.aarch64-darwin.darwin-stibnite`, `checks.x86_64-linux.nixos-magnetite` and `checks.x86_64-linux.nixos-pyrite` evaluate with no failed assertion; the six `safe.bareRepository` and ordering-marker mutations and the round-1 `safe.directory` and ordering mutations still fail evaluation.
- Task 10.2: the sharing projection of the seven non-sharing hosts is unchanged between main `096e494e` and `a783db847a50`.
- Administrators on the sharing hosts, by `id -Gn`: `crs58` on stibnite (`admin`), `cameron` on pyrite and magnetite (`wheel`); no Omnigent worker is in either group.
- Deployed state, 2026-10-21: pyrite (`852kxang…`) and magnetite (`16l3xmaa…`) run the CAM-77 tip `c703a7ec` (ghq-shared `pyl248w5…`), and stibnite (`7vn5s57f…`) a newer working copy whose closure holds the tip's darwin ghq-shared (`jx9x7wyz…`); every participating account's `ghq` resolves to that package.
- Post-deploy checks on that state passed with no failure (`ghq-pd2-gen-*.log`, `ghq-pd2-units-*.log`, `ghq-pd2-{pyrite,magnetite,stibnite}-*.log`, `ghq-pd2-admin-*.log`; 53, 53 and 37 checks): the writer owns each root (`ghq` 986:982 on pyrite, 984:980 on magnetite, `_ghq` 460:460 on stibnite, mode `0750`) with no entry of another owner and none without an owner; no failed unit, and on magnetite nixbot, gitea-mq, gitea, greptimedb, the OpenTelemetry collector and the fleet-alert timer are active; for every account, `ghq root`, `safe.directory = <root>/*`, `safe.bareRepository = explicit`, `ghq-sync -u .`, the read-only refusals, the full and shallow tag behaviour and the direnv layout under `~/.cache`; the writer's control write, and `nobody` refused at the root and at the socket; and a `ghq-shared-migrate` dry run for each host's accounts that changed nothing (every `~/ghq` is already a link, so it planned no move; the deployed tool's administrator check classifies `cameron` and `crs58` as administrators and every Omnigent worker as not).
- Magnetite incident, 2026-10-20: a deploy of plain main, without this change, removed the `ghq` account and its socket; `/var/lib/ghq` was left owned by the orphaned uid 984 and gid 980 and `cameron` was refused. NixOS's uid map kept `ghq` at 984, so redeploying the CAM-77 tip recreated the account with the same ids, and the tree was again the writer's with nothing orphaned; no data moved. Merging the change into main ends this exposure.
- Earlier post-activation smoke on the generation deployed before round 1 (`ghq-postdeploy-*-*.log`) is superseded by the checks above.

Live-tree audits, read-only: round 1 (`ghq-audit-*.log`) and round 2 (`ghq-audit2-*.log`) found no setuid entry, no ACL and no hard link to an inode outside any tree on any host.

## 5a. Code Review Round 1

Roborev round 1 rejected the change with four blockers, all in the migration tool; the change returned to In Progress and every finding is addressed in the commit that owns its files.

| Finding | Commit | Evidence |
|---|---|---|
| F1 symlink and TOCTOU in migrate | wywxsxyp | VM: swap, `config.sanitised` symlink and `.git` symlink cases RED before, GREEN after |
| F2 setuid kept | wywxsxyp | VM setuid case RED before, GREEN after |
| F3 sanitisation bypass | wywxsxyp | VM `commondir`, `gitdir`, `worktrees/`, alternates and nested-repository cases RED before, GREEN after |
| F4 foreign hard link | wywxsxyp | VM hard-link case RED before, GREEN after |
| F5 `repo_dir` escape, empty host | wywxsxyp | handler test RED before, GREEN after |
| F6 `safe.directory` prefixes | swxzwykn | mutations pass before, fail after; unmutated evals pass |
| F7 read timeout | wywxsxyp | handler test RED before, GREEN after |
| F8 rollback ownership | wywxsxyp | VM writer `get -u` before rollback RED before, GREEN after |
| F9 record before chown | wywxsxyp | covered by the rollback round trip |
| F10 set-aside path | vpzsnnyq, nuqnyqqz, vnvymuul | docs now name `~/ghq.pre-shared-<date>` |
| F11 submodule walk, bare target | wywxsxyp | wrapper and handler tests RED before, GREEN after |
| F12 ls-remote, `--tags` combinations, `ext::sh` | wywxsxyp | handler and wrapper tests RED before, GREEN after (`ext::sh` already refused) |
| F13 darwin ordering | swxzwykn | mutation loading the daemon first passes before, fails after |
| F14 test harness | wywxsxyp | wrapper test uses the built package and compares full output and status; VM gated on x86_64-linux, malformed requests assert `refused` |
| F15 docs | wywxsxyp, nuqnyqqz, vpzsnnyq, vnvymuul | design, interface spec, migrate docstring, fragment and skill corrected |
| F16 leftovers | nuqnyqqz, swxzwykn | design records the `.direnv` cleanup; `system.newsyslog` rotates the writer log |

---

## 5b. Code Review Round 2

Roborev round 2 rejected the change with two blockers (G1, G2) and found F3 partly closed; the other round-1 findings are closed.

| Finding | Commit | Evidence |
|---|---|---|
| G1 nested `.git` files, `.git/modules` commondir | wywxsxyp | VM refusal of both nested-file reproductions and sanitisation of the `.git/modules` case, in migration and `--sanitise-existing`, RED before, GREEN after; chose treating every `.git/modules/**` directory with `HEAD` and `objects/` or `commondir` as a root, because git takes exactly those as git directories and a blanket rewrite of every file named `config` inside `.git` would also hit refs and reflogs named `config` |
| G2 ACLs | wywxsxyp | Linux: `system.posix_acl_*` removed by descriptor, VM ACL and promote cases RED before, GREEN after; darwin: `acl_get_fd_np`/`acl_set_fd_np` through ctypes, ACL package test on aarch64-darwin RED before, GREEN after |
| G3 bare repositories | tttrnkqw, swxzwykn, wywxsxyp | `safe.bareRepository = explicit` for participants with assertions on NixOS, darwin and the darwin worker; five mutations fail evaluation; plan and `--sanitise-existing` list bare-shaped directories (VM RED before, GREEN after) |
| G4 rollback repeatable, predictable stage | wywxsxyp | VM: pre-existing stage refused without traceback, recreated stage adopted by rollback, unexpected error names the rollback; each RED before, GREEN after |
| G5 vacuous ordering assertions | swxzwykn | the daemon-disabled mutation passes before and fails after |
| G6 audit and 9.5 precondition | vnvymuul, mrwxxnlm | round-2 audit recorded above; task 9.5 runs only after 6.4 is deployed and re-audits every case |
| G7 second manifest | wywxsxyp | VM standing-manifest case RED before, GREEN after |

## 5c. Code Review Round 3 and the trust-boundary decision

Roborev round 3 found H1–H7. The user decided on 2026-10-17 to narrow the migration trust boundary instead of hardening the sanitiser again: only an administrator's tree moves in place, and every other account's tree is set aside and reacquired through the writer (design D10, task 6.5).

| Finding | Resolution | Evidence |
|---|---|---|
| H1 nested `.git` file parsed unlike git | closed by deletion | nested `.git` checks removed; a non-administrator's tree never enters the shared tree, and an administrator gains nothing it lacks (A36) |
| H2 `.git` files written after the last survey | closed by deletion for other accounts' trees; for an administrator's tree closed by the refusals and the closed window of task 6.7 | round-4 finding I1 showed the mechanism still applied to an administrator's tree while it moved |
| H3 ACL race | closed by deletion | ACL removal removed with the cleanup it served; an administrator's tree carrying any ACL is refused instead (task 6.6) |
| H4 rollback not resumable | fixed (wywxsxyp) | undos skip steps that never took effect or were already undone, and `undone.jsonl` journals each undone step; VM rollback failing on an immutable file completes when run again |
| H5 sanitising deleted refs under `hooks/` | closed by deletion | no sanitising |
| H6 global `safe.bareRepository` undocumented | documented (vpzsnnyq, nuqnyqqz, ovzonvow, vnvymuul) | interface spec, design D4 and D7, `modules/home/README.md` and the `dependency-source-acquisition` skill state its global scope and the `--git-dir`/`GIT_DIR` workaround |
| H7 ACLs on symlinks and special files | closed by deletion | ACL removal removed; the refusal probe examines symlinks without following them (darwin `find -P -acl`, Linux `getfacl -P`) |

## 5d. Code Review Round 4

Roborev round 4 found I1 (blocker) and I2–I8; each is fixed under the user's rule that an administrator's tree moves only if only that administrator could have written it, checked up front, with nothing cleaned (task 6.7, wywxsxyp unless noted).

| Finding | Resolution | Evidence |
|---|---|---|
| I1 others could write an administrator's tree while it moved | fixed | plan refuses foreign-owned, world- or group-writable (group with other members) and outside-hard-linked entries; tree and root closed until `link_root`; VM refusal and mid-apply probe RED before, GREEN after |
| I2 root readable by every account during a whole-tree move | fixed | tree top `0700` before the rename and through the walk; VM probe finds the root `0700` and unreadable by `nobody` |
| I3 hard links extend the chown outside the tree | fixed | plan refuses a non-directory whose link count exceeds its links inside the tree; VM case RED before, GREEN after |
| I4 the account's git in root's session | fixed | `stdin` closed, own session, time limit, `core.fsmonitor=false`; a tree set aside runs only `git config --get` (not exercised for a terminal attack) |
| I5 unchecked reclone output | fixed | non-printables refused, credentials removed, values quoted, protocols outside the writer's own configuration reported as not reacquirable; VM credential case RED before, GREEN after |
| I6 a compromised writer racing root's walks | fixed | writer socket and handlers stopped for `--apply` and `--rollback`, refusal while writer processes run, writer started again afterwards; VM probe RED before, GREEN after (rollback's stop is not probed) |
| I7 stale docs | fixed (nuqnyqqz, vpzsnnyq, swxzwykn, vnvymuul, mrwxxnlm) | `plan.md` 6.1, design D10, the docstring's record claim (parent directories and root mode changes are now recorded), the runbook marked as history, and the H2 row above |
| I8 robustness | fixed | a cut-off last record line is ignored, `--rollback` clears a state directory without a record, and a copy is made under a name of its own before its rename; not exercised by a test |

## 5e. Round-4 Confirmation Follow-ups

The confirmation review passed with follow-ups, each fixed in wywxsxyp (design note in nuqnyqqz).

| Finding | Resolution | Evidence |
|---|---|---|
| J1 group membership undercounted (nested groups) | membership through `getgrouplist` for every account; undetermined membership refuses any group but the account's private group | `package-ghq-shared-test-acl` on aarch64-darwin: `everyone` (gid 12) resolves to 172 accounts; the tool at `a783db847a50` resolves none (`cam77-r6-unit-local-*.log`) |
| J2 writer stop and restart unchecked | the socket or launchd job must be down after the stop, else the writer is restarted and apply refuses; a failed restart is reported instead of "started again" | stubbed `subprocess` in `package-ghq-shared-test-acl`, both platform branches, on both systems; the tool at `a783db847a50` does not refuse a writer that keeps running (`cam77-r6-unit-local-*.log`) |
| I6 legacy `sanitise` undo followed a symlink at its destination | a symlink at the destination is removed before the kept file is copied back | not exercised by a test |
| I5 `urlsplit` raising | caught; the URL is reported as not reacquirable | not exercised by a test |
| I7 verify.md H2 row | already corrected in mrwxxnlm after `a783db847a50`, which the review read | section 5c |

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [x] No files, or any existing files are legitimate residue from before schema installation

No files.

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows; this section is intentionally blank.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation Lint and Discharge Coherence (agent-executed, non-blocking; not validation)

`openspec validate` checks structure only; nothing in this section is validation.

**8a. Designation lint** of the `behavioral` capability `shared-reference-tree` against the designation table (`openspec/specs/world-assumptions/spec.md` plus this change's delta rows):

| Noun | Resolves? | Disposition |
|---|---|---|
| host, operator, account, person, agent, private home | yes | — |
| reference tree, reference repository, participating account, writer, acquisition request, repository-local setting, per-account copy, administrator | yes (delta rows) | — |
| permitted action | resolved | Reworded to "which reference repository is acted on and whether it is added, refreshed or deepened". |
| work | resolved | Reworded to "history or a changed file that exists nowhere else", using the existing `history` row. |

**8b. Discharge coherence**:

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Every participating account reads one reference tree per host | Sharing hosts are declared…; Each participating account resolves the shared root | A35 | discharged |
| Only the writer changes the reference tree | The shared root is owned by the writer…; Readers trust the writer's tree…; Acquisition is delegated… | A34 | discharged |
| A missing reference repository can be requested without a person | Acquisition is delegated…; The writer accepts only constrained requests | — | discharged |
| Only participating accounts can read the reference tree | The shared root is owned by the writer… (mode `0750`, group membership) | — | discharged |
| Sharing the reference tree leaves every private home private | existing worker obligations (private `0700` homes, admitted groups) and Sharing hosts are declared… | — | discharged |
| Moving per-account copies into the reference tree loses nothing and is reversible | Migration moves only administrators' trees in place, sets other trees aside, and can be rolled back | A36 | discharged |
| A34, A35 | — | world | violation-condition witnesses |
| Grounded vocabulary for behavioral requirements | designation table | world | see 8a |

**8c. Alphabet check**:

- Behavioral requirements name no machine-side artifact (no paths, units, sockets, commands).
- The interface capability's trust-boundary requirement mentions "the content of upstream repositories" only to exclude it from the guarantee; it states no property that depends on unobservable world state.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: task 9.4 (deleting stibnite's pre-shared directory and the migration records) awaits the operator's authorization, and until this change is merged a deploy of main removes the writer from a sharing host, as on magnetite on 2026-10-20.
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

In Review: the documenter sub-gate and the pull request for the whole chain; the operator decides 9.4.
