---
linear_story_id: CAM-63
linear_story_identifier: CAM-63
linear_story_title: "Offer niri as a second selectable desktop on pyrite, with GNOME still the default"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-63/offer-niri-as-a-second-selectable-desktop-on-pyrite-with-gnome-still
linear_story_state: Todo
linear_team: CAM
linear_project: pyrite-baremetal-nixos
last_synced_state: Todo
last_synced_at: 2026-09-09T00:00:00Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-09-09T00:00:00Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; issue CAM-63 created in the existing pyrite-baremetal-nixos project and seeded from this proposal's business-facing content. Artifacts authored through tasks.md only; no implementation." }
---

## Why

pyrite has one desktop and no way to try another. The operator wants niri, and the research says the whole niri assembly is three changes, not one: the compositor and its session, the shell that makes it usable, and the replacement of the login screen. Taken together they would remove the only desktop that is known to work on this hardware in the same step that introduces its replacement.

This change takes the first slice only: niri is a second login-screen entry; GNOME/GDM remain installed, GNOME registered/selectable at the greeter, default for users without saved choice and the designated fallback. **Amended after a demonstrated counterexample:** reachability does not hold when `display-manager` is restarted while niri is live; the requirement now explicitly excludes that state (task 9.4). Only the recovery scenario's WHEN is narrowed; working next-login GNOME, sign-out rather than repair and no advance preparation remain promised outside that exception. This corrects an upstream lifecycle promise our configuration cannot deliver: niri v26.04 lacks GNOME 50.1's leader-death bridge, not an available configuration fix deliberately omitted. [U-niri-fallback](known-limitations.md#verification-lesson-and-decided-undischarged-requirement) preserves the counterexample and historical FAIL. **F-niri-upstream = [CAM-66](https://linear.app/cameronraysmith/issue/CAM-66/correct-password-returns-to-gdm-niri-survives-a-display-manager)** / open 9.3 tracks the excluded case, not proof of upstream submission or repair. Independent current verdict: **PASS WITH WARNINGS against the amended requirement**, with incomplete observations retained (`verify.md` §9.10), not fully verified/archive-ready.

**Operational limitation and explicit requirement exception, not a repair:** never restart display-manager with live niri. Quit with `Mod+Shift+E`, confirm, and require cameron's `systemctl --user is-active niri.service` to report `inactive` before an authorized restart; being at the greeter or on SSH alone is insufficient. If already stranded, coordinated SSH recovery stops `niri.service graphical-session.target` in cameron's user manager, verifies both inactive, then retries GNOME. This ends any active graphical session for that user. Full commands, primary sources and evidence boundaries: `known-limitations.md`. The local C monitor was declined and removed, not deferred for deployment.

Two things make this less trivial than "turn niri on". The nixpkgs module pins itself as the default session, and under GDM that rewrites every user's saved session on every display-manager start — so enabling niri without care flips the default away from the working desktop. And yesterday's never-suspend work does not carry: all of it is `gsd-power` and dconf, which a niri session does not run. On a host where roughly one resume in five fails and the power button is the only wake source, a niri session that suspends itself unattended costs a physical trip to the machine. Both are designed against here rather than discovered later.

## What Changes

**niri appears as a second session at the login screen**
- From: one session is registered, so GDM's picker hides itself — the chooser is gated on `ids.length <= 1` in gnome-shell's login dialog, not on any NixOS option.
- To: niri's nixpkgs package registers a second session and the picker appears on its own. Task **8.1 is discharged** by inherited niri panel smoke and the operator's recovered GNOME login, independently corroborated by live session/shell/user-unit readback (`verify.md` §9.8). GNOME reachability after the live-niri display-manager-restart trigger remains broken and is now explicitly excluded, not repaired (§9.10); this recovered login does not erase that defect.
- Reason: the session registry is `services.displayManager.sessionPackages` and nothing else; niri's nixpkgs package already satisfies its contract, so this is enabling an existing mechanism rather than building one.
- Impact: a choice at the login screen, and a per-person memory of which one was chosen last.

**GNOME stays the default for users with no saved choice, and each person's own choice is remembered**
- From: `programs.niri` sets the default session to niri by default; under GDM that runs `set-session niri` before every start, which rewrites every non-system user's saved session and, in its own comment, "basically ignore[s] session history".
- To: the default session is pinned explicitly to the value that leaves saved sessions alone, so a person who has never chosen gets GNOME and a person who has chosen gets what they chose.
- Reason: the fallback has to be the desktop that works, and per-user memory is the mechanism that makes the choice stick.
- Impact: the configuration does not rewrite saved session choices on display-manager starts; GDM still persists the user's selection. This selection mechanism does not establish unconditional GNOME reachability (**U-niri-fallback**).

**The niri session never suspends the host on its own**
- From: the host does not suspend itself on inactivity — but that protection is entirely GNOME-specific, and a niri session runs none of it.
- To: the same guarantee holds for a niri session, established independently by evaluation under the operator's explicit 8.3/8.4 method decision, **not** by untouched mains/battery observation. Corrected task 4.2 remains open for an actual in-niri idle-consumer snapshot, not a deploy.
- Reason: resuming this host is unreliable and recovering a failed resume needs a person at the machine (world assumption A13). An unattended suspend under a desktop nobody checked is a trip to wherever the laptop is.
- Impact: the never-suspends property becomes a property of the host rather than of one desktop.

**An ordinary power-button press in niri neither suspends nor powers off the host**
- From: niri hardcodes an immediate suspend; disabling that alone would hand the key to logind's poweroff default.
- To: disable niri's power-key handling and explicitly make logind ignore the key, as the operator decided (`design.md` D9).
- Reason: the only wake source must not also be an accidental route into an unreliable suspend or a poweroff. Firmware wake is unaffected by logind policy; deliberate suspend by a session command remains possible.
- Impact: paired niri configuration and host-wide logind policy; no change to GNOME dconf, greeter auto-suspend, lid or wake configuration.

**The niri session's settings are checked, at build time, by the niri that will run them**
- From: nothing checks a compositor configuration before it is used.
- To: the settings are authored through a typed schema and checked by running the same niri the system installs; a configuration that would be rejected fails the build instead of failing at the moment a person selects the session.
- Reason: checking with a different niri than the one that runs would produce a guarantee that looks present and is hollow.
- Impact: a rejected configuration is a build failure, which is recoverable from anywhere, rather than a login failure, which is not.

**GNOME's and the login screen's existing never-sleep configuration is not touched**
- From: `gdm.autoSuspend = false` and four dconf keys under `programs.dconf.profiles.user.databases`.
- To: unchanged, byte for byte.
- Reason: they are yesterday's change and they work.
- Impact: none; stated so that a reader does not take "add a session" as licence to reorganize the power configuration.

## Capabilities

### Modified Capabilities

- `graphical-desktop-session` (stratum: `behavioral`): the capability currently asserts that "niri and its Wayland shell assembly are NOT part of this capability" and that "home-manager carries no desktop toggle". Both are contradicted by this slice and are amended in place. Three requirements are added: a second desktop selectable at the login screen with the established one as the default; the newly offered desktop not suspending the host on inactivity; and a desktop not being offered until the settings it will start with have been checked by the program that will start it.

There is no `world` capability delta in this change and no `interface` capability. That is a deliberate choice with a cost, recorded rather than hidden: the `world-assumptions` requirement `Grounded vocabulary for behavioral requirements` is `MODIFIED` by two other unarchived changes, and `MODIFIED` is full replacement, so any fourth modifier must carry a superset of a corpus that is moving underneath it (`openspec/changes/stand-up-nixbot-on-magnetite/design.md` D11; `logs/nixbot-world-assumptions-superset-repair.md`). Three terms this change's requirements use — `desktop`, `default desktop`, and `settings` — have no designation row today. They remain an open designation-lint finding in `design.md` OQ6, not a clean lint. The operator accepts this disposition for slice A; adding rows remains for whichever change next owns that table alone. A structural sync-time superset check is being filed separately as its own Linear issue, not added to CAM-63.

## Impact

Implementation, in a follow-up and only after a human reviews this plan, touches `flake.nix` (one input), `modules/machines/nixos/pyrite/default.nix` (session enablement, the explicit default session, and explicit logind idle/power-key policy), and cameron's home-manager (the typed niri configuration, including disabled power-key handling). No file under `openspec/specs/` is written by hand; the delta syncs at archive.

**Non-goals, each named because each is a live temptation:**

- **Slice B — DankMaterialShell — is out of scope.** No bar, launcher, notification daemon, lock screen, wallpaper, or clipboard manager. A niri session in this slice is a bare compositor. It is a second seat at the table, not a finished desktop.
- **Slice C — greetd plus DankGreeter, dropping GDM and GNOME — is out of scope.** It is a larger change than it looks: gnome-shell's `canLock()` asks `org.gnome.DisplayManager` for its version and returns false when GDM is absent, so GNOME kept as a fallback session under greetd has no screen lock at all. That is a security regression needing its own change.
- **The lid handlers are not touched.** `HandleLidSwitch`/`HandleLidSwitchExternalPower` at `"lock"` and `HandleLidSwitchDocked` at `"ignore"` were an operator decision recorded at `openspec/changes/archive/2026-08-01-pyrite-baremetal-nixos/retrospective.md:229-231`. Adding a session is not grounds to reopen it. That GNOME's lock depends on GDM is noted as an open question for slice C, not a task here: under slice A GDM remains, so GNOME locking is unaffected.
- **Yesterday's never-suspend configuration is not disturbed.** Not the GNOME session's, not the GDM greeter's.
- **The resume defect is not fixed here.** It is tracked separately as CAM-59 and remains unexplained. This change adds a desktop that does not take that risk unattended; it does not lower the risk.
- **Manual suspend is not blocked.** No masked sleep targets, no `AllowSuspend=no`, no blanket inhibitor — the same non-goal yesterday's change carried, for the same reason.
