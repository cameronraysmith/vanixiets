# Verification Report

**Change**: `name-the-parts-of-base-and-ai` (Linear CAM-141)
**Verified at**: `2026-11-28 05:55` (UTC)
**Verifier**: verify subagent (openspec-verify-change, satisfaction-argument-audit section 8), on stibnite

Implementation, merged on `main`:

- Pull request 4488, commit `f5c002dc43bd`: the NixOS base as a list (`modules/nixos/base.nix`) and `checks.x86_64-linux.structure-aspect-parts`. `git range-diff 8b4c77a8efeb..2fa12009ad77 04f35f985..f5c002dc4` shows the landed commit and `2fa12009ad77`, the commit its comparison ran on, differ only in `tasks.md`.
- Pull request 4509, commit `c69bbcac5565`: the darwin base and the `ai` aspect as lists, in one commit with `shape-the-repository-for-its-readers`' package and Brewfile sort (`modules/system/package-order.nix`). `git range-diff fb7b981f1e74..de1600cb6e74 1c2b60fc1..c69bbcac5` reports the two patches equal (`=`). `de1600cb6e74` is the commit the comparison ran on.
- After both: pull request 4510 (`d705c39bd6c6`, `shape-the-repository-for-its-readers`, CAM-142) took `initrd-networking` (formerly `base-initrd-networking`), `r2-usage` and `postgresql-backup` out of the NixOS list. `79734751b` added `nix-build-lock` to it.

Code was read from main's tree: `git archive origin/main` (`d705c39bd6c6`) into `/tmp/ntp-verify`. Line numbers below are at that revision. Evaluations used `nix-stock` (Nix 2.35.6), with no `nix-eval-jobs` process running.

---

## 1. Structural Validation (`openspec validate`)

- [x] This change reports valid under `--strict`

```text
openspec validate name-the-parts-of-base-and-ai --strict -> Change 'name-the-parts-of-base-and-ai' is valid
```

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`. 18 of 29 are ticked; 11 stay open.

Tasks closed at verify:

| Task | Evidence |
|---|---|
| 3.5 | `logs/srr-5b-profiles-20261127-233804.log`: each Mac's `system-path` (`sp-*`) and `system-applications` (`apps-*`) have the same entries, `links_target_differs: 0` and `missing: []`. These links come from replaying the locked `builder.pl`; nothing was built. For blackphos and stibnite the pair replayed was not the pair the drv-diff compared, but its `system-path.drv` and `system-applications.drv` are the same derivations (`logs/ntp-verify-mac-profile-drvs-20261128T055110Z.log`) |
| 6.1 | `logs/ntp-verify-main-20261128T054513Z.log`: one definition for each aspect, from `modules/nixos/base.nix`, `modules/darwin/base.nix` and `modules/home/ai/default.nix`. The check's drvPath is `szfhxyh4202z…` (pull request 4488's), and it builds to `4wcg2z8n3pmd…-structure-aspect-parts` |
| 6.3 | `logs/ntp-verify-part-alone-20261128T054555Z.log`: a `nixosSystem` built from the flake's `nixpkgs` input with only `base-zram-swap` gives `zramSwap.enable = true` and `memoryPercent = 100`. `nix.settings.experimental-features` is `[]` and `trusted-users` is `["root"]`. With `base-nix-settings` added, the features are `["nix-command","flakes"]`. The flake's `nixpkgs` input, not the fleet's overlaid `pkgs`, was used; overlays add no `zramSwap` or `nix.settings` |

Tasks left open:

| Task | Why |
|---|---|
| 3.4, 4.4 | Finding 2. The trace exits 1 on every reached toplevel and on seven homes. The only leaves it rejects there are `apm-deps` and `apm-skills-compose`, rebuilt from texts the same commit changes for `shape-the-repository-for-its-readers` (`git show --stat c69bbcac5`: `preferences-nix-checks-architecture/SKILL.md`, the `40-fleet-and-user-conventions` fragment). The task's verify ("exits 0", otherwise an open question in design.md) is not met, and design.md records no such question |
| 3.6, 4.6 | Finding 2. `drv-delta-darwin-base.txt` and `drv-delta-ai.txt` were never written. The comparison that ran used `shape-the-repository-for-its-readers/drv-delta-order.txt`, and it passes (`logs/drv-diff-fb7b981f1e74-de1600cb6e74-20261128T044712Z/report`, `result: PASS`). That allow-list holds attributes the trace rejects (finding 3) |
| 4.5 | Finding 4. Of the homes, only `home-manager-path` was compared, by replay. `-fonts` (25 accepted pairs) and `-applications` (22) were not compared. Thirteen profiles had members missing from the store |
| 5.1 | Design Open Question 1 is unanswered (design.md has no Resolved Questions) |
| 5.2, 5.3, 5.4 | No host has been deployed and no home activated with either commit. The newest deploy logs are `logs/tsc6-pyrite-deploy-20261124T2134Z.log` and `logs/ws-{magnetite,pyrite}-deploy-20261123T*.log`. The `logs/fdp-*-20261128T05*` files are builds, diffs and state reads for the fleet deploy being prepared for cinnabar, magnetite, pyrite and stibnite. Electrum, galena and scheelite have no deploy prepared. Argentum, rosegold and blackphos are offline |
| 6.2 | Finding 2. No comparison covers the darwin and `ai` steps on their own. The combined `changed` set is not D5's: all 20 homes, 41 x86_64-linux checks, 25 aarch64-darwin checks and 2 runtime tests changed. The trace did not accept every changed toplevel and home |
| 6.4 | Needs 5.3. Blackphos, argentum and rosegold are offline |

Note (2026-11-28): cinnabar, magnetite and pyrite were since switched to main `d705c39bd6c6` and stibnite activated from it (06:27Z to 06:31Z), each running the system built from that commit with no failed unit and no account or group created or deleted (`logs/fdp-*-20261128T06*.log`, tasks 5.2-5.3). No alert or notice was posted to `fleet-alerts` from 06:15Z to 06:33Z (`logs/fdp-alerts-read-20261128T0633Z.log`). argentum, rosegold and blackphos were offline; electrum, galena and scheelite are disabled; no standalone home was activated. A377 is exercised on stibnite only.

Trace runs on the compared pair: `logs/srr-5b-trace-20261127-233754.log` ran on pairs whose drvPaths match the drv-diff's for 174 of 186 attribute sides. The 12 that differ are blackphos, stibnite, `crs58@aarch64-darwin` and their `darwin-*` and `home-manager-crs58` checks, before and after: `fb7b981f1e74` (the fonts fix) landed between the two runs. Rerun on the drv-diff's pairs, the trace gives the same verdict. It accepts `chosenOutputs` of `system-path`, `system-applications` and the three home profiles, the gh-dash bindings and the Brewfile, and it rejects only `apm-deps` and `apm-skills-compose` (`logs/ntp-verify-trace-landed-20261128T054818Z.log`).

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| aspect-parts | pending sync | new capability |
| aspect-parts-interface | pending sync | new capability. Finding 1's scenarios need restating before sync |
| world-assumptions | pending sync | A375-A377 are not in `openspec/specs/world-assumptions/spec.md`. `shape-the-repository-for-its-readers` cites them without defining them, so this change syncs first or with it. The modified grounded-vocabulary table must be merged by hand with rows other changes add |

---

## 4. Design / Specs Coherence and Requirement Trace

### Interface requirements (`aspect-parts-interface`)

| Requirement / scenario | Code on main | Evidence | Status |
|---|---|---|---|
| Each aspect is one definition importing its listed parts | `modules/nixos/base.nix:8-44`, `modules/darwin/base.nix:8-42`, `modules/home/ai/default.nix:9-28` | — | met |
| — The aspects' definitions are read | — | `ntp-verify-main` log: one `_file` per aspect, its list file | met |
| — The lists are read | 32, 30 and 15 names | `ntp-verify-main`: lengths, no duplicates | met for darwin (D2's 29 plus `base-package-order` before `secrets`) and `ai` (D2's 15, in D2's order). For NixOS, met at `f5c002dc4` only (finding 1) |
| — Every former contribution has a name | rule (2) holds on main (check `actual = []`) | — | met when landed. Three NixOS parts are no longer in the list (finding 1) |
| — A part is imported alone | `modules/system/zram-swap.nix` | `ntp-verify-part-alone` log | met |
| A file adding to base, ai or an existing part, or an unlisted part, fails a small check | `modules/checks/structure/aspect-parts.nix:80` (rule 1), `:81-95` (rule 2, with a listed-but-undefined case), `:96-98` (rule 3) | below | met |
| — The check's form and size | `:115` `self.lib.mkStructuralCheck` (`expected = [ ]`, literal name), `:108-113` size `small`, `measured = false`; `:32-35` exempts `ai-skills` and `ai-skills-compose`; `:39-57` lists exactly `base-system-defaults` (9 files) and `ai-claude-code` (5 files) | — | met |
| — A file assigns into base directly | — | `logs/ntp-2-mutants-20261127-194210.log` m1 (NixOS: names `modules/nixos/mutant-into-base.nix`); `logs/srr-5-structure-20261127-223916.log` `mut-darwin-base` | met |
| — A part is in no list | — | `ntp-2-mutants` m2 (`nixos.base-zram-swap: in no base list`); `logs/ntp-verify-mutants-20261128T054532Z.log` (`darwin.base-unlisted: in no base list`, and the build fails); `srr-5-structure` `mut-tuicr`, `mut-ai-unlisted` | met |
| — A second file assigns into an existing part | — | `ntp-2-mutants` m3 (both files and `base-zram-swap` named); `srr-5-structure` `mut-tenth`, `mut-sixth` | met |
| — The key set is read | the check's name is a literal at `:114-115` | `ntp-verify-mutants`: with `nixosBaseParts` replaced by a `throw`, `attrNames checks.x86_64-linux` still holds `structure-aspect-parts`, and reading the check's value throws | met |
| Each step is accepted on its own derivation comparison | — | — | met for the NixOS step. Not met for the darwin and `ai` steps (finding 2) |
| — A leaf differs only in an accepted order | `drv-order-trace.py:93-104` | `logs/ntp-verify-trace-judge-20261128T054749Z.log` | met (see "Acceptance rule" below) |
| — A leaf differs in another field | `:104`, `:142-143`, `:168-169` (exit 1, field printed) | the real rejections of `apm-deps` (`env.buildCommand`) in the trace logs; judge log rows | met |
| — The reordered profiles are built | — | `srr-5b-profiles` (replayed, not built) | met in part (finding 4) |
| — A Brewfile's lines move within a section | `:81-90`, `:100-103` | judge log: an in-section move is accepted. A cross-section move, swapped sections, a changed heading, an added line and a line before the first heading are each rejected. `logs/srr-5-brewfile-20261127-225329.log`: the casks (and stibnite's brews) are reordered within their sections | met |
| — The NixOS step | — | `logs/drv-diff-8b4c77a8efeb-2fa12009ad77-20261128T010505Z/report`: nixos 6/6, darwin 4/4, home 20/20 identical; `structure-aspect-parts` added; `fleet-alert` changed; base-allowed checks only; `PASS` | met |
| — The darwin step | — | combined comparison only | not met as stated (finding 2) |
| — The ai step | — | combined comparison only | not met as stated (finding 2) |

### Behavioral requirements (`aspect-parts`)

| Requirement / scenario | Discharged by | Status |
|---|---|---|
| Each of the three is one parts list | inventory plus check | met |
| — A reader asks what the darwin base is | `modules/darwin/base.nix:8-39` | met |
| — A statement adds outside the list | mutants above | met |
| — A part named and never listed | mutants above | met |
| — A second statement adds to a part | mutants above, multi-file exception named in the check | met |
| A part can be taken alone (and its scenario) | `ntp-verify-part-alone` | met |
| Restating changes nothing delivered beyond declared order | `logs/srr-5b-state2-{parent2,commit2}-20261127-234552.json` (same store paths and priorities; accounts, groups, uids and gids equal); profile replays; trace | met for members and accounts, observed in evaluation only. Not shown for the commit as landed, which also changes two home-delivered texts (finding 2) |
| — Declared differences are read | `drv-delta-order.txt` (another change's allow-list) | met in part: the entries name hosts and homes, but beside the reorders they also declare content changes |
| — A step is compared with its base commit | one comparison for the darwin and `ai` steps together | met in part (finding 2) |
| — A Mac is deployed after the restatement | — | open: no Mac deployed (tasks 5.3, 6.4) |
| — Installed packages compared, every package included | profile replays | met in part (finding 4) |
| — Something other than declared order differs | the trace rejected `apm-deps` and `apm-skills-compose`. The commit landed with those differences declared as another change's content. No open question was recorded | not met as stated (finding 2) |

### Acceptance rule against the trace tool

The spec states the rule in "A leaf differs only in an accepted order" and "A leaf differs in another field". Design D4 states the same three kinds, (a) to (c), plus substitution of changed input paths. `drv-order-trace.py` on main (identical to the change directory's copy) implements:

- (a), `:94-95`: a build named in `PROFILES` (`:16-22`, the five names) and field `structuredAttrs.chosenOutputs` with the same multiset of entries.
- (b), `:96-99`: field `structuredAttrs.value.keybindings.prs` of `gh-dash-config.yml` with the same multiset of whole entries, whose (key, name) pairs are exactly `m`/enqueue, `M`/enqueue stack, `C`/code review.
- (c), `:100-103`: field `structuredAttrs.text` of `Brewfile`. Sections start at lines beginning `# `, and both sides need equal (heading, line multiset) lists in the same order. Text before the first heading is rejected.
- Substitution, `:144-152`: the outputs of paired inputs are replaced before fields are compared. `outputs`, `inputDrvs`, `inputs` and `name` are not compared.
- Everything else is rejected, and so is an input present on one side only (`:142-143`).

The judge log confirms each of these on constructed values. Every rule the spec states matches what the tool accepts. Two departures from D4's prose:

- D4 says a pair of same-named inputs the tool cannot match stops the step. The tool always pairs while both sides have candidates (`:127-139`: shared inputs first, then closure overlap), so that rejection never occurs. A mispair shows up as rejected fields, not as an acceptance.
- A text that embeds a store path without string context is not substituted, so the tool rejects it even when the path is an accepted reorder (finding 3).

### World assumptions

| Assumption | Evidence | Status |
|---|---|---|
| A375 deferred-module levels | the `_file` values read on main end `, via option flake.modules.<class>.<aspect>`, as the check expects (`:62-69`) | holds as used |
| A376 buildEnv first-member rule | profile replays show 0 targets differ | not contradicted where measured |
| A377 nix-darwin deletes undeclared known accounts | `knownUsers`, `knownGroups`, uids and gids equal (`srr-5b-state2`) | not exercised: no Mac deployed |

### Findings

1. **The NixOS list on main is not D2's plus `base-package-order`.**
   - What was checked: `modules/nixos/base.nix:8-41` against design D2 (`design.md:78-79`).
   - Result: main has 32 names. Starting from D2's 33 plus `base-package-order`:
     - `79734751b` added `nix-build-lock`.
     - Pull request 4510 removed `initrd-networking`, `r2-usage` and `postgresql-backup`. `hetzner-cloud` and `gcp-cloud` now import `initrd-networking`, and magnetite's host module imports the other two.
   - Every other name is in D2's order.
   - The darwin and `ai` lists equal D2 as amended.
   - Two interface scenarios are true only at the commits that landed them: "The lists are read" ("the names design D2 lists … plus `base-package-order`") and "Every former contribution … is in its class's list".
   - Needs: restate both so they hold after later changes. For example: the lists hold the names D2 gave at landing, and later changes move parts in or out of a list only by editing it. Or add a dated correction to D2 naming the four later edits.
   - Correction (2026-11-28): both scenarios are restated to hold on main (the list is what the list file holds, each part named once, moved only by editing the list), and design D2 records the five later edits ("Since landing").
2. **The darwin and `ai` steps were not accepted on their own comparison.**
   - What was checked: tasks 3.4-3.6 and 4.4-4.6 against the logs, and `git show c69bbcac5`.
   - Result: both steps landed in one commit with `shape-the-repository-for-its-readers`' order step and two text changes of that change. One drv-diff covers all of it (`PASS`, allow-list `drv-delta-order.txt`). The per-step allow-lists of D5 were not written.
   - On every changed toplevel and on the `cameron@*`, `crs58@*` and `claude-sandbox` homes, the trace exits 1. Its only rejected leaves there are `apm-deps` and `apm-skills-compose`, which the other change's texts reach. Every order difference it reports is accepted.
   - Contrary to D4 and the spec, the rejection did not stop the commit and was not recorded as an open question.
   - Needs one of these:
     - a dated correction in design.md (D4, D5) and in the interface spec ("Each step is accepted on its own derivation comparison", "The darwin step", "The ai step") stating that the two steps landed with the order step under one comparison, and that the trace's only rejections came from the other change's declared content, with the trace logs as evidence;
     - or a trace over a tree holding only this change's edits.
   - Correction (2026-11-28): design D5 records the departure, and Open Question 2 the evidence standing in for the two comparisons. The interface requirement "Each step is accepted on its own derivation comparison" and its darwin and `ai` scenarios are not restated.
3. **The combined allow-list holds attributes the trace rejects for reasons other than content.**
   - What was checked: rejected leaves in `logs/srr-5b-trace-20261127-233754.log` outside the apm and docs leaves.
   - Result:
     - `omnigent-acp-spawn-env-cases.json` (`checks.x86_64-linux.omnigent-acp-spawn-env`) embeds magnetite's and pyrite's omnigent `home-manager-path` as text.
     - `vm-test-evaluates-omnigent-worker-isolation` names the test's run derivation as text.
     - `run-nixos-vm` (both `omnigent-worker-isolation` runtime tests) is rejected on `structuredAttrs.text`.
   - `drv-delta-order.txt:103,123-125` declares them with reasons. D4 would add such an attribute only when every leaf is (a), (b) or (c).
   - They come from the order step, not from this change's lists. Record them in that change's verification, or teach the tool to substitute paths without string context.
   - Correction (2026-11-28): the lines of `drv-delta-order.txt` for these attributes and its header now give the cause: a changed store path embedded as text with no string context, which the trace cannot substitute.
4. **The built-profile comparison is partial.**
   - What was checked: `srr-5b-profiles` against D4 ("every build the tool reports under (a) is built").
   - Result: the profiles were replayed with the locked `builder.pl`, not built.
   - Members were missing from the store in thirteen profiles:
     - `hm-{cameron,crs58}@aarch64-linux` 116 each;
     - `hm-{christophersmith,janettesmith,raquel,tara}@aarch64-linux` 96 each;
     - six other homes 2 each;
     - `sp-scheelite` 1 (`nvidia-persistenced`).
   - No `home-manager-fonts` or `home-manager-applications` was compared, although the trace accepted 25 and 22 such pairs. No log shows `go-containerregistry` realised.
   - Every Mac `system-path` and `system-applications`, and every NixOS `system-path` apart from scheelite's one missing member, is complete and identical (task 3.5).
   - Needs: realise the missing members, and compare `-fonts` and `-applications`, for task 4.5.
   - Correction (2026-11-28): design D4 ("Profiles replayed, not built") states the replay and what was not compared; task 4.5 stays open for it.
5. **A part listed twice passes the check.**
   - What was checked: `ntp-verify-mutants`, which lists `base-zram-swap` twice in `modules/nixos/base.nix`.
   - Result: `actual = []`, and the drvPath is unchanged (`szfhxyh4202z…`). No requirement asks for this case.
   - Suggestion: add a rule naming duplicate entries, since importing a part twice doubles its list-option definitions.

### Leftovers

- `rg 'name-the-parts|CAM-141' modules` finds nothing. The added lines of `f5c002dc4`, `c69bbcac5` and `d705c39bd` under `modules/` cite no design id, task number or step of this change.
- `modules/checks/magnetite-zram-headroom.nix:31-32` says "modules/system/zram-swap.nix exports into the `base` namespace, i.e. every machine". It should say: "modules/system/zram-swap.nix defines `base-zram-swap`, which `modules/nixos/base.nix` lists, so every NixOS host takes it".
- `packages/docs/src/content/docs/concepts/deferred-module-composition.md:232-233` says files in `ai/` "auto-merge into a single aggregate" with "No explicit aggregate definition needed". It should say: each file in `ai/` defines its own part (`ai-<harness>`), `modules/home/ai/default.nix` lists the parts in `flake.lib.homeAiParts`, and `checks.x86_64-linux.structure-aspect-parts` fails on a part in no list.
- `packages/docs/src/content/docs/development/architecture/architecture.md:124-125,193-194` says files in `modules/home/ai/` export to `flake.modules.homeManager.ai` and merge into it. It should give the same statement as the previous item.
- `docs/notes/development/architectural-principles.md` O44 (`:553-560`) already has a Status line describing the three lists and the check. Row A30 (`:159`) still reads as an open finding. It could add "(resolved, O44)".
- Not changed: ADRs 0018 and 0020 and the dated research notes (`docs/notes/development/ai-agents/pi-integration-reconnaissance.md:179-180`, `docs/notes/development/research/nix-kubernetes-product-brief-references.md:433-440`). They are dated records of the state at their time.

---

## 5. Implementation Signal

- [x] Code committed: `f5c002dc4` (pull request 4488, `MERGED` 2026-11-28T01:41:46Z) and `c69bbcac5` (pull request 4509, `MERGED` 2026-11-28T05:12:39Z), per `gh pr view`
- [x] All related commits are on `origin/main`

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files under `docs/superpowers/specs/` (the directory does not exist)

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows. The deploy tasks (5.2-5.4, 6.4) have no automated equivalent: they check what a running host links and what nix-darwin deletes at activation.

---

## 8. Designation Lint and Discharge Coherence

**8a.** Checked against the grounded-vocabulary rows in this change's `world-assumptions` delta and in `openspec/specs/world-assumptions/spec.md`.

- Nouns with rows: base settings, agent tooling, part, parts list, fleet description, host, home configuration, configuration, check, base commit, candidate commit, declared difference, member order, review binding, package, account, identifier, operator.
- Nouns with no row: "restatement step" (only "delivery step" and "setup step" exist), "Homebrew entry", "group" (in the sense of an account group; only "dashboard group" and "plugin group" exist), "activation step" and "configuration file".
- Suggestion: add rows for "restatement step", "Homebrew entry" and "group" (a set of accounts with a gid). Alternatively, reword the scenarios to use "delivery step" and "package".

**8b.**

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| One parts list each | list files plus the structure check | A375 | built; mutants killed |
| A part can be taken alone | the part is its own module | — | observed |
| Restating changes nothing beyond declared order | drv-diff plus trace plus state and profile comparisons | A344, A375, A376, A377 | observed for members and accounts. The per-step trace is not clean (finding 2) and the profile comparison is partial (finding 4). A377 is unexercised until a Mac deploys |

**8c.** No behavioral requirement names a machine phenomenon. The interface requirements name options, files, checks and the tool.

---

## Overall Decision

- [ ] (pass) PASS
- [x] (warn) PASS WITH WARNINGS. Do not archive until:
  - findings 1 and 2 are restated in the spec and design (dated corrections) and tasks 3.4, 3.6, 4.4, 4.6 and 6.2 are closed against the restatement;
  - task 4.5's profiles are completed (finding 4);
  - the operator tasks are done: 5.1, then 5.2 (six NixOS hosts), 5.3 (four Macs, three now offline), 5.4, and 6.4 after 5.3.
- [ ] (fail) FAIL

**Next step**: decide how findings 1 and 2 are restated, then deploy the ten hosts.
