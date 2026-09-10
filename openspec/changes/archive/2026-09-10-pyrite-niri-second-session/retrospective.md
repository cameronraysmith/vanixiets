# Retrospective: pyrite-niri-second-session

> Written: 2026-09-10 UTC, after independent PASS WITH WARNINGS (`verify.md` §9.12)
> Schema: `superpowers-bridge-wrspm`
> Commit evidence: routed implementation range `a34162bf401e1b8db4d0d98fcdc7a414c28d9690..50b2c0dd152e7279a323495a48bcd662daccd1bf`; evaluated wip `28ecab070f0494706acda1bee519a0869d304a85`; later delivery has no groundable source-commit identity
> Worktree: active jj-colocated diamond join shared with other agents; no writing VCS commands, no whole-worktree cleanliness claim

---

## 0. Evidence

- **Tasks: 34 checked / 4 unchecked, 38 total.** Unchecked 2.3 is vacuous by its own rule; 8.2 is split, with remembered choice discharged and no-history a method limitation; 8.6 is declined; 9.3 is upstream follow-up CAM-66 (`tasks.md`, `verify.md` §9.12).
- **Final verdict: PASS WITH WARNINGS against the amended requirement, not full behavioral observation or formal discharge.** 8.3/8.4/8.5 are discharged by evaluation, not observation; 8.6 is declined under CAM-59; 8.7 is discharged by physical tests with same-boot controls. No-history GNOME remains **source-read only**, not discharged-by-evaluation. These qualifications are load-bearing, not footnotes.
- **Runtime observation:** inherited 4.2 snapshot at 03:13:54 UTC, niri session 238 / compositor PID 158454, no idle consumers, `IdleAction=ignore`, zero failed user units (`logs/niri-archive-live-snapshot-20260909-231353.log`). New 6.6/8.2 read at 03:22:14 UTC, same session, from the compositor's own environment (`logs/niri-final-session-observation-20260909-232214.log:1–44`). Logind's Leader is separately 158370.
- **Physical test:** one protected GNOME press in session 176 and two protected niri presses in session 209, all logged, no suspend or shutdown in those windows. Pre-fix same-boot media-keys press requested suspend and entered deep sleep. Authentic whole-boot totals **1 requested / 1 entry**, not zero or two (`verify.md` §§9.9,9.11).
- **Counterexample:** switch complete 00:12:03; display-manager restart 00:12:06 while niri live; session 157 removed but compositor survived; GNOME startup failed until niri termination 00:15:16. The checklist origin is operator testimony; timestamps, authentication success and startup rejection are journal evidence (`logs/niri-final-verdict-cam66-20260910.log:1–8`; `known-limitations.md`).
- **Pinned source freshly read for final verdict:** niri v26.04 commit `8ed0da44d974c32c6877d2f4630c314da0717ecb`, complete `resources/niri-session:1–95`; GNOME 50.1 `leader-systemd.c:246–277`; GDM 50.1 `gdm-session.c:621–625,687–694` (`logs/niri-final-primary-sources-20260909-232259.log:4–175`). Root input edge was executed from current `flake.lock`: `nixpkgs_9 → 85f62611fa3f3eacbcfe3bc7a6d6518b443ca442`, same log:1–2.
- **Diff and time:** routed nine-path scope is inherited from `logs/niri-ledger-scoped-stat-20260909-143809.log`; no aggregate shared-working-copy stat or invented final diff size. The cycle spans September 9–10 UTC; active agent hours and total dispatch count were not instrumented.
- **Dependencies:** one niri-flake input, consuming only `homeModules.config`, both nixpkgs inputs following root; validation uses the system niri package, not an independently selected package (`tasks.md` 1.1–2.4). The C session monitor is **not carried**.
- **Structural readiness:** final strict CLI output is recorded in `logs/niri-slice-a-archive-final.md`. OpenSpec validates Markdown/delta structure only. `verify.md` §8 is agent-executed, non-blocking and **NEVER validation**; reporting a designation lint clean without grounding would be vacuous (`openspec/config.yaml:49–51`).

Evidence labels matter: current host/source reads above were executed by the final worker; earlier runtime/build/physical evidence is inherited or operator-observed. The operator supplied the concurrency-race account and the closure-localisation account below; this worker did not reconstruct those events from a complete execution trace.

## 1. Wins

- **Reading configuration is not evidence it is in force.** Four instances were caught only by runtime interrogation, not source agreement:
  1. `switch-to-configuration` wrote correct `logind.conf` while the running daemon retained **HandlePowerKey=poweroff**; only `busctl` exposed it. Manual reload then made all three properties `ignore`. The before-value is inherited operator evidence, not a newly replayed probe (`verify.md` §9.2; `logs/niri-final-portal-context-20260909.log:959,983–987`).
  2. **display-manager had the same unit-not-restarted pattern.** The evaluated/built session registry was correct, but the already-running GDM did not acquire it just because switch finished. Its actual restart at 19:03:10 and subsequent operator cog/login established adoption (`tasks.md` 6.4). Unfortunately the later checklist applied that remedy from an unsafe state (§2).
  3. **gsd-media-keys adoption of the new dconf database was proven by `/proc/<pid>/maps`, not timing.** PID 148129 starting after generation 10 was suggestive; its mapping of the new store-backed file-db was decisive (`logs/niri-cam66-final-daemon-20260910.log`; `verify.md` §9.8).
  4. **A swallowed permission error made an existing AccountsService file read as absent.** `cat ... 2>/dev/null || echo '(no file yet)'` manufactured a persistence failure; privileged inspection found `[User] Session=niri`, written at login (`verify.md` §9.1; `logs/niri-verify-discrepancies-20260909.log:1–13`).
- **A fifth, smaller instance: the observation command became its own false event.** A journal grep for `suspend requested` matched a sudo audit message recording that very grep, inflating a count. Recounting authentic logind/kernel message prefixes produced **1/1**, not two; raw provenance and explicit correction remain (`verify.md` §9.11; `logs/niri-archive-desktop-sudo-source-20260909-231426.log`). Count owning events, not incidental text.
- **The final niri probe strengthened the argument rather than just checking a box.** Through `/proc/158454/environ`, GNOME idle-delay is `uint32 1800` but the entire gsd power schema is unavailable on niri's `XDG_DATA_DIRS`: GNOME power settings are structurally inapplicable, not merely unread by an absent daemon. All four inhibitors are delay-mode sleep, with no block-mode handle-power-key inhibitor; that independently corroborates the physical niri test (`verify.md` §9.12).
- **The evidence-method line held.** Task 4.2 was eventually closed by a full live process/service/autostart observation, not by the already-passing configuration argument. Benign IBus/keyring helpers were not renamed failures to satisfy an overbroad predicate (`tasks.md` 4.2).

## 2. Misses

- [high] **The post-deploy checklist itself contained the hazard.** “Deploy, then restart display-manager,” executed inside live niri, stranded the compositor and locked the operator out, presenting as a rejected password. Authentication actually succeeded; GNOME startup rejected an already-running graphical session. This was an orchestrator-supplied sequence, not a stray operator mistake. Correct order: **quit niri first, confirm the affected user's niri.service is inactive, then perform any separately authorized restart**; SSH or the greeter alone is not a safety gate (`tasks.md` 6.4; `known-limitations.md`).
- [high] **Task 8.1 was the test that would have caught the session-strand defect.** It remained unchecked while convenient evaluation tasks closed. Recovered two-desktop usability later discharged it but did not repair the strand. A quit-only smoke need not reproduce a live-niri restart; test ordering and initial state belong in the test (`verify.md` §§9.7–9.12).
- [high] **Two agents were dispatched concurrently onto the same artifacts by orchestrator error, and one run's output briefly won a race over the other's.** This is the operator's explicit incident account supplied for this retrospective, not an independently reconstructed filesystem trace. Assign one writer per artifact and reconcile terminal outputs before authorizing a successor; a shared diamond is not write isolation.
- [med] **8.2's no-history half is a method limitation, source-read only.** Destroying the operator's real AccountsService preference to demonstrate a default was declined. GDM 50.1's hardcoded GNOME fallback and explicit null/no preStart rewrite support the expectation, not the observation. The remembered-choice half is discharged; a disposable no-history user is the safe future test (`tasks.md` 8.2).
- [med] **8.3/8.4/8.5 have no untouched behavioral windows.** They are explicitly discharged by evaluation on operator decision. **8.6 was declined**, not awaiting scheduling: re-proving CAM-59's known risky resume failure buys this slice no useful evidence (`tasks.md` 8.3–8.6).
- [med] **No named discharging interface requirements exist for this behavioral delta.** Runtime/build success does not fill that formal gap. Retain all rows as undischarged with V-interface references in the projection; retain the designation/alphabet warnings rather than reporting a vacuous clean lint (`verify.md` §8).

## 3. Plan deviations

`plan.md` was not authored; tasks were the operative ledger. No retrospective plan is fabricated (`verify.md` §7; CLI readiness status).

| Plan/check | Deviation | Reason and evidence boundary |
|---|---|---|
| Unconditional GNOME reachability/recovery | Requirement amended after a real counterexample | Legitimate upstream scope correction, not an erased FAIL; exact exception and CAM-66 remain (§5). |
| Local session-lifetime repair | Sound sd-login C-monitor approach written, then deliberately not carried | Disproportionate, not end-to-end verified, belongs upstream; prototype preserved in logs (§5). |
| Scope stat referred to as task 1.4 in earlier instructions | Replaced shared-working-copy `git diff --stat`/join-wide stat with read-only routed commit comparison | **No 1.4 exists in the current ledger; actual task is 7.2.** `logs/niri-slice-a-ledger.md:109–115` records this numbering mismatch, rather than inventing a task. |
| 4.2 “nothing active” autostart predicate | Corrected to “no idle consumers,” retaining live observation | Pinned niri explicitly wants `xdg-desktop-autostart.target`; benign consumers are allowed. Malformed predicate, not missing implementation. |
| 6.6 prescribed GNOME prerequisite transcript | Discharged via inherited mapped database adoption plus new live-niri environment/inhibitor observation, under explicit operator disposition | No pretend replay of original order and no risky restart. |
| 8.2 whole sequence | Split remembered choice from no-history method limitation | Operator declined destroying real preference; disposable account later. |
| 8.3/8.4/8.5 untouched intervals | Evaluation discharge, not observation | Explicit method substitution, never inferred from correcting a malformed predicate. |
| 8.6 deliberate suspend/wake | Declined | CAM-59 physical-recovery risk; not a passed test. |

**Verification tasks were repeatedly malformed, not merely unmet.** Correcting a predicate to match the actual requirement is legitimate; substituting an evidence method is not the same act and requires an explicit disposition. That line was held for 4.2 and for the predecessor's 6.6/8.2 block.

## 4. Skill / workflow compliance

| Skill/workflow | Use and boundary |
|---|---|
| `superpowers:brainstorming` | Existing `brainstorm.md`; inherited, not rerun at archive. |
| `superpowers:writing-plans` | Skipped; no `plan.md`, tasks carry the operative method and deviations. |
| `superpowers:using-git-worktrees` | Skipped; jj-colocated shared diamond, orchestrator-owned routing, no writing VCS allowed. |
| `superpowers:subagent-driven-development` | Inherited multi-worker execution evident from logs; this final child launches no agents. Dispatch total uninstrumented; overlapping writers were a process defect. |
| `superpowers:test-driven-development` | Positive/negative generated-config builds exist, not a substitute for physical session lifecycle tests. No claim of runtime TDD. |
| `superpowers:requesting-code-review` | Inherited repeated verification/review reports; final worker independently compares criteria rather than requesting another fanout. |
| `superpowers:finishing-a-development-branch` | Autonomous commit/push/PR skipped; orchestrator owns VCS. |
| `openspec-linear-sync` | Read skill, lifecycle and literal UPSERT mapping; archive then update existing canonical document then Done, with explicit workspace gate. Results in final report. |

### Deliberately Skipped Skills

- **Writing a plan after the fact:** skipped because it would fabricate advance planning. Prevention: decide a tasks-as-plan exception at inception and fill `verify.md` §7 regardless; formal missing dependency remains recorded, as in the prior house retrospective.
- **Git worktrees/autonomous branch finishing:** skipped under the jj shared-join/no-writing-VCS constraint. Prevention: schema graph should sanction jj isolation/routing explicitly; repeating the exception does not make concurrently writing the same artifact safe.
- **Runtime TDD:** no safe disposable real GDM/systemd environment was available for leader-death failure injection, and pyrite cannot be used without physical-recovery authorization. Prevention: upstream CAM-66 test work belongs in a disposable environment. Mock success and builds are not an end-to-end repair claim.
- **Repo-wide lint/format:** deliberately skipped because other agents own other paths; use scoped artifact and structural checks. No implementation source changed in this final pass.

## 5. Surprises

- **A requirement was amended after a counterexample, legitimately.** Weakening a requirement to match a defect we could fix would be bar-lowering. This one promised upstream niri session-lifecycle behavior no configuration of ours delivers: niri v26.04 waits for its service then cleans up, whereas GNOME 50.1 has an independent FIFO EOF/HUP leader-death bridge ([niri exact source](https://github.com/niri-wm/niri/blob/8ed0da44d974c32c6877d2f4630c314da0717ecb/resources/niri-session#L46-L53); [GNOME 50.1](https://github.com/GNOME/gnome-session/blob/50.1/gnome-session/leader-systemd.c#L246-L277)). The owner narrowed unconditional reachability and recovery WHEN only for display-manager restart while niri is live; retained GNOME registration/selectability/default-for-no-history and unchanged recovery THEN/AND outside the exception. **CAM-66 remains excluded and unrepaired**, with the incident and historical FAIL intact.
- **A fix was written and deliberately not carried.** The `niri-login-session` monitor, in C using libsystemd `sd-login`, was sound in approach but disproportionate to adding a second session, unverified end-to-end, and upstream work rather than an indefinite machine-module daemon. `logs/niri-session-strand-defect.md` preserves the investigation/prototype; removal and native build are in `logs/niri-slice-a-limitation-record.md`. No removed monitor is represented as deployed or as satisfying CAM-66.
- **Lock node names are first-come, not ownership.** `.nodes.root.inputs.nixpkgs` resolves to **`nixpkgs_9` (`85f6261`)**. The node merely named `nixpkgs` carries `044bfe75…` for another input. Two passes got this backwards and one “corrected” the record in the wrong direction (`logs/niri-slice-a-apply-phase1b.md:193–220`; `logs/niri-slice-a-ledger.md:18`; correction `logs/niri-slice-a-verify-final.md:95–97`). Ask **which lock node an input resolves to**, never which revision is “the nixpkgs.” Fresh execution reconfirms the edge (`logs/niri-final-primary-sources-20260909-232259.log:1–2`).
- **An `--impure` getFlake invocation produced a different toplevel than the pure flake reference.** Actual divergent successful outputs are in `logs/niri-ledger-pure-impure-20260909-143548.log:9,17,25`. The operator reports this was localised to an unrelated impurity-sensitive **`hm_nviminit.lua`** derivation: deployment is pure and the impure closure was an evidence-gathering artifact. That localisation and deployment-mode statement are relayed operator evidence; this final worker did not recover a complete closure-diff trace or rerun evaluation to substantiate them independently. Do not relabel the impure closure as what was deployed.
- **Desktop metadata is still not fully explained.** `Desktop=` is empty in logind while both `XDG_CURRENT_DESKTOP` and `XDG_SESSION_DESKTOP` are niri in the compositor environment and its entry declares `DesktopNames=niri`. GDM/PAM source distinguishes those paths but this host's complete propagation ordering remains unresolved, not guessed (`verify.md` §§9.11–9.12).

## 6. Promote candidates → long-term learning

- [ ] [high] **Prove adoption in the consumer, not correctness in the file.** → project guidance. Use live D-Bus for logind, actual session registry/greeter for GDM, mapped file-db for dconf daemons, and explicit permission/error handling for privileged state. Runtime identity and observation provenance belong beside every claim.
- [ ] [high] **Treat post-deploy ordering as a testable operational interface.** → deployment skill. Write preconditions for each restart; test fallback task 8.1 before relying on it. “Run over SSH” is not a lifecycle precondition.
- [ ] [high] **Single writer per artifact in a shared working copy.** → orchestrator workflow. Non-overlapping tasks are not necessarily non-overlapping files; join terminal results before successor edits.
- [ ] [med] **Separate malformed predicate repair from method substitution.** → verification skill. Record the old predicate, actual requirement, unchanged method, and separately any operator-approved substitution/declination.
- [ ] [med] **Resolve input edges before citing pins; match evaluation purity to deployment.** → evidence guidance. Store the input-to-node edge and mode with every closure identity; divergent closures are not interchangeable.
- [ ] [med] **V-interface / architecture-decision:** introduce named interface properties for registry/history, idle/power-control and validator identity, or formally decide this corpus's alternative discharge convention. The four delta requirements remain formally undischarged; runtime PASS does not manufacture S (`verify.md` §8b).
- [ ] [low] **V-vocabulary:** next sole designation-table owner should ground world/shared terms and move machine-side lifecycle/configuration predicates to interface stratum (`verify.md` §8a/8c). No clean lint without a real table read, and no §8 finding called validation.

### Deferred work, follow-ups, and non-goals

These are explicit boundaries, not dropped acceptance failures or promises of completion in this slice.

- **CAM-66 — session strand, upstream.** Report the exact v26.04 leader-death failure and GNOME comparison, preserve unverified prototype, then investigate in a disposable real GDM/systemd environment. Upstream submission is not yet grounded; task 9.3 stays unchecked. The live-niri restart exception is not repaired; deliberate lingering and `moshi-hook` policy remain.
- **CAM-59 — resume failure.** Historical 8 failures / 38 cycles; no new suspend was authorized or executed by the final worker. 8.6 is **declined**, not merely awaiting a test, and slice A is harm reduction, not a resume fix.
- **CAM-60 — unattended boot.** Remote wake/stage-1 unlock limitations remain; this session change does not create unattended recovery.
- **CAM-61 — Bluetooth and `wlp2s0`.** Bluetooth UART bring-up race and Wi-Fi/PCI-subtree loss on warm reboot are untouched. Do not generalize cold-cycle success into warm-reboot safety (prior CAM-62 retrospective §6).
- **CAM-64 — OpenSpec MODIFIED content loss.** Whole-requirement replacement can discard other deltas' content. This delta touches only graphical-desktop-session, **not world-assumptions**; the command-level enumeration and world hash are in `logs/niri-final-readiness-cli-20260909-232232.log`. This archive does not resolve the other change's table hazard.
- **Slice B:** `xwayland-satellite` absent (X11 applications unavailable); `xcursor-theme "default"` warning; GNOME `GlobalShortcutsProvider` `InvalidArgs` warning; portal **functional transactions untested**, despite installed/started backends. Evidence/boundaries: `tasks.md` 8.8, `verify.md` §9.3 and design OQ1/OQ2. Also slice B: **8.2 no-history half**, tested safely with a disposable user, and the **empty Desktop= observation**. None is silently guessed or discharged here.
- **Coverage and corpus:** evaluation-only idle windows remain labelled; same-program include check is vacuous because no include is used. V-interface/V-vocabulary and prior CAM-62 formal-discharge/blank-and-lock coverage remain discoverable in the regenerated satisfaction projection.

Archive operations, exact modified/moved files, projection counts and Linear receipts are in `logs/niri-slice-a-archive-final.md`; publication/merge and deployed source commit identity are not inferred from archiving.
