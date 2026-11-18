# Verification Report

**Change**: `pin-apm-dependencies-in-apm-yml` (CAM-110)
**Verified at**: `2026-11-18 19:50` UTC
**Verifier**: `Cam110Verify` subagent, running the `openspec-verify-change` skill over the schema `superpowers-bridge-wrspm`

Evidence names are files under `logs/`, which is git-ignored.
Times are UTC.
Implementation: #4007, merged as `146c9591` on parent `433a2c34`. Relock: #4008, merged as `9a762a0b`.

## Summary

| Dimension | Status |
|---|---|
| Completeness | 24/24 tasks; 10 ADDED interface and 6 ADDED world requirements covered; 3 removals confirmed |
| Correctness | 16/16 ADDED requirements map to code and evidence; 1 scenario only partly covered (W2) |
| Coherence | D1-D8 followed; W1 (D1 and one spec scenario misstated where the download is copied) resolved in this commit |

## 1. Structural Validation (`openspec validate --all --json`)

- [x] Every item belonging to this change reports `"valid": true`

**Result**:

```text
openspec validate --all --json: 58 items, 56 valid.
Invalid: stand-up-gitea-mq-on-magnetite, stand-up-nixbot-on-magnetite. Both fail only on
"Requirement text is very long (>500 characters)" warnings in their own delta specs; neither is this change.
openspec validate pin-apm-dependencies-in-apm-yml --strict: Change 'pin-apm-dependencies-in-apm-yml' is valid
```

| Item | Type | Issues |
|---|---|---|
| stand-up-gitea-mq-on-magnetite | change | long-requirement warnings in `merge-queue-interface`; another change, outside this verification |
| stand-up-nixbot-on-magnetite | change | long-requirement warnings in `world-assumptions`; another change, outside this verification |

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

`openspec instructions apply` tracks `tasks.md`. All 24 checkboxes are ticked, each with a dated sub-bullet that names its log.
This verification ticked group 8. The evidence for each item is recorded under it in `tasks.md`:

- 8.1: the compose diff and the upstream-parity logs.
- 8.2: `logs/cam110-8.2-toplevels-20261118-144814.log`. At main `9a762a0b`, both toplevels evaluate to each host's realised `/run/current-system`, and each closure holds the compose its system evaluates to.
- 8.3: the stibnite skills log and `logs/cam110-8.3-8.4-ntfy-20261118-144519.log`. No alert or notice was posted.
- 8.4: the pyrite deploy log and `logs/cam110-8.4-pyrite-generation-diff-20261118-144647.log`, which compares generation 107 against 108; the ntfy record also covers this activation.
- 8.5: the relock logs and `logs/cam110-8.5-agents-install-20261118-144455.log`. The frozen install exits 0, and the lock is byte-identical before and after.

**Incomplete tasks**: none.

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `third-party-plugin-dependency` | pending sync | The main spec still holds the three REMOVED requirements and none of the 10 ADDED ones; archive applies both. |
| `world-assumptions` | pending sync | A136-A141 are absent from the main spec; archive appends them. |

### REMOVED requirements: the old behavior is gone

Each baseline is the requirement of the same name in `openspec/specs/third-party-plugin-dependency/spec.md`.

| Removed requirement | Baseline behavior searched for | Result |
|---|---|---|
| First-party packages declare nix-pinned apm dependencies on upstream plugins | `fetchFromGitHub` fetchers feeding the compose; the `*Src`/`*Rev` options; pre-seed and replace-ref blocks; `gitMinimal` in the compose | Removed. `rg 'superpowersSrc\|agencySrc\|worktrunkSrc\|pre-seed\|replace-ref\|gitMinimal'` over `pkgs/by-name/apm-skills-compose`, `modules/home/ai` and `modules/checks` finds nothing. `pkgs/by-name/agent-plugins/` holds only the six marketplace fetchers. The single `fetchFromGitHub` left in a check, `modules/checks/structure/cli-skill-release-alignment.nix:86`, is D6's gh-stack content-equality proof and feeds nothing into the composition. |
| Upstream plugins consumed without forking and extended additively | whole-repository `MARKETPLACE_PLUGIN` consumption of superpowers and agency resolved through a pre-seeded checkout | Removed. `modules/home/ai/plugins/planning-and-development/apm.yml:13-30` declares only per-skill paths, and the guard rejects a whole-repository entry (task 1.2, `logs/cam110-guard-realtree-20261118-131732.log`). The additive no-fork rules continue under the ADDED requirement. |
| Release-aligned offline Mergify skill dependency | `structure-mergify-release-alignment`, which compared `agent-plugins-mergify-cli`'s version with `mergify-cli-bin`'s | Removed. `modules/checks/structure/` holds `cli-skill-release-alignment.nix` and `flake-shape.nix`, and `rg mergify-release-alignment modules` finds nothing. |

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs / code correspondence | Gap |
|---|---|---|---|
| D1 fixed-output download | `apm-deps-<digest>`, recursive hash, `apm lock`, `_local` removed, `generated_at`/`apm_version` deleted | `pkgs/by-name/apm-skills-compose/deps.nix:67-69,91,94`. The output lock holds 26 remote entries, each with `resolved_commit` and `content_hash`, and has no timestamp, apm version or `deployed_files` (`/nix/store/b8rfbmz3…-apm-deps-aee8f99f…/apm.lock.yaml`). | W1 (copy location), resolved (below) |
| D2 guard digest | the first 32 hex characters of sha256 over `{ apm = apm.version; deps; }`, with no import-from-derivation | `guard.nix:146`; proved with import-from-derivation disabled (task 1.2) | none |
| D3 per-skill entries and fifth rule | 15 + 3 entries at one ref per repository; blobless `ls-tree` listing inside the fixed-output build | `apm.yml:13-30`; `deps.nix:50-51`; mutant fails naming `diagnosing-superpowers` (task 1.4) | none |
| D4 agency subagents and rule dropped | skills kept, agents and rule not delivered | stibnite: hickey, lowy and fact-check present, 0 agency agents, no `do-stop-guard` | none |
| D5 key on `apm.version` | not the store path | `deps.nix:29`; apm 0.35.1 renames the download (task 1.5b) | none |
| D6 one alignment rule over five pairs | `sourceRev` per CLI, a static key set, a negative control, the gh-stack tag proof | `modules/checks/structure/cli-skill-release-alignment.nix`; six attributes build; mutants fail (tasks 4.4-4.5) | none |
| D7 keep carried LICENSE files | `apmDepsHash` moves with apm's normalization | `carried_licenses` in the download lock; one hash on both platforms (task 1.3) | none |
| D8 bump plus post-merge relock; stray locks removed | the root lock follows the merge | #4007 leaves `apm.lock.yaml` unchanged (`git diff --stat 433a2c34 146c9591 -- apm.lock.yaml` is empty); #4008 relocks; no `modules/home/ai/plugins/*/apm.lock.yaml` remains | none |

**Drift warnings** (non-blocking):

- W1 (resolved in this commit). D1 said the compose "copies that output next to the generated root manifest". The scenario `offline root-manifest composition` said the composition "places the download beside it". The code writes the manifest to the build directory (`package.nix:130`) and copies `apm_modules/` and `apm.lock.yaml` under the install root `$out` (`package.nix:125-128`), because apm reads both there. Task 2.1 records that copying beside the manifest failed all 26 dependencies (`logs/cam110-compose-linux-20261118-132404.log`). This commit corrects the scenario in `specs/third-party-plugin-dependency/spec.md`, D1 in `design.md` (with a citation of `package.nix:125-130` and task 2.1's evidence), task 2.1's own statement in `tasks.md`, and Task 4 Step 3's snippet in `plan.md`. The other "beside" occurrences in the change concern other files: the guard and its tests in task 1.2, and the release commit in `brainstorm.md`.

## 5. Implementation Signal

- [x] No unstaged files in the worktree (`jj st`: the working copy has no changes besides this verification chain)
- [x] All related commits have been pushed and merged

**Commit range**: `433a2c34..146c9591` (#4007, implementation) and `146c9591..9a762a0b` (#4008, relock). CI for #4007 built 287 attributes; #4008's nixbot eval, build and effects succeeded (`logs/pr-cam-110-relock-20261118-140155.log`).

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files: `ls docs/superpowers/specs/*.md` prints nothing.

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows. The live-environment checks (marketplace 3.2, activations 8.3 and 8.4, relock 8.5) were run, not deferred, so this section is empty by rule.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

## 8. Designation Lint and Discharge Coherence

These are checks the agent carried out by reading; `openspec validate` does not perform them.

### 8a. Designation lint

The proposal tags `third-party-plugin-dependency` `interface` and `world-assumptions` `world`; no capability is tagged `behavioral`.
The lint therefore has no input; this is not a clean lint result.

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Remote apm dependency commits are written once, in the declaring package's manifest | guard: full-SHA and line-shape throws, 17/17 nix-unit fixtures (1.2); retired fetchers (5.1) | — | discharged |
| Remote apm dependencies are downloaded in one guarded fixed-output derivation | `deps.nix` with the D2 digest; same hash on both platforms and `--rebuild` (1.3); ref and apm mutants renamed and failed; unrelated edits kept the name (1.5) | A139, A140, A141 | discharged |
| The composition installs remote apm dependencies offline from the download | `package.nix:111-133`; 26/26 `(cached)`; git-on-PATH, withheld-download and missing-dependency controls fail (2.1) | A136, A140 | discharged |
| superpowers and agency are consumed per skill directory | `apm.yml:13-30`; parity with upstream and no hook files (3.1); plain apm on seven targets (3.2); fifth-rule mutant (1.4) | A137, A141 | discharged |
| A same-ref check guards the per-skill upstream dependencies | guard rules 1-4: mixed-ref, whole-repository and path fixtures throw (1.2) | — | discharged |
| Upstream plugins are extended additively without forking | inspection: the compose has no patch or override layer; the bridge schema stays a home-manager module | — | discharged (inspection, per its trust boundary) |
| Each CLI and its agent skill resolve to the same upstream release | five alignment attributes build; moved-ref mutants fail naming both commits (4.2-4.5) | — | discharged |
| The release-alignment checker is exercised with a deliberate mismatch | the negative control builds and fails when the comparison always passes (4.5) | — | discharged |
| Upstream tool skills are delivered unmodified | worktrunk, gh-stack and superpowers parity diffs empty (3.1, 4.3, 4.4); `structure-playwright-skill-parity` with its mutant (4.6) | A138 | discharged |
| A remote apm dependency bump is one reviewed manifest edit | updaters move `sourceRev` and the ref together (4.2, 4.3); a ref change without a hash update fails printing the new hash (1.5a) | A139 | partly discharged, W2 |
| The root apm lock is refreshed after a dependency change reaches main | #4007 leaves the root lock unchanged; #4008 relock; frozen install exits 0 (8.5) | — | discharged |
| A136 — apm installs a locked remote dependency from apm_modules without fetching | — | — | observed: 26/26 `(cached)` with no git and no network (2.1) |
| A137 — apm installs a virtual-subdirectory dependency as that directory alone | — | — | observed: no superpowers or agency hook in either tree or on any of seven targets (3.1, 3.2) |
| A138 — apm removes a downloaded package whose content no longer matches its lock | — | — | not violated: not exercised in this cycle; evidence is the earlier F6 code read |
| A139 — apm's download bytes change only with apm's version | — | — | observed for apm 0.36.0: one hash on both platforms and on `--rebuild` (1.3); 0.35.1 differs (1.5b) |
| A140 — apm lock records commits and content hashes but no deployed files | — | — | observed: the download lock holds 26 entries with commit and content hash and no `deployed_files` |
| A141 — GitHub serves a shallow, blobless fetch of a commit by its SHA | — | — | observed: sandboxed probe on both systems (1.1) and the fifth rule in every download build (1.4) |

### 8c. Alphabet check

The interface requirements name only machine-observable phenomena: manifests, refs, derivation names, hashes, build results, file trees and check attributes.
What the machine cannot observe (whether an upstream commit is benign, how a marketplace user's harness behaves, whether a harness loads the skills) appears only in their trust boundaries, as exclusions.
The world requirements name apm and GitHub behaviour, not repository interfaces. No violations.

## Issues by Priority

**CRITICAL**: none.

**WARNING**:

- W1 (resolved in this commit, record kept). Design decision and spec scenario wording diverged from the code on where the download is copied: `design.md` D1 said "next to the generated root manifest", the delta scenario said "beside it", and `pkgs/by-name/apm-skills-compose/package.nix:125-130` copies it under the install root `$out`. Resolution: the scenario, D1, task 2.1's statement and plan Task 4 Step 3 now say it is copied under the install root, and D1 cites `package.nix:125-130` and task 2.1's failing-"beside" evidence.
- W2. Scenario `a bump touches two places` is covered only in parts. The updater scratch runs (4.2, 4.3) and the hash-mismatch mutant (1.5a) show each step, but no single bump diff was observed touching only `ref:` lines, `apmDepsHash` and the recorded commit; #4007 was itself the migration and touched more. Recommendation: record the next real bump (the next superpowers or worktrunk release) as the evidence, or have a scratch-copy run of `worktrunk-bin/update.sh` plus a hash update show `git diff --stat` limited to `version-control-and-forge/apm.yml`, `worktrunk-bin/package.nix` and `apm-skills-compose/package.nix`.
- W3. Pyrite's before-tree for 8.4 was reconstructed from system generation 107's home-manager files, not dereferenced from the live tree before activation as 8.3's method states. The two are equivalent for skills that home-manager delivers, and the live after-tree was compared directly. Recommendation: none for this change; future activation tasks should save the live before-snapshot.

**SUGGESTION**:

- S1. `~/.claude/skills/harborize` on stibnite is a hand-made symlink from 2026-08-14 that has dangled since then, into a draft-branch path (#2747). It is pre-existing and outside this change's scope, and the stibnite log's dangling-link count missed it. Recommendation: remove the link or land #2747; for future counts, use `find -xtype l`.
- S2. `moshi-visuals` under pyrite's `~cameron/.claude/skills` is an unmanaged file, written at 19:42:03Z under cameron's account, that no generation contains. It is outside this change's scope. Recommendation: none here; noted so later skill-tree diffs on pyrite do not attribute it to the compose.

**Final assessment**: No critical issues. 2 open warnings to consider (W2, W3), 1 warning resolved in this commit (W1), and 2 suggestions. Ready for archive (with noted improvements).

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: W2, the bump scenario is evidenced only in parts; W3, pyrite's before-tree was reconstructed from generation 107. W1 (the copy-location wording in D1 and the offline-composition scenario) is resolved in this commit.
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

In Review: roborev (code review), then documenter (docs review). Write `retrospective.md`, then archive (`openspec-archive-change`), which fires In Review to Done and the document upsert for project `pi-agent-environment`.
