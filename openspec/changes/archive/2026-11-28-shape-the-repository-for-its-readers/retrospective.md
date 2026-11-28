# Retrospective: shape-the-repository-for-its-readers

> Written: 2026-11-28 (after verify reported NOT READY FOR ARCHIVE, after its F1 and F3 were done by #4511 and its other findings had dated corrections, before archive)
> Commit range: planning `04f35f985` (#4487); then on `main` `963e6ac6b` (#4497), `c69bbcac5` (#4509), `d705c39bd` (#4510), `709ada4e3` (#4511) and `8918ef77a` (#4512, the verification, re-measurement and deploy record)
> Worktree: merged to main; this retrospective and the archive are one further commit

---

## What the change set out to do

Fresh read-only agents, measured on `main` `1e8fb9ff6d66`, answered 20 of 20 lookups right in a median of two files, so the layout was not the cost. Three runs per harder task showed what was: a new host went into 12 host lists, 4 unenforced, and every run missed a step; listing a host's composition took 26-33 files; a home's systems could not be read without evaluation; checks and hand-entered secrets each had two conventions (proposal Why). The change took the smallest shape that evidence supports (design D3, candidate (i)): host lists derived from the registry or checked against it, `just composition` with a route obligation, one placement rule per kind of addition, package and Homebrew lists sorted, the order of review bindings, overlays and darwin activation snippets written in one place, and the people registry's literals derived.

## 0. Evidence

- **Commit range**: `04f35f985` (plan, #4487), `963e6ac6b` (host lists, composition, placement rules, people's literals, #4497), `c69bbcac5` (sort, darwin and `ai` parts lists, #4509), `d705c39bd` (initrd networking and two services only where used, #4510), `709ada4e3` (gh-dash bindings, overlay order, activation order, `structure-fleet` control, #4511), `8918ef77a` (verification, re-measurement, deploy record and text corrections, #4512); 6 commits
- **Diff size**: `963e6ac6b` +1917 / −571 across 51 files; `c69bbcac5` +553 / −246 across 91 files; `d705c39bd` +175 / −59 across 18 files; `709ada4e3` +241 / −126 across 28 files; `8918ef77a` +1275 / −101 across 29 files; artifacts included
- **Tasks done**: 52/60 at archive (`tasks.md`); the 8 open tasks are listed under "Open items" with their reasons
- **Active hours**: about 5.6 h from the plan (2026-11-27 20:06 −05:00) to the verification record (2026-11-28 01:44 −05:00)
- **New external dependencies**: none
- **Bugs encountered post-merge**: none observed on the deployed hosts. The verification found three order items not done and `structure-fleet` without a control (F1, F3), done by #4511
- **OpenSpec validate state at archive**: `repository-shape` and `repository-shape-interface` valid under `openspec validate <spec> --type spec --strict`; `openspec validate --specs --strict` fails on the same 18 specs as on `main` before the sync, `apple-laptop-hardware-support` and `world-assumptions` among them, on warnings only
- **Test coverage signal**: four drvPath comparisons, each PASS: `96a3c1ef8a8d..c63a450f800e` (no host or home changed), `fb7b981f1e74..de1600cb6e74` (order and two home-delivered texts), `c69bbcac5565..d705c39bd6c6` (pyrite only), `d705c39bd6c6..709ada4e324b` (no host, home or runtime test changed); mutants of `host-list-keys`, `hetznerBootLoader`, `cloud.type`, `compositionRoutes` and a darwin part moved in its list; the profile replay of 54 profiles; the reader re-measure at `d705c39bd6c6`

Commit chain (chronological):

```
04f35f985 docs(openspec): plan shaping the repository for its readers
963e6ac6b refactor(fleet): derive host lists from the registry, print a host's composition, state placement rules
c69bbcac5 refactor(fleet): sort package lists and name the parts of the darwin base and the ai aspect
d705c39bd refactor(nixos): give remote-unlock initrd networking and two services only to the hosts that use them
709ada4e3 refactor(fleet): write gh-dash bindings, overlay order and activation order values independently of import order
8918ef77a docs(openspec): record the verification, re-measurement and deploy of the repository-shape changes
(this commit) docs(openspec): archive name-the-parts-of-base-and-ai and shape-the-repository-for-its-readers
```

---

## 1. Wins

- The measurement decided the shape. Lookups were already cheap, so the class-first tree stayed: two files moved (`ntfy-alerter.nix` and `hm-sops-bridge.nix`, from `nixos/` to `system/`) and one part was renamed (`base-initrd-networking` to `initrd-networking`), against about 400 moves for a feature-first re-layout that would have moved none of the measured costs (design D3). The costs measured were removed instead: host lists derived or checked, a composition command, rules where the tree held two answers.
- A new server's generated steps, the `fleet-deployers` link among them, were listed by every placement run, 3 of 3 against 0 of 3 at the baseline (task 10.1).
- Package lists, Homebrew lists, review bindings, overlays and darwin activation snippets take their order from a sort or one written list, not from import depth: moving a darwin part, a gh-dash part, an overlay file or an activation snippet changes no configuration (tasks 5.4-5.7).
- Deploying confirmed the predictions on four hosts: cinnabar, magnetite and pyrite were switched and stibnite activated at `d705c39bd6c6`, each running the system built from that commit, no unit failed, no account or group was created or deleted, and the sops manifests were the predicted store paths. The two differences were on cinnabar, where `zpool-probe.timer` kept its start time and the one-shot `zerotier-autoaccept-zerotier` ran once and exited 0 (task 8.2). Two reads of `fleet-alerts`, at 06:33Z and at 06:59Z, 28 minutes after the last switch, found no message since the deploy began (`logs/fdp-alerts-read-20261128T0633Z.log`, `logs/fdp-alerts-read-20261128T0659Z.log`).

## 2. Misses

- [high] [painful | evidence: tasks.md 10.1, 10.1b, verify §4 "Measure targets"] The acceptance requirement, "Restructuring is accepted on what readers can do", is not met. Of design D1's targets, by number:
  - met: 1 (lookups 20 of 20); 4 for PL1 and PL3 (3 of 3 each), and PL5 against the rule `modules/checks/README.md` states (3 of 3; 2 of 3 against the key); 5 as the guide counted it (8 / 6 / 1; by D1's definition 9 / 6 / 2); 6 (every PL2 run lists every generated step, 3 of 3); 10 reported (I2, 90 files under `modules/`, baseline 91);
  - not met: 2 (lookup files maximum 6 against the baseline's 4); 3 (question 17's mislead recurs, and `modules/README.md:70` caused a new one); 9 (tree arm: E2 files median 22 to 27; I1 0 of 3, files 16 to 16; E1 2 of 3 complete against 1 of 2, files 29.5 to 30);
  - not measured: 7 and 8, the commands arm, because the measuring agents have no shell (task 10.1b).
- [med] [painful | evidence: verify F1, F3] Three order items and `structure-fleet`'s control were planned for the first two passes and missed there; they landed after the verification as #4511, compared against `drv-delta-order-items.txt`.
- [med] [painful | evidence: verify F4, F9, F11] The requirement said the order step changes order only; the step also carried two texts delivered into homes, and the third pass changed pyrite's initrd. The requirement was restated as "Restructuring delivers nothing but its declared differences". The second comparison ran on parent `fb7b981f1e74`, six commits before the landed parent `1c2b60fc1`, with the same patch.
- [med] [nit | evidence: verify F7] `grade.py` graded nothing: the baseline and the re-measure were graded by hand.
- [low] [nit | evidence: verify F8] A ninth hand-written host list, the evaluator table in `modules/README.md`, was missed in the count.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| D5 steps 1-4, 2b, 7 | One commit, `963e6ac6b`, under `drv-delta-first-pass.txt` | Every step had the same acceptance: no host or home changes |
| 5a, 5.3 | No priority step | Measured on every enabled host, no path is provided by two equal-priority members (task 5.2) |
| 5b, 6 | One commit with `name-the-parts-of-base-and-ai`'s darwin and `ai` steps | Those steps waited for the order step, so that they would change no derivation |
| 5.5-5.7, 2.6 | Landed after the verification, as #4511 | Missed in the order step (verify F1, F3) |
| 8.1, 8.4 | No standalone home is known to be in use; the five aarch64-linux standalone homes were activated in a throwaway virtual machine | design Resolved Question 14 |
| 10.1 | Tree arm only, hand-graded | The measuring agents have no shell; `grade.py` does not read the records' form |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | not evidenced in the change's files |
| superpowers:subagent-driven-development          | not evidenced in the change's files |
| (transitive) superpowers:test-driven-development | yes in the mutant form: each new check and judge shown failing against a mutant |
| (transitive) superpowers:requesting-code-review  | yes for #4511 (review corrections under tasks 5.5-5.7); not evidenced in the change's files for the other commits |
| superpowers:finishing-a-development-branch       | yes (#4497, #4509, #4510, #4511 and #4512 merged) |

Review gates: no review-gate decision is recorded for this change beyond the reviews that ran before each commit landed; no review.md. `verify.md`'s Overall Decision is NOT READY FOR ARCHIVE, with the state of each of its conditions recorded under it at archive.

## 5. Surprises

- nixpkgs applied the overlays reverse-alphabetically by file name (`zed-delta` first, `aeneas` last), not in import order as `compose.nix` said; `overlayOrder` now writes that order (task 5.6).
- `just composition magnetite` printed 83 names at the measured commit, not the 81 the re-measure graded against, because three parts were added or renamed after the first pass (verify F10).

## 6. Promote candidates → long-term learning

- [ ] [med] **Measure readers before restructuring a repository: the costs were in host lists, composition and duplicate conventions, not in the layout.**
  → **Promote to** memory
  > **Why**: 20 of 20 lookups were right in a median of two files on the old tree; a re-layout would have moved none of the measured costs.
  > **How to apply**: before proposing a directory re-layout.
- [ ] [low] **A reader measure whose acceptance needs a shell needs measuring agents with a shell, planned before the measure runs.**
  → **Promote to** one-off
  > **Why**: targets 7 and 8 could not be measured.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| Targets 2, 3 and 9 not met; 7 and 8 not measured (task 10.1b) | not taken up; a commands-arm run needs measuring agents with a shell |
| The mesh address seam: `ztRecords`, the one host list a new host joins by hand, and the ZeroTier readers I2 counts | migrate-mesh-to-tincr |
| The evaluator table in `modules/README.md`, a host list kept by convention only | not taken up |
| pyrite's orphaned `vars/per-machine/pyrite/initrd-ssh/` files (task 6b.2); pyrite's new initrd, without `virtio_net` and `virtio_pci`, takes effect at its next boot | a separate, reviewed removal; pyrite's next boot |
| argentum and rosegold, offline at the deploy, and blackphos, which has no machine: the three Macs not deployed (task 8.3) | the next deploy of argentum and rosegold |
| `resolverReload = 500` in `activationOrder` ties with any other `mkBefore` snippet in `postActivation` | not taken up |
| Task 5.8: the order trace exits 1 at the two home-delivered texts | not taken up; the restated requirement admits them |
| Tasks 6.2 and 6.4: four files assigning into two aggregates are not split; no comparison isolates the parts lists | not taken up |
| Task 9.2: `docs/notes/development/architectural-principles.md` lacks the resolving commits | a later edit of that file |
| Task 10.2: the `basalt` trial of adding a server | not taken up |
| The standalone homes: activated only in a test machine, up to the secrets step | not taken up |
| `grade.py` cannot read the baseline's or the re-measure's records (verify F7) | not taken up |
| The world-assumptions designation tables: `part` and `review binding` have rows both in `Grounded vocabulary for behavioral requirements` (from `name-the-parts-of-base-and-ai`) and in `Designations for the shape of the fleet description` | not taken up |
