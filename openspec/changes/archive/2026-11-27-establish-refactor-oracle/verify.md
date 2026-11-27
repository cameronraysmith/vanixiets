# Verification Report

**Change**: `establish-refactor-oracle`
**Verified at**: `2026-11-27 04:00` (UTC)
**Verifier**: `verify-den-ready-1` (openspec-verify-change, HIL verify phase)

Code verified: jj change `mrsktorvvtqs` (commit `e7bd270f6d83`, feat(apps): drv-diff and eval-cost) and `yxruvwlsxllr` (commit `2ac5a55e96db`, docs and change files), read with `jj --ignore-working-copy file show`.
The working copy's `modules/apps/{drv-diff,eval-cost}.{nix,sh}`, `drv-diff-base-allow.txt` and `justfile` are identical to `2ac5a55e96db` (`git diff 2ac5a55e96db -- …` empty), and the built app `/nix/store/naghnpqx4js4kffsnr8dq7nfv0v0dv9z-drv-diff` (from `nix eval --raw .#apps.aarch64-darwin.drv-diff.program`) carries `--reuse`, so the checks below that ran that program ran this change's code.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
81 items: 76 passed, 5 failed (all 35 specs pass; 5 of 46 changes fail).
openspec validate establish-refactor-oracle --json: valid, 0 issues.
```

The five failures are other changes of the project with no delta yet; none is this change:

| Item | Type | Issues |
|---|---|---|
| compose-hosts-from-cohesive-aspects | change | no deltas found |
| declare-host-user-relations-once | change | no deltas found |
| seam-secrets-away-from-clan-vars | change | no deltas found |
| stand-up-gitea-mq-on-magnetite | change | invalid (not this change) |
| stand-up-nixbot-on-magnetite | change | invalid (not this change) |

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

24 of 24 tasks checked; no `- [ ]` remains.

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| refactor-identity-oracle | pending sync | new capability; no `openspec/specs/refactor-identity-oracle/` yet |
| refactor-identity-oracle-interface | pending sync | new capability; no main spec yet |
| world-assumptions | pending sync | ADDED A310–A313 (absent from the main spec); MODIFIED grounded-vocabulary requirement copies the corpus table, appends rows and adds `evaluator` to the three-sense list. Merge by hand at archive with rows other changes added since (design, Risks: declare-test-size-classes' `check` row and `run` sense) |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D2 seven maps | nixos, darwin, home, `checks.<s>`, `vmTests.<s>`; defaults x86_64-linux/aarch64-darwin and x86_64-linux/aarch64-linux | interface "dumps seven drvPath maps", scenario "The default maps" | none |
| D5 revisions by commit | `git rev-parse --verify <rev>^{commit}`, `git+file://…?rev=` | "reads each side from its commit only" | none |
| D6/D7 allow-list and exits | four expectations, exact attributes, exit 0/1/2, failing-at-both listed | allow-list, exit, failing-to-evaluate requirements | none |
| D13 base allow-list | whole-source or per-kind checks, permanent `may-change`, duplicates exit 2 | "Checks built from the whole repository are allowed once" | none |
| D14 re-judgement | `--reuse DIR`, new `report.<UTC>`, original untouched | "A recorded run can be re-judged without evaluating" | none |
| D8/D9 cost protocol and baselines | warm-up, interleaved fresh runs, five figures, header conditions, committed note | eval-cost requirements; behavioral cost-claim requirement | none |

**Drift warnings** (non-blocking):

- none between design and specs. One implementation-to-spec divergence was listed under Findings (W2); it is resolved by rewording the spec and plan.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree (for this change's code: working copy equals `2ac5a55e96db` for every code file; the shared jj join's working copy holds other changes' edits, not inspected here)
- [ ] All related commits have been pushed (not pushed; on the shared join, unpublished)

**Commit range**: `398623707d36..2ac5a55e96db` (`mrsktorvvtqs`, `yxruvwlsxllr`), on trunk `14a6b01878c3`.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` prints nothing.

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

plan.md has no `[~]` rows; section left blank by the template's rule.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## Requirement traceability

Evidence directories: `R` = `logs/drv-diff-b718b62ec596-07877c74b4e5-20261127T012031Z` (this change's run, 857.5 s, `report.20261127T015155Z` the re-judgement against the current base list); `M` = `logs/drv-diff-096de303b53b-8270a07764a7-20261127T013526Z` (mutant, 831.1 s, reports `report.20261127T0151{56,57,58}Z*`).
"This run" = re-judgements and negative cases I ran on 2026-11-27 with the built app; each took under a second and evaluated nothing. Files they wrote into `M` were removed afterwards; the synthetic directories were in a temp dir.

### refactor-identity-oracle-interface

| Requirement / scenario | Code | Evidence | Status |
|---|---|---|---|
| Seven maps without building: default maps | `drv-diff.sh:153-155,241-257` | `R/header`: nixos 6, darwin 4, home 20, checks.x86_64-linux 238, checks.aarch64-darwin 115, vmTests.x86_64-linux 21, vmTests.aarch64-linux 3 | verified |
| — commit with itself | `drv-diff.sh:269-275,316-317` | not run as `just drv-diff c c`; this run: `--reuse` on a copy of `M` with each set's before dump as both sides: every set identical, 4 failing-at-both, five base entries "not occurring", PASS, exit 0 | verified on synthetic dumps (W3) |
| — nothing is built | `drv-diff.sh:216-219` (`nix eval --raw …drvPath`), `:231-236` (IFD off) | no `building` or `will be built` line in any `*.err` of `R` or `M` | verified |
| — host added at the candidate | `drv-diff.sh:270` (`added`) | code only; no run had an added attribute | code-traced |
| Each side from its commit: dirty working copy | `drv-diff.sh:110-111,213,229` | both runs made from the shared join's working copy, which holds other changes' edits; their dumps match the commits' traced edits | verified by construction and code |
| — not a commit | `drv-diff.sh:110-111` | this run: `--before nosuchrev123 --after HEAD` → `--before does not name a commit`, exit 2, before any evaluation | verified |
| Evaluator fixed and recorded: `nix` names another evaluator | `drv-diff.nix` (`NIX_STOCK = fleetNix`), `drv-diff.sh:193-200` | `R/header`: `nix-2.35.6` path and version; `nix-eval-jobs-2.35.4` path, whose name carries the version | verified (W2 resolved) |
| Allow-list: malformed entry | `drv-diff.sh:119-146` | this run: bad expectation and bad set each exit 2 naming `file:line` | verified |
| — entry absent at both commits | `drv-diff.sh:289-291` | `M/report.20261127T015158Z` (task 3.3) and this run (`darwin.nosuchhost changed`): exit 2, names the entry | verified |
| Base allow-list: secret-scan check | `drv-diff-base-allow.txt`, `drv-diff.sh:148` | `R/report.20261127T015155Z`: both `gitleaks` "allowed by base", PASS | verified |
| — change repeats a base entry | `drv-diff.sh:150-151` | this run: `checks.x86_64-linux.gitleaks may-change` → exit 2 naming both lines | verified |
| Exit by the allow-list: undeclared difference | `drv-diff.sh:293-317` | `M/report.20261127T015156Z`: UNDECLARED `darwin.argentum` with both drvPaths, FAIL (exit 1) | verified |
| — declared difference | same | `M/report.20261127T015157Z`: declared, PASS | verified |
| — declared, did not happen | same | `M/report.20261127T015157Z-3`: `NOT OCCURRING vmTests.x86_64-linux.devloop-ingest changed`, FAIL | verified |
| — possible difference | same | this run: `darwin.stibnite may-change` listed `not occurring` (non-failing); exit decided by the mutant's other undeclared lines | verified |
| — mutant revision | — | `M/report.20261127T015156Z`: exactly `darwin.argentum` and `checks.aarch64-darwin.darwin-argentum` undeclared, five base checks allowed, nothing else | verified |
| Re-judge without evaluating: allow-list edited | `drv-diff.sh:93-106,161-186` | `R/report.20261127T015155Z` with `ntfy-tls-verification` moved into the base list; original `R/report` unchanged | verified |
| — directory missing a dump / header | `drv-diff.sh:95,163-167` | this run: missing `checks.aarch64-darwin.after.jsonl` → exit 2 naming it; empty dir → exit 2 naming `header`; `--reuse` with `--before` → exit 2 | verified |
| Failing to evaluate: at both | `drv-diff.sh:272,311-312` | `R`: four vmTests listed failing at both, PASS | verified |
| — at the candidate only | `drv-diff.sh:273,278` | code only; no run had a failing-at-one attribute | code-traced |
| `eval-cost` interleaving | `eval-cost.sh:97-121` | baseline logs: rows in order 1 before, 1 after, 2 before, 2 after | verified |
| — key-set mode | `eval-cost.sh:93` | `logs/eval-cost-checks-x86_64-linux-20261127T005938Z.log`: four rows, five figures | verified |
| `eval-cost` records conditions: another evaluation running | `eval-cost.sh:70-85` | `logs/eval-cost-checks-x86_64-linux-20261127T004902Z.log`: header lists a running iets `nix build`; both rows in `.log` and `.jsonl` | verified |

### refactor-identity-oracle (behavioral)

| Requirement | Evidence | Status |
|---|---|---|
| A refactor changes no derivation it did not declare (4 scenarios) | `R/report.20261127T015155Z`: nixos 6, darwin 4, home 20, vmTests 17+3 identical; 34 changed checks = 5 base + 29 `drv-delta.txt` entries; mutant shows undeclared difference fails; base entries named once | verified at `b718b62ec596..07877c74b4e5` (W1) |
| A declared difference happens | `M/report.20261127T015157Z-3` | verified |
| A failure to evaluate is a difference only when new | failing-at-both: `R`; failing-at-one: code only | partial (code-traced for "broken by the refactor") |
| Cost claim on alternating measurements against a recorded baseline | `eval-cost.sh` protocol; `docs/notes/development/eval-cost-baselines.md` three baseline tables, each matching its log; reference table marked "not comparable" | verified |

### world-assumptions

A310–A313 added; grounded-vocabulary rows added (see §8). Discharges recorded in §8b.

### Documents (tasks 5–7)

At `yxruvwlsxllr`: no `### O07/O08/O13` heading; "The five principles" with P5 at `architectural-principles.md:46`; "Planned decomposition as OpenSpec changes" at `:567`; baselines note linked; ADR-0018/0019/0020 each carry `**Amended**` and `## Amendment (2026-11-26)`; `modules/README.md:89` names `just drv-diff`; `modules/home/README.md:32` names `github:denful/den`; no `ssh-known-hosts` under `modules/clan`; `logs/docs-linkcheck-20261126-205552.log` ends `✔ vanixiets-docs-linkcheck… (35s)`.
`architectural-principles.md:13` still says "the four principles are the limit-point compression of those eight"; read as a historical statement about P1–P4, not a stale count (S1).

## Findings

**CRITICAL**: none.

**WARNING** (non-blocking):

- **W1. The oracle's proof of this change is at superseded commits.** Tasks 3.4/8.2 judged `b718b62ec596..07877c74b4e5`. The change has since been rebased onto trunk `14a6b01878c3` (now `398623707d36..2ac5a55e96db`) and edited: `drv-diff.sh` (+`--reuse`, 138 lines), `drv-diff-base-allow.txt` (+`ntfy-tls-verification`), `justfile` (+`drv-diff-rejudge`), the baselines note. The non-openspec, non-app diff of the change is byte-identical across the two (equal `sha1` of `git diff`), and each later edit reaches only checks already declared or base-allowed (`apps-build`, `deploy-stock-nix`, `ntfy-tls-verification`, `treefmt`, `gitleaks`) [INFERENCE]. No run at the final pair is recorded. Recommendation: before archive, run `just drv-diff 398623707d36 2ac5a55e96db openspec/changes/establish-refactor-oracle/drv-delta.txt` (about 14 min), or accept the inference.
- **W2 (resolved by wording). `nix-eval-jobs` version not recorded as such.** `drv-diff.sh:200` writes `readlink -f` only; the interface requirement said the header records "the resolved evaluator paths and versions", and plan Step 4 asked for `--version` of both. iets rejects `--version`, so the version is recorded by the store path name (`nix-eval-jobs-2.35.4`). Resolved: the interface requirement, its scenario and plan Step 4 now say `nix-eval-jobs` is recorded by its resolved store path, whose name carries the version, and state why.
- **W3. "Comparing a commit with itself" and "added"/"failing at one commit" are not exercised end to end.** Self-identity was discharged by a two-commit run (3.1) plus my synthetic re-judgement; `added` and `failing-at-one` paths are code-traced only (`drv-diff.sh:270,273,278`).

**SUGGESTION**:

- **S1.** `architectural-principles.md:13` could say "P1–P4" instead of "the four principles" to avoid reading as a stale count.
- **S2.** On the absent-entry exit-2 path a re-judgement writes `header.<UTC>` and `report.<UTC>` holding the error; harmless, but the run directory gains a non-report file.
- The four vmTests failing at both commits in `R` (`caddy-root-from-vars`, `tincr-mesh`, `tincr-mesh-partition`, `omnigraph-seed`) predate trunk `14a6b01878c3` and `c8ee415b5`, which address `caddy-root-from-vars`' IFD and the omnigraph probe's options; a run at the new base may show fewer.

---

## 8. Designation lint and discharge coherence (agent-executed, not validation)

### 8a. Designation lint (behavioral: `refactor-identity-oracle`)

`openspec/specs/world-assumptions/spec.md` exists; the delta's table (corpus plus this change's rows) was used.
Content nouns resolved to rows: refactor, declared difference, base commit, candidate commit, comparison, configuration (host's), host (fleet), home configuration, check, runtime test, derivation, repository (two senses), commit, evaluator (Nix sense), evaluation cost, cost measurement, baseline.
Unresolved: none. ("reason", "claim", "author" are not content nouns.)

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| A refactor changes no derivation it did not declare | interface: seven-map dump; exit by allow-list; base allow-list | A310, A311, A313 | A310 configured (darwin `sandbox: false` recorded in baselines note); A311 not violated (two runs from a dirty working copy, dumps traced to commits); A313 observed (`nix` on PATH is iets classic, `eval-cost` header 004902Z; oracle used `nix-2.35.6`) |
| A declared difference happens | interface: exit by the allow-list (declared-but-absent) | A310 | observed on `M` (3.3) |
| A failure to evaluate is a difference only when new | interface: failing-to-evaluate requirement | A311 | failing-at-both observed; failing-at-one code-traced |
| Cost claim on alternating measurements | interface: `eval-cost` interleaving and records | A312, A313 | A312 observed (equal `nrThunks` across four runs in each of three baselines) |
| A310–A313 (world) | — | — | ADDED as world assumptions; statuses as above |
| Grounded vocabulary (MODIFIED) | — | — | rows added; lint in 8a |

No undischarged requirement.

### 8c. Alphabet check

Behavioral requirements name no interface phenomenon (no command, file, exit code or flag). Interface requirements reference world state only through trust-boundary notes citing A310–A313. No violations.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `W1 (proof run at superseded commits; final-pair run not recorded), W3 (self-compare, added and failing-at-one exercised synthetically or by code only); W2 (nix-eval-jobs version only in path) resolved by wording`
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

In Review: roborev code review, then documenter review. Before archive: decide W1 (run or accept), and merge the world-assumptions table by hand at sync.
