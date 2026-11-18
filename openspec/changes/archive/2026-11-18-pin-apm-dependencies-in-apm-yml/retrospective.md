# Retrospective: pin-apm-dependencies-in-apm-yml

> Written: 2026-11-18 (after verify passed with warnings)
> Commit range: `34938e555^..338628afd`, plus this archive commit
> Worktree: merged to main (jj chains from `main@origin`, joined in the working copy; no workspaces)

---

## 0. Evidence

- **Commit range**: `34938e555^..338628afd`: 4 change commits, each merged through the queue (one unrelated commit, `433a2c34`, landed between the proposal and the implementation), plus the archive commit
- **Diff size**: proposal +1336 across 8 files; implementation +865 / −6122 across 34 files; relock and implementation together +2795 / −6593 across 35 files (`git diff --shortstat 433a2c34 9a762a0b`); verify +201 / −15 across 6 files. Most deletions are the retired fetchers, the compose's pre-seed blocks and the stray plugin locks
- **Tasks done**: 24/24 (`grep -cE '^\s*- \[x\]' tasks.md` → 24)
- **Active hours**: about 5 h on 2026-11-18, from the spike to the verify merge (19:53Z); the proposal merged at 17:55Z, the implementation at 18:49Z, the relock at 18:59Z
- **Subagent dispatches**: 7 named: `ApmSpikeVerify`, `ApmSandboxLinux` and `ApmSuperpowersD1` (the spike's independent verifications), `ApmDepsChange` (proposal), `Cam110Implement` (implementation and relock), `Cam110Verify` (verify), `Cam110Archive` (this retrospective and archive)
- **New external dependencies**: none. superpowers moved v6.3.0 → v7.0.2, worktrunk's skill to v0.81.0, gh-stack's skill to v0.3.0; all were already consumed
- **Bugs encountered post-merge**: none
- **OpenSpec validate state at archive**: `openspec validate pin-apm-dependencies-in-apm-yml --strict` valid before the archive. After the sync, `openspec validate --all` fails only the two pre-existing items of other changes (`stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite`); `openspec validate --all --strict` fails the same 33 items as at `338628afd`, none new. `third-party-plugin-dependency` is among them only for its placeholder Purpose, which the sync leaves untouched. The archive applied 11 ADDED interface requirements (verify's summary counted 10; its §8b table lists all 11), 3 REMOVED and 6 ADDED world assumptions; A136–A141 collide with no main or active-change number (`migrate-mesh-to-tincr` holds A128–A135 and A142)
- **Test coverage signal**: 17/17 nix-unit fixtures for the guard; mutants for the ref, apm-version, fifth-rule, alignment (worktrunk, gh-stack, mergify-cli) and playwright-parity checks, all failing as expected; a negative control for the alignment comparison; offline-composition controls (git on PATH, withheld download, missing dependency); host witnesses on stibnite (`system-228`) and pyrite (generation 107 → 108)

Commit chain (chronological):

```
34938e555 docs(openspec): propose pin-apm-dependencies-in-apm-yml                                 (#4005)
146c95918 feat(apm): pin remote apm dependencies once, in apm.yml                                  (#4007)
9a762a0b1 chore(apm): relock the root apm.lock.yaml after pinning dependencies in apm.yml          (#4008)
338628afd openspec(apm): verify pin-apm-dependencies-in-apm-yml                                    (#4009, PASS WITH WARNINGS)
<archive>  openspec(apm): retrospective and archive of pin-apm-dependencies-in-apm-yml
```

### In-Review sub-gates: waived

The operator waived both In-Review sub-gates, roborev (code review) and documenter (docs review), on 2026-11-18: "Yes waive". The orchestrator relayed the waiver. Neither review was run, so no approval exists; the archive gate proceeds on the waiver, which stands in place of the approvals the gate expects.

---

## 1. Wins

- One fact, one place: each remote commit is now written only in the declaring plugin's `apm.yml` (#4007). Eight fetchers, six compose options, ten pre-seed blocks and the Mergify-only alignment check are gone; the change deleted about seven times as many lines as it added (§0).
- The design rested on measured feasibility, not on reading apm's source: a throwaway spike plus two independent verifications on stibnite and magnetite (sandboxed) closed R1–R4 before the proposal (`brainstorm.md`, "Spike, then independent verification").
- The spike's verification found the one dangerous failure mode before it reached a design: Nix reuses a fixed-output path by name and hash, so a pin bump that forgot `apmDepsHash` silently returned the old download, and the consumer later failed with a misleading `git executable not found` (N1/R4). D2's guard, which names the download after its inputs, closes it, and task 1.5 proves it with ref and apm-version mutants.
- The marketplace install works again: plain apm on seven targets installs no superpowers or agency hook (task 3.2), and `diagnosing-superpowers` arrives with superpowers v7.0.2.
- Release alignment now covers every CLI/skill pair from one upstream release, and it caught real drift on day one: worktrunk and gh-stack moved to their CLIs' releases (tasks 4.2–4.5).
- The relock was kept out of the implementation PR (D8): #4007 left `apm.lock.yaml` unchanged and #4008 relocked from `main`, so the root lock never described an unmerged tree.

## 2. Misses

- [med] [painful | evidence: tasks.md 4.1, `logs/apm-deps-probes-20261118-132254.log`] The gh-stack probe as written in plan.md Task 0 Step 2 was vacuous. `fetchFromGitHub` with the default name `source` and nixpkgs' own `outputHash` yields the store path of nixpkgs' tagged source, which was substituted from cache.nixos.org without fetching anything, so it would have "passed" for any commit. This is the same same-name fixed-output reuse the guard exists to prevent, in a different place. The probe was rerun with `name = "gh-stack-probe-<rev>"`: `2a49e675…` fetched and matched, `14fc42ed…` failed with a mismatch. The check in task 4.4 carries the commit in its name for the same reason.
- [med] [painful | evidence: verify W1, tasks.md 2.1, `logs/cam110-compose-linux-20261118-132404.log`] D1 and the `offline root-manifest composition` scenario said the download is copied "beside" the generated root manifest. Implementation found that apm reads `apm_modules/` and `apm.lock.yaml` under the install root `$out`; copied beside the manifest, all 26 dependencies failed. The code was right, but the design and spec wording stayed wrong until verify corrected them (#4009).
- [low] [nit | evidence: verify W2] Scenario `a bump touches two places` is evidenced only in parts (updater scratch runs, hash-mismatch mutant). No single real bump diff was observed. Left open.
- [low] [nit | evidence: verify W3] Pyrite's before-tree for task 8.4 was reconstructed from generation 107's home-manager files rather than saved live before activation. Left open; equivalent for home-manager-delivered skills.
- [low] [nit | evidence: verify S1] The stibnite dangling-link count missed `~/.claude/skills/harborize`, a hand-made link into a draft-branch path (#2747) that has dangled since 2026-08-14. It predates this change and is out of scope; the miss is in the count's method (`find -xtype l` would have found it).

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| Task 0 Step 2 (tasks 4.1) | Probe rerun with a commit-carrying derivation name | The plan's expression was satisfied from cache without fetching (§2) |
| 4.4 | The gh-stack tag check names its derivation after the commit | Same reason: a constant name would let a stale or cached path satisfy it |
| 2.1 / Task 4 Step 3 | The download is copied under the install root, not beside the manifest | apm reads both there; "beside" failed all 26 dependencies (W1) |
| W1 wording | D1, the scenario, task 2.1 and plan Task 4 Step 3 corrected in the verify commit | Design and spec text lagged the code |
| T2 (Linear) | Todo → In Progress recorded as observed, not posted | Linear already read In Progress at verify; the write was made outside the ledger |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, after a spike and two independent verifications) |
| superpowers:writing-plans                        | yes (`plan.md`, `tasks.md`) |
| superpowers:using-git-worktrees                  | yes (jj chains from `main@origin` joined in the working copy) |
| superpowers:subagent-driven-development          | yes (orchestrator plus named worker subagents, §0) |
| (transitive) superpowers:test-driven-development | partly (guard fixtures, mutants and negative controls written as task gates; the plan's own gh-stack probe had no negative control until rerun) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (each chain published as a PR and merged through the queue) |

### Deliberately Skipped Skills

- **`superpowers:requesting-code-review`** (and the roborev and documenter sub-gates)
  - **What was skipped**: the In-Review code review and documentation review.
  - **Why this cycle**: the operator waived both sub-gates on 2026-11-18 ("Yes waive").
  - **How to prevent recurrence**: `scope-judgment rule`. A waiver is an operator decision, recorded with its date and words (§0). This is the second consecutive change waived on the same day (after `retire-legacy-sops-tooling`), so it is carried into §6 as a schema candidate.

## 5. Surprises

- Nix's fixed-output reuse by name and hash bit twice: once as the stale download N1 the guard prevents, and once in the plan's own gh-stack probe, where a default-named fetch with a known hash was served from cache.nixos.org without fetching.
- apm reads `apm_modules/` and `apm.lock.yaml` from the install root, not from the manifest's directory.
- apm's download bytes depend on its version (0.35.1 renames and changes the download; task 1.5b), so the guard's digest keys on `apm.version`.
- `skills:` and `targets:` change the download (fresh-name probes in the brainstorm), so the digest carries every key of each entry, not only repository, path and ref.

## 6. Promote candidates → long-term learning

- [ ] [high] **A fixed-output probe or check proves nothing unless its name changes with what it claims to test** → **Promote to memory** (type: feedback)
  > **Why**: the plan's gh-stack probe reused nixpkgs' `source` name and hash and was substituted from cache without fetching, so it would have passed for any commit (tasks 4.1); the same mechanism is N1's stale download.
  > **How to apply**: whenever a `fetchFrom*` or other fixed-output derivation is used as evidence, put the input under test (commit, ref, version) in its `name`, and run a mutant that must fail before counting the pass.

- [ ] [med] **Feasibility claims about a tool's file layout must be checked against where it actually reads, not where it writes** → **Promote to memory** (type: feedback)
  > **Why**: D1 said "beside the manifest"; apm reads under the install root, and the design text lagged the code until verify (W1).
  > **How to apply**: when a design names a path a tool reads from, cite the observed run (log) that established it, or mark it inferred.

- [ ] [med] **Two consecutive changes waived both In-Review sub-gates** → **Promote to schema** (`superpowers-bridge-wrspm` In-Review gate)
  > **Why**: `retire-legacy-sops-tooling` and this change were both archived on 2026-11-18 under operator waivers of roborev and documenter.
  > **How to apply**: if the next change is waived again, decide whether the sub-gates should be opt-in per change (declared in the proposal) rather than default.

- [ ] [low] **Close W2 with the next real superpowers or worktrunk bump** → **One-off**
  > **Why**: the bump scenario has no single observed diff; the next real bump is its natural evidence.
  > **How to apply**: on that bump, record `git diff --stat` showing only `ref:` lines, `apmDepsHash` and the recorded commit.

- [ ] [low] **Count dangling links with `find -xtype l`** → **One-off** (the harborize link itself is out of scope)
  > **Why**: the stibnite count missed `~/.claude/skills/harborize` (S1).
  > **How to apply**: in the next skill-tree witness.
