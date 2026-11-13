# Decision capture: workstation parity between pyrite and stibnite

The operator settled the inputs below in conversation before this change was scaffolded.
This file records them as given; the `superpowers:brainstorming` dialogue was not rerun, matching the decision-capture form of the sibling pyrite changes.
Status words are the operator's: DECIDED, OPEN with a recorded recommendation where one was given, and [INFERENCE] for claims nobody has verified yet.

## Background

stibnite (nix-darwin, aarch64-darwin MacBook) is the daily driver.
pyrite (NixOS, x86_64-linux, Intel MacBookPro14,1, niri with DankMaterialShell, 2 cores and 4 threads, 16 GiB) has a working desktop session but lacks most of what daily work on stibnite relies on.
The program brings pyrite to practical daily-driver parity, so that either laptop can be carried while the other is reached over SSH.
Along the way, stibnite's own imperative configuration becomes more declarative.

Evidence gathered for this capture, all under the ignored `logs/parity/` directory:

- `parity-inventory.md` lists the repository-declared surface of both machines with file and line citations.
- `imperative-probe-20261113-132429.log` lists stibnite's imperative layer: per-keyboard modifier mappings set in System Settings, sixteen applications in `/Applications` not installed by Homebrew, the App Store or Nix, six login items, one user launch agent not from Nix, seventeen changed system hotkeys, three text replacements, Raycast's data, and pmset values.
- `ssh-matrix-20261113-133443.log` shows pyrite reaching no host: its agent holds no identities, `~/.ssh` holds only `config`, and every reachable host refuses with `Permission denied (publickey)`.
- `raycast-hotkeys.json` shows Raycast's global hotkey (Command+Space) and three window-management hotkeys as the only custom hotkeys.

## Goal

Either laptop can be the daily driver, with the other reached over SSH.
The fraction of stibnite's configuration that is declarative rises, measured before and after by counting inventory items by declaration status.

## Principles

1. Match the job, not the tool. Each inventory item is a job (launch apps, snap windows, manage clipboard, hold secrets, and so on) implemented natively per OS.
2. Installation and configuration are separate axes. A cask declared in nix-darwin is a declarative install; imperative application configuration is the debt.
3. On macOS, items are declared by whatever mechanism the constraints allow. Homebrew casks and the Mac App Store remain legitimate where TCC privacy grants tie to stable application paths and signatures, where a capability exists only in the App Store build (Bitwarden's, for example), or where auto-updaters or licensing require them. Nix-built applications on macOS are not a goal in themselves.
4. On Linux, prefer nixpkgs packages and home-manager modules; use binary derivations where source builds are uncached and costly (as in `pkgs/by-name/*-bin` and `omnigraph`); use Flatpak through nix-flatpak only with a per-application justification; use web applications where the web application is the product.
5. Improve both ways. Where pyrite needs something declared, declare it for stibnite too: Zen through the home-manager module of `0xc000022070/zen-browser-flake` on both, and window chords declared once as chord-to-intent.
6. Do not port macOS mechanisms to Linux: no Homebrew on Linux, no launchd-shaped services, and no scattered `isDarwin` conditionals. One module per capability carries per-OS implementations.

## Decision catalogue

### Q1 Launcher and clipboard — DECIDED

The launcher is the DMS launcher on pyrite, where `Mod+Space` already works, and Raycast on stibnite.
Clipboard history is DMS's clipboard on pyrite.
On stibnite, Maccy is redundant with Raycast's clipboard history and is removed in a later cleanup.

### Q2 Bitwarden roles — DECIDED; SSH identity — OPEN pending a spike

Bitwarden holds secrets.
`rbw`, the Rust Bitwarden CLI, gives command-line and script access on both machines with a GUI pinentry, as in `Mic92/dotfiles` `home-manager/desktop.nix:78-79`.
The Bitwarden browser extension runs in Zen on both machines.
The macOS Bitwarden application stays installed from the Mac App Store.

An earlier decision moved SSH authentication and git signing to cross-enrolled YubiKey FIDO2 resident `ed25519-sk` keys (as in `Mic92/dotfiles` `darwinModules/openssh.nix:6`), each machine's credential on its primary YubiKey (pyrite 32720759, stibnite 32720546) and a second on the other machine's, mirroring pyrite's two systemd-fido2 LUKS tokens in keyslots 1 and 2.
The operator withdrew that decision on 2026-11-13; the SSH identity is OPEN pending an SSH-identity spike, on this evidence:

- Bitwarden's SSH agent serves only Ed25519 and RSA keys from the vault and tries every vault key in turn, with no per-host selection (<https://bitwarden.com/help/about-ssh/>, "Supported key types" and "Agent limitations"); stibnite's agent currently offers 19 keys, against sshd's default `MaxAuthTries` of 6.
- stibnite must keep Apple's `/usr/bin/ssh`: Nix OpenSSH's BSD sockets cannot route over ZeroTier's feth interfaces, while Apple's ssh uses Network.framework (`modules/home/security/tools.nix:21-22`); the Mac App Store Bitwarden application and its socket also carry code-signing and sandbox expectations.
- Apple's `/usr/bin/ssh` lacks built-in FIDO middleware [INFERENCE: verify], so a YubiKey SSH key on stibnite would need a client stibnite cannot use.
- Unattended agents sign commits: Linux signs with a passphrase-less sops key file (commits `1f5307618`, `f22380648`), and darwin signs through the Bitwarden agent (`3cd8189f8`); a hardware key that needs a touch per signature cannot sign unattended.

Spike questions:

- Q2.1: Can Bitwarden Desktop on pyrite (from nixpkgs) serve as the SSH agent, unlocking through system authentication (polkit, then PAM, then pam_u2f with a YubiKey touch)? [INFERENCE: verify]
- Q2.2: Is nixpkgs `bitwarden-desktop` cached, and what would Flatpak's sandbox imply for the agent socket and polkit?
- Q2.3: What is the one rule for unattended signing, consistent with the signer principal `unify-vcs-author-identity` fixes?
- Q2.4: Does stibnite need any YubiKey SSH key at all?
- Q2.5: Should a YubiKey key exist only as a vault-independent emergency login from pyrite?

Consilience target: one ssh-identity capability module replacing the scattered `isDarwin` branches in `core/ssh.nix`, `core/bitwarden.nix`, `development/git.nix` and `development/jujutsu.nix`; one key source, the Bitwarden vault, for interactive SSH and signing on both machines; per-platform code only where forced (the socket path through `modules/lib/bitwarden-socket-path.nix`, the ssh binary, and the unlock method, Touch ID or polkit with pam_u2f); and one shared rule for unattended signing.

### Q3 Window chords — partly DECIDED, one OPEN

Raycast's hotkeys are the only custom hotkeys besides the global one.
Command+Space opens the launcher (DECIDED).
Command+Option+F is Raycast Window Management "maximize", which fills the screen without entering fullscreen; on pyrite it maps to niri's `maximize-window-to-edges` (DECIDED) [INFERENCE: the DMS bar stays visible; verify on pyrite].
Command+Option+Left and Command+Option+Right put the window on the left or right half (OPEN between two options):

- O1, tiled: set the column to 50% width and move the column left or right.
- O2, floating: float the window and size and position it to exactly half the output.

The recommendation is O1, to be decided by trying both on pyrite.

### Q4 Modifier semantics on pyrite's built-in keyboard — OPEN

The choice is between Command acting as Super for niri and Command acting as Control for applications.
No recommendation was recorded.

### Q5 Caps Lock to Escape on both machines — OPEN

stibnite currently remaps Caps Lock to Escape imperatively, per keyboard, through System Settings.
The built-in keyboard comes first.
A ZSA Moonlander-class keyboard follows later; on stibnite it currently swaps Left Control and Left Command imperatively.
No recommendation was recorded.

### Q6 Install-mechanism policy per OS — OPEN

The principles above bound the policy; the per-OS policy itself is not yet written.
No recommendation was recorded.

### Q7 stibnite as an always-reachable home machine — OPEN

stibnite's current pmset values are AC sleep 0 and womp 1, with battery sleep 1.
Closed-lid behaviour is unknown [INFERENCE].
No recommendation was recorded.

### Q8 State in scope — OPEN

The recommendation is yes, handled last.

## Phases and slices

Phase 0 is discovery: which applications are actually used, which macOS TCC grants exist, the per-application settings of kept applications, Linux availability and quality per application, and SSH authentication per host.

Phase 1 has three slices:

- S1: pyrite dispatches builds to magnetite (in progress elsewhere).
- S2: an SSH identity for both machines, authorized fleet-wide, so pyrite reaches every host including `stibnite.zt`; originally a YubiKey identity, now a spike on Q2.1 to Q2.5 followed by the decided slice.
- S3: window chords.

Sub-projects from the earlier triage follow:

- Shared-layer fixes: pyrite trusts the caddy `.zt` root CA and the local k8s development CA, which stibnite trusts and pyrite does not; a Zed binary on Linux, since `programs.zed-editor.package = null` everywhere; fonts declared in Nix on both machines instead of fifteen Homebrew cask fonts; gating the darwin-only `dnsreset` command and the `zerotier-join` launchctl hint.
- Declarative Zen on both machines.
- Desktop behaviour: key repeat 15/2 on macOS (225 ms delay, 30 ms interval) translated to niri `repeat-delay` 225 and `repeat-rate` 33; natural scrolling off; tap to click; screenshots to `~/Downloads`; Dock persistent applications compared with DMS pinned applications.
- GUI application triage per application, into five buckets: share as-is; same application with Linux packaging; a different tool for the same job; no good Linux equivalent, handled by a binary derivation or by using stibnite remotely; and darwin by nature, recorded so nobody ports it.
- Containers and VMs natively on Linux.
- Backups on both machines.
- State, last.

Each slice is an independently shippable pull request.

## Scope notes

The ZSA keyboard on pyrite comes later; the built-in keyboard comes first.
pyrite has no fingerprint reader, so the YubiKey fills that role where it can: sudo through pam_u2f (OPEN), unlocking a Bitwarden agent through polkit and pam_u2f (Q2.1, [INFERENCE: verify]), and rbw unlock [INFERENCE: verify].
