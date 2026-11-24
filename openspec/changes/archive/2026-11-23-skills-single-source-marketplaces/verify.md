# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `skills-single-source-marketplaces` (CAM-122)
**Verified at**: `2026-11-23 20:19` UTC (first run 20:01 UTC)
**Verifier**: subagent `SkillsCloseout` (omp), running `openspec-verify-change` and this schema's checks 1–7 on `main` 43a4ac7d plus the relock commit; re-run by subagent `SkillsVerifyFixes` on `main` 9c288da5 plus the commits that close tasks 1.4, 1.5, 5.4, 6.1 and 6.2 and the two drift warnings

Prechecks: the change's commits on `main` run from `f2d5a9335` (`docs(openspec): propose skills-single-source-marketplaces`) to `43a4ac7d5` (`docs(openspec): record stage 5 and its follow-ups of skills-single-source-marketplaces`), and `tasks.md` holds 31 `- [x]` lines, so both are positive.
OpenSpec ran with HOME and the XDG directories under a scratch directory, the `superpowers-bridge-wrspm` schema copied there from `modules/home/ai/openspec/assets/schemas`.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items report `"valid": true`, for this change and the main specs

**Result**:

```text
totals: 68 items, 66 passed, 2 failed (changes 35/33, specs 33/33)
openspec validate skills-single-source-marketplaces --strict: Change 'skills-single-source-marketplaces' is valid
```

The two failures are other changes, unchanged since `track-main-in-claude-sandbox`'s verify: `stand-up-gitea-mq-on-magnetite` and `stand-up-nixbot-on-magnetite`.
The re-run gave the same totals and the same two failures, and `--strict` on this change printed "is valid" (openspec 2.1.1; log `skills-verify-fixes-openspec-20261123-151929`).

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

36 of 36.

Closed since the first run: 1.4 (A138 and A140 hold under apm 0.38.0; logs `apm-verify-f5f6-038-20261123-151020`, `apm-verify-f6-online-038-20261123-151107`), 1.5 (26 apm-touching x86_64-linux checks built on magnetite's store, 111 aarch64-darwin checks evaluated, at `main` 9c288da5; logs `skills-1.5-x86-apm-checks-magnetite-20261123-151738`, `skills-1.5-darwin-eval-20261123-151020`), 5.4 (`git ls-remote origin claude-marketplace` prints nothing), 6.1 (stibnite generation 243 delivers `but`, no `gitbutler-but-cli`), 6.2 (in Claude 6.28899.6, 18 plugins listed, the two installs show 5 and 16 skills, and `version-control-and-forge` moved to an app-numbered "v2" holding the `but` rename without any version change).

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `first-party-skill-distribution` | pending sync | 1 MODIFIED (`Build-time apm composition of first-party skills`), 1 ADDED |
| `skill-marketplace-publication` | pending sync | new capability, 5 ADDED |
| `skill-marketplace-publication-interface` | pending sync | new capability, 7 ADDED |
| `third-party-plugin-dependency` | pending sync | 1 ADDED |
| `world-assumptions` | pending sync | 8 ADDED (A213–A220), 6 MODIFIED (A136–A140, the designation table) |

The archive step syncs them.

## 4. Design / Specs Coherence Spot Check

Every ADDED and MODIFIED behavioural requirement and its scenarios, mapped to what discharges it.

| Requirement (scenarios) | Discharged by | Evidence |
|---|---|---|
| Build-time apm composition (deterministic offline build; per-harness flat deployment; an apm release changes the trees) | `pkgs/by-name/apm-skills-compose` with `--no-frozen`, the `.apm-local/installation` removal and the tree oracle (G1, G6, G7) | tasks 2.2, 2.3, 2.5: rebuild deterministic; four oracle mutants fail naming the skill |
| First-party skills conform to the Agent Skills specification (name differs; frontmatter does not parse) | `checks.x86_64-linux.skills-spec-conformance`, `pkgs/by-name/skill-validator` (G9) | task 7.5: both mutants fail |
| An apm consumer installs every published plugin group (skills group; instructions group; group added) | `apm-marketplace-consumer` (G5a), `just agents-marketplace-remote` (G5b), `skills-marketplace-drift` (G3) | tasks 5.1, 6.3 (22/22 against GitHub `main` 43a4ac7d, coverage intact), 4.3 (unlisted group fails) |
| A Claude user installs every skill group with all its first-party skills (installed in a Claude app; a dependency's skills are wanted) | `claude-marketplace-install` (G4) for Claude Code; D12 (remote skills excluded); desktop by the operator (D13) | task 4.6: `total 126`; task 6.2: in Claude 6.28899.6, 18 plugins listed, none `agent-context-*`, `nix-build-operations` 5 skills and `planning-and-development` 16 |
| A Claude user follows the published skills without versions (a skill changes on main) | no `version` in the Claude entries (D3), A219 | Claude Code 2.1.330 observation in A219; task 6.2: in Claude 6.28899.6, `version-control-and-forge` offered an app-numbered "v2 · current" holding the `but` rename (#4188) with no version change |
| Publication never changes what the fleet's hosts receive (the published layout changes) | G1 per stage; stage 5 changes the trees deliberately (D15, design Migration Plan) | tasks 3.1, 7.4; task 6.1: stibnite generation 243 delivers `but`, no `gitbutler-but-cli` |
| A skills CLI user installs each first-party skill (listed; one selected) | root `skills.sh.json` from the generator (D14), `skills-cli-discovery` (G8) | tasks 7.2, 7.3, 7.7 ("Found 126 skills" from GitHub `main`) |
| Each fact about a plugin group is authored once (per-group manifest reappears; list and tree disagree) | `lib/plugin-groups.nix` and `pkgs/by-name/skills-marketplace` assertions | task 4.3: the `plugin.json`, unlisted-group and name mutants fail |
| Both marketplace files are generated and committed unchanged (description changes; apm bump changes bytes) | `skills-marketplace-drift` (G3), `just agents-marketplace` | tasks 4.4, 4.5 |
| Claude Code installs every Claude entry with exactly its group's skills (missing directory; no skills path) | `claude-marketplace-install` (G4) | task 4.6: both mutants fail |
| An offline apm consumer installs from a served copy (a published source path is wrong) | `apm-marketplace-consumer` (G5a) | task 5.1: the typo mutant fails at that group (re-run on magnetite's store after the fix below, `mutant-s5-consumer-source-typo-magnetite-20261123-151804`) |
| The composed trees are compared with their sources and recorded hashes (remote skill changes; first-party skill rewritten) | G1 with `skills.json` `{names, remote}` | task 2.5 |
| The composition installs without frozen mode and leaves no installation id (CI variable; two builds compared) | G6, G7 one-off proofs | tasks 2.2, 2.3 |
| Group discovery is computed once (a group of skills is added) | `lib/plugin-groups.nix`, used by the compose, `deps.nix`, home-manager and the generator | task 2.1: drvPaths unchanged |
| A whole-plugin upstream is consumed through a skill list (list diverges; selection removed) | the mattpocock list rule in `deps.nix` (G2); G1's names for the removed selection | task 2.6: the `tdd` mutant fails; task 2.5: `tdd` missing fails on names |
| A213–A220, A136–A140 (world assumptions) | Evidence recorded per assumption | A138 and A140 re-observed under apm 0.38.0, both hold (task 1.4); A218 and A219 recorded with Claude 6.28899.6 (task 6.2) |

The consumer mutant "a group manifest that makes apm deploy it whole" (design D7, G5a) ran after the merge on magnetite (logs in the `skills-arch` workspace's `logs/`): `nix-build-operations` with its `apm.yml` replaced by a `.claude-plugin/plugin.json` in the served copy only was deployed to `.agents/plugins/`, and the check failed (`mutant-g5a-group-deployed-whole-served-20261123-145603`, `...-served-diag-20261123-145747`).
A `plugin.json` beside the `apm.yml` left the group flat and the check passed, as A213 states (`mutant-g5a-group-deployed-whole-20261123-145436`).
After the fix below, the same mutant fails with "FAIL: nix-build-operations deploys no .agents/skills" (and `.claude/skills`), followed by what apm deployed: `.agents/plugins/nix-build-operations` and `.claude/settings.json` (`mutant-g5a-group-deployed-whole-served-20261123-151229`); the unmutated check prints "installed 18 of 22 registered groups" (`s5-apm-marketplace-consumer-magnetite-20261123-151229`).

**Drift warnings** (non-blocking): both from the first run are resolved.

- The deploy-whole mutant failed G5a through `ls` exiting 2 under `pipefail` before any `FAIL:` line named the group. Fixed in `modules/checks/apm-marketplace-consumer.nix`: the check tests the tree first, prints `FAIL: $group deploys no $tree` and lists what apm deployed under `.agents` and `.claude`.
- The spec scenario "A per-group manifest reappears" said the generator's build fails; the stray-manifest rule is an evaluation-time assertion (task 4.3). The scenario in `specs/skill-marketplace-publication-interface/spec.md` now says evaluation of the generator fails, before any build starts.

## 5. Implementation Signal

- [x] No unstaged files in the worktree (the jj working copy is committed: the fix, the spec wording and these records)
- [x] All related commits have been pushed: `f2d5a9335..9c288da5` is on `origin/main`; the consumer fix (`ca5969679`), the spec wording (`29a1f809d`) and the two record commits (`10ce41e8d`, `418f65643`) reached `origin/main` after this run (checked at archive time, `main` db5e5b881)

**Commit range**: `f2d5a9335..9c288da5`, then `ca5969679`, `29a1f809d`, `10ce41e8d` and `418f65643`

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` printed nothing.

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows, so this section is blank (PASS).

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: task 6.1 rests on the reported names (`but` present, `gitbutler-but-cli` absent, 181 entries) without the `diff -r` of three skills its verify names; the desktop installs did not appear in Claude Code's plugin state on stibnite (observed, not explained); the four commits of this re-run are not yet published
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

All 36 tasks are complete, the implementation matches every requirement and scenario above, and both drift warnings from the first run are resolved.

**Next step**:

Publish this stack as one pull request; after it merges, write the retrospective and archive the change.
