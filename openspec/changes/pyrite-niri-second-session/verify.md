# Verification Report

**Change**: `pyrite-niri-second-session` (CAM-63)
**Verified at**: 2026-09-09; physical-test/evaluation/declination verdict 2026-09-10 UTC (§9.9); subsequent documentation-only narrow amendment and independent verdict (§9.10).
**Verifier**: inherited runtime/research workers, followed by amendment worker; schema `superpowers-bridge-wrspm`, numbered manual fallback (skill tool unavailable in the original pass).

**Final verdict: PASS WITH WARNINGS against the explicitly amended requirement — not fully verified or archive-ready. 32 checked / 6 unchecked.** The amendment was made **after** the CAM-66 counterexample: it replaces unconditional reachability with GNOME registered/selectable at the greeter and default for users with no recorded choice, and explicitly excludes restarting display-manager while niri is live. Only recovery WHEN is narrowed; THEN/AND remain standing outside that exception. This corrects a promise of unavailable upstream lifecycle behavior — niri v26.04 lacks GNOME 50.1's leader-death bridge, which our configuration cannot supply — not an available configuration fix deliberately omitted. **CAM-66 remains unrepaired and tracked.** Independent criterion/evidence comparison is §9.10, not an assumption that amendment means PASS. **8.3/8.4/8.5 discharged by evaluation, not observation; 8.6 declined under CAM-59; 8.7 physically discharged in both desktops with same-boot controls; whole-boot suspend totals 1/1, not zero. Corrected 4.2 remains open for an actual in-niri runtime observation, not a deploy. Task 8.1 was the test that would have caught the session-strand defect; the checklist's deploy → restart display-manager sequence itself caused lockout from inside live niri.** The pre-amendment FAIL remains correct historical evidence, not erased by this verdict.

Evidence attribution: **[inherited execution]** means the predecessor/ledger actually ran the cited command; **[verified here]** means this worker read the host or exact source; **[operator]** means physical observation supplied by the operator. Those are not interchangeable. No deployment, restart, reload, suspend, button test, source edit, writing git/jj command or `just lint` was performed here. First action was `pwd` → `/Users/crs58/projects/vanixiets`.

**GNOME power-button amendment:** the no-source-edit statement above describes the original runtime verification pass. The follow-up edits only pyrite's dconf/comment and this change's tasks/design/delta/verification artifacts, evaluates and builds the fix, and leaves the verdict unchanged. New evidence is labelled **[amendment execution/source]** in §9.6; no deploy, restart, reload, suspend or physical press was performed by that worker.

**Limitation disposition follow-up (2026-09-10 UTC):** this pass removes only the monitor block from pyrite's module and deletes the change-local harness, updates the change artifacts and preserves the prototype only in authorized upstream-report logs. Build/eval/source/scope results are in `logs/niri-slice-a-limitation-record.md`; inherited journal is explicitly distinguished from new execution. No deployment, restart, reload, service stop, suspend or physical test was performed. The operator's reasons are recorded verbatim in substance in `known-limitations.md`: disproportionate to offering a second session, indefinite C-daemon maintenance in a machine module, and never end-to-end-verified machinery in a physically recoverable login path.

**Undischarged-requirement follow-up:** documentation-only implementation of the spec owner's task-9.4 decision; no Nix source or delta spec edits, no rebuild or runtime operations. The predecessor's removal/build/eval evidence above is inherited, not rerun. New strict validation, task-count and scoped byte/diff checks: `logs/niri-slice-a-undischarged-record.md`. This pass qualifies delivery claims in proposal/design/brainstorm without changing the requirement's intent or text.

**CAM-66 follow-up:** **F-niri-upstream = [CAM-66 — Correct password returns to GDM: niri survives a display-manager restart](https://linear.app/cameronraysmith/issue/CAM-66/correct-password-returns-to-gdm-niri-survives-a-display-manager)**. This documentation-only pass re-derived the live GNOME session and deployed database (§9.8), closes only 8.1, and corrects the mistaken “power-button fix undeployed” premise. No Nix source edits or host state-changing operations. **28 checked / 10 unchecked; FAIL remains.** New evidence: `logs/niri-slice-a-cam66-link-final.md`.

**Final verdict follow-up:** documentation-only, read-only SSH/source research, no Nix changes, deployment, restart, reload or suspend. The operator's physical tests are independently journal-grounded in §9.9; the operator's evaluation substitution and deliberate-suspend declination are recorded explicitly. Prior temporal claims below are historical where superseded by §9.9. Toplevel rebuild skipped. Findings/command logs: `logs/niri-slice-a-final-verdict.md` and `logs/niri-final-verdict-*-20260910.log`.

**Current amendment pass / attribution boundary:** all §9.1–§9.9 runtime/source execution and physical tests below are inherited, even where their original authors label them `[verified here]` or “fresh.” This worker re-read every current change artifact and both predecessor reports before editing, read the preserved pinned primary-source transcripts, applied the exact draft, corrected 4.2 without checking it, and independently compared the amended criteria to that accumulated evidence (§9.10). Only local structural validation and scoped checks are new execution. No host query or mutation, Nix edit or rebuild. Historical “unchanged requirement / FAIL” statements below describe their pre-amendment pass; current dispositions are §9.10 and Overall Decision.

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items report `"valid": true`.

Actual summary [verified here], `logs/niri-final-prechecks-20260909.log`:

```json
"totals": { "items": 27, "passed": 27, "failed": 0 }
"byType": {
  "change": { "items": 12, "passed": 12, "failed": 0 },
  "spec": { "items": 15, "passed": 15, "failed": 0 }
}
```

Change-local command/output after the amendment edits (`logs/niri-amend-applied-strict.log`; predecessor's pre-amendment run remains `logs/niri-final-verdict-strict-20260910.log`):

```console
$ openspec validate pyrite-niri-second-session --strict
Change 'pyrite-niri-second-session' is valid
```

Exit 0. No failed structural item. **This checks Markdown structure and delta well-formedness only**, not runtime behavior, vocabulary grounding, alphabet discipline or entailment (`openspec/config.yaml`, `rules.verify`). §8 is agent-executed and non-blocking, never validation.

## 2. Task Completion (`tasks.md`)

- [ ] All tasks complete — **32 checked / 6 unchecked**, 38 total. Checked **8.3, 8.4, 8.5** are evaluation discharges under explicit operator decision, **not untouched wall-clock observations**; **8.7** is physical testing plus journal/session corroboration. Unchecked: **2.3** vacuous by its explicit rule; **8.6 declined**; **4.2, 6.6, 8.2** remaining prescribed runtime coverage; **9.3** upstream submission. Decision 9.4 now applies the narrow amendment; neither it nor recovered usability 8.1 repairs the excluded CAM-66 case. No check is relabelled as re-executed.

Five existing tasks were newly discharged: **4.1, 4.4, 6.3, 6.4, 8.8**; new **6.5** records the already-performed manual logind reload plus live verification. Prior 17 checked tasks retain the ledger's actual evaluation/build evidence, not claimed re-execution here.

| Newly discharged | Evidence/method |
|---|---|
| 4.1 | Evaluated explicit idle policy plus deployed live `IdleAction=ignore` [inherited execution], runtime log lines 107–123. |
| 4.4 | Evaluated/rendered policy, delivered config/drop-in inspection, live short/long-press `ignore` [inherited execution], same lines; not a physical press. |
| 6.3 | Successful remote `clan-boot` and `clan-switch` units and finished switch at 19:00:04 [verified here], `logs/niri-final-package-20260909.log`, activation-unit section; subsequent SSH and matching current generation [inherited execution]. Local update-command exit transcript was not recovered; journal success is the explicitly recorded equivalent. |
| 6.4 | GDM restart at 19:03:10 follows activation at 19:00:04 [verified here], `logs/niri-final-portal-context-20260909.log:959,994-1011`; inherited ActiveEnterTimestamp agrees. |
| 6.5 (new) | Sudo reload and `Config file reloaded.` at 19:02:28 [verified here], same log lines 983–987; live D-Bus values [inherited execution]. |
| 8.8 | niri actually failed to spawn satellite and disabled integration, followed by unset-DISPLAY diagnostic [inherited execution], runtime log lines 226–227. Task now explicitly allows this direct diagnostic instead of pretending interactive shell commands ran. |
| 8.1 (CAM-66 pass) | Inherited niri cog/terminal/quit observation plus operator-reported recovered GNOME login, corroborated read-only by active seat0 uid-1000 session 176, gdm-password/Wayland/user/tty2, running GNOME Shell 50.2, active GNOME manager and inactive niri (§9.8). Not a replay of the restart defect or its repair. |
| 8.3/8.4/8.5 (final pass) | **Evaluation, not observation**, by explicit operator decision. Exact niri/gsd source, delivered KDL, dependencies/autostarts, both delivered dconf profiles and live logind policy; no 35-minute untouched intervals (§9.9). |
| 8.7 (final pass) | Operator physical presses; re-derived GNOME 176/niri 209 journal attribution; 1 GNOME and 2 niri presses, each window 0 suspend/PM/shutdown; same-boot positive and negative controls (§9.9). Deliberate wake subcheck declined with 8.6. |

| Incomplete task | Reason | Blocks complete acceptance/archive now? |
|---|---|---|
| 2.3 | `includes=[]`; explicitly vacuously satisfied, not exercised. Task itself forbids checking an empty-list branch. | No; no artificial include needed. |
| 4.2 | Corrected to **no idle consumer**, not no autostart. Delivered pinned unit `Wants=xdg-desktop-autostart.target`; old `xdg-autostart*` misses it and `app-…@autostart` services. Complete in-niri process/service snapshot not recovered (§§9.9–9.10). | Retained runtime coverage gap per D7: **seen, not deduced**. Needs only an attributed in-niri observation, not a deploy; configuration/dependency evidence does not close it. |
| 6.6 (amendment) | Fix deployed and post-deploy daemon loaded its file-db. Physical tests now pass, but prescribed in-session desktop/gsettings/inhibitor transcript remains missing. | Retained collection gap, not a need to redeploy/restart or deny the physical result. |
| 8.2 | Session=niri persisted; no no-history GNOME login, next-login preselection/relogin, or post-selection restart comparison. | Yes for full scenario verification; persistence itself is no longer missing. |
| 8.6 | **DECLINED by operator**: CAM-59 historical 8/38 failure cohort, physical-power-cycle risk; re-proving the defect buys this change nothing. | Explicit deliberate-suspend/guard/wake coverage limitation, not a passed test or a future scheduling request. |
| 9.3 | Upstream niri submission not established; prototype/research preserved in logs. **F-niri-upstream = CAM-66** is the real Linear follow-up (operator metadata, not independently API-queried). | Follow-up for the explicitly excluded, unrepaired U-niri-fallback case, not a local-daemon shipping requirement; reporting alone cannot repair it. |

## 3. Delta Spec Sync State

CLI-resolved delta (`openspec status --change pyrite-niri-second-session --json`, in prechecks log):
`openspec/changes/pyrite-niri-second-session/specs/graphical-desktop-session/spec.md`.

| Capability | Sync status | Notes |
|---|---|---|
| graphical-desktop-session | Pending sync | Main spec still excludes niri and says home-manager has no desktop toggle. Delta modifies that requirement and adds the choice/persistence, independent inactivity/power-control, and same-program settings-check requirements. Expected unarchived state; no main-spec edit here. |

## 4. Design / Specs Coherence Spot Check

| Decision | Requirement correspondence (delta spec lines) | Result |
|---|---|---|
| D1/D4, additive niri and explicit null | 39–67, amended choice/default/history and recovery | Registry/history evidence and panel usability support the retained semantics (§§9.1,9.8–9.10). The proven live-niri display-manager-restart failure is now explicitly excluded, still unrepaired (CAM-66), not a failing test inside the amended domain. 8.2 remains an observation gap. |
| D3/D6, exact validator and immutable includes | 103–124 | Same niri store path plus positive/negative builds establish validation; includes are vacuous. |
| D7, desktop-independent idle protection | 68–85 | **Discharged by evaluation**, per operator decision for 8.3/8.4: no configured idle consumer and live logind ignore. No untouched AC/battery observation; 4.2's process snapshot still missing (§9.9). |
| D9, paired policy plus GNOME amendment | 72,87–96 | Protected ordinary presses in both desktops pass by operator testing and journal controls (8.7). 6.6's prescribed transcript remains missing; deliberate suspend/wake **declined** (8.6). |
| D8, preserve existing GNOME/GDM inactivity configuration | 81–85 | Baseline comparison plus both delivered file-db readbacks and exact gsd guards support **evaluation discharge** (8.5), not repeated behavioral windows. |
| OQ2, portal sufficiency | Not a separate behavioral acceptance requirement | Installed/started backends verified, functional transactions not exercised; qualification and B-portal follow-up added. |

Drift warnings: design's shorthand “still the default” needs the never-chosen qualification, now explicit; its migration prose does not mean no user state exists. The pin at former `design.md:121` and `tasks.md:7` was wrong and is corrected (§9.5). The narrow CAM-66 requirement amendment is explicit and **post-counterexample**, not a claim the original smoke established unconditional fallback (§9.10). Bare compositor, no shell/locker, and no X11 support remain the declared slice boundary, not newly supplied features.

## 5. Implementation Signal

- [ ] Whole worktree clean — not asserted or surveyed; active shared jj diamond contains other agents' work and is outside this verification scope.
- [ ] All related commits pushed — not independently established; orchestrator owns routing.

Schema prechecks [verified here] returned **56** commits and **17** previously checked tasks before edits (`logs/niri-final-prechecks-20260909.log`). This is only an implementation-presence signal, not ownership/push proof. Change-scoped prior committed range `a34162bf401e1b8db4d0d98fcdc7a414c28d9690..50b2c0dd152e7279a323495a48bcd662daccd1bf` and immutable evaluated wip `28ecab07…` are grounded by `logs/niri-slice-a-ledger.md:15-16,104-115`. This pass's three change-artifact writes are intentionally unrouted. Other agents' edits were not touched or reported.

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

```console
$ ls docs/superpowers/specs/*.md 2>/dev/null
(no output)
```

- [x] No files found. CLI resolves brainstorm to this change's `brainstorm.md` (prechecks log). No leak action.

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` is absent; the schema graph reports that unmet dependency (`logs/niri-final-schema-20260909.log`). Tasks carry the live-check role. No `[~]` plan rows exist, but omitting the actual coverage gaps would mislead.

| Manual check | Closest executed evidence | Equivalent? / follow-up |
|---|---|---|
| 4.2 idle consumers | Delivered unit/autostart evaluation and journal startup sequence; current post-exit process snapshot | No equivalence to an in-niri process snapshot; retained open. Benign autostarts are not idle consumers. |
| 8.1 both interactive desktops | Inherited niri operator smoke plus recovered GNOME operator login and live session/shell/user-unit readback (§9.8) | Discharged by actual runtime evidence, not automated-test equivalence. Does not repair U-niri-fallback. |
| 8.2 never-chosen/relogin/restart memory | Pinned GDM source, persisted Session=niri, empty evaluated preStart | No; observe the remaining sequence without unauthorized state clearing. |
| 8.3/8.4 niri AC/battery idle | Exact-tag absence of idle configuration, delivered no-consumer configuration, live logind ignore | **Evaluation discharge explicitly chosen by operator**, replacing the former method/refusal. Not a 35-minute untouched AC/battery observation. |
| 8.5 GNOME/greeter regression | Both delivered file-db profiles, effective user readback, exact gsd idle-watch guards | **Evaluation discharge explicitly chosen by operator**, not repeated regression windows. |
| 8.6 deliberate suspend/wake | Existing CAM-59, no blanket block (4.3) | **Declined by operator** due physical recovery risk; no behavioral equivalence or future test request. |
| 8.7 ordinary key in GNOME and niri | Three actual presses, session attribution, 0 suspend/PM/shutdown per window; positive pre-fix and negative post-fix controls | Physical test discharged, **not** automated equivalence; operator owns panel usability observation. Wake declined with 8.6. |

Carry these into retrospective **Misses**, with these task IDs as follow-up references; no retrospective exists yet and none is claimed written. §7 recording itself is non-blocking. Complete acceptance/archive readiness remains unclaimed because prescribed observations are incomplete; the current qualified verdict distinguishes those gaps from demonstrated failures against the amended criteria (§9.10).

## 8. Designation Lint and Discharge Coherence (agent-executed; warning, non-blocking)

This section is **not validation**. Main `openspec/specs/world-assumptions/spec.md` exists and its designation table was read; this is not a clean/vacuous lint. Proposal tags the sole changed capability `behavioral`; no world/interface delta exists.

### 8a. Designation lint

Requirement-statement extraction (amended delta lines 5–7,41–44,71–75,106–107): inherited grounded compound terms include `host`/`machine` (fleet sense), `panel`, `login screen`, `desktop session` (only the logged-in state), `inactivity`, `suspended state`, `wake source`, `operator`, and `power source` (mains/battery). The table does not designate the following remaining subject matter; related scenario vocabulary is also recorded rather than used to claim a clean result. The amendment adds machine vocabulary recorded explicitly below; no fresh clean lint is claimed.

| Unresolved noun/term | Disposition |
|---|---|
| desktop (including established/newly offered/default desktop) | World/shared selectable thing, not the designated desktop-session state; design OQ6 accepted open finding. |
| settings | World/shared contents, not the designated settings panel; OQ6. |
| person | Not synonymous with operator; vocabulary follow-up. |
| choice / recorded choice | User selection and persisted selection need distinct grounding; vocabulary follow-up. |
| login / sign-in | Event, not the designated login-screen state; vocabulary follow-up. |
| session (graphical use) | Existing bare `session` rows are autonomous/Pi-persisted; explicitly use/designate desktop-session sense. |
| physical control / press / release | Related to wake source but event/control vocabulary is not separately designated. |
| network | Shared reachability phenomenon; existing table mentions it but has no row. |
| program | Machine phenomenon in same-program requirement, not a designated world term; review stratum/observable contract. |
| copy / version | Program identity/version, machine phenomenon; same review. |
| file / check / configuration | In generated-settings requirement these are machine artifacts/operations, not grounded by generic target/path or human activation rows. |
| host module / options / system-level / home-manager configuration | Machine phenomena retained by MODIFIED stock-GNOME requirement; move to interface in a separately scoped corpus repair. |
| GNOME / GDM / niri / nixpkgs / home-manager | Named machine software, not designation rows; same retained alphabet issue. |
| Wayland shell assembly / bar / launcher / notification daemon / lock screen / wallpaper / clipboard manager | Undesignated machine components in the modified requirement's scope sentence. |
| shell / portals / polkit agent / keyring / dconf / settings daemon / applet / control center | Further machine-component nouns in retained scenarios, not grounded world vocabulary. |
| boot / LUKS container / ZFS root / stage-1 prompt / initrd / token / PIN / passphrase / credential / unlock | Retained boot/unlock scenario vocabulary is not grounded by this table; the forge-credential row is not a general credential designation. Separate corpus review, not repaired here. |
| greeter / registered / display-manager / restart / niri.service / inactive / leader-death bridge | Amendment names machine-side registration, lifecycle and service-state predicates. `login screen` does not by itself ground these operations/artifacts; retain V-vocabulary/V-interface, not a clean behavioral-alphabet claim. |

The known OQ6 gaps are not the only lexer findings. Related action nouns such as selection/rejection/failure/recovery inherit no automatic designation from prose mentioning them. Follow-up **V-vocabulary**: next sole owner of the designation table should enumerate/add the world/shared rows and relocate machine predicates; OQ6's separately proposed sync-time superset check has no claimed issue ID. No table edits here.

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| MODIFIED local GNOME under GDM | No named interface requirement; implementation options and boot ordering embedded directly in behavioral text | No explicit named world discharger; retained D1/D11 references are design, not W | **Undischarged (no named S)**; follow-up V-interface. Runtime/policy evidence does not supply a named S. |
| ADDED two desktops/default/history | No named S; GDM registry/history mechanism exists only in design/tasks | No named W | **Undischarged (no named S), V-interface.** Historical unconditional U-niri-fallback failed; the current requirement explicitly excludes live-niri display-manager restart, tracked as unrepaired **CAM-66 / F-niri-upstream**, open 9.3. Applied decision 9.4 and independent amended behavioral verdict are §9.10. Recovered GNOME usability closes 8.1, not the defect or separate 8.2 history/relogin gaps. |
| ADDED independent inactivity/power policy | No named S; niri/logind mechanisms described in design/tasks | Explicit A13, still applicable; no new resume experiment | **Undischarged (no named S)**; V-interface. Separately: idle tasks discharged by evaluation, ordinary-key test physically discharged, deliberate suspend/wake declined (§9.9). |
| ADDED same-program settings check | No named S; actual config derivation/binary equality and negative build are evidence, not a named interface spec | No named W | **Undischarged (no named S)**; V-interface. Executed build layer passes; includes vacuous. |

**V-interface follow-up:** retrospective §6 Promote → `architecture-decision`: explicitly decide whether to introduce named machine-interface properties for registry/history, idle/power control, and build-validator identity, or formally document this corpus's alternative discharge convention. Never omit these rows from archive's regenerated satisfaction projection; `openspec/config.yaml` archive guidance requires follow-up references for undischarged requirements.

### 8c. Alphabet check

MODIFIED stock-GNOME text retains option paths, commands, daemons and boot internals despite its behavioral tag (delta lines 5–35). The ADDED settings-check requirement also uses machine-side program/copy/version/file identity; treating those as world vocabulary without designation is not grounded. Added choice/idle text has §8a gaps, and the explicit CAM-66 amendment adds registration/greeter/display-manager/restart/niri.service predicates that need machine-interface treatment in the corpus follow-up. No interface delta exists, so the unobservable-world-state restriction has no interface subject. These remain **agent-executed warn-and-record findings, non-blocking and never validation**, not a basis for manufacturing FAIL or a clean lint.

## 9. Runtime Findings and Corrections

### 9.1 AccountsService persisted; GNOME is fallback, not cameron's next default

[inherited execution] `logs/niri-verify-discrepancies-20260909.log:1-13`:

```text
Modify: 2026-09-09 19:04:57.497589650 +0000
 Birth: 2026-09-09 19:04:57.497589650 +0000
[User]
Session=niri
Icon=/home/cameron/.face
SystemAccount=false
```

Live AccountsService `Session` is `s "niri"` (runtime log 258–259; `SessionType` empty). **The earlier “not persisted” report was a false negative:** the orchestrator ran unprivileged `cat ... 2>/dev/null || echo "(no file yet)"`, conflating unreadable with missing. This is the orchestrator's acknowledged evidence-gathering error, not a change defect. `logs/pyrite-niri-session-evidence-20260909-150844.log`'s “still absent” is superseded; neither historical log is edited.

[verified here] Exact installed GDM **50.1** source, not default branch (package selection and patch list in `logs/niri-final-portal-runtime-20260909.log`; fetched files in `logs/niri-final-gdm-source-20260909.log`):

- [`gdm-session-settings.c:285–309`](https://github.com/GNOME/gdm/blob/50.1/daemon/gdm-session-settings.c#L285-L309) reads `act_user_get_session`; [`368–390`](https://github.com/GNOME/gdm/blob/50.1/daemon/gdm-session-settings.c#L368-L390) saves with `act_user_set_session` when loaded and a session name exists.
- [`gdm-session-worker.c:2535–2549`](https://github.com/GNOME/gdm/blob/50.1/daemon/gdm-session-worker.c#L2535-L2549) saves account details in the worker's session state transition. This matches file birth at login, not a requirement that logout complete first.
- [`gdm-session.c:1101–1126`](https://github.com/GNOME/gdm/blob/50.1/daemon/gdm-session.c#L1101-L1126) checks saved entry validity and updates greeter default; [`687–694`](https://github.com/GNOME/gdm/blob/50.1/daemon/gdm-session.c#L687-L694) returns saved session before fallback; [`621–625`](https://github.com/GNOME/gdm/blob/50.1/daemon/gdm-session.c#L621-L625) tries GNOME only in fallback. [`2735–2743`](https://github.com/GNOME/gdm/blob/50.1/daemon/gdm-session.c#L2735-L2743) prefers explicit selection, otherwise that default.

**Plain operational consequence: cameron's remembered session is now niri. The next login defaults to niri unless the cog is used to pick GNOME. GNOME remains the default only for users with no recorded choice.** The cog selects the designated fallback; it does **not** guarantee that GNOME can start after the live-niri display-manager-restart trigger (§9.7, **U-niri-fallback**). This is source-grounded expected next-login selection behavior, not an observed second login or unconditional usable fallback.

Does that satisfy acceptance? **The memory/default semantics do at the evaluated/source layer:** the delta limits its no-choice scenario to a person who has *never chosen* and separately requires the chosen desktop at later logins. The historical cameron niri default was expected, not itself a FAIL. **The former unconditional fallback criterion was UNSATISFIED:** working GNOME without repair/preparation failed after the live-niri display-manager restart (§9.7). The current amendment explicitly excludes that state (§9.10); recovered GNOME login closes 8.1 (§9.8), not a lifecycle repair. The September 9 saved-choice/next-login statements above are historical, not a new read of AccountsService after the subsequent GNOME choice. Task 8.2's prescribed observed sequence remains open.

### 9.2 Logind did not reload on switch

[operator/prior execution] Correct `logind.conf` was written while running logind still returned `HandlePowerKey=poweroff`, until manual `systemctl reload systemd-logind`. This worker did not witness the before-reload D-Bus call.

[verified here] Successful switch completed **19:00:04**; sudo ran reload at **19:02:28**, immediately followed by `Config file reloaded.` (`logs/niri-final-portal-context-20260909.log:959,983-987`). [inherited execution] post-reload D-Bus short press, long press and idle action all return `s "ignore"`, unchanged lid policy, and `systemd-analyze cat-config` shows the correct delivered file with no additional override (runtime log 107–123).

**Deploying this change does not fully take effect without a logind reload or a reboot.** File-only inspection would have passed falsely. New **task 6.5** makes the reload/runtime gate explicit, analogous to actual display-manager task **6.4** (the brief's “2.3” is the include task in this ledger). No source fix, reboot or reload was performed here. Pinned nixpkgs [`logind.nix:67–73`](https://github.com/NixOS/nixpkgs/blob/85f62611fa3f3eacbcfe3bc7a6d6518b443ca442/nixos/modules/system/boot/systemd/logind.nix#L67-L73) sets reload-if-changed but leaves the configuration-file trigger commented; the marker alone is no proof a changed file caused a reload.

### 9.3 Portal determination: running backends, teardown exits; transactions unproven

The orchestrator's blanket “no failed systemd units” used only `systemctl --failed`, not `--user`. **Acknowledged scoping/evidence-gathering error**, not a source defect. Predecessor observed zero failed system units **and two failed user units** (runtime log 239–251).

[verified here] Delivered units and exact journal in `logs/niri-final-portal-runtime-20260909.log:1-66`:

```text
Sep 09 19:04:59 pyrite systemd[1133]: Started Portal service (GNOME implementation).
Sep 09 19:04:59 pyrite systemd[1133]: Started Portal service (GTK/GNOME implementation).
Sep 09 19:04:59 pyrite systemd[1133]: Started Portal service.
Sep 09 19:07:31 pyrite xdg-desktop-portal-gnome[112853]: Lost connection to Wayland compositor.
Sep 09 19:07:31 pyrite xdg-desktop-portal-gtk[112869]: Error reading events from display: Broken pipe
Sep 09 19:07:31 pyrite systemd[1133]: xdg-desktop-portal-gtk.service: Main process exited, code=exited, status=1/FAILURE
Sep 09 19:07:31 pyrite systemd[1133]: xdg-desktop-portal-gnome.service: Main process exited, code=exited, status=1/FAILURE
```

Both backend units and frontend are **Type=dbus** with their expected BusNames. “Started” therefore means the bus name was acquired, not merely an attempted exec ([systemd v261.1 `systemd.service.xml:215–227`](https://github.com/systemd/systemd/blob/v261.1/man/systemd.service.xml#L215-L227)). They did not fail during the 19:04:59–19:07:31 session interval. They exited on losing the compositor exactly when niri quit. The user manager remained to retain failed status; this is **teardown failure-state noise, not a backend that never started**.

The source/delivery chain is real, not “xdg.portal enabled” alone:

1. Effective nixpkgs **85f6261** [`niri.nix:28–31,62–86`](https://github.com/NixOS/nixpkgs/blob/85f62611fa3f3eacbcfe3bc7a6d6518b443ca442/nixos/modules/programs/wayland/niri.nix#L28-L86) installs the GNOME portal, imports GTK wiring, uses GNOME/GTK preference and makes Nautilus D-Bus-activatable for FileChooser. Delivered `/etc/xdg/xdg-desktop-portal/niri-portals.conf` matches (portal-runtime log 53–57).
2. Installed backend is **xdg-desktop-portal-gnome 50.0**, GTK **1.15.3**, frontend **1.22.1** (delivered units). GNOME 50.0 [`filechooser.c:365–397`](https://github.com/GNOME/xdg-desktop-portal-gnome/blob/50.0/src/filechooser.c#L365-L397) exports FileChooser and delegates to `org.gnome.Nautilus`. Delivered service resolves to Nautilus **50.2.2**; actual bus config contains its service directory (`logs/niri-final-portal-context-20260909.log:1-7`; package log DBus section).
3. GNOME backend startup initializes FileChooser and ScreenCast after acquiring the bus ([50.0 main:110–178](https://github.com/GNOME/xdg-desktop-portal-gnome/blob/50.0/src/xdg-desktop-portal-gnome.c#L110-L178)). A failed compatible-display initialization would print `Non-compatible display server, exposing settings only.` ([304–310](https://github.com/GNOME/xdg-desktop-portal-gnome/blob/50.0/src/xdg-desktop-portal-gnome.c#L304-L310)); that diagnostic is absent from this backend's journal.
4. GNOME ScreenCast watches `org.gnome.Mutter.ScreenCast` ([50.0 `gnomescreencast.c:719–802`](https://github.com/GNOME/xdg-desktop-portal-gnome/blob/50.0/src/gnomescreencast.c#L719-L802)). niri **v26.04** implements/starts the corresponding D-Bus service ([`src/dbus/mod.rs:119–131`](https://github.com/niri-wm/niri/blob/v26.04/src/dbus/mod.rs#L119-L131)); pinned nixpkgs package defaults `withScreencastSupport=true` and enables `xdp-gnome-screencast` (`logs/niri-final-package-20260909.log`, package source). This explains why the GNOME backend is appropriate on niri; it is not inherently GNOME-Shell-only.

**Answer:** this nixpkgs niri session did get running, D-Bus-ready portal backends, with the source/delivered wiring needed for dialogs and screencast. **No successful FileChooser request or ScreenCast stream was observed.** Startup is not an end-to-end transaction test, and a post-session query could activate/change services rather than retrospectively test that session; none was attempted. Thus a claim “portals never worked” is unsupported, and so is an unconditional “file dialogs and screen sharing tested working.”

One separate, genuine startup warning is not hidden by the teardown determination:

```text
Sep 09 19:04:59 pyrite .gnome-control-[112862]: Failed to open service channel Wayland connection, portal dialogs may misbehave (GDBus.Error:org.freedesktop.DBus.Error.InvalidArgs: Invalid service client type).
```

Full journal places it after launching `org.gnome.Settings.GlobalShortcutsProvider`, not in either failed backend process (`logs/niri-final-portal-context-20260909.log:254-260`). niri v26.04 rejects service-client types other than `1` ([`mutter_service_channel.rs:14–21`](https://github.com/niri-wm/niri/blob/v26.04/src/dbus/mutter_service_channel.rs#L14-L21)). Actual dialog impact is **not established**. Record this bounded compatibility warning and the transaction-coverage limitation under **design.md B-portal**, slice B follow-up, not a slice-A task or invented claim that all portals are broken. No failed state was reset and no service was restarted.

### 9.4 Cursor and Xwayland: known slice-B limitations

[inherited execution] niri's actual messages, runtime log 226–229:

```text
WARN niri::cursor: error loading xcursor default@48: no default icon
WARN niri::utils::xwayland::satellite: error spawning xwayland-satellite at "xwayland-satellite", disabling integration: No such file or directory (os error 2)
```

Delivered config says `xcursor-theme "default"`. No theme installed is the operator-supplied premise; this worker did not audit all cursor search paths. The lookup failure itself is verified and cosmetic: **B-cursor**. Satellite absence is confirmed by the compositor, not merely an evaluated package list: X11-only applications unsupported, **B-xwayland**, accepted OQ1 limitation. Neither is added as a slice-A implementation task.

### 9.5 Pin correction and inherited runtime identity

Root lock follows **`nixpkgs_9 → 85f62611fa3f3eacbcfe3bc7a6d6518b443ca442`**, not the unrelated node `nixpkgs → 044bfe75…` (predecessor context log 1–47). Corrected former `design.md:121` and `tasks.md:7`; effective-pin logind lines were re-read in this pass (portal-context log 747–852). `logs/niri-slice-a-apply-phase1b.md:193-220`'s supersession claim and ledger line 18's supposed root/effective distinction are incorrect historical interpretations, not defects in the change. The logs remain unchanged and are explicitly superseded here.

Do not conflate prior outputs: immutable-wip builds produced pure `7gb7…` and impure `l4is…`; the **then-deployed September 9** generation was **najhrzgayg05kd8bzm5g7n8rj74b7f80**, corroborated by activation journal. **Current generation is pgww7gi7jxb3ibdbfa2mphb2azid0znx (generation 10)**, re-derived in §9.8, not a grounded source-commit mapping. Full derivation equality is not claimed. Delivered niri remains `/nix/store/y32xfvyx99qp91s2g3d2dr8wsx7k3gb0-niri-26.04/bin/niri`; historical KDL evidence remains runtime log 49–88.

[inherited execution] niri opened IPC `/run/user/1000/niri.wayland-1.112705.sock`, consumed **1.020s CPU over 2min 33.945s wall time, 189.7M peak**, and exited after confirmation. The socket is a historical opening, not claimed still open. Whole-boot suspend counters were **0 / 0**, not proof of 35-minute niri AC/battery windows (runtime log 210–237). [operator] cog selection, Important Hotkeys overlay, Ghostty bind/command and clean return to GDM establish a usable bare-compositor smoke test, not a complete desktop assembly.

### 9.6 Historical GNOME power-button amendment and deployment (physical results now in §9.9)

**[operator/supplied evidence, not independently replayed]** At 21:16:36 UTC, `suspend requested from client PID 124058 ('.gsd-media-keys') (unit user@1000.service)` was followed by `PM: suspend entry (deep)` while the operator was in GNOME. That press used the configuration without GNOME protection and tested nothing about our niri/logind design. The prior ordinary-press requirement explicitly covered only the newly offered desktop; this is a genuine amendment to include the established GNOME desktop session, not a retrospective assertion that the old clause already covered it.

**[inherited source, completed by amendment source]** gsd **50.1**, commit `ec681847221cf44e658363b9d8137b4cbae7b321`: [power schema:39–43](https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/blob/ec681847221cf44e658363b9d8137b4cbae7b321/data/org.gnome.settings-daemon.plugins.power.gschema.xml.in#L39-43) defaults to `'suspend'` and explicitly lists enum nick `'nothing'`. [Media-keys:2142](https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/blob/ec681847221cf44e658363b9d8137b4cbae7b321/plugins/media-keys/gsd-media-keys-manager.c#L2142) reads the enum; **:2174 dispatches**, while the `NOTHING` branch returns. [3430–3444](https://gitlab.gnome.org/GNOME/gnome-settings-daemon/-/blob/ec681847221cf44e658363b9d8137b4cbae7b321/plugins/media-keys/gsd-media-keys-manager.c#L3430-3444) requests the `handle-power-key` block inhibitor. [systemd v261.1 logind.conf:258–267](https://github.com/systemd/systemd/blob/v261.1/man/logind.conf.xml#L258-L267) says this makes `Handle*` settings irrelevant; GNOME dispatches its own suspend request. Full citations and patch audit: `logs/niri-slice-a-powerbutton-gnome-final.md`.

**[amendment execution]** Added only `power-button-action = "nothing"` and the concise inhibitor rationale in pyrite's module. Resolved evaluation (exit 0, `logs/niri-powerbutton-after-dconf-20260909-193100.log`) returns:

```json
[{"lockAll":false,"locks":[],"settings":{"org/gnome/desktop/session":{"idle-delay":"@u 1800"},"org/gnome/settings-daemon/plugins/power":{"power-button-action":"nothing","sleep-inactive-ac-timeout":"0","sleep-inactive-ac-type":"nothing","sleep-inactive-battery-timeout":"0","sleep-inactive-battery-type":"nothing"}}}]
```

Five power keys plus idle-delay; no locks declaration, empty resolved locks, idle delay unchanged. Full toplevel `nix build .#nixosConfigurations.pyrite.config.system.build.toplevel --no-link` succeeded (exit 0) at `/nix/store/akq1sxw1bisvqhsbz5j5ik245zpky2xk-nixos-system-pyrite-26.11.20260804.85f6261`; first attempt timed out at 120 seconds, retry completed (`logs/niri-powerbutton-toplevel-build-retry-20260909-193307.log`). That was a build, not activation by that worker. **The subsequent live generation 10 does deliver the fix** (§9.8); no equality to that build or source commit is inferred. Historical strict/scope evidence: `logs/niri-slice-a-powerbutton-gnome-final.md`.

**[amendment source; adoption now verified in §9.8]** Pinned nixpkgs [dconf.nix:96–105](https://github.com/NixOS/nixpkgs/blob/85f62611fa3f3eacbcfe3bc7a6d6518b443ca442/nixos/modules/programs/dconf.nix#L96-L105) writes a store-backed `file-db` after `user-db:user`. dconf **0.49.0** [engine:329](https://gitlab.gnome.org/GNOME/dconf/-/blob/0.49.0/engine/dconf-engine.c#L329) opens the profile; [file source:29–49](https://gitlab.gnome.org/GNOME/dconf/-/blob/0.49.0/engine/dconf-engine-source-file.c#L29-49) has no bus and reopens only if no values were loaded. For a future database replacement an existing daemon needs a fresh GNOME session, not deploy alone; any authorized display-manager restart is subject to the no-live-niri gate. **This deployment already has a fresh daemon with the new database mapped.** Task 6.6 stays open only for the prescribed remaining in-session gsettings/desktop/inhibitor observations; no new restart is needed to re-prove adoption. User overrides intentionally win; never reset them silently.

**Historical status at this amendment/readback pass:** 8.7 was then unverified in both desktops and idle windows remained open. **Evidence disposition supersedes it (§9.9): 8.7 physically discharged in both desktops; 8.3–8.5 discharged by evaluation, not observation; 8.6 declined.** 6.6's specified collection transcript remains missing, not a reason to deny the actual subsequent physical result or repeat a restart. CAM-66 independently justified the pre-amendment FAIL; current amended verdict is §9.10.

### 9.7 Login-breaking niri strand: the unexercised GNOME fallback was substantive

**[strand follow-up: read-only execution/source]** Exact host journal establishes a successful switch at **2026-09-10 00:12:03 UTC**, then `sudo ... systemctl restart display-manager` at **00:12:06**. GDM closed cameron's PAM session and logind removed **session 157**, but niri PID **126628** only logged `pausing session` and stayed running in the user manager. GNOME attempts at **00:12:31**, **00:12:47**, and **00:13:25** authenticated but aborted with `A graphical session is already running!`; PID **147637** dumped core. Niri finally received SIGTERM at **00:15:16** during the reported manual recovery. These historical operations were observed in the journal, **not issued by this follow-up worker**. Full timestamped evidence and sources: `logs/niri-session-strand-defect.md`.

**Task 8.1 (GNOME fallback login) is the test that would have caught the session-strand defect before the operator hit it in the affected post-restart state. It sat unchecked while other tasks were discharged by evaluation.** A task demanding runtime observation must not be deferred because it is inconvenient. This is a verification-process lesson, not self-flagellation: the FAIL verdict was right for a concrete reason not identified at the time. The clean quit-only smoke did not establish fallback after GDM restart and need not reproduce this defect. The later recovered GNOME login (§9.8) now closes 8.1 but cannot erase the counterexample.

**Checklist hazard, not stray operator action:** generation 10 is dated **00:11:53 UTC**, switch completed **00:12:03**, restart followed **00:12:06** with niri live (new read-only journal: `logs/niri-cam66-final-runtime-20260910.log:39–70`). **[Operator] This was the orchestrator-supplied post-deploy sequence.** The session strand was a direct consequence of that ordering: the checklist itself contained the hazard. The corrected no-live-niri precondition belongs before any restart instruction.

**Correction, explicitly bounded:** there is **no evidence that ordinary greeter session-switching strands niri**. The earlier attribution to switching was inference and is **refuted** by the exact sudo restart command in the journal. This is a known defect with one journal-proven trigger, not proof about every possible logout/VT-switch route. The exact historical signal delivered to the launcher remains unknown.

**[primary source re-read / inherited journal]** Niri v26.04 (`8ed0da44…`) runs `niri.service` under lingering `user@1000.service`, not the removed system-manager scope. Its launcher has no leader-death bridge: cleanup follows `systemctl --user --wait start niri.service`, so killing the launcher skips it; niri does not terminate on its logind session closing. Systemd 261.1's `graphical-session.target` already has `StopWhenUnneeded=yes`, but niri's `BindsTo` keeps it needed. GNOME 50.1 checks that target before starting its own session and aborts with `A graphical session is already running!` (journal signal **6/ABRT**). GDM returns to the greeter, presenting as a rejected password though PAM authentication succeeded. GNOME itself is unaffected by this missing bridge because its FIFO leader monitor handles unclean leader death; the selected monitor is nix-community gnome-session-ctl 50.0. This comparison is source-grounded, not a fresh GNOME kill test. Complete exact-version file citations and journal excerpts: `known-limitations.md`.

**[operator decision / inherited removal execution]** The local `niri-login-session.service`, embedded C/comments, niri's extra `BindsTo`/`After`/`ExecStopPost`, and change-local `monitor-tests.py` are removed from source. The operator declined indefinite C-daemon maintenance and unverified login-path machinery as disproportionate to slice A, not because the diagnosis or C was poor. Native toplevel build and generated-unit evaluations passed; the built unit returned to nixpkgs' package-plus-metadata shape (`logs/niri-slice-a-limitation-record.md`). That worker performed no deployment; this does not mean the power-button fix is undeployed (§9.8). No deployed source revision is groundable and the lifecycle defect remains. Prototype/harness survive only in authorized upstream-report logs (9.3), not as an in-tree repair.

**Operational rule:** **never restart display-manager while niri is live**. Quit niri with **`Mod+Shift+E` and confirm**, or arrange an authorized restart from GNOME/the greeter; first require cameron's `systemctl --user is-active niri.service` to return **`inactive`**. SSH or greeter location alone does not establish that precondition. Task 6.4 and the restart paths in 6.6/8.2 now carry this gate. Ordinary switching is not claimed to be a reproducer. Lingering remains deliberate clan inventory policy (`modules/clan/inventory/services/users/cameron.nix:53–61`), and `moshi-hook` depends on it for unattended operation (`modules/home/ai/moshi/default.nix:227–245`); disabling it was never an available fix.

**Recovery if stranded:** with operator coordination over SSH as cameron, run `systemctl --user stop niri.service graphical-session.target` in the affected user's manager, check both are `inactive`, then retry GNOME at the panel. This ends any active graphical session for that user; it is not routine logout guidance. Operator-reported recovery is corroborated by later SIGTERM/subsequent PAM opening, not replayed here. Full commands and evidence boundaries are in `known-limitations.md`.

**[historical spec-owner decision, earlier 9.4, now superseded] RETAIN the requirement unchanged as UNSATISFIED / undischarged.** At that time delta **39–43** promised GNOME reachable at every login regardless of earlier sessions; **62–66** promised recovery by sign-out without repair/preparation. The live-niri restart counterexample defeated those unchanged clauses. `known-limitations.md` retained **U-niri-fallback**, **F-niri-upstream = CAM-66**, and open **9.3**. CAM-66 remains operator-supplied Linear metadata, not proof of upstream submission. Historical operator reasoning rejected fitting the bar to an implementation defect; `openspec/config.yaml:58` requires undischarged rows/follow-up, never silent acceptance. **Current decision explicitly distinguishes an unavailable upstream lifecycle facility from an available configuration fix and applies the narrow post-counterexample amendment (§9.10)**, preserving this incident, earlier decision and its correct FAIL rather than silently erasing them. No monitor restoration.

### 9.8 CAM-66 update: recovered GNOME login and actual deployed protection

**[verified here, read-only SSH, 2026-09-10 01:49:20 UTC]** `logs/niri-cam66-final-runtime-20260910.log:1–37` returns session `176`, uid `1000`, `Name=cameron`, `Seat=seat0`, `TTY=tty2`, `Service=gdm-password`, `Type=wayland`, `Class=user`, `Active=yes`, `State=active`. PID **148024** runs GNOME Shell; its actual executable returns **`GNOME Shell 50.2`** (`logs/niri-cam66-final-daemon-20260910.log:1`). User manager: `gnome-session-manager@gnome.service` **active/running**, PID **148016**; `niri.service` **inactive/dead**, PID **0**. This corroborates **[operator] successful GNOME fallback login**, completing task 8.1 together with the inherited niri cog/terminal/quit smoke. SSH does not visually observe panel interaction; this recovered login is not a new uninterrupted two-desktop replay and not a repair of U-niri-fallback.

**Correction: the power-button fix IS deployed.** Both `/run/current-system` and the system profile resolve to `/nix/store/pgww7gi7jxb3ibdbfa2mphb2azid0znx-nixos-system-pyrite-26.11.20260804.85f6261`; profile is **generation 10**, timestamp **2026-09-10 00:11:53.298207399 +0000**. Its `etc/dconf/profile/user` contains `user-db:user` followed by `file-db:/nix/store/6gz8yrljg6p5ljydb40y3ijqc9ikzcg4-dconf-db`. Direct file-db-only dconf reads (bypassing user overrides) returned (`logs/niri-cam66-final-runtime-20260910.log:39–59`):

```text
power-button-action='nothing'
sleep-inactive-ac-type='nothing'
sleep-inactive-ac-timeout=0
sleep-inactive-battery-type='nothing'
sleep-inactive-battery-timeout=0
idle-delay=uint32 1800
niri 26.04 (Nixpkgs)
```

Running **gsd-media-keys PID 148129** started **00:16:24 UTC** (`ps`); systemd's ExecMainStartTimestamp is **00:16:25**. Both are after deployment/switch completion. Stronger than timing alone, `/proc/148129/maps` shows the **6gz8… dconf database mapped**; SSH user-profile `dconf read` also returns **`'nothing'`** (`logs/niri-cam66-final-daemon-20260910.log:2–5`). The daemon has loaded the new database; this is not merely committed configuration or a fresh CLI reading a file unknown to the old daemon.

**Historical boundaries at the 01:49 pass:** deployed source revision absent/unproven; 6.6's in-session desktop/gsettings/inhibitor transcript missing; at that time 8.7 had not run and idle tasks were open. **Superseded by §9.9:** physical 8.7 now discharged; 8.3–8.5 discharged by evaluation; 8.6 declined. The initial `pgrep -x gnome-shell` lookup returned no PID and `/proc//exe` failed; the actual `ps` PID yielded the version above. Linear metadata remains operator-supplied, not API verification or proof of an upstream submission.

### 9.9 Final evidence: physical controls, evaluation discharge and declined risk

**[verified here] Read-only SSH, 2026-09-10 UTC.** First action `pwd` returned `/Users/crs58/projects/vanixiets`. SSH at **02:07:08** returned uptime **22:48**, boot ID **55dc8d7c-66ba-4b7f-b160-e6459e3c61d0**, and the greeter (both cameron desktop units already inactive); this is not a live-niri process snapshot (`logs/niri-final-verdict-initial-20260910.log:1–14`). No deployment, restart, reload, suspend, long hold or writing git/jj command was performed. The operator, not this worker, performed the physical tests.

#### Physical test 8.7 — both desktops independently grounded

Fresh journal retrieval establishes GNOME session **176** opened **00:16:22.441165**, GNOME manager started **00:16:23.383361**, shell PID **148024** started **00:16:23.582733** and shortcuts service **00:16:25.344108** (`logs/niri-final-verdict-counts-controls-20260910.log:17–21`). That is after generation-10 deployment; inherited direct daemon-map evidence is in §9.8. This session remained until **02:03:08**, with the press at **02:02:54.328864** (`logs/niri-final-verdict-button-window-20260910.log:903–1035`). This is the user's GNOME session, not the later gdm-greeter GNOME instance.

Fresh niri session **209** opened **02:03:35.776364**; PID **154670** started niri **26.04** at **02:03:36.449630**, loaded `/home/cameron/.config/niri/config.kdl`, connected the internal Apple panel and opened Wayland/IPC. Presses followed at **02:03:39.311662** and **02:03:41.429194**, then confirmed exit at **02:03:50.852104** and session removal **02:03:52.155279** (same log **1308,1496–1528,1582–1584,1671–1741**). Thus “both desktops” is journal-grounded, while physical press/release and panel usability remain **[operator] observations**, not things SSH can see.

Separate unit/kernel-scoped queries, actual output (`logs/niri-final-verdict-separate-windows-20260910.log:1–10`):

```text
=== GNOME: 2026-09-10 02:02:45 through 2026-09-10 02:03:08 UTC ===
presses=1
suspend_requests=0
suspend_entries=0
shutdown/poweroff_requests=0
=== niri: 2026-09-10 02:03:36 through 2026-09-10 02:03:52 UTC ===
presses=2
suspend_requests=0
suspend_entries=0
shutdown/poweroff_requests=0
```

**Why this is stronger than silence:** the **same boot** contains a positive control — logind `Power key pressed short.` **21:16:36.327747**, `suspend requested from client PID 124058 ('.gsd-media-keys')` **21:16:36.392292**, kernel `PM: suspend entry (deep)` **21:16:37.863260** — and the negative control: the three post-fix presses explicitly received by logind, with no action. Seeing the key rules out missing input as the explanation. Positive-control sources: `logs/niri-final-verdict-counts-controls-20260910.log:22–25`, `logs/niri-final-verdict-policy-20260910.log:2–4`. Whole-boot authentic request/entry counts are **1/1**, not zero. Kernel resume exit is **21:17:09.957011**. **“Continuous uptime” means no reboot, not 22 hours without ever sleeping**: the positive control is a real earlier sleep. In the protected test interval, 13 logind JSON events have one boot ID and realtime-minus-monotonic spread **2 μs**, corroborating no sleep gap (`logs/niri-final-verdict-continuity-20260910.log:1–16`). Later SSH confirms reachability; no continuous SSH ping stream during the operator's presses is claimed.

8.7 is now discharged by this physical evidence, not by pretending its entire original prerequisite transcript was collected: 6.6's prescribed in-session desktop/gsettings/inhibitor snapshot remains missing. Deliberate suspend/wake subcheck is **declined with 8.6**, not claimed observed.

#### Idle tasks 8.3/8.4/8.5 — EVALUATION, NOT OBSERVATION

**[operator decision]** Explicitly replace the original untouched-window method, including 8.4's former refusal of configuration-only discharge, with evaluation. This changes the task's discharge method, **not the delta requirement**, and is recorded rather than concealed. **No 35-minute untouched AC or battery interval, nor repeated GNOME/greeter interval, was performed.** Freshly executed grounds:

1. **Exact niri source:** GitHub's annotated `v26.04` tag resolves to **8ed0da44d974c32c6877d2f4630c314da0717ecb**. An in-memory case-insensitive scan of **all 18 files in `niri-config/src/`** returns **0 matches** for `idle`, independently reproducing the reported `git grep -i idle` result without creating a checkout or running a writing git command. This pass used an archive scan, **not literally git grep**. Actual output: `logs/niri-final-verdict-pinned-source-20260910.log:1–25`; primary [configuration tree](https://github.com/niri-wm/niri/tree/8ed0da44d974c32c6877d2f4630c314da0717ecb/niri-config/src), [notify/inhibit handlers:517–533](https://github.com/niri-wm/niri/blob/8ed0da44d974c32c6877d2f4630c314da0717ecb/src/handlers/mod.rs#L517-L533). It has no idle-suspend timer in its configuration language; its notifier/inhibitor side requires an external consumer to act.
   The exact protocol name is grounded through niri's pinned **Smithay 0.7.0**, commit **ff5fa7df392cecfba049ffed55cdaa4e98a8e7ef** in that niri revision's `Cargo.lock`: [`idle_notify/mod.rs:1,52–65`](https://github.com/Smithay/smithay/blob/ff5fa7df392cecfba049ffed55cdaa4e98a8e7ef/src/wayland/idle_notify/mod.rs#L52-L65) imports `wayland_protocols::ext::idle_notify::v1` and documents client monitoring of user idle status. Actual pinned dependency/source output: `logs/niri-final-verdict-smithay-protocol-20260910.log:1–67`. A prior literal `ext-idle-notify` scan of niri itself produced no output; this dependency trace, not that empty scan, grounds **ext-idle-notify-v1**.
2. **Delivered niri configuration/dependencies:** current KDL resolves to `/nix/store/c3i3j0ss7bl6kixs9di4ghxzklh61vx8-config.kdl`; full read contains no include, startup daemon or suspend/poweroff bind (`logs/niri-final-verdict-policy-20260910.log:50–111`). `niri.service` has no local monitor overrides and its delivered dependency graph/autostart entries have no configured idle consumer (`logs/niri-final-verdict-dconf-autostart-20260910.log:38–449`). Its XDG target **does** launch keyring/IBus/user-directory helpers (physical journal **1512–1528**); no-idle-consumer is not no-autostart. This independently supports the configured-mechanism argument without claiming task 4.2's process snapshot.
3. **gsd-power boundary:** delivered service is GNOME-target-gated (`Requisite`/`PartOf=org.gnome.SettingsDaemon.Power.target`); niri's delivered graph does not pull that target. The journal stops cameron's GNOME power target **02:03:07.998859**, before niri; no user-1000 power-service start occurs in the niri interval. Greeter uid **60578** power-service activity is distinct. Current post-exit user unit is `inactive/dead`, PID 0; historical timestamps are already collected away (`CollectMode=inactive-or-failed`). Sources: `logs/niri-final-verdict-power-lifetime-20260910.log:1–35`, physical journal **967,1171–1185**, dependency log above. **The supplied “previously confirmed live absent in niri” process snapshot was not recovered; it is relayed operator history, not independently verified as a live process observation by this pass.** Task 4.2 therefore stays open. The evaluation rests on delivered gating/dependencies, not a fabricated `ps` result.
4. **Live logind D-Bus** returns `s "ignore"` for **IdleAction**, **HandlePowerKey**, **HandlePowerKeyLongPress** (`logs/niri-final-verdict-policy-20260910.log:43–49`). This is effective daemon state, not just file intent.
5. **Delivered user AND GDM dconf** file-db-only reads return `sleep-inactive-ac-type='nothing'`, `sleep-inactive-battery-type='nothing'`, both timeouts **0**; effective SSH user-profile dump agrees (`logs/niri-final-verdict-dconf-autostart-20260910.log:1–18`). GDM has no explicit power-button value in that read (blank output joins the next label); the task here concerns its four inactivity keys, not a greeter button guarantee. Process-substitution profiles selected delivered file-db lines only; no remote file was written. Exact gsd **50.1**, commit **ec681847221cf44e658363b9d8137b4cbae7b321**, [`idle_configure():2071–2108`](https://github.com/GNOME/gnome-settings-daemon/blob/ec681847221cf44e658363b9d8137b4cbae7b321/plugins/power/gsd-power-manager.c#L2071-L2108), selects the AC/battery pair and registers a sleep watch only for nonzero timeout and a non-NOTHING action. Both independent guards prevent that watch here (executed source retrieval: pinned-source log **112–149**).
6. **Boot history** spans greeter, GNOME and niri; authentic logind/kernel counts are **1 request / 1 entry**, attributable solely to the pre-fix media-keys button control, hence **zero idle-attributed** requests and **zero post-deployment** suspend/shutdown requests (`logs/niri-final-verdict-counts-controls-20260910.log:1–16`). An unscoped grep of the whole journal can count sudo's logged query string itself (policy log line 5); counts here explicitly select logind/kernel, not that self-match. Whole-boot zero is not asserted.

**Established by evaluation:** for the delivered policy/dependency configuration, no configured mechanism can initiate an idle suspend, independently for niri and for both power sources, while the delivered GNOME/GDM watch guards remain disarmed. **Not established:** an untouched 35-minute behavioral observation, arbitrary manually started/future idle consumers, all possible user overrides, or the missing historical process snapshot. User overrides intentionally remain possible. The boot counts corroborate the mechanism argument; they do not substitute for inactivity/power-source observation.

#### Declination and vacuity

**8.6 DECLINED [operator decision].** The cited historical CAM-59 cohort is **8 failures / 38 cycles**: the first-party diagnosis records **30 successes + 7 failures** (`logs/pyrite-resume-failure-diagnosis.md:75–117`), and the archived change records one additional failed deliberate suspend requiring power-cycle recovery (`openspec/changes/archive/2026-09-09-pyrite-never-sleep/tasks.md:115–136`). That supports the operator's roughly-one-in-five risk rationale; this is a **historical cohort, not newly recomputed current all-boot totals or a precise future probability**. The new positive control itself adds a later successful entry/exit and is not retroactively included in that cohort. Re-proving CAM-59 buys this change nothing at that physical recovery risk. No new deliberate suspend/guard/wake test is claimed or requested; 8.6 stays unchecked and declined.

**2.3 vacuous, unchecked by its own rule:** inherited merged-host `includes=[]` evaluation (`logs/niri-ledger-eval-20260909-143146.log`) plus delivered no-include KDL inspection. No artificial branch was exercised. No other remaining task is vacuous: **4.2, 6.6, 8.2** remain actual collection/sequence gaps; **9.3** remains upstream-report follow-up, with CAM-66 not proof of upstream submission. No missing observations are silently removed or labelled completed. The later narrow requirement amendment is explicit in §9.10. Pre-amendment counts and strict/scoped checks remain in `logs/niri-slice-a-final-verdict.md`.

**Inherited CAM-66 cross-check:** read-only journal retrieval reproduced switch **00:12:03.093473**, restart command **00:12:06.532360**, session-157 removal **00:12:06.648563**, surviving niri pausing **00:12:06.703987**, three GNOME “A graphical session is already running!” failures and niri SIGTERM **00:15:16.671788** (`logs/niri-final-verdict-cam66-20260910.log:1–8`). This grounds the pre-amendment FAIL in an actual violation, not checklist arithmetic. The command sequence's origin as the supplied checklist is operator attribution (§9.7); trigger/order and failure are journal facts. The current amendment (§9.10) explicitly excludes that exact state, not a finding that the incident was harmless.

### 9.10 Applied narrow CAM-66 amendment and independent verdict

**Scope and provenance:** this worker read both terminal predecessor reports and every current change artifact before editing; merged rather than replaced §§9.7–9.9, preserving physical/session evidence and the process finding. No runtime investigation was redone. Pinned primary-source contents were re-read from `logs/niri-limitation-primary-sources-20260909-212206.log:4–115,155–187`: niri **v26.04 / 8ed0da44d974c32c6877d2f4630c314da0717ecb**, full `resources/niri-session` and unit; GNOME **50.1**, `leader-systemd.c:246–277`. Their stable upstream URLs are in `known-limitations.md:70–74`. Inherited evaluations/builds/delivered queries remain attributed to their executing workers; physical use remains operator observation. New execution is local strict validation and scoped checks only.

**Amendment applied after the counterexample, not a hidden waiver:** exact drafted requirement body and scenario WHEN from `logs/niri-slice-a-amend-and-verdict.md:57–88`. The requirement now positively guarantees GNOME registered/selectable at the greeter and default for users with no recorded choice, with per-user persistence/no host overwrite retained. It names the exception: **GNOME reachability does not hold when display-manager is restarted while niri is live (CAM-66)**. The operator must quit niri and confirm the affected user's `niri.service=inactive` before restart. In the recovery scenario only WHEN narrows; THEN/AND remain byte-for-byte: working next-login GNOME, sign-out rather than repair, and no advance preparation **outside that named exception**. The former line-128 tracking note now records the amendment, retained promises and excluded-case follow-up rather than falsely saying no requirement changed. No idle/power or settings-validation requirement is amended.

**Legitimacy, not bar-lowering:** the former promise included niri's session-lifecycle behavior that no configuration of ours can deliver at these versions. The complete pinned launcher waits before cleanup and has no independent leader-death monitor; GNOME 50.1 explicitly supplies a FIFO EOF/HUP bridge. The missing facility is upstream code, not an available setting we declined to set. The historical prototype would add new lifecycle machinery, was never end-to-end verified against real GDM/systemd, and is not proof of a supported configuration fix. This owner-authorized scope correction is explicit **after failure**, with the failure, checklist hazard, original FAIL and CAM-66 retained. It does not claim a repair, arbitrary session-switch safety, an upstream submission or closure of 9.3.

**Task 4.2 correction preserves the observation method:** require **no idle consumer**, permitting benign autostarts. Pinned/delivered `niri.service` explicitly `Wants=xdg-desktop-autostart.target` (`logs/niri-final-verdict-dconf-autostart-20260910.log:38–53`; upstream service:8–9). The old `xdg-autostart*` wildcard misses that target and generated `app-…@autostart.service` names (same log:298,356). During a confirmed niri session inspect the affected user's full process list, running services, the actual target and generated autostart dependencies; distinguish greeter-user processes and establish no `swayidle`, `hypridle`, user `gsd-power` or other consumer. **4.2 stays UNCHECKED** per D7 (original `design.md:114`): **seen, not deduced**. No complete live snapshot was recovered; post-exit/configuration/graph evidence cannot substitute. Closure needs only that observation, **not a deploy/restart/reload**.

#### Independent comparison against all retained acceptance criteria

| Retained criterion | Grounded evidence and disposition |
|---|---|
| Stock GNOME/GDM; two registered/selectable desktops; interactive panel use | Inherited evaluated `sessionNames=["gnome","niri"]`, built entries and delivered GDM environment (tasks 3.1/6.2); operator cog/niri/Ghostty/quit and recovered GNOME usability with live session 176 corroboration (8.1, §§9.8–9.9). No removal or non-exception panel failure established. Retained boot/unlock clauses unchanged; no fresh boot test claimed. |
| GNOME default without recorded choice; saved choice persists/no host overwrite | Evaluated null default/empty preStart and built no-rewrite service (3.2); pinned GDM 50.1 fallback/saved-choice ordering and actual persisted `Session=niri` (§9.1). Supports retained semantics, not a completed 8.2 never-chosen/relogin/restart observation sequence. That gap remains open, not waived. |
| Working next-login GNOME / sign-out rather than repair / no preparation outside CAM-66 | Niri's confirmed clean quit and usable GNOME are inherited operator/runtime evidence (8.1); complete pinned launcher performs shutdown after its wait returns. The demonstrated repair-required case had precisely the excluded live-niri restart trigger (§9.7), not an ordinary clean sign-out. No retained-domain counterexample is established; no claim that every possible route was physically exercised. |
| Independent niri AC/battery inactivity protection; unchanged GNOME/greeter protection | **8.3/8.4/8.5 discharged by evaluation, not observation**, under explicit operator method decision: pinned notify-only source, delivered no-consumer configuration/graph, live logind ignore, both dconf profiles and exact gsd watch guards (§9.9). No untouched 35-minute windows; 4.2 remains open for its separate observed snapshot. |
| Ordinary power press neither suspends nor powers off in either desktop | **8.7 discharged by physical test** (§9.9): GNOME **176 until 02:03:08**, press **02:02:54.328864**; niri **209 / PID 154670 from 02:03:36**, presses **02:03:39.311662 / 02:03:41.429194**. Same-boot positive control: **21:16:36.327747 press → 21:16:36.392292 suspend requested from `.gsd-media-keys` → 21:16:37.863260 `PM: suspend entry`**. Negative control: post-fix presses reach logind, no suspend/shutdown follows; operator reports usable desktops. Whole-boot totals **1 request / 1 entry**, the pre-fix event, not zero. Missing 6.6 transcript stays open. |
| Deliberate suspension/wake retained, no blanket block | Task 4.3's scoped evaluation/diff found no blanket block. **8.6 declined by operator** under CAM-59 historical **8/38** physical-power-cycle risk; not an observed niri suspend/guard/wake pass and not a future scheduling request. Firmware-wake premise remains inherited, not newly tested; no prohibition/regression established. |
| Settings checked before selection by exact runtime program; immutable used includes | Inherited actual positive/negative niri-validation builds (2.4), identical validator/runtime store paths (2.1), built/delivered KDL (2.2/2.5). `includes=[]`: 2.3 remains vacuous and unchecked by its own rule, not a mutable used include or unexecuted validation. No mismatch established. |

**Independent result: PASS WITH WARNINGS against the amended requirement; not full verification/archive readiness.** The historical decisive counterexample is outside the now-explicit domain, while the retained positive claims have the evidence above. No other demonstrated violation was found. Unperformed prescribed observations are real gaps, not fabricated failing tests or completed tests; 4.2, 6.6, 8.2 remain open, 8.6 declined, 2.3 vacuous/unchecked, 9.3 upstream follow-up open. **32 checked / 6 unchecked**, unchanged. The amendment is not permission to discharge 4.2 on the idle evaluation.

**What would constitute FAIL now:** GNOME absent/unselectable, wrong no-history fallback, host overwrite of saved choice, or working GNOME unavailable after sign-out in the retained scenario **without** the live-niri display-manager-restart trigger; an idle-triggered suspend; a protected ordinary press requesting suspend/poweroff; a blanket prohibition on deliberate suspension/wake; or validator/runtime mismatch, an accepted invalid generated config or mutable used include. None is established by the inherited evidence. The real pre-fix GNOME press was before deployment of its protection; it is the positive control, not a protected-policy failure. If a retained-domain counterexample emerges, FAIL follows regardless of checkbox count or structural success.

**New local verification:** `openspec validate pyrite-niri-second-session --strict` reports `Change 'pyrite-niri-second-session' is valid` (exit 0), output `logs/niri-amend-applied-strict.log`. Scoped diffs, byte comparison of all 506 Nix files against this worker's entry and exact draft/THEN/AND/ledger checks: `logs/niri-amend-applied-scope.log`. Report with exact before/after: `logs/niri-slice-a-amend-applied-verdict.md`. Toplevel rebuild skipped: documentation-only changes. Concurrent `modules/nixos/gitea-mq.nix` diff is other work, untouched and not a defect; no aggregate clean-Nix-worktree claim.

## Overall Decision

- [ ] PASS — fully verified, archive-ready.
- [x] **PASS WITH WARNINGS — against the explicitly amended requirement, not fully verified/archive-ready.** **32 checked / 6 unchecked.** Narrow post-counterexample CAM-66 amendment, evaluation-only 8.3/8.4/8.5, declined 8.6, physical/session-attributed 8.7 with same-boot controls and whole-boot **1/1**, corrected/open 4.2, missing 6.6/8.2 observations and upstream 9.3 all remain visible in §9.10.
- [ ] FAIL — the former unconditional requirement did fail; that is retained history, not the current criterion. A retained-domain violation listed in §9.10 would restore FAIL.

**Verification-process finding:** task **8.1** was the runtime GNOME fallback check that would have caught the defect in the affected post-restart state; it sat unchecked while other tasks were discharged by evaluation. A clean quit-only smoke need not reproduce this defect. Closing the recovered GNOME login, physical power tests, idle evaluation or amending the requirement cannot erase that counterexample. The original post-deploy **deploy → restart display-manager ordering caused the lockout inside live niri**, not an unrelated operator mistake. All future restart instructions retain the no-live-niri gate; no host action is authorized here.

**§8 is agent-executed, non-blocking and NEVER validation** (`openspec/config.yaml:49–51`). Its designation, alphabet and no-named-interface discharge findings remain open, including machine vocabulary added by the amendment; no ungrounded clean lint. `openspec validate` checks structure only. Retain undischarged formal rows and follow-ups in the regenerated archive projection rather than silently accepting them. Bare-compositor portal/cursor/X11 limitations remain bounded slice-B work.

**Remaining evidence questions, not resolved by interpretation:** can an actual attributed in-niri snapshot be supplied to close 4.2; can the missing 6.6 in-session transcript and 8.2 no-history/relogin/safely-gated restart-memory sequence be supplied; and what is the upstream report URL/status if 9.3 has been submitted? These remain open, with no inferred waiver, deploy or risky test authorized. 8.6's declination and the amendment decision are settled, not reopened.
