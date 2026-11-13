## Context

stibnite is a nix-darwin aarch64-darwin MacBook and the operator's daily driver.
pyrite is a NixOS x86_64-linux Intel MacBookPro14,1 running niri with DankMaterialShell, with 2 cores, 4 threads and 16 GiB.
Both machines compose the same `crs58` home-manager aggregates (`cameron` is an alias of `crs58`, `modules/home/users/aliases.nix:22`), so the shared layer already evaluates for pyrite.
The gap lies in what sits outside that layer: stibnite's nix-darwin system surface (Homebrew, `system.defaults`, trust stores, Colima) and its imperative layer.

The repository-declared inventory is `logs/parity/parity-inventory.md`.
The imperative layer was probed on 2026-11-13 (`logs/parity/imperative-probe-20261113-132429.log`): three per-keyboard modifier mappings, sixteen unmanaged applications in `/Applications`, six login items (Raycast, BetterDisplay, Handy, Google Drive, Itsycal, Bitwarden), one user launch agent not from Nix, seventeen changed system hotkeys, three text replacements, Raycast's own database, and pmset values.
The SSH matrix (`logs/parity/ssh-matrix-20261113-133443.log`) shows pyrite reaching no host: its agent holds no identities and `~/.ssh` holds only `config`.
Raycast's exported hotkeys (`logs/parity/raycast-hotkeys.json`) are the global Command+Space hotkey and three window-management hotkeys: left half, maximize and right half, each on Command+Option.

Observed divergences that the slices close:

- pyrite's niri touchpad sets `natural-scroll = true` (`modules/home/niri/default.nix:16`), while stibnite sets natural scrolling off (`modules/darwin/system-defaults/nsglobaldomain.nix`).
- The fleet-wide key list is `flake.users.crs58.meta.sshKeys` (`modules/home/users/crs58/meta.nix:10`), consumed by `modules/system/admins.nix:20`, `modules/clan/inventory/services/users/cameron.nix:50` and `modules/machines/darwin/stibnite/default.nix:132`; it holds one unlabelled `ssh-ed25519` key and two phone keys.
- Git signing on stibnite uses the Bitwarden agent's public key (`modules/home/development/git.nix:27-34`, commit `3cd8189f8`); on Linux it uses a passphrase-less private key file from sops, so unattended agents can sign (commits `1f5307618`, `f22380648`), and pyrite's interactive account holds no such key.
- stibnite's Nix OpenSSH is withheld on purpose: Nix OpenSSH's BSD sockets cannot route over ZeroTier's feth interfaces, while Apple's ssh uses Network.framework (`modules/home/security/tools.nix:21-22`).
- stibnite's Bitwarden SSH agent currently offers 19 keys, and Bitwarden's agent tries every vault key in turn with no per-host selection, against sshd's default `MaxAuthTries` of 6 (<https://bitwarden.com/help/about-ssh/>, "Agent limitations").
- pyrite's Zen comes from `youwen5/zen-browser-flake` as a bare package (`modules/home/zen-browser/default.nix`); stibnite's comes from the `zen` cask.
- `programs.zed-editor.package = null` on every platform (`modules/home/development/zed/default.nix:17`), so pyrite has Zed's configuration but no binary.

## Goals / Non-Goals

**Goals:**

- Either laptop serves as the daily driver, with the other reached over SSH.
- Every workstation job is implemented natively per OS or recorded as darwin by nature or served remotely.
- The declared share of stibnite's configuration rises, measured by counting inventory items by declaration status before and after each slice.
- Each slice ships as an independent pull request that leaves both machines working.

**Non-Goals:**

- Nix-built macOS applications as an end in themselves.
- Homebrew, launchd-shaped services or macOS mechanisms on Linux.
- The ZSA keyboard on pyrite; the built-in keyboard comes first.
- Deciding the OPEN catalogue entries inside this change; each is decided at the start of the slice that needs it.
- Activation or deployment; every slice's activation is a separate operator act.

## Decisions

### D1: one module per capability, with per-OS implementations

- **Choice**: Each workstation job is one first-party capability module whose Darwin and Linux implementations sit side by side, selected once by platform inside that module.
- **Rationale**: Principle 6 forbids scattering `isDarwin` across unrelated modules; one module per job keeps a job's two implementations reviewable together.
- **Alternatives considered**: per-OS module trees duplicate the job's intent and drift apart; inline platform conditionals in every consumer are the scattering principle 6 forbids.
- **Boundary**: first-party source; no vendored module changes.

### D2: installation and configuration are counted separately

- **Choice**: Every inventory item carries a declaration status on two axes, installation and configuration, each one of `declared`, `imperative` or `not applicable`.
  The declared share is the number of declared axis values over the number of applicable ones, counted for stibnite before and after each slice.
- **Rationale**: Principle 2: a declared cask with hand-set preferences is half-declared, and counting it as fully declared would hide the debt.
- **Alternatives considered**: a single per-item flag cannot express a declared install with imperative configuration.
- **Boundary**: source versus delivered: an item is declared when its value is in this repository and delivered by activation, not when it happens to match on a running machine.

### D3: install mechanisms, by OS

- **Choice**: On macOS, any declared mechanism the constraints allow, with Homebrew casks and the Mac App Store kept where TCC grants, App Store-only capabilities, auto-updaters or licensing require them.
  On Linux, nixpkgs and home-manager modules first, then binary derivations under `pkgs/by-name/*-bin` (as with `omnigraph`) where source builds are uncached and costly, then nix-flatpak with a per-application justification, then web applications where the web application is the product.
- **Rationale**: Principles 3 and 4; TCC behaviour is recorded as world assumption A86 and the Bitwarden constraint as A87.
- **Alternatives considered**: forcing Nix-built applications on macOS breaks TCC grants on every store-path change [INFERENCE from A86].
- **Status**: the bounds are DECIDED; the written per-OS policy is OPEN (Q6).
- **Boundary**: vendored versus first-party: binary derivations are first-party packaging of vendored release artifacts and must pin hashes.

### D4: launcher and clipboard history

- **Choice**: DMS launcher (`Mod+Space`, already bound) and DMS clipboard on pyrite; Raycast launcher and Raycast clipboard history on stibnite; Maccy removed in a later cleanup.
- **Status**: DECIDED.
- **Boundary**: first-party niri binds on pyrite; Raycast's configuration lives in its own database on stibnite (source-versus-delivered: not in this repository).

### D5: secrets in Bitwarden, access by role

- **Choice**: Bitwarden holds secrets.
  `rbw` gives CLI and script access on both machines with a GUI pinentry, as in `Mic92/dotfiles` `home-manager/desktop.nix:78-79`, where the pinentry is the repository's own `rbw-pinentry` package rather than a nixpkgs one.
  The Bitwarden browser extension runs in Zen on both machines; the macOS Bitwarden application stays from the Mac App Store (A87).
- **Status**: DECIDED; which GUI pinentry each OS uses is a detail of the slice.
- **Boundary**: vendored versus first-party: `rbw` and its home-manager module are vendored from nixpkgs and home-manager; any pinentry wrapper is first-party.

### D6: SSH identity and signing — OPEN pending a spike

- **Withdrawn choice**: cross-enrolled YubiKey FIDO2 resident `ed25519-sk` keys for SSH and git signing (pyrite's primary on 32720759, stibnite's on 32720546, a second credential for each on the other's YubiKey), with stibnite using Nix OpenSSH.
  The operator withdrew it on 2026-11-13 because stibnite must keep Apple's `/usr/bin/ssh` (A90), which lacks FIDO middleware (A88) [INFERENCE: verify]; the Mac App Store Bitwarden application and its socket carry code-signing and sandbox expectations; and a touch per signature cannot serve the unattended agents that sign commits today.
- **Evidence**: Bitwarden's agent serves only Ed25519 and RSA vault keys and tries each in turn with no per-host selection (<https://bitwarden.com/help/about-ssh/>, "Supported key types" and "Agent limitations"); stibnite's agent offers 19 keys against sshd's default `MaxAuthTries` 6.
  Linux unattended signing uses a passphrase-less sops key file (`1f5307618`, `f22380648`); darwin signs through the Bitwarden agent (`3cd8189f8`).
- **Spike questions**:
  - Q2.1: can nixpkgs Bitwarden Desktop on pyrite be the SSH agent, unlocking through polkit, PAM and pam_u2f with a YubiKey touch [INFERENCE: verify]?
  - Q2.2: is nixpkgs `bitwarden-desktop` cached, and what would Flatpak's sandbox imply for the agent socket and polkit?
  - Q2.3: what single rule governs unattended signing, consistent with the signer principal of `unify-vcs-author-identity`?
  - Q2.4: does stibnite need any YubiKey SSH key at all?
  - Q2.5: should a YubiKey key exist only as a vault-independent emergency login from pyrite?
- **Consilience target**: one ssh-identity capability module replacing the `isDarwin` branches in `modules/home/core/ssh.nix`, `modules/home/core/bitwarden.nix`, `modules/home/development/git.nix` and `modules/home/development/jujutsu.nix`; one key source, the Bitwarden vault, for interactive SSH and signing on both laptops; per-platform code only where forced: the socket path (`modules/lib/bitwarden-socket-path.nix`), the ssh binary, and the unlock method (Touch ID on stibnite, polkit with pam_u2f on pyrite); and one shared rule for unattended signing.
- **Constraints any outcome honours**: stibnite keeps Apple's `/usr/bin/ssh` (A90); no host is offered more keys before the right one than its sshd's `MaxAuthTries`; unattended signing needs no touch; the signer principal stays the one `commit-author-identity-interface` fixes.
- **Status**: OPEN; the spike's answers become a decided entry here before S2's implementation tasks start.
- **Boundary**: source versus delivered: public keys are in source and reach each host's authorized keys only at that host's deploy; private keys live in the vault, a sops secret, or a security key, never in source.
  Vendored versus first-party: Bitwarden Desktop and its agent are vendored; the ssh-identity module is first-party.

### D7: window chords declared once as chord to intent

- **Choice**: One first-party table maps each chord to an intent (launcher, fill screen, left half, right half); niri's binds on pyrite are generated from it.
  Command+Space is the launcher; Command+Option+F maps to niri's `maximize-window-to-edges` [INFERENCE: the DMS bar stays visible; verify on pyrite].
  Command+Option+Left and Right are OPEN between O1 (tiled: column to 50% width, then move the column) and O2 (floating: float and size to exactly half), recommended O1 after trying both on pyrite.
- **Rationale**: Principle 5: declaring the chord once lets stibnite's side be checked against the same table, even while Raycast stores its own hotkeys.
- **Status**: launcher and fill screen DECIDED; halves OPEN.
  How stibnite consumes the table (Raycast import or documentation only) is a Phase 0 question.
- **Boundary**: first-party niri configuration; Raycast's hotkey store is outside this repository.

### D8: modifier semantics and Caps Lock

- **Choice**: none yet.
  Modifier semantics on pyrite's built-in keyboard (Command as Super for niri, or Command as Control for applications) is OPEN (Q4).
  Caps Lock to Escape on both machines is OPEN (Q5): stibnite sets it per keyboard through System Settings today, with the built-in keyboard first and the ZSA keyboard, which also swaps Left Control and Left Command on stibnite, later.
- **Boundary**: the stibnite mappings are imperative state in `com.apple.keyboard.modifiermapping.*`; any declared replacement is first-party.

### D9: shared-layer fixes

- **Choice**: pyrite trusts the caddy `.zt` root CA and the local k8s development CA that stibnite already trusts (`modules/darwin/zt-services-trust.nix`, `modules/machines/darwin/stibnite/default.nix:214-233`).
  Linux gets a Zed binary while the cask keeps supplying stibnite's.
  Fonts are declared in Nix on both machines instead of the fifteen Homebrew cask fonts.
  `dnsreset` is installed only on Darwin, and `zerotier-join`'s launchctl hint is printed only on Darwin.
- **Rationale**: each is a gap or a wrong-platform artifact in the shared layer that the inventory located with file and line.
- **Boundary**: the CA certificates are first-party values shared by both platforms' trust declarations; font packages are vendored from nixpkgs.

### D10: declarative Zen on both machines

- **Choice**: Replace the `youwen5/zen-browser-flake` input with `0xc000022070/zen-browser-flake` and use its home-manager module on both machines, including the Bitwarden extension.
- **Rationale**: Principle 5: what pyrite needs declared is declared for stibnite too.
- **Open detail**: whether the module installs Zen on Darwin or only configures a cask-installed Zen depends on the TCC findings of Phase 0 and on the module's Darwin support [INFERENCE: unverified; acquire the source before deciding].
- **Boundary**: vendored versus first-party: the module is vendored and pinned; profile, policy and extension settings are first-party.

### D11: desktop behaviour

- **Choice**: Translate stibnite's `InitialKeyRepeat` 15 and `KeyRepeat` 2 (macOS units of 15 ms, so 225 ms delay and a 30 ms interval) to niri `repeat-delay` 225 and `repeat-rate` 33.
  Natural scrolling is off on both, which changes pyrite's current `natural-scroll = true`.
  Tap to click stays on.
  Screenshots go to `~/Downloads` on both.
  stibnite's 28 Dock persistent applications are compared with DMS pinned applications.
- **Boundary**: first-party niri and DMS settings on pyrite; nix-darwin `system.defaults` on stibnite already declares its side.

### D12: per-application triage

- **Choice**: Each GUI application is placed in one bucket: share as-is; same application with Linux packaging; a different tool for the same job; no good Linux equivalent, handled by a binary derivation or by using stibnite remotely; or darwin by nature, recorded so nobody ports it.
- **Rationale**: Principle 1, applied per application, with Phase 0 usage data deciding which applications are worth a slot.

### D13: later sub-projects

Containers and VMs run natively on Linux rather than through a Colima-shaped VM.
Backups are declared on both machines.
State comes last (Q8, recommended in scope).
Each sub-project opens with its own decision record before implementation.

## Risks / Trade-offs

- [Risk] Any change to the operator's authorized keys changes every host's closure, and a host that has not deployed still refuses a new key → Mitigation: keep the existing key until each host's deploy record shows the new closure, and prove login from both laptops before retiring anything.
- [Risk] An agent offering many keys exhausts `MaxAuthTries` before the right key is tried → Mitigation: the spike's design selects keys per host or reduces the offered set, and S2's acceptance includes a login to every host.
- [Risk] `maximize-window-to-edges` may be absent from the pinned niri or may cover the DMS bar → Mitigation: verify the action against the pinned niri and observe it on pyrite before closing S3.
- [Risk] Replacing the Zen input changes pyrite's browser package and may lose the existing profile → Mitigation: back up the profile directory before activation; profile state is in scope only with Q8.
- [Risk] Moving casks or App Store applications to other mechanisms invalidates TCC grants (A86) → Mitigation: Phase 0 records each kept application's grants before any mechanism changes.
- [Trade-off] Raycast's hotkeys stay in Raycast's database, so stibnite's chord side may remain imperative → accepted until Phase 0 shows a declared import path.
- [Trade-off] O1 tiled halves differ from Raycast's exact halves when other columns exist → accepted pending the operator's trial of both options.

## Migration Plan

Slices ship in order S1, S2, S3, then the sub-projects, each as one pull request.
Every slice is evaluated before merge; x86_64-linux builds run on magnetite, and aarch64-darwin attributes are evaluated only, built at the operator's activation on stibnite.

If S2's decided design changes the operator's authorized keys, its deployment order matters because it edits a shared list that every host's closure reads: each host authorizing the operator's keys (cinnabar, electrum, argentum, rosegold, galena, scheelite, magnetite, pyrite, stibnite, blackphos) accepts a new key only once it deploys.
Deploy the hosts reachable today first, then pyrite and stibnite, and confirm each host's deploy record before relying on a new key there; hosts provisioned only on demand (electrum, galena, scheelite) pick it up at their next provisioning.

Rollback for every slice is reverting its pull request and redeploying the affected hosts; S2 keeps the existing key authorized until login from both laptops is proven, so a rollback never locks the operator out.

## Open Questions

- Q3: half-window chords, O1 or O2 (recommended O1, decided on pyrite).
- Q4: modifier semantics on pyrite's built-in keyboard (no recommendation recorded).
- Q5: Caps Lock to Escape mechanism on both machines (no recommendation recorded).
- Q6: install-mechanism policy per OS (no recommendation recorded).
- Q7: stibnite as an always-reachable home machine, with pmset AC sleep 0, womp 1, battery sleep 1, and closed-lid behaviour unknown [INFERENCE] (no recommendation recorded).
- Q8: state in scope (recommended yes, last).
- Q2.1 to Q2.5: the SSH identity and signing spike (D6).
- sudo through pam_u2f on pyrite (OPEN) and rbw unlock by YubiKey [INFERENCE: verify].
- Retiring the unlabelled `ssh-ed25519` key after S2 (operator confirmation).
- How stibnite consumes the chord table (Phase 0).
