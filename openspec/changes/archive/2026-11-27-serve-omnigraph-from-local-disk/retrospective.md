# Retrospective: serve-omnigraph-from-local-disk

> Written: 2026-11-27 (after verify passed with warnings, before archive)
> Commit range: `7ffb76200..40189458f`, 21 commits touching the change's files, `049bd37dd` (the backup bucket's terraform state) beside them
> Worktree: merged to main up to `7018377df`; `40189458f` (the fourth check's `verify.md`), this retrospective and the archive follow

---

## What the change set out to do

magnetite (Hetzner fsn1) served its OmniGraph graphs from the R2 bucket `sciexp` in eastern North America: the root `cookbooks-f17` took about 26 min to create, and a start took 2 min 40 s to 4 min 50 s to open ten small graphs (proposal Why; `verify.md` Alerts table; `DeployMagnetite-switch.md`, the R2 baseline of 290 s and the two R2 deploys at 159.5 s and 183.7 s).
The change was to watch the running server first, then move the root to a ZFS dataset on magnetite's own disk, recover by itself from the stale lock a crash leaves on a local root only when that is safe, back the root up off the host every night, and alert on a server that is not serving or a backup that is overdue (proposal; design D1–D14).

Measured result (`logs/agent-reports-20261126/DeployMagnetite-switch.md`, design "Operator evidence, 2026-11-27"):
- creating and seeding the root: about 26 min on R2, 5.1 s on disk (bootstrap 17:12:44.1 to 17:12:49.2Z on 2026-11-26, then 2.5 s of seeds);
- start to ready: 2 min 40 s to 4 min 50 s on R2, 2.3 s on disk (probe 2.183 s), 4.232 s at the first start after the reset of 2026-11-27;
- restore of the nightly snapshot `831ae1d2` rehearsed in place on magnetite (outage 37.0 s, most of it between hand-run steps; every count, commit id, path, owner and file hash equal) and without the host on a workstation (restored in 2 s, the same answers as magnetite).

---

## 0. Evidence

- **Commit range**: `7ffb76200..40189458f`, 21 commits (chain below)
- **Diff size**: +8203 / −982 lines across 49 files, artifacts included
- **Tasks done**: 36/36 (`tasks.md`; groups 6, 7 and 8 added after verification)
- **Active hours**: not recorded; 35.7 h elapsed from `7ffb76200` (2026-11-26 04:03 UTC) to `40189458f` (2026-11-27 15:43 UTC)
- **Subagent dispatches**: 18 saved reports under `logs/agent-reports-20261126/` (`Cam127*.md`, `DeployMagnetite-switch.md`, `OmnigraphRestoreDrill.md`, `LocalRootCrashProbe.md`)
- **New external dependencies**: none (no new flake input; restic and ZFS were already in the fleet)
- **Bugs encountered post-merge**: 8, all found after the delivery commits were on `main` and deployed:
  1. `vmTests.x86_64-linux.omnigraph-seed` stopped evaluating at `2dbb1e25a`, because the probe module set an option only `base` declared (fixed in `c8ee415b5`).
  2. The way back to R2 did not evaluate: magnetite's notified units named the three local-root units on either store (verify finding 1; fixed in `c5dacfad6`).
  3. A backup interrupted in its prune or check left an exclusive restic lock that failed every later backup (finding 2; fixed in `7d1cb0e52`).
  4. A refused start's only message was the generic failure notice, without the reason or the manual step (finding 3; fixed in `b0ae591ae`).
  5. The `world-assumptions` delta carried a stale copy of the vocabulary requirement, 28 of `main`'s rows behind (finding 4; fixed in `de37dff6c`).
  6. A switch to `"r2"` would leave `omnigraph-backup.prom` in `/run/node-exporter-textfile`, firing `HostProbeStale` and later `OmnigraphBackupStale` (finding 5; fixed in `2661af5dd`).
  7. A `cluster status` answer that was not one JSON object ended the recovery with jq's exit 5 and no refusal (finding 6; fixed in `11ace51d9`).
  8. The cleanup's requirement said it runs on every `switch-to-configuration`; it does not run on `boot` or `dry-activate` (finding 7; fixed in `7018377df`).
- **OpenSpec validate state at archive**: `openspec validate serve-omnigraph-from-local-disk --strict` valid; `openspec validate --specs --strict` adds `graph-store` and `graph-store-interface`, both valid, and changes no other result
- **Test coverage signal**: `checks.x86_64-linux.omnigraph-lock-recovery-rehearsal` with the mutants `scanSkipped`, `btimeUnchecked`, `omnigraphAtPidExcused`, `statusUnguarded` and `errTrapRemoved`, each rejected; `vmTests.x86_64-linux.omnigraph-local-root` (medium, script 89.64 s on pyrite) and `vmTests.x86_64-linux.omnigraph-state-directory-transitions` (medium, 66.41 s); `checks.x86_64-linux.omnigraph-retired-roots` on both stores; `fleet-alert` cases with threshold mutants for both rules; every remedy of groups 6 and 7 shown red first (tasks 6.1–6.3, 7.1, 7.2)

Commit chain (chronological):

```
7ffb76200 docs(openspec): plan serving omnigraph from local disk on magnetite
2dbb1e25a feat(omnigraph): watch the server's readiness and graphs on magnetite
7d02f0a58 feat(omnigraph): serve a local root with stale-lock recovery and nightly backup
725969298 fix(omnigraph): refuse lock recovery on unreadable process state or an omnigraph at the lock pid
afd978d84 feat(magnetite): serve omnigraph from local disk
083caaa5a fix(perses): make the OmniGraph view readable at a glance
3d1f2ff27 fix(perses): fit the OmniGraph view's names and stat tiles to their panels
c8ee415b5 fix(omnigraph): declare the textfile options the probe and backup set
27ac2fe88 docs(omnigraph): record the restore drills and the restore without the host
ec2c878bf docs(openspec): verify serving omnigraph from local disk
7d1cb0e52 fix(omnigraph-backup): remove stale restic locks before each backup
b0ae591ae fix(omnigraph): post a notice when the lock recovery refuses, naming the reason
c5dacfad6 fix(magnetite): switch the omnigraph root store with one setting
de37dff6c docs(openspec): amend serving omnigraph from local disk after verification
fbb25ce19 docs(openspec): re-verify serving omnigraph from local disk
2661af5dd fix(node-exporter-textfile): remove at activation every textfile no declared writer writes
11ace51d9 fix(omnigraph): end the lock recovery only by its refusal, a recovery or nothing to do
227d8b324 docs(openspec): amend serving omnigraph from local disk after the second verification
7528573e7 docs(openspec): verify serving omnigraph from local disk a third time
7018377df docs(node-exporter-textfile): say when the textfile cleanup runs
40189458f docs(openspec): verify the cleanup wording of serving omnigraph from local disk
(this commit) docs(openspec): archive serving omnigraph from local disk
```

## 1. Wins

- The disk met the goal by two orders of magnitude: root creation 26 min to 5.1 s, start to ready minutes to 2.3 s (above).
- The crash probe (`LocalRootCrashProbe.md`) established before any design what a local root does: a killed server's `lock.json` stays and blocks every start, `force-unlock` checks only the id and removed a live server's lock, commits are whole across five kills, and a file copy of a live root opened 2 times of 8 while copies of a frozen root opened 8 of 8. D4's refusal rows and D5's snapshot-only backup follow from it (A232–A234).
- The stale-lock recovery worked in the first real crash without a person (below).
- Both restores were rehearsed before archive, in place and off the host, and both returned identical answers (tasks 5.3, 5.6).
- Every remedy after verification was shown failing first: the runtime test's stale-lock leg (`logs/cam127-fix-backup-lock-red-20261127-042317.log`), the rehearsal's refusal and spelled-root rows, the way-back check, the textfile leg and the status-guard rows (design, "Verification findings and remedies").

## 2. Misses

- [high] [blocking | evidence: verify finding 1, `afd978d84`, `c5dacfad6`] magnetite was switched to disk while the documented way back did not evaluate. The check `omnigraph-retired-roots` read the store's URI on `"r2"` but none of the assertions the switch broke, and the runbook named two of the three edits it needed.
- [high] [blocking | evidence: verify finding 2, `7d1cb0e52`] A reset during the night's prune or check would have stopped every later backup: nixpkgs runs `restic unlock` only between backup and prune, and restic refuses a backup's lock beside any exclusive lock, stale or not. The same order was in `postgresql-backup.nix` before this change.
- [med] [painful | evidence: verify findings 3, 6] The recovery's refusals reached the operator only as `FAILED omnigraph-server.service`, and one malformed answer bypassed the refusal altogether; it took two remedy rounds (`b0ae591ae`, then `11ace51d9` with the `ERR` trap) before every end of the program went through the one refusal path.
- [med] [painful | evidence: verify finding 5, `2661af5dd`] A store switch would have left a textfile in `/run` that fires two alerts; the fix reaches every NixOS host, not only magnetite.
- [med] [painful | evidence: `c8ee415b5`] `vmTests.x86_64-linux.omnigraph-seed` did not evaluate from `2dbb1e25a` (2026-11-26 04:37 UTC) to `c8ee415b5` (2026-11-27 03:30 UTC). The two new omnigraph tests imported `node-exporter-textfile` themselves to get past the same error instead of fixing the module, and nothing on a pull request evaluates `vmTests`.
- [med] [painful | evidence: verify findings 4, 7] The vocabulary delta went stale against `main` and the cleanup's requirement claimed a run on `boot`; both were wording, each cost a verification round.
- [low] [nit | evidence: verify §2] Task 3.1's command output was not saved under `logs/`; task 2.8's notice window lacks its last 4 minutes; task 1.6's rendered view rests on observations passed on, not seen by the verifier.

What the misses say about the practice: the delivery commits passed their checks and runtime tests and were deployed with findings 1, 2, 3 and 6 in them. Each was found by reading a requirement against what the code or the host does around it: the way back by evaluating magnetite on `"r2"`, the backup lock by reading restic's lock code at the version magnetite runs, the refusal notice by following a refusal to what the operator receives, the malformed answer by running the program over a stub. The tests exercised what their author expected to happen.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| D1: dataset at `/var/lib/private/omnigraph/clusters` below the `DynamicUser` state directory | The dataset is `/var/lib/omnigraph` itself, the state directory of a static user (D13) | systemd 262 id-maps a `DynamicUser` state directory owned by root or `nobody`, and that fails while a dataset is mounted below it: every unit failed with `Failed to create an id-mapped mount: Device or resource busy` (`logs/cam127b-local-root-red-20261126-003539.log`; A241) |
| D13 first form: the static user only for a local root | The static user `omnigraph` on both stores | The same user on both stores means switching stores changes no unit's user and no state directory; the first deploy moved the `DynamicUser` directory to a plain `/var/lib/omnigraph`, left `65534:65534` behind an id-mapped mount (task 2.8) |
| (none planned) D14 | `omnigraph optimize` forbidden on a local root by an assertion | In the runtime test a direct `optimize` left its admission lock behind, and the next start met a direct writer's lock the recovery rightly refuses (A242) |
| D3: the store as a `let` value | An option, then `flake.lib.omnigraphClusterRoots.stores.magnetite` that the host table and the backup follow | The check evaluates magnetite on the other store through `extendModules`; then finding 1 |
| (none planned) 6.1–6.4, 7.1–7.5, 8.1 | Three groups of remedies | Findings 1–7 of the verification runs |
| Restore procedure (2.7) | Timer stopped with the server, the chosen snapshot rather than `latest`, `@pre-restore` before emptying; restic records `omnigraph`'s uid, not `0:0` | Review of `7d02f0a58` (L4) and the runtime test's first run on `72596929` |
| 5.3 (a restore from a workstation) | Reworded to the in-place drill; 5.6 added for the restore without the host | Both rehearsed on 2026-11-27 (`OmnigraphRestoreDrill.md`) |
| D6 | The gauge `vanixiets_omnigraph_graph_reads_ok` and a journal line per failed read | The first probe deploy found `GET /graphs` answering 403 to `monitor` on the R2 root, logged nowhere |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | no (`tasks.md` carried the plan; no `plan.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | yes (the saved reports in §0) |
| (transitive) superpowers:test-driven-development | yes for the rehearsal rows of `72596929` and every remedy of groups 6 and 7 (red logs named in `tasks.md`); no for the delivery commits' first runtime-test cases, whose red runs are design findings rather than tests written first |
| (transitive) superpowers:requesting-code-review  | yes (review of `7d02f0a58` on 2026-11-26, fixed in `72596929`; verify.md, In Review gates) |
| superpowers:finishing-a-development-branch       | yes (the delivery and remedy commits merged to `main`) |

### Deliberately Skipped Skills

- **`superpowers:writing-plans`**
  - **What was skipped**: a separate `plan.md`.
  - **Why this cycle**: `tasks.md` held each task with its verification command and owner files from `7ffb76200`, and verify §7 records that no row is marked `[~]` because no `plan.md` exists.
  - **How to prevent recurrence**: `scope-judgment rule` — a `tasks.md` whose every task names its verify command stands as the plan; say so in `tasks.md`'s header rather than leaving the artifact absent without a note.
- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill.
  - **Why this cycle**: the repository is jj-colocated; each delivery and remedy landed as its own chain on the development join. A second jj workspace made once during the first remedies left the shared checkout stale (`Cam127VerifyFixes.md`, Process).
  - **How to prevent recurrence**: `schema graph fix` — accept a jj chain in the shared working copy as the isolation mechanism in a jj repository, and say that a second workspace is not one; the same answer as the archived `serialise-shared-reference-tree-writes` retrospective.

## 5. Surprises

- systemd 262 cannot create a `DynamicUser` state directory's id-mapped mount with a dataset mounted below it, and after moving such a directory to a static user leaves it `65534:65534` behind an id-mapped mount rather than chowning it (A241, design D13).
- `omnigraph optimize` run directly against a local root keeps its admission lock (A242).
- restic records the snapshot directory's files with `omnigraph`'s uid and gid, not `0:0` as the runbook first said (`72596929`).
- nixpkgs' restic module runs `unlock` after `backup`, so a stale exclusive lock refuses every later backup (verify finding 2).
- `switch-to-configuration boot` installs the boot loader and exits without activating (verify finding 7).
- A NixOS test VM ignores `fileSystems`; the dataset had to be declared through `virtualisation.fileSystems` (`Cam127LocalRootSupport-latest.md`).
- The module system rejects a definition of an undeclared option even under a false `mkIf` (`c8ee415b5`).

## The reset of magnetite on 2026-11-27

magnetite reset without a shutdown at about 05:20:30Z while `omnigraph-server` (pid 2243500) served the local root, and booted at 05:21:38Z (verify §4, "The stale-lock recovery at the reset").
At 05:22:01Z the recovery found the dead server's serve lock `01M8DNH1BVCDGSB87QDAHK164C` (taken 04:51:55Z, before the boot), found its pid absent in the new boot, reached row 12 of D4, and cleared it by its exact id, running `cluster status` and `force-unlock` as `omnigraph`.
The server served at 05:22:04.57Z, start to ready 4.232 s; the counter went from 0 to 1; one low-priority `omnigraph lock recovered on magnetite` notice was posted; entity counts and stored-query answers equalled those before.
This was the recovery's first real crash, and it cleared the lock by itself. It exercised "the pid is gone", not "the pid now runs another program", which only the rehearsal and the runtime test hold.
Stored `vanixiets_omnigraph_ready` stayed 1, because the outage of about 95 s fell between probe runs; the nightly backup had ended at 03:40:34Z and left neither `@restic` nor a restic lock.

## 6. Promote candidates → long-term learning

- [ ] [high] **Evaluate a host on every value its documented way back sets before switching it.**
  → **Promote to** skill (`openspec-verify-change`, section 4)
  > **Why**: magnetite's way back to R2 failed evaluation on an assertion no check read, and was found only by evaluating the whole toplevel on `"r2"` after the switch (verify finding 1).
  > **How to apply**: any change that adds a reversible per-host setting; evaluate the toplevel on each value before the deploy that leaves the old one.
- [ ] [med] **A restic job needs `restic unlock` before `backup`.**
  → **Promote to** memory
  > **Why**: nixpkgs' order leaves an interrupted prune's or check's exclusive lock in front of every later backup (verify finding 2).
  > **How to apply**: any `services.restic.backups` job with `pruneOpts` or `checkOpts`.
- [ ] [med] **A program whose failure must be announced needs one exit path for every failure, its own steps included.**
  → **Promote to** memory
  > **Why**: an unguarded `jq` under `errexit` ended the recovery before it refused (verify finding 6); the `ERR` trap under `errtrace` closed it.
  > **How to apply**: shell programs that post a notice on refusal; drive each step to fail over a stub and check that the notice is sent.
- [ ] [med] **Runtime tests must be evaluated on every pull request.**
  → **Promote to** schema (the check `feat(checks): fail a pull request whose runtime test does not evaluate`, not yet on `main`)
  > **Why**: `omnigraph-seed` did not evaluate for about 23 hours, and two new tests worked around the cause (`c8ee415b5`).
  > **How to apply**: a module imported by test nodes that sets options from another module.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| A signal (a stop during the start, an OOM kill) ends the recovery without a refusal; killed between a confirmed `force-unlock` and its post, the lock is gone with no count and no notice (verify, warnings not taken up) | no change or issue holds it yet; carried in the CAM-127 qualifications of `satisfaction.md` |
| `restic unlock` keeps a lock of this host younger than 30 minutes whose pid now runs another program, and sends that program SIGHUP; it skips a lock R2 holds unreadable, which still refuses the backup (verify, warnings not taken up) | no change or issue holds it yet; carried in the CAM-127 qualifications of `satisfaction.md` |
| The remedies of groups 6 to 8 were not deployed at verification: the first nightly `restic-backups-postgresql` (about 02:30Z) and `restic-backups-omnigraph` (about 03:30Z) runs with `unlock` before `backup`, a refusal and its notice on the host, and the lock-recovery tile showing 1 are unobserved (verify, Overall Decision) | magnetite's next deploy and the journals of the night after it; the omnigraph view at its next reading |
| The activation's textfile cleanup has not run on a real switch to `"r2"` (verify, Overall Decision) | the first switch of magnetite back to R2 |
| `s3://sciexp/omnigraph/clusters/cookbooks-f17` and its marker stay as the way back to R2; deleting them removes it (verify §5) | kept; no change or issue holds a decision on it |
| The retired roots `dev-graph` and `dev-graph-v9` and the rollback root `dev-graph-v10` still hold objects (oldest 2026-08-06 and 2026-10-01) although their lifecycle rules in `modules/terranix/cloudflare.nix` delete objects older than a day; the rules on `sciexp` could not be read with the `omnigraph-r2` token (403), so whether they were applied is unknown (verify §5) | an explicit operator decision on the roots and their rules before any deletion; no change or issue holds it yet |
| `omnigraph optimize` is not available on a local root (D14, A242); compaction waits on served optimize or a `cleanup` with the server stopped (A240) | the assertion stays until an OmniGraph release releases the lock; reviewed at each OmniGraph bump (design, Gate 1 table) |
| The restore without the host depends on a workstation holding the admin age key that decrypts `omnigraph-backup-r2` and `omnigraph-backup-restic` (verify §5; task 5.6) | the runbook's "Restoring without the host"; the key's custody is outside this change |
| The per-graph panels have data only since the switch (2026-11-26 17:12Z); their first week, and how the view reads it, is ahead (verify §5) | the omnigraph view after 2026-12-03 |
| `omnigraph-r2`'s credential stays deployed on magnetite while nothing uses it; pyrite's `cameron` has no omnigraph credential, so the documented aliases do not answer there (verify §5) | no change or issue holds it yet |
