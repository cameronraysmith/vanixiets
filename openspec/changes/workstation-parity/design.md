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
- The fleet-wide key list is `flake.users.crs58.meta.sshKeys` (`modules/home/users/crs58/meta.nix:10`), consumed by `modules/system/admins.nix:20`, `modules/clan/inventory/services/users/cameron.nix:50` and `modules/machines/darwin/stibnite/default.nix:132`; it holds the unlabelled vault login key `…sqSGyUH+` and two phone keys.
- Before the signing change, git on stibnite signed through the Bitwarden agent (`modules/home/development/git.nix:27-34`, commit `3cd8189f8`) and Linux signed with a passphrase-less sops key file (commits `1f5307618`, `f22380648`); `separate-commit-signing-from-login`, deployed in its phase A, moved every home to a dedicated per-person clan-vars signing key signed through `agentFreeSshKeygen`.
- stibnite's Nix OpenSSH is withheld on purpose: Nix OpenSSH's BSD sockets cannot route over ZeroTier's feth interfaces, while Apple's ssh uses Network.framework (`modules/home/security/tools.nix:21-22`).
- Bitwarden's agent tries every vault key in turn with no per-host selection (<https://bitwarden.com/help/about-ssh/>, "Agent limitations"), and the vault offers 19 keys (every person's login key, host keys, CI keys) to every server, against sshd's default `MaxAuthTries` of 6 (finding F26).
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

### D5: secrets in Bitwarden's cloud, access by role

- **Choice**: Bitwarden's cloud service (bitwarden.com) holds secrets; nothing is self-hosted.
  Amended by the operator's decisions of 2026-11-16, which replace the 2026-11-13 choice of `rbw` for command-line and script access.
  Each role uses one of Bitwarden's own clients:
  - Interactive use and the SSH agent: the Bitwarden desktop application, already deployed on both laptops (D6).
  - Scripts and the command line: the official `bw` from nixpkgs (`bitwarden-cli`, already in the `security` home aggregate, `modules/home/security/tools.nix:11`) on both laptops.
    It is the only command-line vault client, and the only one the sops tooling depends on (`retire-legacy-sops-tooling`, CAM-107).
    `bw unlock` asks for the master password on the terminal, and scripts use the session it returns; it has no pinentry, so the command-line unlock is no longer required to be graphical, while the desktop application keeps the graphical unlock (Touch ID on stibnite, polkit on pyrite) for interactive and SSH use.
  - The Bitwarden browser extension runs in Zen on both machines; the macOS Bitwarden application stays from the Mac App Store (A87).
- **Rationale**: `bw` is maintained by the people who change the vault's key formats and releases every two to four weeks (cli-v2026.9.0 on 2026-09-17, cli-v2026.10.0 on 2026-10-15, cli-v2026.10.1 on 2026-10-29); it comes from the nixpkgs pin, so a broken release, such as the 2026.9.0 user-key-id backfill migration that leaves the vault locked against servers lacking its route (bitwarden/clients#23937), arrives only with a lock update.
  The desktop application already covers interactive and agent use, so no further client is needed.
- **Rejected alternative: `rbw`** (the 2026-11-13 choice, as in `Mic92/dotfiles` `home-manager/desktop.nix:78-79`):
  - Upstream `doy/rbw` is unmaintained: its last release (1.15.0) and last commit (`77464d4`) are from 2025-12-31; issue #338, "Project maintainership", has been open since 2026-05-08 with no reply from the maintainer; about six competing forks exist and none is the agreed successor.
  - Login fails with HTTP 400 when bitwarden.com triggers new-device verification (#318, open since 2026-02-21).
  - Editing an item that has its own item key re-encrypts it without that key and corrupts it (#364; fixes only in open PRs #368 and #371).
  - `rbw add` and `rbw edit` fail with HTTP 422 against Vaultwarden 1.37.4 and later (#385; fix in unmerged PR #386).
  - It parses only EncString types 2, 4 and 6 (`src/cipherstring.rs:43-90`), while Bitwarden's V2 user keys are type 7 (`COSE_ENCRYPT0_TYPE` in the Bitwarden SDK), so it would stop working if the account were upgraded to V2 keys.
  - Revisit only if a maintained successor appears, for example Bitwarden's Rust CLI in `bitwarden/sdk-internal` `crates/bw`, whose commands are today mostly `todo!()` (`main.rs:105-147`).
- **Rejected alternative: self-hosted Vaultwarden now**:
  - Vaultwarden lags the official clients: clients 2026.8.0 and later needed Vaultwarden 1.37.2, and the user-key-id route arrived only in 1.37.4 (#7693).
  - Its advisories arrive steadily: 1.37.4 fixed seven, including the High 8.1 GHSA-69q9-v8p6-xvx3, and 1.37.5 two more.
  - It adds a host, a database, TLS, SMTP, backups and monitoring, and buys nothing the fleet lacks today.
  - Self-hosting makes the vault the root of trust in a circular chain: the vault host's clan vars need its machine key, which is encrypted to admin-user, whose private key lives in the vault; a lost vault host could then be rebuilt only from the offline `&admin` sops key.
  - Revisit only if Bitwarden moves the SSH agent or SSH-key items out of its free tier or degrades them there, if the vault must be reachable only over ZeroTier, or if data residency is required.
    Then: a Vaultwarden on a NixOS clan host in the shape of clan-infra's `modules/vaultwarden.nix` (`clan.core.postgresql` with `clan.core.state` backups), with an offsite restic backup as in pinpox/nixos `modules/vaultwarden/default.nix`, deployed only after recovery with the offline `&admin` sops key has been rehearsed.
- **Evidence**: the client and server research of 2026-11-16 (rbw and `bw` issues, release dates and source lines as cited above; Vaultwarden release notes 1.37.1 to 1.37.5; the reference deployments of Mic92, clan-infra, Qubasa, pinpox and jfly).
- **Status**: DECIDED 2026-11-16.
- **Boundary**: vendored versus first-party: `bw`, the desktop application and the browser extension are vendored; the only first-party part is the package list.
  Source versus delivered: the vault's contents stay on bitwarden.com, outside this repository.

### D6: SSH identity — DECIDED 2026-11-14

- **Choice**: The Bitwarden vault holds the login keys and serves interactive SSH login on both laptops; commit signing never uses an agent (D6 defers signing entirely to `separate-commit-signing-from-login`, whose phase A is deployed).
  stibnite is unchanged: Mac App Store Bitwarden, Touch ID unlock, Apple's `/usr/bin/ssh` (A90).
  On pyrite:
  - nixpkgs `bitwarden-desktop` is in `environment.systemPackages`, because its polkit action `com.bitwarden.Bitwarden.unlock` loads only from the system profile.
  - "Unlock with system authentication" goes through polkit, with `pam_u2f` on the `polkit-1` PAM service only: control `sufficient`, `cue`, origin and appid `pam://pyrite`, authfile from the committed public enrollment `modules/machines/nixos/pyrite/u2f-keys` (YubiKey 32720759; 32720546 to be appended as backup).
  - The `polkit-agent-helper@` sandbox override is mirrored from nixpkgs' global-u2f branch, which nixpkgs applies only when u2f is enabled globally.
  - Login and the DMS lock screen stay password-only.
  - Bitwarden's socket is the only SSH agent: home-manager's `ssh-agent` and `gcr-ssh-agent` are off, through the `programs.bitwarden-ssh-agent.enable` option (default `isDarwin`), now in `modules/home/core/ssh-identity.nix`, which replaced `bitwarden.nix` in #3872.
  - Keys are pinned per host with `IdentitiesOnly`: `*.zt` to the login key `…sqSGyUH+` (`~/.ssh/bitwarden-login.pub`), `github.com` to the RSA authentication key `…AIz7rQ==` (`~/.ssh/bitwarden-github.pub`), since GitHub holds the login key only as a signing key.
  - pyrite imports srvos's `shared/common/well-known-hosts.nix` for the GitHub, GitLab and sourcehut host keys; it imports no srvos profile.
- **Rationale**: one key source for login on both laptops; pyrite gets a touch unlock without a fingerprint reader (A89) and without weakening login or the lock screen; pinning is required, not optional, because the vault offers 19 keys to every server (F26); signing needs no unlock, so unattended agents sign whatever the vault's state.
- **Spike evidence**:
  - Q2.1 (2026-11-14, deployed from branch `pyrite-bitwarden-yubikey`): the YubiKey enrolled with one touch and no PIN (`logs/parity/pamu2fcfg-pyrite-32720759.out`); the vault unlocked by touch through polkit (helper ran 10:25:57–10:26:05 EST, operator confirmed); after a full logout and login the session's `SSH_AUTH_SOCK` is Bitwarden's socket; `ssh magnetite.zt` and `ssh stibnite.zt` offer only the login key through Bitwarden and authenticate; `ssh -T git@github.com` offers only the RSA key and authenticates.
  - Q2.2 to Q2.4 (`logs/parity/ssh-identity-spike-q2-q4.md`): `bitwarden-desktop` 2026.10.2 at the pin is on cache.nixos.org but not the fleet cache; its polkit action loads only through `environment.systemPackages`; a Flatpak would also need the policy installed host-side; all signing becomes unattended through a key file, with Bitwarden only for login; no host or use case needs a hardware-backed key from stibnite.
  - Q2.5, a YubiKey `sk` key as a vault-independent emergency login from pyrite: deferred, optional.
- **Withdrawn alternative (history)**: cross-enrolled YubiKey FIDO2 resident `ed25519-sk` keys for SSH and git signing (pyrite's primary on 32720759, stibnite's on 32720546, a second credential for each on the other's YubiKey), with stibnite using Nix OpenSSH.
  The operator withdrew it on 2026-11-13 because stibnite must keep Apple's `/usr/bin/ssh` (A90), which has no built-in FIDO provider, although its security key helper can load an external one (A88, verified against apple-oss-distributions/OpenSSH tag `OpenSSH-323` and stibnite's `ssh-sk-helper` entitlements); the Mac App Store Bitwarden application and its socket carry code-signing and sandbox expectations; and a touch per signature cannot serve the unattended agents that sign commits.
- **Remaining**: the reboot check (3.9).
  The backup YubiKey turned out unnecessary (3.8), and the per-host pinning on stibnite and the shared ssh-identity module landed in #3872 (3.10, 3.11).
- **Boundary**: source versus delivered: the public enrollment and the pinned public keys are in source; the private login keys stay in the vault and the YubiKey's credential on the YubiKey.
  Vendored versus first-party: `bitwarden-desktop`, `pam_u2f` and srvos's host-key list are vendored; the agent option, the PAM wiring, the sandbox override and the pins are first-party.

### D7: window chords declared once as chord to intent

- **Choice**: One first-party table maps each chord to an intent (launcher, fill screen, left half, right half); niri's binds on pyrite are generated from it.
  Command+Space is the launcher; Command+Option+F maps to niri's `maximize-window-to-edges`; the DMS bar auto-hides and, when revealed, overlays the filled window (observed on pyrite on 2026-11-14).
  Command+Option+Left and Right are O3, tiled, DECIDED on 2026-11-14: the column is set to 50% width and moved one position left or right, so two such columns share the view as a left and a right half and nothing overlaps.
  niri 26.04 has no action placing a tiled column on half of the current view, only `center-column` and `center-visible-columns`, so a tiled half is relative to its neighbour rather than a fixed half of the screen.
  O1 (50% width, moved to the first or last position of the whole strip) jumped too far, and O2 (floating on exactly half the output) left the window above the strip, where filling the screen with another window overlapped it; O1's move stays on Command+Option+Shift+Left and Right.
  Command+Option+Down (`move-window-to-tiling`) and Command+Option+Up (`switch-focus-between-floating-and-tiling`) stay bound for windows that float for other reasons.
- **Rationale**: Principle 5: declaring the chord once lets stibnite's side be checked against the same table, even while Raycast stores its own hotkeys.
- **Status**: launcher, fill screen and halves DECIDED and confirmed on pyrite on 2026-11-14.
  How stibnite consumes the table (Raycast import or documentation only) is a Phase 0 question.
- **Boundary**: first-party niri configuration; Raycast's hotkey store is outside this repository.

### D8: modifier semantics and Caps Lock

- **Choice**: Caps Lock sends Escape on pyrite's built-in keyboard through niri's `input.keyboard.xkb.options = "caps:escape"`, matching stibnite's one-way mapping (DECIDED 2026-11-14; macOS can remap Caps Lock but not Escape, so stibnite has no swap to match).
  Declaring stibnite's side (nix-darwin `system.keyboard.remapCapsLockToEscape`) waits on a check that it, applied to every keyboard through `hidutil`, does not interfere with the ZSA keyboard's Left Control and Left Command swap, which stibnite also sets per keyboard.
  Modifier semantics on pyrite's built-in keyboard: Command stays Super for niri, and applications keep Control for copy and paste with Control+Shift in terminals (DECIDED 2026-11-16, Q4).
  Rejected: Command as Control for applications through an application-aware remapper (Toshy, xremap or keyd), which needs a niri-aware focused-window query for the terminal exception and re-homing niri's Super binds, for muscle-memory parity alone.
- **Boundary**: the stibnite mappings are imperative state in `com.apple.keyboard.modifiermapping.*`; any declared replacement is first-party.

### D9: shared-layer fixes

- **Choice**: pyrite trusts the caddy `.zt` root CA and the local k8s development CA that stibnite already trusts (`modules/darwin/zt-services-trust.nix`, `modules/machines/darwin/stibnite/default.nix:214-233`).
  Linux gets a Zed binary, nixpkgs' FHS variant (`zed-editor.fhs`) so the language servers and agent binaries Zed downloads run on NixOS, while the base cask list keeps supplying every Mac's.
  Zed's command is `zeditor` on every workstation: nixpkgs' package provides it on Linux, and the darwin aspect `zeditor` (`modules/darwin/zeditor.nix`), which `darwin-workstation` imports, installs a `zeditor` command that execs the bundle's `Contents/MacOS/cli`; Linux cannot use the name `zed`, because ZFS's event daemon `zed` is on pyrite's system `PATH`, and the cask's own `zed` link on the Macs stays as Homebrew installs it.
  Zed's AI features are on with edit predictions off (`disable_ai = false` written out, `edit_predictions.provider = "none"`), and every home that installs Claude Code declares Zed's Claude Agent as the bare registry entry (`agent_servers.claude-acp`, type `registry`), so the adapter runs its bundled Claude.
  The entry sets no `CLAUDE_CODE_EXECUTABLE`: with it set, the adapter passes a session's MCP servers, their `env` and `headers` included, on a command line other accounts of the machine can read.
  Fonts are declared in Nix on both machines instead of the fifteen Homebrew cask fonts.
  `dnsreset` is installed only on Darwin, and `zerotier-join`'s launchctl hint is printed only on Darwin.
- **Rationale**: each is a gap or a wrong-platform artifact in the shared layer that the inventory located with file and line.
- **Boundary**: the CA certificates are first-party values shared by both platforms' trust declarations; font packages are vendored from nixpkgs.
- **Delta, decided 2026-11-27**: Delta, Zed Industries' agent workspace application (bundle `com.zed-industries.delta`), is declared on pyrite as `pkgs.zed-delta`, an overlay over the `delta` flake input (`github:zed-industries/delta-nix`), and on stibnite, rosegold, argentum and blackphos by the darwin aspect `zed-delta` (`modules/darwin/zed-delta.nix`), which `darwin-workstation` imports, so every workstation Mac has it and no host body repeats the decision.
  The aspect adds the `zed-delta` cask with its binary link suppressed (`args.no_binaries`) and installs a `zed-delta` command that execs the bundle's `Contents/MacOS/delta`, so the command is `zed-delta` on every workstation.
  The cask would otherwise link `bin/delta`, the name of the git diff pager; jj's `ui.pager` and lazygit's pager call that pager by store path, as git's `programs.delta` already does, so no `PATH` order can substitute another `delta`.
  Zed's package rule is unchanged: null on Darwin, where the base cask list supplies Zed on every Mac.
  Boundary: the cask's application is vendored and updates itself (`auto_updates`), so Homebrew's bundle install adopts an existing hand-installed `/Applications/Delta.app` without comparing versions, and the cleanup mode `uninstall` never zaps its data under `~/Library/Application Support/delta`; the command, the suppression and the overlay are first-party.

### D10: declarative Zen on both machines

- **Choice**: Replace the `youwen5/zen-browser-flake` input with `0xc000022070/zen-browser-flake` and use its home-manager module, including the Bitwarden extension; pyrite first, with stibnite decided after the operator has used pyrite's declared Zen (decided 2026-11-15).
- **Rationale**: Principle 5: what pyrite needs declared is declared for stibnite too.
- **Shape on pyrite**: one profile declared at its existing directory, so Zen keeps it; stibnite's URL bar CSS and deliberate preferences in `userChrome`/`settings`; its custom shortcuts and search engines; extensions through `policies.ExtensionSettings` with `normal_installed`. Spaces, pins and essentials stay with Sync; `extensions.settings` is avoided because it disables `ExtensionStorageIDB` profile-wide.
- **Darwin, if adopted**: the module can configure the cask's Zen.app with `package = null`, and writes policies to the `app.zen-browser.zen` defaults domain, leaving the signed bundle untouched.
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
- [Risk] A host pattern without a pin falls back to offering all 19 vault keys and exhausts `MaxAuthTries` (F26) → Mitigation: pin every host pattern the operator logs in to, on both laptops, and check the pins in `pyrite-desktop`.
- [Risk] After Bitwarden restarts, the touch unlock is unavailable until one master-password unlock, so a reboot leaves pyrite without an agent until the operator types it → Mitigation: the reboot check confirms the sequence; accepted as Bitwarden's documented behaviour.
- [Risk] A single enrolled YubiKey is a single point of failure for touch unlock on pyrite → Mitigation: append YubiKey 32720546 to `u2f-keys`; the master password remains a fallback.
- [Risk] `maximize-window-to-edges` may be absent from the pinned niri or may cover the DMS bar → resolved: niri 26.04 has the action, and the auto-hiding DMS bar overlays the filled window when revealed (2026-11-14).
- [Risk] Replacing the Zen input changes pyrite's browser package and may lose the existing profile → Mitigation: back up the profile directory before activation; profile state is in scope only with Q8.
- [Risk] Moving casks or App Store applications to other mechanisms invalidates TCC grants (A86) → Mitigation: Phase 0 records each kept application's grants before any mechanism changes.
- [Trade-off] Raycast's hotkeys stay in Raycast's database, so stibnite's chord side may remain imperative → accepted until Phase 0 shows a declared import path.
- [Trade-off] A tiled half is relative to the neighbouring column, not a fixed half of the screen like Raycast's → accepted: floating halves overlapped a filled window, and tiled halves keep the strip in charge of every window.

## Migration Plan

Slices ship in order S1, S2, S3, then the sub-projects, each as one pull request.
Every slice is evaluated before merge; x86_64-linux builds run on magnetite, and aarch64-darwin attributes are evaluated only, built at the operator's activation on stibnite.

S2's decided design changes no authorized keys, so it changes only pyrite's closure (and stibnite's when its pins land).
If a later decision changes the operator's authorized keys, its deployment order matters because it edits a shared list every host's closure reads: each host authorizing the operator's keys (cinnabar, electrum, argentum, rosegold, galena, scheelite, magnetite, pyrite, stibnite, blackphos) accepts a new key only once it deploys; deploy the hosts reachable today first, then pyrite and stibnite, and confirm each deploy record before relying on the key there.

Rollback for every slice is reverting its pull request and redeploying the affected hosts; reverting S2 on pyrite restores home-manager's `ssh-agent` and `gcr-ssh-agent`.

## Open Questions

- Q3: half-window chords: DECIDED on 2026-11-14, tiled (O3), after O2 (floating) overlapped filled windows; O1's move stays on the shifted chords.
- Q4: modifier semantics on pyrite's built-in keyboard — resolved 2026-11-16 in D8: Command stays Super for niri and applications keep Control; the Command-as-Control remapper is rejected.
- Q5: Caps Lock to Escape: DECIDED for pyrite on 2026-11-14 (`caps:escape`); stibnite's declaration waits on the ZSA check.
- Q6: install-mechanism policy per OS (no recommendation recorded).
- Q7: stibnite as an always-reachable home machine, with pmset AC sleep 0, womp 1, battery sleep 1, and closed-lid behaviour unknown [INFERENCE] (no recommendation recorded).
- Q8: state in scope (recommended yes, last).
- Q2.5: a YubiKey `sk` key as a vault-independent emergency login from pyrite (deferred, optional).
- sudo through pam_u2f on pyrite (OPEN).
- How stibnite consumes the chord table (Phase 0).
