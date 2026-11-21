# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `bootstrap-claude-sandbox` (CAM-118)
**Verified at**: `2026-11-21 22:56` UTC
**Verifier**: subagent `SandboxChangeAuthor` (omp), running `openspec-verify-change` and this schema's checks 1–8

Prechecks: `git log --oneline $(git merge-base HEAD origin/main)..HEAD | wc -l` returned 2, and `tasks.md` holds 32 `- [x]` lines, so both are positive.
The implementation is on `origin/main`, from `090fca026` (`feat(claude-sandbox): add the claude-sandbox profile and the shared sandbox aggregate`) to `7c2a300ba` (`refactor(sandbox): name the cloud workspace directory once`).

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
totals: 64 items, 62 passed, 2 failed (changes 33/31, specs 31/31)
bootstrap-claude-sandbox: valid: true, 1 WARNING:
  world-assumptions/spec.md: MODIFIED "Grounded vocabulary for behavioral requirements":
  Requirement text is very long (>500 characters).
`openspec validate bootstrap-claude-sandbox --strict`: fails on that same warning alone.
```

The two failures are other changes, not this one:

| Item | Type | Issues |
|---|---|---|
| `stand-up-gitea-mq-on-magnetite` | change | its MODIFIED "Grounded vocabulary for behavioral requirements" omits the scenario "The terms with two senses are read" that the main spec now has |
| `stand-up-nixbot-on-magnetite` | change | the same |

This change's one warning is structural and known: OpenSpec 2.1.1 warns on a MODIFIED requirement over 500 characters that is longer than the main spec's version, and every designation row this change adds lengthens the designation table.
Many active changes that add rows carry the same warning; it is not fixable without moving the rows out of the table, which `rules.specs` forbids.
`--strict` therefore exits non-zero for this change, on that warning alone.

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

`openspec instructions apply` reports `progress: {total: 32, complete: 32, remaining: 0}` with task tracking configured and no unavailable tracking files.

**Incomplete tasks**: none.

Ticked clauses that do not hold as originally written, each reworded or annotated in `tasks.md` with a dated note (2026-11-21), stated here so no reader takes them as met verbatim:

| Task | What differs from the original clause |
|---|---|
| 2.1 | The clause names an Edit call; the stibnite run made a Write call, which the same `Edit\|Write\|MultiEdit` matcher sends to the same hook. |
| 3.4 | Reworded: the hook's own `PATH` and `CLAUDE_ENV_FILE` were never printed; S7 is shown by E2's snapshot start logging both hooks with no setup run, S8 by `SOPS_AGE_KEY=set` plus `session-secrets status=ok`; the hook's environment is moot because hooks run by store path (D4) and tools reach `PATH` through the default profile (A180). |
| 5.2 | Reworded to exclude `/root/.claude/projects`, where the one hit was the session's own transcript quoting the patterns; `rg` does not follow symlinks, so the credentials symlink's target was not read; rendered secrets live on `/dev/shm` by design. |
| 7.2 | The Default child probed 12 of R12's tools by name, not all; session 4's E1 called every one (8.1). The 30-day renewal is a standing obligation. |
| 7.3 | Done for the 15 branches it lists; the task 7.2 report branches `claude/sandbox-reports-72` and `-72c` exist at verification time, so its verify command prints them until they are deleted after this change records their content. |
| 8.3 | Reworded: the baseline is Default, which has a setup step (a ghq install) that writes nothing under `/root/.claude`; `launcher-settings.json` differs in size (3039 B against 906 B), and `nix eval` shows the profile never writes it or any other harness path. |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `claude-sandbox-bootstrap` | pending sync | new capability; no `openspec/specs/claude-sandbox-bootstrap/` yet |
| `world-assumptions` | pending sync | adds A167–A183 and the cloud-session designation rows; its MODIFIED table was built from the main spec and must be re-checked against any table rows other changes sync first |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D2 | the setup script names the activation package by store path, realises it from two caches, evaluates nothing, ends in `exit 0` | `One closure defines the environment`; `Setup never prevents a session from starting` | none; implemented in `modules/apps/claude-sandbox-setup-script.nix`, held by `modules/checks/claude-sandbox-setup-script.nix` |
| D3 | SessionStart hook `claude-sandbox-repo-context` runs `apm-context-compile --auto --if-stale` per attached repository | `Attached repositories get their repository context`; `User context is not repeated in repository context` | none; `modules/home/users/claude-sandbox/default.nix` |
| D4 | hook commands by store path | `Required tools present` (indirectly), R8, R14 | none; assertion in `modules/home/ai/claude-code/hooks.nix:34-36` |
| D5 | scoped recipient and file, decrypted at session start into `/dev/shm`, never at activation | `No secret at rest`; `Linear skills in cloud sessions` | none; `.sops.yaml:59`, `modules/checks/claude-sandbox-session-secrets.nix` |
| A183 | `/home/user` is no account's home | `vanixiets.sandbox.workspaceDirectory` (`modules/home/sandbox/default.nix:41`) | none |

**Drift warnings** (non-blocking):

- None between design.md and the specs. design.md keeps A176 and S4 from the dropped bootstrap sub-flake; both are marked as no longer relied on (S4 "dropped", and A176's violation scenario says no `claude-sandbox-bootstrap` requirement rests on it since Q91), so this is history, not drift.
- Open observation, design.md §Open Questions: `ghq.root` set by the profile in `/root/.config/git/config` was not visible to `git config --global` in a cloud session, though ghq still cloned to `/home/user/ghq`; the same shadowing could affect the commit author identity. Not yet explained; probe at the next renewal.

---

## 5. Implementation Signal

- [ ] No unstaged files in the worktree
- [ ] All related commits have been pushed

The implementation commits are on `origin/main` (`090fca026..7c2a300ba`).
This verification's own artifact edits (tasks.md, design.md, the world-assumptions delta, this file) were in the jj working copy at verification time and are squashed into change `tnxtmwtr`, which is not pushed; publishing is the orchestrator's step.

**Commit range**: `090fca026..7c2a300ba` (implementation); `tnxtmwtr` (this round's artifacts, unpublished).

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` lists nothing.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows, so this section is blank by rule.
The cloud checks were run, not deferred: sessions 3, 4 and the task 7.2 round, quoted in `tasks.md`.

---

## 8. Designation Lint and Discharge Coherence (agent-executed, non-blocking; not validation)

### 8a. Designation lint

Resolved against the designation table as this change's `world-assumptions` delta leaves it (the main spec lacks the new rows until sync).
Lexer pass over the behavioral capability `claude-sandbox-bootstrap`; resolved nouns are not listed.

| Requirement | Unresolved or mis-sensed noun | Finding |
|---|---|---|
| One closure defines the environment | `activation package`, `store path`, `flake` | no row; machine phenomena, so by `rules.specs` they belong in an interface capability, which this change has not added |
| One closure defines the environment | `closure` | the existing row's sense is "the complete built system a configuration produces for one host"; here it is a home configuration's closure, a second sense needing its own row |
| No secret at rest | `disk` (the container's disk) | no row; only `disk share` and `disk health` exist |
| Linear skills in cloud sessions | `credential` | three rows exist (notification service, service database) and `operator credential`; none is this sense (an agent's Linear key the operator holds) |
| Required tools present | `interactive terminal`, `clipboard` | no rows |
| One source for agent context and skills | `definitions in this repository` | no row; vague |

### 8b. Discharge coherence

S names design decisions (no interface capability exists yet). W statuses: `observed` means the assumption's own claim was seen to hold, in the sessions named, all on 2026-11-21; nothing here has been observed across the documented seven-day snapshot expiry or the 30-day cache window.

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| Context and skills from the first prompt | D1, D2 | A167, A168, A172, A174, A178 observed; S2, S3 observed (sessions 3, 4, 7.2) | discharged (8.1, 7.2) |
| One closure defines the environment | D2 | A175, A177, A181 observed; S1 observed only for "a script change triggers a new setup run" (session 4), not for the seven-day expiry | discharged; renewal liveness unobserved |
| Setup never prevents a session from starting | D2 | A170 observed | discharged (8.2) |
| Setup finishes within the snapshot window | D2 | A169 observed once at 360 s; S5 observed (31 s for 5,226,590,784 bytes) | discharged |
| Additive to harness-owned state | D1 | A178 observed | discharged (8.3, with its reworded clause) |
| No secret at rest | D2, D5 | A172 observed; S8 observed | discharged (5.2, with its reworded clause and stated limits) |
| Every bootstrap run reports | D2 | A179 observed | discharged (8.1, 8.2) |
| Attached repositories get their repository context | D3 | A172, A175, A183 observed; S7 observed (session 4 E2) | discharged (4.1) |
| User context is not repeated in repository context | D3 | A167 observed | discharged (4.2) |
| One operator action per development iteration | controller loop | A179 observed | discharged (8.4, 7.2) |
| Idempotent setup without external side effects | D2 | A171, A182 observed | discharged (5.1 in a container; the cloud's double run seen in sessions 3 and 4) |
| Required tools present | D1, D4 | A173, A180 observed | discharged (8.1) |
| One source for agent context and skills | D1 | — (a property of the repository: `CLAUDE.md` is crs58's own store path, task 1.4) | discharged by evaluation |
| Linear skills in cloud sessions | D5 | A172 observed; S7, S8, S9, S10 observed | discharged (8.1, 7.2) |

No requirement is undischarged.

### 8c. Alphabet check

- `One closure defines the environment` (behavioral) names interface phenomena: `activation package`, `store path`, `flake`. Recorded, not rewritten here.
- `Additive to harness-owned state` names the platform's launcher settings, hooks, synced skills and the Claude Code program; these are listed in the `harness-owned state` row's world phenomenon, so they resolve.
- The `world-assumptions` requirements A167–A183 quote commands and paths as evidence in their monitoring scenarios; their statements are indicative, so this is not an alphabet violation.
- No interface capability exists, so the interface-side check is not applicable.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `openspec validate --strict` fails on the known structural warning (§1); the 2.1, 3.4, 5.2, 7.2, 7.3 and 8.3 clauses are met only as reworded or annotated (§2); the designation lint finds machine nouns in `One closure defines the environment` and four nouns without a fitting row (§8a); the ghq-root shadowing is unexplained (§4); both delta specs await sync (§3).
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

No critical issues found: every task is ticked and every requirement has implementation evidence.
Warnings: 5 (the §1 structural warning, the reworded clauses, the §8a lint findings, the §8c alphabet finding, the ghq observation).
Suggestion: 1, to add an interface capability carrying the closure, store-path and flake vocabulary when the lint findings are addressed.

**Next step**:

Delete the branches `claude/sandbox-reports-72` and `-72c` (their content is now in `tasks.md` and `design.md`), then archive: sync both delta specs, regenerate the satisfaction projection as `config.yaml` directs, and mirror the specs to the `pi-agent-environment` project's documents.
Before or at that archive, decide whether to fix the §8a findings (rows for the new senses, and moving the closure wording into an interface capability) or record them as follow-ups in the retrospective.
