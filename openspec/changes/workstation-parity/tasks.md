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

## 3. S2: SSH identity and signing — spike, then the decided slice

- [ ] 3.1 Q2.1: install nixpkgs Bitwarden Desktop on pyrite as a trial and test it as the SSH agent, unlocking through polkit, PAM and pam_u2f with a YubiKey touch [INFERENCE: verify] — verify: a recorded finding with the agent socket path, the unlock prompt observed, and `ssh-add -L` listing vault keys on pyrite.
- [ ] 3.2 Q2.2: record whether nixpkgs `bitwarden-desktop` is substitutable from the binary caches for the pinned nixpkgs, and what Flatpak's sandbox would imply for the agent socket and polkit — verify: `nix path-info --store https://cache.nixos.org` (or the fleet cache) result for the pinned derivation, and a recorded Flatpak comparison citing its permissions.
- [ ] 3.3 Q2.3: write the one rule for unattended signing on both platforms, consistent with the signer principal `commit-author-identity-interface` fixes, starting from the Linux sops key file (`1f5307618`, `f22380648`) and the darwin Bitwarden-agent signing (`3cd8189f8`) — verify: the rule recorded in design.md D6 and accepted by the operator.
- [ ] 3.4 Q2.4: decide whether stibnite needs any YubiKey SSH key, recording the outcome of an `ed25519-sk` login attempt with `/usr/bin/ssh` against A88 — verify: the observed login result and the recorded decision.
- [ ] 3.5 Q2.5: decide whether a YubiKey key exists only as a vault-independent emergency login from pyrite — verify: the recorded decision in design.md D6.
- [ ] 3.6 Record the decided SSH identity design as a DECIDED D6 entry, with per-host key selection that keeps every host within its `MaxAuthTries` — verify: design.md D6 marked DECIDED, and the interface spec gains the decided requirements with `openspec validate workstation-parity --strict` exiting 0.
- [ ] 3.7 Implement one ssh-identity capability module replacing the `isDarwin` branches in `modules/home/core/ssh.nix`, `modules/home/core/bitwarden.nix`, `modules/home/development/git.nix` and `modules/home/development/jujutsu.nix`, platform-specific only for the socket path, the ssh binary and the unlock method — verify: `nix eval` of both laptops' SSH, git and jj configuration matches the decided design, with stibnite's `ssh` still `/usr/bin/ssh`.
- [ ] 3.8 Add focused checks for the interface constraints: stibnite keeps Apple's ssh, unattended signers need no touch, and per-host key selection, each with a mutant — verify: each check passes on the candidate and fails on its mutant, built on magnetite.
- [ ] 3.9 If the decided design changes `flake.users.crs58.meta.sshKeys`, deploy the hosts reachable today, then pyrite and stibnite, reading every alert or notice posted since each deploy started and recording each with its cause — verify: each host's deploy record names the new closure, and every alert or notice since the deploy start is explained.
- [ ] 3.10 Open a remote shell from pyrite to every awake provisioned host, `stibnite.zt` included, and from stibnite to pyrite, and sign one commit interactively and one unattended on each laptop — verify: a new SSH matrix with no refusal on any reachable host, and `git log --show-signature -1` verifying each commit as the operator's.
- [ ] 3.11 Decide with the operator whether to retire the unlabelled `ssh-ed25519` key and any agent the decided design replaces, and apply the decision — verify: the recorded decision, and, if retired, `nix eval` showing the key removed.

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
