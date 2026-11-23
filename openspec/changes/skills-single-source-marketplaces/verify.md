# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `skills-single-source-marketplaces` (CAM-122)
**Verified at**: `2026-11-23 20:01` UTC
**Verifier**: subagent `SkillsCloseout` (omp), running `openspec-verify-change` and this schema's checks 1–7 on `main` 43a4ac7d plus the relock commit

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

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

31 of 36. Each open task records its reason in `tasks.md`.

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 1.4 Re-observe A138 and A140 under apm 0.38.0 | no rerun of the F5 and F6 procedures under apm 0.38.0 is logged; both assumptions' Evidence still reads "to be re-observed" | yes, unless the operator closes it without measurement |
| 1.5 Build the 32 apm-touching checks on x86_64-linux, evaluate the 111 darwin ones | no log of that sweep exists; each stage built its own checks on magnetite instead (tasks 3.1, 4.5, 4.6, 5.1, 7.3, 7.5) | yes, unless closed by that substitute evidence |
| 5.4 The operator deletes `origin/claude-marketplace` | operator action; `git ls-remote origin claude-marketplace` still prints `d68d40ed` on 2026-11-23 | yes |
| 6.1 Corpus unchanged on a stibnite activation | stibnite has not activated a generation from 43a4ac7d (`~/.claude/skills` holds `gitbutler-but-cli`, no `but`); the expected names now differ from stage 4's by the D15 rename | yes |
| 6.2 Desktop install count and update (A218, A219) | the Add marketplace dialog listed exactly 18 plugins, none `agent-context-*`; installing `nix-build-operations` (5) and `planning-and-development` (16), "Check for updates" after a version-free edit, and the app version are not yet observed | yes |

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
| A Claude user installs every skill group with all its first-party skills (installed in a Claude app; a dependency's skills are wanted) | `claude-marketplace-install` (G4) for Claude Code; D12 (remote skills excluded); desktop by the operator (D13) | task 4.6: `total 126`; task 6.2 partial: 18 plugins listed, none `agent-context-*`; install counts open |
| A Claude user follows the published skills without versions (a skill changes on main) | no `version` in the Claude entries (D3), A219 | Claude Code 2.1.330 observation in A219; desktop update open (task 6.2) |
| Publication never changes what the fleet's hosts receive (the published layout changes) | G1 per stage; stage 5 changes the trees deliberately (D15, design Migration Plan) | tasks 3.1, 7.4; the activation check, task 6.1, is open |
| A skills CLI user installs each first-party skill (listed; one selected) | root `skills.sh.json` from the generator (D14), `skills-cli-discovery` (G8) | tasks 7.2, 7.3, 7.7 ("Found 126 skills" from GitHub `main`) |
| Each fact about a plugin group is authored once (per-group manifest reappears; list and tree disagree) | `lib/plugin-groups.nix` and `pkgs/by-name/skills-marketplace` assertions | task 4.3: the `plugin.json`, unlisted-group and name mutants fail |
| Both marketplace files are generated and committed unchanged (description changes; apm bump changes bytes) | `skills-marketplace-drift` (G3), `just agents-marketplace` | tasks 4.4, 4.5 |
| Claude Code installs every Claude entry with exactly its group's skills (missing directory; no skills path) | `claude-marketplace-install` (G4) | task 4.6: both mutants fail |
| An offline apm consumer installs from a served copy (a published source path is wrong) | `apm-marketplace-consumer` (G5a) | task 5.1: the typo mutant fails at that group |
| The composed trees are compared with their sources and recorded hashes (remote skill changes; first-party skill rewritten) | G1 with `skills.json` `{names, remote}` | task 2.5 |
| The composition installs without frozen mode and leaves no installation id (CI variable; two builds compared) | G6, G7 one-off proofs | tasks 2.2, 2.3 |
| Group discovery is computed once (a group of skills is added) | `lib/plugin-groups.nix`, used by the compose, `deps.nix`, home-manager and the generator | task 2.1: drvPaths unchanged |
| A whole-plugin upstream is consumed through a skill list (list diverges; selection removed) | the mattpocock list rule in `deps.nix` (G2); G1's names for the removed selection | task 2.6: the `tdd` mutant fails; task 2.5: `tdd` missing fails on names |
| A213–A220, A136–A140 (world assumptions) | Evidence recorded per assumption | A138 and A140 re-observation under apm 0.38.0 open (task 1.4); A218 and A219 desktop evidence partial (task 6.2) |

The consumer mutant "a group manifest that makes apm deploy it whole" (design D7, G5a) ran after the merge on magnetite (logs in the `skills-arch` workspace's `logs/`): `nix-build-operations` with its `apm.yml` replaced by a `.claude-plugin/plugin.json` in the served copy only was deployed to `.agents/plugins/`, and the check failed (`mutant-g5a-group-deployed-whole-served-20261123-145603`, `...-served-diag-20261123-145747`).
A `plugin.json` beside the `apm.yml` left the group flat and the check passed, as A213 states (`mutant-g5a-group-deployed-whole-20261123-145436`).

**Drift warnings** (non-blocking):

- The deploy-whole mutant fails G5a through `ls` exiting 2 under `pipefail` at the missing `.agents/skills`, before the check prints a `FAIL:` line naming the group; the log shows only the previous group as the last output. Recommendation: in `modules/checks/apm-marketplace-consumer.nix`, test `[ -d "$root/$tree" ]` before the `ls` and print `FAIL: $group deploys no $tree` so the failure names the group.
- The spec scenario "A per-group manifest reappears" says the generator's build fails; the stray-manifest rule is an evaluation-time assertion (task 4.3), which fails earlier and also names the file. Recommendation: say "evaluation of the marketplace generator fails" in `specs/skill-marketplace-publication-interface/spec.md` before archive.

## 5. Implementation Signal

- [x] No unstaged files in the worktree (the jj working copy is committed: the relock and these records)
- [ ] All related commits have been pushed: `f2d5a9335..43a4ac7d5` is on `origin/main`; the relock and record commits are not yet published

**Commit range**: `f2d5a9335..43a4ac7d5`, then the relock (`apm.lock.yaml` at 43a4ac7d, lockfile v4) and the record commit

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files, or any existing files are legitimate residue from before schema installation

`ls docs/superpowers/specs/*.md` printed nothing.

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows, so this section is blank (PASS).

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [ ] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `<explanation>`
- [x] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

The implementation matches every requirement and scenario above; the failure is task completion alone: five tasks are open (1.4, 1.5, 5.4, 6.1, 6.2), three of them waiting on the operator.

**Next step**:

The operator finishes task 6.2 (install counts, update, app version) and records D13's step 4 in A218's and A219's Evidence, deletes `origin/claude-marketplace` (5.4), and activates stibnite (6.1); tasks 1.4 and 1.5 are run or closed with a stated reason. Then re-run verify, write the retrospective and archive.
