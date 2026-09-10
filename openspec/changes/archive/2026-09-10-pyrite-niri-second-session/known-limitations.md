# Known limitation: niri survives a display-manager restart

Status: **known operational limitation for slice A; explicitly excluded by the narrow CAM-66 requirement amendment, not repaired or silently discharged**. The operator declined the local monitor; the earlier retain-unchanged/UNSATISFIED decision and FAIL were correct before the amendment (task 9.4). The final independent verdict is **PASS WITH WARNINGS, archive-ready against the amended requirement, not fully observed or formally discharged (`verify.md` §9.12)**. 8.2 no-history remains a source-read-only method limitation, 8.3/8.4/8.5 evaluation, 8.6 declined, 8.7 physical controls with whole-boot 1/1. This record supersedes the proposed local repair and loose greeter-switching language in `logs/niri-session-strand-defect.md` §§6–8; it preserves the incident and decision history.

## Operator decision (not the worker's judgement)

The operator decided **not to carry** the `niri-login-session.service` monitor. Their reasons: repairing niri's session lifecycle is disproportionate to slice A, whose objective is offering niri as a second session; it would require maintaining a C daemon inside a machine module indefinitely; and its end-to-end behavior was explicitly never verified against real GDM/systemd, so shipping it would put unverified machinery into the login path of a machine whose only recovery is physical. The diagnosis and careful C are not rejected; the local implementation is removed, not deferred for deployment.

The module's entire monitor/comment/C block and its niri `BindsTo`/`After`/`ExecStopPost` additions are removed, and `monitor-tests.py` is deleted from this change. For an upstream report only, the exact pre-removal module (monitor at lines 353–450) and harness are preserved in authorized, non-deployed log artifacts: `logs/niri-limitation-pyrite-before.nix` and `logs/niri-limitation-monitor-tests-upstream.py`. They are not imported, shipped, or a maintained test suite. Historical diagnosis/build/mock evidence remains in `logs/niri-session-strand-defect.md`; it never established real GDM/systemd behavior for that monitor. No upstream issue submission or exact existing issue is claimed.

## Exact reproducer and observed mechanism

**Journal-proven trigger: `sudo systemctl restart display-manager` while a niri session is live. Do not execute this reproducer on pyrite.** These are inherited journal observations re-read for this record, not commands run by this worker:

```text
Sep 10 00:12:06 ... sudo[146383]: ... COMMAND=/run/current-system/sw/bin/systemctl restart display-manager
Sep 10 00:12:06 ... pam_unix(gdm-password:session): session closed for user cameron
Sep 10 00:12:06 ... session-157.scope: Deactivated successfully.
Sep 10 00:12:06 ... Removed session 157.
Sep 10 00:12:06 ... niri[126628]: ... pausing session
Sep 10 00:15:16 ... niri[126628]: ... quitting due to receiving signal SIGTERM
```

All timestamps are **2026-09-10 UTC**. The sudo command, PAM close, scope deactivation/removal and pause are in `logs/niri-strand-logout-detail-20260909-202428.log:260–294`; surviving PID 126628 and eventual manual-recovery SIGTERM are in `logs/niri-strand-lifetime-20260909-202300.log:24–44`. Niri paused rather than exited at session removal (and continued inactive-device messages until recovery). The exact historical signal/order killing the launcher is not in the collected journal.

**Post-deploy process finding (2026-09-10):** read-only host evidence re-derived generation **10**, dated **00:11:53 UTC**, switch completion **00:12:03**, and the restart **00:12:06** while niri was live (`logs/niri-cam66-final-runtime-20260910.log:39–70`). **[Operator attribution] The deploy-then-restart sequence was supplied by the orchestrator.** The strand directly followed that instruction ordering; the post-deploy checklist itself contained the hazard. It was not a stray operator action. The corrected checklist now requires `niri.service=inactive` before restart.

`niri.service` runs under the lingering **`user@1000.service`**, outside the system manager's `session-157.scope`: the supplied incident cgroup is `/user.slice/user-1000.slice/user@1000.service/session.slice/niri.service` (operator evidence, not a reconstructed dead PID's `/proc`). Niri v26.04 has **no leader-death lifecycle bridge**: it does not terminate in response to its logind session closing, so it survives in that user manager. Its launcher only requests shutdown after the foreground `systemctl --user --wait start niri.service` returns; killing the launcher bypasses those later lines. `graphical-session.target` **already has `StopWhenUnneeded=yes`**; niri's `BindsTo=graphical-session.target` is a requiring relationship that keeps the target needed while niri remains alive. Neither original user unit is bound to the removed system-manager login scope. Primary source references are below.

The next GNOME attempt authenticated successfully, then failed session startup:

```text
Sep 10 00:13:24 ... pam_unix(gdm-password:session): session opened for user cameron(uid=1000) by (uid=0)
Sep 10 00:13:25 ... .gnome-session-[147637]: A graphical session is already running!
Sep 10 00:13:25 ... Process 147637 (.gnome-session-) of user 1000 terminated abnormally with signal 6/ABRT, processing...
Sep 10 00:13:25 ... pam_unix(gdm-password:session): session closed for user cameron
```

Source: `logs/niri-strand-auth-gnome-units-20260909-203514.log:10–15`; the same pattern appears at 00:12:31 and 00:12:47 (lines 2–9). GDM bounces back to the greeter: it presents as a rejected password, **but authentication succeeded**. GNOME aborts because the graphical target is still active, not because the password is wrong.

**Not established:** there is **no evidence that ordinary greeter session-switching strands niri**. The earlier claim attributing this incident to ordinary switching was inference and is **refuted** by the captured restart command. This is not proof that every possible session-switch sequence is safe; it is a correction of the claimed reproducer. A VT/greeter switch alone is not evidence that logind removed a session. Do not broaden the exact trigger into a vague “switching breaks niri” claim.

## Operational rule and recovery

**Never restart `display-manager` while a niri session is live.** Quit niri first with **`Mod+Shift+E` and confirm**; its own quit action tears down cleanly (operator smoke and journal: `logs/niri-verify-runtime-20260909.log:210–233`, launcher cleanup source below). Alternatively arrange any authorized display-manager restart from GNOME or the greeter, with no live niri session. Merely being at the greeter or running the command over SSH is not sufficient: check the affected user's manager first.

As `cameron` on pyrite, locally or over SSH:

```sh
systemctl --user is-active niri.service
```

The required output is **`inactive`** (systemctl's nonzero inactive exit status is expected). `active`, `activating`, `failed`, or an inability to query the manager does not satisfy this check. Only proceed with a separately authorized restart after the rule is satisfied. GNOME is unaffected by this particular missing-bridge defect because it has a FIFO leader monitor; this is source-grounded, **not** a newly performed real GNOME leader-kill test or a claim that GNOME has no other lifecycle bugs.

**Recovery if already stranded:** with operator coordination, SSH as the affected user and stop both units **in the user manager**, not system units and not root's user manager:

```sh
ssh cameron@pyrite.zt 'systemctl --user stop niri.service graphical-session.target'
ssh cameron@pyrite.zt 'systemctl --user is-active niri.service graphical-session.target'
```

Both should report `inactive` before retrying GNOME at the panel. Stopping `graphical-session.target` ends any active graphical session for that user; this is recovery for the stranded state, not a routine logout substitute. The operator reported that stopping these units restored login; the journal independently confirms the later niri SIGTERM and subsequent PAM session (`logs/niri-strand-lifetime-20260909-202300.log:42–47`). This worker did not replay recovery, deploy, restart, stop services, or suspend pyrite.

## Upstream ownership and exact-version comparison

Primary files were re-read at these exact versions, not default branches (transcript: `logs/niri-limitation-primary-sources-20260909-212206.log`):

| Owner/version | Source and consequence |
|---|---|
| niri **v26.04**, commit **8ed0da44d974c32c6877d2f4630c314da0717ecb** | [`resources/niri.service:1–14`](https://github.com/niri-wm/niri/blob/8ed0da44d974c32c6877d2f4630c314da0717ecb/resources/niri.service#L1-L14) binds only to the graphical target, with no login-lifetime monitor. [`resources/niri-session:24–53`](https://github.com/niri-wm/niri/blob/8ed0da44d974c32c6877d2f4630c314da0717ecb/resources/niri-session#L24-L53) waits at line 47, then starts shutdown at 50 and unsets environment at 53; full file 1–95 has no exit/signal trap or independent leader monitor. |
| root nixpkgs **85f62611fa3f3eacbcfe3bc7a6d6518b443ca442** (`nixpkgs_9`) | [`niri.nix:49–60`](https://github.com/NixOS/nixpkgs/blob/85f62611fa3f3eacbcfe3bc7a6d6518b443ca442/nixos/modules/programs/wayland/niri.nix#L49-L60) imports package units and adds restart/PATH metadata only; [`package.nix:44–48,91–95`](https://github.com/NixOS/nixpkgs/blob/85f62611fa3f3eacbcfe3bc7a6d6518b443ca442/pkgs/by-name/ni/niri/package.nix#L44-L95) patches paths/shebang and installs upstream integration. The missing bridge is **niri upstream's defect**, not a nixpkgs dependency patch or our typed settings. |
| systemd **261.1** | [`graphical-session.target:10–15`](https://github.com/systemd/systemd/blob/v261.1/units/user/graphical-session.target#L10-L15) already has `StopWhenUnneeded=yes`; [`systemd.unit.xml:731–748`](https://github.com/systemd/systemd/blob/v261.1/man/systemd.unit.xml#L731-L748) defines `BindsTo`; [`997–1006`](https://github.com/systemd/systemd/blob/v261.1/man/systemd.unit.xml#L997-L1006) defines unneeded cleanup. |
| GNOME session **50.1** | [`leader-systemd.c:246–277`](https://gitlab.gnome.org/GNOME/gnome-session/-/blob/50.1/gnome-session/leader-systemd.c#L246-277) documents the system-scope leader/user-manager FIFO bridge, including EOF/HUP on unclean death. [`309–328`](https://gitlab.gnome.org/GNOME/gnome-session/-/blob/50.1/gnome-session/leader-systemd.c#L309-328) checks the graphical target and aborts **before** starting GNOME's target. [`330–347`](https://gitlab.gnome.org/GNOME/gnome-session/-/blob/50.1/gnome-session/leader-systemd.c#L330-347) opens the FIFO and registers handlers; [`data/gnome-session.target:9–15`](https://gitlab.gnome.org/GNOME/gnome-session/-/blob/50.1/data/gnome-session.target#L9-15) binds to the monitor. |
| selected nix-community **gnome-session-ctl 50.0** | [`gnome-session-ctl.c:158–177`](https://github.com/nix-community/gnome-session-ctl/blob/50.0/gnome-session-ctl.c#L158-L177), [`188–232`](https://github.com/nix-community/gnome-session-ctl/blob/50.0/gnome-session-ctl.c#L188-L232), [`285–295`](https://github.com/nix-community/gnome-session-ctl/blob/50.0/gnome-session-ctl.c#L285-L295) watches FIFO input/HUP, notifies stopping, and starts the shutdown target. Actual selected executable is confirmed by the inherited live unit at `logs/niri-strand-auth-gnome-units-20260909-203514.log:40–55`, not assumed to be GNOME's bundled executable. |

**Lingering is deliberate clan inventory policy, not an available fix:** `modules/clan/inventory/services/users/cameron.nix:53–61` explicitly enables it to preserve unattended per-user daemons. `modules/home/ai/moshi/default.nix:227–245` requires lingering for an unattended Moshi connection and installs `moshi-hook` under `default.target`. Current evaluation confirms `linger=true` and `moshiHookPresent=true`. Another retained SSH login can also keep the user manager alive; disabling linger would neither respect policy nor reliably remove the failure condition. No policy module was changed.

## Verification lesson and decided undischarged requirement

**Task 8.1 (GNOME fallback login) is the test that would have caught this before the operator hit it in the affected post-restart state.** It sat unchecked while other tasks were discharged by evaluation; runtime observation must not be deferred because it is inconvenient. A quit-only cycle need not reproduce this trigger. Task 8.1 is now discharged by inherited niri panel smoke plus the operator's recovered GNOME login, independently corroborated by live session 176/GNOME Shell 50.2 and inactive niri (`verify.md` §9.8). That recovered login does not erase this counterexample or retrospectively change the pre-amendment **FAIL**. Current evidence dispositions remain visible: 8.3/8.4/8.5 evaluation, not observation; 8.6 declined under CAM-59; 8.7 physical same-boot controls, whole-boot 1/1; 4.2 open for an actual in-niri observation, not a deploy (§§9.9–9.10).

**Historical spec-owner decision (earlier task 9.4, since superseded): RETAIN the requirement unchanged and record it as UNSATISFIED.** At that time delta `specs/graphical-desktop-session/spec.md:39–43` and `:62–66` were not amended, delimited, or rescoped. Closing that decision did not discharge the requirement or close upstream task 9.3. The historical report `logs/niri-slice-a-undischarged-record.md` remains unchanged.

**Historical operator reasoning:** amending merely to match a defect would fit the specification to the implementation — lowering the bar so the change passes. `openspec/config.yaml:58`, `operations.archive.guidance`, requires: **“Record undischarged requirements as rows with a follow-up reference. Never omit them and never silently accept them.”** The current decision distinguishes that concern from a promise of unavailable upstream lifecycle behavior: the amendment is explicit, after the counterexample, and the incident/follow-up are retained below rather than silently accepted or labelled repaired.

**Current spec-owner decision (task 9.4 applied):** use the drafted narrow amendment from `logs/niri-slice-a-amend-and-verdict.md:57–88`. Positively guarantee GNOME registration/greeter selectability and default for users with no recorded choice; preserve per-user persistence/no host overwrite. Explicitly exclude the state caused by restarting display-manager while niri is live, where GNOME reachability does not hold. In the recovery scenario **only WHEN changes**; THEN/AND still promise working next-login GNOME, sign-out rather than repair and no advance preparation outside that named exception. The old non-normative spec note no longer says nothing was amended.

**Why legitimate here, not bar-lowering:** this was amended **after a demonstrated counterexample** to correct a session-lifecycle promise that no configuration of ours can deliver at the selected upstream versions. niri **v26.04 / 8ed0da44d974c32c6877d2f4630c314da0717ecb** has no leader-death bridge; its launcher waits before cleanup (`resources/niri-session:24–53`, full file 1–95), whereas GNOME **50.1** explicitly implements the FIFO EOF/HUP bridge (`leader-systemd.c:246–277`). Exact pinned primary contents are preserved in `logs/niri-limitation-primary-sources-20260909-212206.log:20–115,155–187`; stable upstream URLs are in the comparison table above. This is not an available local setting deliberately omitted: shipping new lifecycle code would add the missing upstream facility, not configure one niri already supplies. The withdrawn prototype was never real-GDM/systemd verified and is not proof of a supported configuration fix. CAM-66 remains the excluded-case follow-up, with no repair, upstream submission or successful arbitrary lifecycle route inferred.

| Historical undischarged requirement / current excluded case | Status and precise counterexample | Cause / operational handling | Follow-up reference |
|---|---|---|---|
| **U-niri-fallback:** [two-desktop requirement](specs/graphical-desktop-session/spec.md#requirement-a-person-at-the-panel-can-choose-between-two-desktops-and-the-established-one-is-what-they-get-if-they-do-not-choose) and [unusable-desktop recovery scenario](specs/graphical-desktop-session/spec.md#scenario-the-newly-offered-desktop-is-unusable-at-the-panel); former unconditional clauses at lines 39–43 / 62–66. | **Historically UNSATISFIED; now explicitly excluded, still unrepaired — not discharged as a repair.** After `display-manager` restart **while niri is live**, niri survives login-session removal and authenticated GNOME startup aborts. Journal-proven trigger: 00:12:06 UTC, 2026-09-10; ordinary greeter switching is not established as a trigger. User-manager repair contradicted the former unconditional promise. | niri **v26.04** lacks GNOME **50.1**'s FIFO leader-death bridge; exact-version sources above. Never restart display-manager with live niri; quit/confirm and require affected-user `niri.service=inactive`. Coordinated affected-user SSH recovery stops `niri.service graphical-session.target`, checks both inactive, retries GNOME; commands/side effects above. Avoidance is not a repair. | **[CAM-66](https://linear.app/cameronraysmith/issue/CAM-66/correct-password-returns-to-gdm-niri-survives-a-display-manager)** (**F-niri-upstream**, below); task **9.3** remains open. Retain this row, counterexample, explicit amendment and follow-up in the archive satisfaction projection; never present the excluded case as successfully discharged. |

### F-niri-upstream — CAM-66

**[CAM-66 — Correct password returns to GDM: niri survives a display-manager restart](https://linear.app/cameronraysmith/issue/CAM-66/correct-password-returns-to-gdm-niri-survives-a-display-manager)** is the real follow-up, not CAM-63. Operator-supplied metadata: team **CAM**, project **`48b4123d589b`**, **Backlog**, priority **2**; not independently queried through Linear (no Linear tool discoverable in the predecessor pass). This follow-up owns [U-niri-fallback](#verification-lesson-and-decided-undischarged-requirement), now explicitly excluded by the linked amended requirement/scenario; the delta's non-normative tracking note links back here. No upstream niri issue submission or repair is claimed.

Task **9.3** owns recording the actual upstream issue URL/status when submitted and linking it through that Linear follow-up, with the exact-version comparison, journal and explicitly unverified prototype archive. Reporting alone will not repair U-niri-fallback: any future claim to restore unconditional reachability needs lifecycle evidence, not merely observance of the avoidance rule or the amendment. No local monitor restoration or pyrite failure injection is authorized by this follow-up.

**Verification consequence:** the former unconditional requirement actually failed; amendment does not rewrite that history. Final independent comparison finds no retained-domain counterexample and no undispositioned blocker: **PASS WITH WARNINGS, archive-ready (`verify.md` §9.12)**. 4.2 is observed, 6.6 runtime-discharged, 8.2 remembered choice discharged/no-history source-read-only METHOD LIMITATION (operator declined destroying real preference; disposable account later), 8.6 declined, 2.3 vacuous/unchecked, 9.3 open. The C monitor remains excluded, not deployed or repaired. Verify §8 is agent-executed, non-blocking and never validation; its designation/interface findings remain open.
