## 1. Phase 0: discovery and baseline

- [ ] 1.1 Build the parity inventory with a declaration status on each item's installation and configuration sides, from `logs/parity/parity-inventory.md` and `logs/parity/imperative-probe-20261113-132429.log` — verify: an inventory file in which every item cites its source and carries two status values from `declared`, `imperative` or `not applicable`.
- [ ] 1.2 Count stibnite's baseline declared share from that inventory — verify: the count and the command or query that produced it, recorded with the inventory's revision.
- [ ] 1.3 Record which GUI applications the operator uses, from login items, Dock persistent applications and the operator's account of daily use — verify: a usage column on each application item, with the operator's confirmation recorded.
- [ ] 1.4 Record the macOS TCC grants each kept application holds on stibnite — verify: a per-application grant list read from System Settings or the TCC database, attached to the inventory.
- [ ] 1.5 Record the per-application settings each kept application holds imperatively — verify: a per-application list of settings and where each is stored.
- [ ] 1.6 Record Linux availability and quality per application: nixpkgs package or home-manager module, binary release, Flatpak, web application, or none — verify: one row per application with `nix eval` of `meta.available` on x86_64-linux where a nixpkgs package exists.
- [ ] 1.7 Record SSH authentication per host: which account, which authorized keys, and how stibnite's sshd reads them given srvos's `AuthorizedKeysFile none` drop-in — verify: an SSH matrix like `logs/parity/ssh-matrix-20261113-133443.log` with each refusal explained.
- [ ] 1.8 Seed the job catalogue from the inventory, one row per workstation job with each laptop's implementation or its darwin-by-nature or remote disposition — verify: every application and desktop item of the inventory maps to a job row.
- [ ] 1.9 Determine how stibnite can consume the chord table (Raycast import, or documentation only) — verify: a recorded finding with the Raycast mechanism tested or ruled out.
- [ ] 1.10 Acquire `0xc000022070/zen-browser-flake` into the reference tree and record its home-manager module's Darwin support — verify: the module source read at a pinned revision, with Darwin install support stated from that source.

## 2. S1: pyrite dispatches builds to magnetite (in progress elsewhere)

- [ ] 2.1 pyrite dispatches x86_64-linux builds to magnetite — verify: the S1 slice's own acceptance, recorded here by reference once its pull request merges.

## 3. S2: SSH identity — spike, then the decided slice

- [x] 3.1 Q2.1: install nixpkgs Bitwarden Desktop on pyrite and test it as the SSH agent, unlocking through polkit, PAM and pam_u2f with a YubiKey touch — verify: deployed from branch `pyrite-bitwarden-yubikey` on 2026-11-14; YubiKey 32720759 enrolled with one touch and no PIN (`logs/parity/pamu2fcfg-pyrite-32720759.out`); vault unlocked by touch through polkit (helper ran 10:25:57–10:26:05 EST, operator confirmed); after logout and login `SSH_AUTH_SOCK` is Bitwarden's socket.
- [x] 3.2 Q2.2: record whether nixpkgs `bitwarden-desktop` is substitutable for the pinned nixpkgs, and what Flatpak would imply for the agent socket and polkit — verify: `logs/parity/ssh-identity-spike-q2-q4.md` §Q2: 2026.10.2 output `gh4wj912…` present on cache.nixos.org, 404 on the fleet cache; the polkit action loads only through `environment.systemPackages`, for the package and for a Flatpak alike.
- [x] 3.3 Q2.3: write the one rule for unattended signing — verify: `logs/parity/ssh-identity-spike-q2-q4.md` §Q3 recommends key-file signing only; the operator approved it as `separate-commit-signing-from-login` (dedicated per-person clan-vars signing key, `agentFreeSshKeygen`), deployed in its phase A.
- [x] 3.4 Q2.4: decide whether stibnite needs any YubiKey SSH key — verify: `logs/parity/ssh-identity-spike-q2-q4.md` §Q4 finds no host or use case needing one and Apple's ssh built without a built-in FIDO library (checked in Apple's source, not by a login attempt); stibnite stays unchanged per D6.
- [ ] 3.5 Q2.5: decide whether a YubiKey `sk` key exists as a vault-independent emergency login from pyrite — deferred and optional — verify: a recorded decision in design.md D6 when taken up.
- [x] 3.6 Record the decided SSH identity design as a DECIDED D6 entry, with per-host key pinning — verify: design.md D6 marked DECIDED 2026-11-14; the interface spec states the agent, pinning, polkit-only touch unlock and agent-free signing requirements; `openspec validate workstation-parity --strict` exits 0.
- [x] 3.7 On pyrite, install `bitwarden-desktop` system-wide, confine `pam_u2f` to `polkit-1` with the mirrored `polkit-agent-helper@` sandbox override, make Bitwarden the only SSH agent through `programs.bitwarden-ssh-agent.enable`, pin `*.zt` and `github.com`, and import srvos's well-known hosts — verify: deployed from branch `pyrite-bitwarden-yubikey`; the `pyrite-desktop` assertion "polkit unlocks Bitwarden by YubiKey touch" and `checks.pyrite-bitwarden-unlock`; `ssh magnetite.zt` and `ssh stibnite.zt` offer only the login key and authenticate, and `ssh -T git@github.com` offers only the RSA key and authenticates.
- [x] 3.8 ~~Enroll backup YubiKey 32720546 on pyrite~~ Not needed, decided by the operator on 2026-11-14: `polkit-1` stacks `pam_u2f` and `pam_unix` both as `sufficient`, so without the enrolled YubiKey every polkit prompt falls back to the account password, and Bitwarden's own fallback is the master password; a second enrolled key adds no recovery path, unlike a LUKS keyslot, where a security key can be the only way in.
- [ ] 3.9 Check pyrite across a reboot — verify: after reboot and Bitwarden's start, the first unlock asks for the master password once, the next unlock succeeds by touch, and `SSH_AUTH_SOCK` is Bitwarden's socket.
- [ ] 3.10 Pin per-host keys on stibnite as on pyrite (`*.zt` to the login key, `github.com` to the RSA authentication key), keeping Apple's `/usr/bin/ssh` — verify: `nix eval` of stibnite's SSH match blocks shows `IdentitiesOnly` with the pinned files; after activation, `ssh -v` from stibnite to a `.zt` host and to GitHub offers one key each and authenticates.
- [ ] 3.11 Replace the remaining `isDarwin` branches in `modules/home/core/ssh.nix` and `modules/home/core/bitwarden.nix` with one shared ssh-identity capability module, platform-specific only for the socket path (`modules/lib/bitwarden-socket-path.nix`), the ssh binary and the unlock method; the git and jj signing branches already went away in the signing change — verify: `nix eval` of both laptops' SSH configuration and agent socket is unchanged from before the refactor, and stibnite's `ssh` is still `/usr/bin/ssh`.
- [ ] 3.12 Add focused checks for the interface constraints not yet regulated: stibnite keeps Apple's ssh, and stibnite's per-host pins, each with a mutant — verify: each check passes on the candidate and fails on its mutant; x86_64-linux checks built on magnetite, aarch64-darwin checks evaluated only.
- [ ] 3.13 Open a remote shell from pyrite to every awake provisioned host, `stibnite.zt` included, and from stibnite to pyrite — verify: a new SSH matrix from both laptops with no refusal on any reachable host.

Cross-reference: during the pyrite deploy, the omnigent host units looped on an expired login (exit 78) instead of stopping (`logs/parity/omnigent-restart-loop-pyrite-20261114-102514.log`, `-102520.log`).
The operator approved `RestartPreventExitStatus=78` on 2026-11-14; it lands with the omnigent service, outside this change, so an expired login becomes one `SystemdUnitFailed` alert.

## 4. Secrets access through rbw

- [ ] 4.1 Enable `rbw` on both laptops with a graphical pinentry per OS — verify: `nix eval` of `programs.rbw` on both homes, with the pinentry a graphical program.
- [ ] 4.2 Unlock `rbw` and read a secret from a script on each laptop — verify: after activation, `rbw get` of a test entry returns its value on each laptop after a graphical unlock prompt.
- [ ] 4.3 Determine whether `rbw` unlock can use the YubiKey [INFERENCE] — verify: a recorded finding from rbw's documentation or source.

## 5. S3: window chords

- [ ] 5.1 Add the first-party chord table and generate pyrite's niri binds from it, with `Mod+Space` for the DMS launcher and `Mod+Alt+F` for `maximize-window-to-edges` — verify: `nix eval` of the generated binds shows both, with every existing bind unchanged.
- [ ] 5.2 Confirm the pinned niri provides `maximize-window-to-edges` and validates the generated configuration — verify: the installed niri validator, built on magnetite, exits 0.
- [ ] 5.3 Observe fill screen on pyrite and record whether the DMS bar stays visible — verify: the operator's observation after activation.
- [ ] 5.4 Try O1 and O2 for the half-window chords on pyrite and record the operator's choice — verify: the recorded decision in design.md with the option that was not chosen and why.
- [ ] 5.5 Implement the chosen half-window chords from the chord table — verify: `nix eval` of the binds, niri validation exit 0, and the operator's observation of both halves.
- [ ] 5.6 Record stibnite's side of the chord table through the mechanism found in 1.9 — verify: the chord table and Raycast's exported hotkeys agree, compared against `logs/parity/raycast-hotkeys.json`.

## 6. Keyboard modifiers and Caps Lock

- [ ] 6.1 Decide the modifier semantics of pyrite's built-in keyboard (Q4) — verify: the decision recorded in design.md with the rejected option.
- [ ] 6.2 Decide the Caps Lock to Escape mechanism for both laptops' built-in keyboards (Q5) — verify: the decision recorded in design.md.
- [ ] 6.3 Implement the decided modifier and Caps Lock settings for the built-in keyboards — verify: `nix eval` of the delivered settings on both laptops, and the operator's key test after activation.

## 7. Shared-layer fixes

- [ ] 7.1 Add the caddy `.zt` root CA and the local k8s development CA to pyrite's trust store from the same first-party source stibnite uses — verify: `nix eval` shows the same two certificates in both laptops' declarations; after activation, `curl` to a `.zt` service from pyrite succeeds without `--insecure`.
- [ ] 7.2 Give Linux a Zed package while Darwin keeps a null package — verify: `nix eval` of `programs.zed-editor.package` on both homes; the pyrite home builds on magnetite.
- [ ] 7.3 Declare the fifteen fonts as Nix packages on both laptops and remove them from `caskFonts` — verify: `nix eval` of the font packages on both homes and of stibnite's casks; after activation, `fc-list` on pyrite and Font Book on stibnite show each font.
- [ ] 7.4 Install `dnsreset` only on Darwin and print `zerotier-join`'s launchctl hint only on Darwin — verify: `nix eval` of both homes' packages, and the built `zerotier-join` on pyrite contains no `launchctl`.

## 8. Declarative Zen on both laptops

- [ ] 8.1 Back up pyrite's and stibnite's Zen profiles before any change — verify: a dated archive of each profile directory outside the repository.
- [ ] 8.2 Replace the `youwen5/zen-browser-flake` input with `0xc000022070/zen-browser-flake`, following root nixpkgs, preserving every other lock node — verify: a semantic `flake.lock` comparison in which only the Zen nodes change.
- [ ] 8.3 Configure Zen through the module's home-manager module on both laptops, with the Bitwarden extension declared and the Darwin install mechanism chosen from 1.4 and 1.10 — verify: `nix eval` of both homes; the pyrite home builds on magnetite.
- [ ] 8.4 Confirm the Bitwarden extension fills a sign-in page in Zen on both laptops — verify: the operator's observation after activation.

## 9. Desktop behaviour

- [ ] 9.1 Set niri `repeat-delay` 225 and `repeat-rate` 33 on pyrite — verify: `nix eval` of `programs.niri.settings.input.keyboard`; the operator's key-hold comparison with stibnite after activation.
- [ ] 9.2 Set pyrite's touchpad `natural-scroll` false and keep `tap` true — verify: `nix eval` of `programs.niri.settings.input.touchpad`.
- [ ] 9.3 Set pyrite's niri `screenshot-path` inside `~/Downloads` — verify: `nix eval` of `screenshot-path`; a screenshot taken after activation lands in `~/Downloads`.
- [ ] 9.4 Compare stibnite's 28 Dock persistent applications with DMS pinned applications and declare pyrite's pinned set — verify: `nix eval` of the DMS pinned applications, each mapped to a job catalogue row.

## 10. GUI application triage

- [ ] 10.1 Write the install-mechanism policy per OS within the principles' bounds (Q6) — verify: the policy recorded in design.md and accepted by the operator.
- [ ] 10.2 Place each used application in one bucket: share as-is, same application with Linux packaging, different tool for the same job, no good Linux equivalent (binary derivation or stibnite remotely), or darwin by nature — verify: one bucket per application in the job catalogue, using 1.3 to 1.6.
- [ ] 10.3 Declare the unmanaged applications on stibnite that stay, and remove Maccy — verify: `nix eval` of stibnite's casks and App Store applications; the probe's unmanaged list shrinks when rerun after activation.
- [ ] 10.4 Ship each bucket's Linux implementations as their own pull requests — verify: per pull request, `nix eval` and a build on magnetite of pyrite's home.

## 11. Containers and VMs on Linux

- [ ] 11.1 Record the container and VM jobs stibnite's Colima, OrbStack and Podman Desktop serve, and choose native Linux implementations — verify: the job catalogue rows and a decision record.
- [ ] 11.2 Declare the chosen runtime on pyrite — verify: `nix eval` of pyrite's configuration; pyrite's system builds on magnetite.

## 12. Backups

- [ ] 12.1 Decide what is backed up from each laptop and to where — verify: a decision record.
- [ ] 12.2 Declare backups on both laptops — verify: `nix eval` of both configurations, and one restore of a test file on each laptop.

## 13. stibnite as an always-reachable home machine

- [ ] 13.1 Decide stibnite's power and lid settings for being left at home (Q7), recording closed-lid behaviour — verify: the decision in design.md with the observed closed-lid behaviour.
- [ ] 13.2 Declare the decided pmset settings — verify: `nix eval` of stibnite's configuration; `pmset -g` after activation matches.

## 14. State

- [ ] 14.1 Decide which application and desktop state is in scope (Q8) — verify: a decision record listing each state item.
- [ ] 14.2 Declare or document the in-scope state per item — verify: per item, its declaration status updated in the parity inventory.

## 15. Integration Verification

- [ ] 15.1 Recount stibnite's declared share after each slice ships — verify: the count is recorded per slice and is never lower than the one before it.
- [ ] 15.2 The operator carries pyrite as the daily workstation for one working day with stibnite at home — verify: the operator's record of each workstation job done, each done remotely, and each missed, with every miss added to the job catalogue.
- [ ] 15.3 An unattended agent on each laptop signs a commit while nobody is present, and the operator logs in to every awake host from both laptops — verify: `git log --show-signature` verifies the agent's commit as the operator's with no touch requested, and the SSH matrix from both laptops has no refusal.
- [ ] 15.4 Strict OpenSpec validation of this change — verify: `openspec validate workstation-parity --strict` exits 0.
