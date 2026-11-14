---
linear_story_id: CAM-99
linear_story_identifier: CAM-99
linear_story_title: "Bring pyrite to daily-driver parity with stibnite"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-99/bring-pyrite-to-daily-driver-parity-with-stibnite
linear_story_state: Todo
linear_team: CAM
linear_project: workstation-parity
last_synced_state: Todo
last_synced_at: "2026-11-13T20:01:05Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-13T20:01:05Z", transition: "Backlog->Todo", outcome: "posted", note: "Project 69d5244a4e10 and issue CAM-99 created in Todo with description seeded from proposal.md; binding, state, project and labels confirmed by read-only view" }
---

## Why

stibnite is the only laptop the operator can work from: pyrite holds no SSH identity and reaches no host, and most of stibnite's daily tooling exists only there, much of it configured by hand.
Bringing pyrite to parity lets either laptop be carried while the other is reached over SSH.
Declaring what stibnite does imperatively along the way makes both machines reproducible from this repository.

## What Changes

This change is a program: it records the goal, the principles, the decision catalogue and the slice order, and each slice ships as its own pull request.

**Daily-driver parity**
- From: pyrite offers a desktop session but not the jobs daily work needs; stibnite's launcher, window chords, clipboard history, secrets access and desktop feel exist only on stibnite.
- To: every workstation job in a catalogue is done natively on either laptop, or is recorded as darwin by nature or served from stibnite remotely.
- Reason: either laptop can be the daily driver.
- Impact: non-breaking; pyrite gains configuration and stibnite's behaviour is preserved.

**Remote-login identity**
- From: stibnite logs in through the Bitwarden SSH agent, which offers 19 vault keys to every host; pyrite's interactive account has no identity at all.
- To: the Bitwarden vault serves interactive SSH login on both laptops, with one pinned key per host; on pyrite, nixpkgs Bitwarden Desktop is the only agent and unlocks by YubiKey touch through polkit; commit signing uses no agent, as the separate signing change decides.
- Reason: pyrite reaches every host, including stibnite, without exceeding any host's `MaxAuthTries`, while stibnite keeps Apple's ssh and Touch ID.
- Impact: pyrite's and stibnite's closures only; no authorized key changes.

**Declared share of stibnite**
- From: stibnite's imperative layer (per-keyboard modifier mappings, Raycast hotkeys, unmanaged applications, login items, pmset values) is undeclared and uncounted.
- To: inventory items are counted by declaration status before and after each slice, and the declared share rises.
- Reason: improve both machines, not only pyrite.
- Impact: non-breaking.

## Capabilities

### New Capabilities

- `workstation-parity` [behavioral]: either laptop serves as the operator's daily workstation for every catalogued workstation job, reaches the other and the fleet by remote shell, signs commits as the operator (unattended agents included), keeps secrets in one password vault, answers the same chord with the same intent, and the declared share of stibnite's configuration rises.
- `workstation-parity-interface` [interface]: the evaluated configuration properties that realize the decided parts: stibnite keeps Apple's ssh, agent-free commit signing, the Bitwarden agent with one pinned key per host, pyrite's Bitwarden-only agent and polkit-only touch unlock, the niri chord bindings and input settings, the certificate authorities in pyrite's trust store, the Zen and `rbw` home-manager declarations, fonts declared in Nix, and the gating of darwin-only commands.

Trust boundary of `workstation-parity-interface`: its properties hold of evaluated NixOS, nix-darwin and home-manager configurations and of the files activation delivers from them.
They do not establish that a vault or security key holds the key a public key names, that an unlock succeeds, that a host has deployed the configuration, that a window visibly occupies the region an action requests, or that a person judges the desktop's feel equivalent.
Requirements still OPEN in the decision catalogue (half-window chords, modifier semantics, Caps Lock remapping, install-mechanism policy, stibnite's reachability, state) carry no interface requirement until decided.

### Modified Capabilities

- `world-assumptions` [world]: adds designations for the parity vocabulary (daily workstation, workstation job, job catalogue, remote shell, security key, remote-login credential, commit signature, password vault, vault client, daily browser, chord, intent, window, launcher, clipboard history, parity inventory, inventory item, declaration status, declared share, certificate authority, key repeat, scroll direction, tap to click, screenshot, Downloads folder, bar, working area, fullscreen, touchpad, script, local development cluster) and adds A86 (macOS ties a privacy grant to an application's location and signature), A87 (some Bitwarden capabilities on macOS ship only in its App Store build), A88 (Apple's bundled SSH client has no built-in FIDO provider, and an external provider is loadable), A89 (pyrite has no fingerprint reader) and A90 (on macOS only Apple's SSH client reaches hosts over ZeroTier's feth interfaces).

`graphical-desktop-session` is not modified: its requirements govern which desktop a person gets and suspend behaviour, and this change states chords and input feel separately.

## Impact

Code, by slice: `modules/home/core/{ssh,bitwarden}.nix`, `modules/lib/bitwarden-socket-path.nix`, `modules/machines/nixos/pyrite/u2f-keys`, a new ssh-identity module, `modules/home/niri/default.nix`, `modules/home/zen-browser/default.nix`, `flake.nix` and `flake.lock` (Zen input), `modules/home/development/{zed/default.nix,fonts.nix}`, `modules/darwin/homebrew.nix`, `modules/darwin/system-defaults/*.nix`, `modules/machines/{nixos/pyrite,darwin/stibnite}/default.nix`, `modules/home/tools/commands/{system/dnsreset.nix,network/zerotier-join.sh}`, and focused checks under `modules/checks/`.
Hosts whose closures change at their next deploy: pyrite and stibnite.
New flake input: `0xc000022070/zen-browser-flake`, replacing `youwen5/zen-browser-flake`.
No Linear binding is created; binding is deferred.
