# Retrospective: name-the-parts-of-base-and-ai

> Written: 2026-11-28 (after verify passed with warnings and its findings 1-4 had dated corrections, before archive)
> Commit range: planning `b3bce6027` (#4477); then on `main` `f5c002dc4` (#4488), `c69bbcac5` (#4509, one commit with `shape-the-repository-for-its-readers`' order step) and `8918ef77a` (#4512, the verification record)
> Worktree: merged to main; this retrospective and the archive are one further commit

---

## What the change set out to do

`flake.modules.nixos.base`, `flake.modules.darwin.base` and `flake.modules.homeManager.ai` were each the implicit union of the files that assigned into them: 33, 37 and 19 files at `fcf3a652e6f1`, with no file saying what they held (proposal Why). The change made each one a single definition importing a named list of parts, `flake.lib.nixosBaseParts`, `flake.lib.darwinBaseParts` and `flake.lib.homeAiParts`, in `modules/nixos/base.nix`, `modules/darwin/base.nix` and `modules/home/ai/default.nix`, and added `checks.x86_64-linux.structure-aspect-parts`, which fails on a file assigning into an aspect or an existing part and on a part in no list (design D2, D3, D6).

## 0. Evidence

- **Commit range**: `b3bce6027` (plan, #4477), `f5c002dc4` (NixOS list and the structure check, #4488), `c69bbcac5` (darwin and `ai` lists with the package and Brewfile sort, #4509), `8918ef77a` (verification, deploy record and text corrections, #4512); 4 commits
- **Diff size**: `f5c002dc4` +185 / −59 across 37 files; `c69bbcac5` +553 / −246 across 91 files, shared with `shape-the-repository-for-its-readers`; artifacts included
- **Tasks done**: 20/29 at archive (`tasks.md`); the 9 open tasks are listed under "Open items" with their reasons
- **Active hours**: about 6.6 h from the plan (2026-11-27 19:09 −05:00) to the verification record (2026-11-28 01:44 −05:00)
- **New external dependencies**: none
- **Bugs encountered post-merge**: none observed. The deploy of cinnabar, magnetite and pyrite and the activation of stibnite at `d705c39bd6c6` ran with no failed unit and no account or group created or deleted (tasks 5.2-5.4)
- **OpenSpec validate state at archive**: `aspect-parts` and `aspect-parts-interface` valid under `openspec validate <spec> --type spec --strict`; `openspec validate --specs --strict` fails on the same 18 specs as on `main` before the sync, `world-assumptions` among them, on warnings only
- **Test coverage signal**: `structure-aspect-parts` with its mutants (a file assigning into `nixos.base`, a part removed from its list, a second file assigning into `base-zram-swap`, a tenth file into `base-system-defaults`, a sixth into `ai-claude-code`, `ai-tuicr` unlisted, `darwin.base-unlisted`); `just drv-diff 8b4c77a8efeb 2fa12009ad77` PASS for the NixOS step; `just drv-diff fb7b981f1e74 de1600cb6e74` with `drv-delta-order.txt` PASS for the darwin and `ai` steps together; `drv-order-trace.py` over every changed toplevel and home; the profile replay; `base-zram-swap` taken alone (task 6.3)

Commit chain (chronological):

```
b3bce6027 docs(openspec): plan naming the parts of the base and ai aspects
f5c002dc4 refactor(nixos): make the base aspect an explicit list of named parts
c69bbcac5 refactor(fleet): sort package lists and name the parts of the darwin base and the ai aspect
8918ef77a docs(openspec): record the verification, re-measurement and deploy of the repository-shape changes
(this commit) docs(openspec): archive name-the-parts-of-base-and-ai and shape-the-repository-for-its-readers
```

---

## 1. Wins

- What the base settings and the agent tooling hold is read in three files; on `main` the lists hold 32, 30 and 15 names, each once (verify §4, task 6.1).
- A file that assigns into an aspect or into another file's part, or a part in no list, fails a small check that names it (verify §4, mutants).
- A part can be taken alone: a `nixosSystem` with only `base-zram-swap` has `zramSwap.enable = true` and none of `base-nix-settings`' settings (task 6.3).
- The NixOS step changed no toplevel and no home (`logs/drv-diff-8b4c77a8efeb-2fa12009ad77-20261128T010505Z`).

## 2. Misses

- [med] [painful | evidence: design D5 "Departure", Open Question 2, verify finding 2] The parts were named in three steps, and two of them, the darwin `base` and `ai` lists, rode on `shape-the-repository-for-its-readers`' package sort in one commit, `c69bbcac5`. Neither had a comparison of its own, `drv-delta-darwin-base.txt` and `drv-delta-ai.txt` were never written, and the trace exits 1 on the ten toplevels and seven homes at `apm-deps` and `apm-skills-compose`, which carry that change's two text edits. What stands in for the two comparisons (design Open Question 2): the combined comparison against `drv-delta-order.txt` (PASS); the trace accepting every order difference and rejecting only those two texts, on the compared pairs and again on the drv-diff's own pairs (`logs/srr-5b-trace-20261127-233754.log`, `logs/ntp-verify-trace-landed-20261128T054818Z.log`); every host's `systemPackages` and every home's `home.packages` holding the same store paths with the same priorities, and on the Macs equal accounts, groups, uids and gids (`logs/srr-5b-state2-{parent2,commit2}-20261127-234552.json`); the trace tool's test on constructed values (`logs/ntp-verify-trace-judge-20261128T054749Z.log`); and a part moved within its list leaving every toplevel and home identical (`logs/srr-verify-mutant-darwin-order-20261128T055245Z.log`). Open Question 2 has no recorded answer.
- [med] [painful | evidence: design D4 "Profiles replayed, not built", verify finding 4] The built-profile comparison ran as a replay of the locked `builder.pl`; nothing was built. Thirteen profiles had members missing from the store, and no `home-manager-fonts` or `home-manager-applications` was compared (task 4.5).
- [low] [nit | evidence: verify finding 1] Two interface scenarios held only at the commits that landed them, since later changes moved parts out of and into the NixOS list; restated on 2026-11-28.
- [low] [nit | evidence: verify finding 5] A part listed twice passes the check; no requirement asks for that case. Not taken up.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| D5, pull requests 2 and 3 | Landed in one commit with the order step, under `shape-the-repository-for-its-readers/drv-delta-order.txt` | That change held both steps until its order step landed, so that they would change no derivation; they were then applied on top of it in the same commit (its task 6.1) |
| 3.4, 4.4, 6.2 | The trace exits 1 at two texts; recorded as design Open Question 2, not added to an allow-list | The texts are the other change's content, not order |
| 3.5, 4.5 | Profiles replayed with the locked builder, not built | Building every profile was not run |
| 5.1, 5.4 | No standalone home is known to be in use; the five aarch64-linux standalone homes were activated in a throwaway virtual machine instead | design Resolved Question 1 |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | not evidenced in the change's files |
| superpowers:subagent-driven-development          | not evidenced in the change's files |
| (transitive) superpowers:test-driven-development | yes in the mutant form: each rule of the structure check shown failing against a mutant |
| (transitive) superpowers:requesting-code-review  | not evidenced in the change's files |
| superpowers:finishing-a-development-branch       | yes (#4488 and #4509 merged) |

Review gates: no review-gate decision is recorded for this change beyond the reviews that ran before each commit landed; no review.md. `verify.md`'s Overall Decision is PASS WITH WARNINGS.

## 5. Surprises

- Naming the darwin parts put `base-homebrew` one import level deeper than `zed-delta`, which moved a cask in every Mac's `Brewfile`; the Homebrew lists are now sorted by name, as the package lists are (design D4, kind (c)).
- A home's standalone activation in a machine with no age key runs every step through linking the generation, installing packages and reloading systemd, and exits 1 only at the sops-nix step (design Resolved Question 1).

## 6. Promote candidates → long-term learning

- [ ] [med] **A step held to land on another change's commit loses its own comparison; either run a comparison of a tree holding only its edits before combining, or state in advance what will stand in for it.**
  → **Promote to** memory
  > **Why**: the darwin and `ai` steps landed under one combined allow-list, and the trace's rejections, from the other change's texts, could not be separated afterwards.
  > **How to apply**: any change whose steps are planned to ride on another change's commit.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| Tasks 3.4, 3.6, 4.4, 4.6 and 6.2: the darwin and `ai` steps have no comparison of their own; design Open Question 2 has no recorded answer | not taken up; what stands in is listed in §2 |
| Task 4.5: building the thirteen incomplete profiles and comparing `home-manager-fonts` and `home-manager-applications` | not taken up |
| Task 5.2: electrum, galena and scheelite are disabled and were not deployed | their next provisioning |
| Tasks 5.3 and 6.4: argentum and rosegold were offline and were not deployed; blackphos has no machine; A377 is exercised on stibnite only | the next deploy of argentum and rosegold |
| The standalone homes: activated only in a test machine, up to the secrets step; no secret decryption, no exit 0, no x86_64-linux or aarch64-darwin standalone home, no real host | not taken up |
| A part listed twice passes `structure-aspect-parts` (verify finding 5) | not taken up |
