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
- [x] 1.10 Acquire `0xc000022070/zen-browser-flake` into the reference tree and record its home-manager module's Darwin support — verify: the module source read at a pinned revision, with Darwin install support stated from that source.
  Read 2026-11-16 at `ad99018e37999e659ae43f9c6ac126161ca147bc`, both the `ghq` checkout (`/private/var/lib/ghq/github.com/0xc000022070/zen-browser-flake`) and the `zen-browser` node of `flake.lock`.
  `flake.nix` lists `aarch64-darwin` in `supportedSystems` and exports `homeModules.beta` (the `default`), `twilight` and `twilight-official`.
  `hm-module/default.nix` builds on home-manager's `mkFirefoxModule` with the Darwin profile path `~/Library/Application Support/Zen` and the defaults domain `app.zen-browser.zen`.
  `hm-module/package.nix` defaults `darwin.packageMode` to `signed`, which installs the `.app` untouched and routes policies through `targets.darwin.defaults` and native messaging hosts through `mozilla.firefoxNativeMessagingHosts`; `extraPrefs`, `extraPrefsFiles` and `pkcs11Modules` are rejected by assertion in that mode, and `wrapped` enables them at the cost of the upstream signature.
  So the module can configure the cask's Zen.app with `package = null`, writing policies to `app.zen-browser.zen`, as D10 records.

## 2. S1: pyrite dispatches builds to magnetite (in progress elsewhere)

- [x] 2.1 pyrite dispatches x86_64-linux builds to magnetite — verify: the S1 slice's own acceptance, recorded here by reference once its pull request merges.
  Merged as #3852 (`d6b07847`, 2026-11-13); on 2026-11-16 pyrite's `/etc/nix/machines` matches the PR's acceptance line for line, its x86_64-linux entry is magnetite.zt's address, and `builders = @/etc/nix/machines`.
  magnetite's `nix-grpc-daemon` logged 158 requests from `cn=pyrite` since 2026-11-13, among them `BuildDerivation` of `calibre-library-sync.drv` (2026-11-15 17:58Z) and of niri's `config.kdl.drv` (19:06Z).

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
  Progress 2026-11-16: in the current boot (since 02:05 EST, after the 14 warm reboots of 00:19–02:05), the Bitwarden user unit started at login (02:09:44), its SSH agent listens on `~/.bitwarden-ssh-agent.sock`, and the cameron session's `SSH_AUTH_SOCK` is that socket.
  The journal has no `polkit-agent-helper@` run and no Bitwarden unlock since that boot, so the master-password-once-then-touch sequence is not evidenced; the operator's observation of the first two unlocks after the next reboot (or a polkit helper run for Bitwarden in the journal after a master-password unlock) settles it.
- [x] 3.10 Pin per-host keys on stibnite as on pyrite (`*.zt` to the login key, `github.com` to the RSA authentication key), keeping Apple's `/usr/bin/ssh` — verify: `nix eval` of stibnite's SSH match blocks shows `IdentitiesOnly` with the pinned files; after activation, `ssh -v` from stibnite to a `.zt` host and to GitHub offers one key each and authenticates.
  Both laptops import `flake.modules.homeManager.bitwarden-key-pins` (`modules/home/core/ssh-identity.nix`); stibnite's rendered `~/.ssh/config` differs from main's only by `IdentitiesOnly yes` + `IdentityFile ~/.ssh/bitwarden-login.pub` under `Host *.zt`, a new `Host github.com` block pinning `~/.ssh/bitwarden-github.pub`, and `AddKeysToAgent no` (`logs/ssh-identity/stibnite-ssh-config.{main,candidate}`); Apple's `/usr/bin/ssh` (OpenSSH_10.3p1, LibreSSL 3.3.6) offers only the agent key matching a `.pub`-only `IdentityFile` under `IdentitiesOnly yes`, and both agent keys without it (`logs/parity/apple-ssh-pub-identityfile-*.log`).
  Activated 2026-11-14 with #3872: from a terminal outside herdr, `ssh -v magnetite.zt true` offered only `bitwarden-login.pub` (`SHA256:WbnjY1…`) and authenticated, and `ssh -vT git@github.com` offered only `bitwarden-github.pub` (`SHA256:CoaK9g…`) and GitHub greeted cameronraysmith.
- [x] 3.11 Replace the remaining `isDarwin` branches in `modules/home/core/ssh.nix` and `modules/home/core/bitwarden.nix` with one shared ssh-identity capability module, platform-specific only for the socket path (`modules/lib/bitwarden-socket-path.nix`), the ssh binary and the unlock method; the git and jj signing branches already went away in the signing change — verify: `nix eval` of both laptops' SSH configuration and agent socket is unchanged from before the refactor, and stibnite's `ssh` is still `/usr/bin/ssh`.
  Done in `modules/home/core/ssh-identity.nix`, which replaces `bitwarden.nix`; its only platform branch is the default agent (Mac App Store Bitwarden on darwin), with the socket path from `bitwardenSocketPath` and the ssh binary from `modules/home/security/tools.nix`; colima, OrbStack and XQuartz stay darwin-only in `ssh.nix` as application integrations.
  `SSH_AUTH_SOCK`, the ssh-agent setting and the openssh package are identical to main on both laptops (`logs/ssh-identity/*-agent.{main,candidate}.json`); pyrite's rendered config differs only in `AddKeysToAgent confirm` to `no`, and stibnite's (besides the 3.10 pins) in `yes` to `no`, which is inert because Bitwarden refuses client-added keys (`logs/parity/bitwarden-about-ssh.md` §No ssh-add key management) and stibnite's effective value was already `no` through its `id_*_sk` Match block (`ssh -G magnetite.zt`); magnetite's home keeps `confirm` and its ssh-agent.
  `modules/checks/ssh-identity.nix` asserts both laptops' pins and stibnite's Apple ssh on the real configurations; mutants (pins removed, login pin changed, Nix OpenSSH added, GitHub pin dropped on pyrite) fail evaluation (`logs/ssh-identity-mutants-*.log`); `home-manager-crs58`, `pyrite-bitwarden-unlock` and `nixos-pyrite` built on magnetite, `darwin-stibnite` evaluated.
- [ ] 3.12 Add focused checks for the interface constraints not yet regulated: stibnite keeps Apple's ssh, and stibnite's per-host pins, each with a mutant — verify: each check passes on the candidate and fails on its mutant; x86_64-linux checks built on magnetite, aarch64-darwin checks evaluated only.
- [ ] 3.13 Open a remote shell from pyrite to every awake provisioned host, `stibnite.zt` included, and from stibnite to pyrite — verify: a new SSH matrix from both laptops with no refusal on any reachable host.

Cross-reference: during the pyrite deploy, the omnigent host units looped on an expired login (exit 78) instead of stopping (`logs/parity/omnigent-restart-loop-pyrite-20261114-102514.log`, `-102520.log`).
The operator approved `RestartPreventExitStatus=78` on 2026-11-14; it lands with the omnigent service, outside this change, so an expired login becomes one `SystemdUnitFailed` alert.

## 4. Secrets access through the official Bitwarden CLI

Revised 2026-11-16 by the operator's decisions recorded in design.md D5: `bw` replaces `rbw` as the command-line vault client, and the former 4.3 (whether `rbw` unlock can use the YubiKey) is dropped, since `bw` unlocks with the master password and no requirement asks for a YubiKey unlock on the command line.

- [ ] 4.1 Confirm the official `bw` is the vault client on both laptops and `rbw` is absent — verify: `nix eval` of the operator's home packages on pyrite and stibnite lists nixpkgs `bitwarden-cli` and no `rbw`, and `programs.rbw` is not enabled on either (aarch64-darwin evaluated only).
- [ ] 4.2 Unlock `bw` and read a non-secret field from a script on each laptop — verify: after a vault test login item `workstation-parity-bw-probe` with username `parity-probe` and a throwaway password is created, a script on each laptop runs `bw unlock --raw` (master password on the terminal) into `BW_SESSION`, then `bw sync`, then compares `bw get username workstation-parity-bw-probe` with `parity-probe` and prints only the match result; it prints no session token or password, and exits 0 on pyrite and on stibnite.

## 5. S3: window chords

- [ ] 5.1 Add the first-party chord table and generate pyrite's niri binds from it, with `Mod+Space` for the DMS launcher and `Mod+Alt+F` for `maximize-window-to-edges` — verify: `nix eval` of the generated binds shows both, with every existing bind unchanged.
- [x] 5.2 Confirm the pinned niri provides `maximize-window-to-edges` and validates the generated configuration — verify: the installed niri validator, built on magnetite, exits 0.
  niri 26.04 lists the action, and niri-flake's `niri validate` passed for pyrite's configuration in #3869 and again with the decided halves.
- [x] 5.3 Observe fill screen on pyrite and record whether the DMS bar stays visible — verify: the operator's observation after activation.
  Observed by the operator on 2026-11-14: the DMS bar is set to auto-hide, and when revealed at the top edge it overlays the filled window as intended, so fill screen and the bar don't conflict.
- [x] 5.4 Try O1 and O2 for the half-window chords on pyrite and record the operator's choice — verify: the recorded decision in design.md with the option that was not chosen and why.
  Decided 2026-11-14: first O2, floating; after O2 overlapped a filled window, O3, tiled; see D7.
- [x] 5.5 Implement the chosen half-window chords from the chord table — verify: `nix eval` of the binds, niri validation exit 0, and the operator's observation of both halves.
  O3 is implemented, directly rather than from a chord table (5.1 is open), validated by niri-flake, and deployed to pyrite (#3875); the operator confirmed on 2026-11-14 that two halves share the view and filling the screen with another window moves them along the strip without overlap.
- [ ] 5.6 Record stibnite's side of the chord table through the mechanism found in 1.9 — verify: the chord table and Raycast's exported hotkeys agree, compared against `logs/parity/raycast-hotkeys.json`.

## 6. Keyboard modifiers and Caps Lock

- [x] 6.1 Decide the modifier semantics of pyrite's built-in keyboard (Q4) — verify: the decision recorded in design.md with the rejected option.
  Decided by the operator on 2026-11-16 and recorded in D8 and Q4: pyrite keeps Control for copy and paste, Super is not remapped to Command, and the application-aware remapper is the rejected option.
- [ ] 6.2 Decide the Caps Lock to Escape mechanism for both laptops' built-in keyboards (Q5) — verify: the decision recorded in design.md.
  Decided for pyrite on 2026-11-14: niri's `caps:escape` (D8); stibnite's declaration waits on the ZSA check.
- [ ] 6.3 Implement the decided modifier and Caps Lock settings for the built-in keyboards — verify: `nix eval` of the delivered settings on both laptops, and the operator's key test after activation.
  pyrite's `caps:escape` is implemented and deployed (#3875), and the operator confirmed on 2026-11-14 that Caps Lock sends Escape; stibnite's side waits on the ZSA check (D8).

## 7. Shared-layer fixes

- [x] 7.1 Add the caddy `.zt` root CA and the local k8s development CA to pyrite's trust store from the same first-party source stibnite uses — verify: `nix eval` shows the same two certificates in both laptops' declarations; after activation, `curl` to a `.zt` service from pyrite succeeds without `--insecure`.
  Done 2026-11-16 (#3901): `flake.modules.nixos.workstation-ca-trust` adds `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value` and `kubernetes/clusters/local/pki/root_ca.crt` to pyrite's `security.pki.certificateFiles`, the same files stibnite's `zt-services-trust` and host module declare.
  On pyrite the bundle carries both roots with the source fingerprints (`7E:78:…:2E:82`, `1B:2B:…:ED:63`), `curl https://ntfy.zt/` returns 200 without `--insecure`, and `openssl s_client -verify_return_error` returns `0 (ok)`.
- [x] 7.2 Give pyrite's home a Zed package while every other home, stibnite's included, keeps a null package — verify: `nix eval` of `programs.zed-editor.package` on pyrite's and stibnite's homes and on the other Linux homes; the pyrite home builds on magnetite.
  Declared 2026-11-15: the shared zed module's package is `lib.mkDefault null` and pyrite's cameron home sets `pkgs.zed-editor`; `nix eval` shows pyrite's cameron at `zed-editor-1.28.1`, stibnite, magnetite, cinnabar and every standalone home still null, and `userSettings` unchanged on each host; pyrite's system built on magnetite (`/nix/store/jxqgrxm8fi1kbclanp67zbl31y76wkkm-nixos-system-pyrite-26.11.20261114.82566df`); waits on activation and the operator opening Zed.
  Re-checked 2026-11-16 after the move into `modules/home/linux-workstation` (#3887, #3888): `nix eval` gives `zed-editor-1.28.1` for pyrite's cameron and null for stibnite's crs58, every other NixOS and nix-darwin cameron/crs58/tara/raquel/janettesmith/christophersmith home, and every standalone `homeConfigurations` entry.
  The `omnigent-*` homes on magnetite and pyrite report home-manager's own `zed-editor` default but `enable = false`, because they don't import the shared zed module, so nothing installs it.
  `/nix/store/jg6gsxqw0r0rbbrags9wvl8vs41gzfyy-zed-editor-1.28.1` is in magnetite's store and in pyrite's running system, which puts `zeditor` and `zed-delta` in cameron's profile.
- [ ] 7.3 Declare the fifteen fonts as Nix packages on both laptops and remove them from `caskFonts` — verify: `nix eval` of the font packages on both homes and of stibnite's casks; after activation, `fc-list` on pyrite and Font Book on stibnite show each font.
- [ ] 7.4 Install `dnsreset` only on Darwin and print `zerotier-join`'s launchctl hint only on Darwin — verify: `nix eval` of both homes' packages, and the built `zerotier-join` on pyrite contains no `launchctl`.
- [ ] 7.5 Declare Delta under the command `zed-delta` on pyrite through `pkgs.zed-delta` and on every Mac that imports `darwin-workstation` (stibnite, rosegold, argentum, blackphos) through the `zed-delta` darwin aspect, with jj and lazygit calling the diff pager by store path — verify: `nix eval` of `homebrew.casks` and the `environment.systemPackages` names on the four Macs, of pyrite's home packages, and of the operator's jj `ui.pager` and lazygit pager command.
  After activation on each of stibnite, rosegold and argentum, and on blackphos, which is semi-permanently offline, when it is next activated: `brew list --cask` lists `zed-delta`, `/opt/homebrew/bin/delta` does not exist, `zed-delta --version` prints Delta's version and `delta --version` prints the diff pager's; on stibnite the hand-installed `/Applications/Delta.app` is adopted by the cask and `~/Library/Application Support/delta` keeps its contents.
  After activation on pyrite: `zed-delta --version` prints Delta's version and the launcher lists Delta from its desktop entry.

## 8. Declarative Zen on both laptops

- [ ] 8.1 Back up pyrite's and stibnite's Zen profiles before any change — verify: a dated archive of each profile directory outside the repository.
  pyrite: `~/backups/zen-pyrite-20261115-001954.tar.gz` (119 MB, 1586 entries) was taken with Zen closed before the 2026-11-15 activation, and removed at the operator's request once the declared Zen proved itself; stibnite's backup is due before any change there.
- [x] 8.2 Replace the `youwen5/zen-browser-flake` input with `0xc000022070/zen-browser-flake`, following root nixpkgs, preserving every other lock node — verify: a semantic `flake.lock` comparison in which only the Zen nodes change.
  Done 2026-11-15, following root nixpkgs and home-manager; the node-by-node comparison changed only the `zen-browser` node, and no youwen5 node remains.
- [ ] 8.3 Configure Zen through the module's home-manager module on both laptops, with the Bitwarden extension declared and the Darwin install mechanism chosen from 1.4 and 1.10 — verify: `nix eval` of both homes; the pyrite home builds on magnetite.
  pyrite configured 2026-11-15 (D10) and built on magnetite; stibnite waits on the operator's experience with pyrite.
- [ ] 8.4 Confirm the Bitwarden extension fills a sign-in page in Zen on both laptops — verify: the operator's observation after activation.
  pyrite: the operator confirmed on 2026-11-15 that the policy-installed Bitwarden extension works in Zen; stibnite's half waits on 8.3.

## 9. Desktop behaviour

- [ ] 9.1 Set niri `repeat-delay` 225 and `repeat-rate` 33 on pyrite — verify: `nix eval` of `programs.niri.settings.input.keyboard`; the operator's key-hold comparison with stibnite after activation.
- [x] 9.2 Set pyrite's touchpad `natural-scroll` false and keep `tap` true — verify: `nix eval` of `programs.niri.settings.input.touchpad`.
  Done in the user session's niri configuration and the DankGreeter's on 2026-11-14 at the operator's request (#3878); the operator confirmed the scroll direction and `Ctrl+Up` opening niri's overview on pyrite.
- [x] 9.3 Set pyrite's niri `screenshot-path` inside `~/Downloads` — verify: `nix eval` of `screenshot-path`; a screenshot taken after activation lands in `~/Downloads`.
  Set on 2026-11-14 (#3882), with the macOS capture chords bound to `dms screenshot` writing to the same directory: Mod+Shift+3 and 4 save the screen or a region (taken on release) to a file, their Ctrl variants copy to the clipboard only, and Mod+Shift+5 saves the focused window; the operator confirmed a capture landing in `~/Downloads` on pyrite.
- [ ] 9.4 Compare stibnite's 28 Dock persistent applications with DMS pinned applications and declare pyrite's pinned set — verify: `nix eval` of the DMS pinned applications, each mapped to a job catalogue row.
- [x] 9.5 Declare pyrite's dark colour-scheme preference — verify: the portal's `org.freedesktop.appearance` `color-scheme` reads 1 after activation, and Zen's "system" theme renders dark.
  pyrite's system dconf database sets `org/gnome/desktop/interface` `color-scheme` to `prefer-dark` as an unlocked default (#3879); before it the key was unset and the portal reported 0, no preference.
  After activation the portal read 1 once its already-running services were restarted, and the operator confirmed on 2026-11-14 that Zen's "system" theme renders dark.
- [x] 9.6 Restore the power button on pyrite's DMS lock screen — verify: `nix eval` of the rendered `lockScreenWidgetInstances` shows `lock_power` enabled; the operator sees the button on the lock screen after activation.
  Progress 2026-11-15: DMS 2.1.2 builds the lock screen from `lockScreenWidgetInstances`, whose default disables `lock_power`, and applies the `lockScreenShowPowerActions` migration only to versioned settings files, so the flag has no effect in nix-generated settings; `modules/home/dms/default.nix` now declares 2.1.2's default list with only `lock_power` enabled, to be re-checked on DMS bumps.
  The DankGreeter is deliberately unchanged: its only settings input, `configFiles`, is copied by the greetd `preStart` hook that pyrite-dankgreeter D5 disables, and feeding it settings needs its own design.
  Done (#3895): the operator saw the button after a `dms` restart, which a running shell needs to re-read the replaced settings link.
- [x] 9.7 Make a manual suspend on pyrite wake reliably — verify: repeated `rtcwake` suspend cycles resume in about the RTC interval; the operator's suspend and wake from the power menu.
  Progress 2026-11-15: resume from deep (S3) brought core 1 (CPUs 1 and 3) back online in 0.5–6 s every time and up to 761 s on some resumes, with displays, network and userspace still down, which looked like a machine that would not wake (boot-clock `power:suspend_resume` traces).
  `mem_sleep_default=s2idle` takes no CPU offline: 8 of 8 cycles resumed in 63 s (#3894).
  Open on 2026-11-15, answered below: the s2idle standby drain on battery, since the platform reaches neither S0ix nor PC10; the S3 root cause is tracked in CAM-104.
  Done 2026-11-16: pyrite runs `mem_sleep_default=s2idle` (`/sys/power/mem_sleep` `[s2idle] deep`), and the operator suspends and wakes it from the power menu and over ssh; the journal shows an overnight s2idle suspend from 02:17 to 10:37 EST that resumed.
  The operator measured the standby drain off the charger overnight on 2026-11-15/16, 85% to 22%, and accepted it; warm reboots after a suspend are covered by 9.9 (#3899).
- [ ] 9.8 Reach pyrite from other home clients promptly after it resumes — verify: `ping 192.168.50.35` from stibnite answers within a minute of pyrite's wake.
  Progress 2026-11-15: pyrite re-associates and works outbound within about a minute, but the Verizon CHR30A router black-holes traffic from its other wireless clients to pyrite for 5–13+ minutes after any re-association, on either mesh node or band; `ssh pyrite.zt` returns after 1–3 minutes through ZeroTier's relay.
  Not fixable on pyrite (access-control block, BSSID pin and random MAC ruled out); the firmware report or own access points are tracked in CAM-105.
- [x] 9.9 Make a warm reboot on pyrite restart by itself with Wi-Fi and Bluetooth intact — verify: supervised warm reboots on battery restart with no button press, the BCM4350 probing (`Firmware: BCM4350`, no `MMIO read failed`) and Bluetooth reporting `chip id 92`.
  Done 2026-11-16: since 2026-11-15 the power-cycling resets (`reboot=pci`, EFI cold) left pyrite off on battery while restarting on AC, so pyrite now reboots through `reboot=acpi`, and `reboot-quiesce-radios` first unbinds Bluetooth (firmware BTPD) and brcmfmac and runtime-suspends root port 00:1d.0, so the firmware's RP09 `_PS3`/`_PS0` reset the chip before the CF9 reset.
  10 plain warm reboots and 3 after an s2idle suspend passed, restarting in 11–17 s; Thunderbolt, lost on every suspend, came back with each reboot.

## 10. GUI application triage

- [ ] 10.1 Write the install-mechanism policy per OS within the principles' bounds (Q6) — verify: the policy recorded in design.md and accepted by the operator.
- [ ] 10.2 Place each used application in one bucket: share as-is, same application with Linux packaging, different tool for the same job, no good Linux equivalent (binary derivation or stibnite remotely), or darwin by nature — verify: one bucket per application in the job catalogue, using 1.3 to 1.6.
- [ ] 10.3 Declare the unmanaged applications on stibnite that stay, and remove Maccy — verify: `nix eval` of stibnite's casks and App Store applications; the probe's unmanaged list shrinks when rerun after activation.
- [ ] 10.4 Ship each bucket's Linux implementations as their own pull requests — verify: per pull request, `nix eval` and a build on magnetite of pyrite's home.
  Progress: pyrite's GUI applications (Zed from nixpkgs, Calibre, Zathura, gdu) moved from its host block into `flake.modules.homeManager.linux-workstation` (`modules/home/linux-workstation/`), which only homes with a graphical session import.
  The module adds Delta from `github:zed-industries/delta-nix`, exposed as `zed-delta` so `delta` stays the git pager, and Antigravity Hub from the locked `llm-agents` input.
  pyrite's cameron home also gains a read-only Google Drive remote, `gdrive` (`drive.readonly`), in its own rclone config that a sops-nix template renders (0600) from crs58's client secret and token, kept out of `programs.rclone` because its `rclone-config` service passes secrets as process arguments; `rclone-gdrive` runs rclone against that config, and the on-demand `calibre-library-sync` command (`modules/home/linux-workstation/calibre-library-sync.nix`) mirrors `gdrive:Library/{theory,experiment,philosophy}` one-way into `~/Calibre/<library>`: it refuses while Calibre runs, shows a dry-run summary and asks before syncing, and has no timer, because calibre's FAQ warns that a library inside a cloud-sync folder loses data.
  The operator confirmed on 2026-11-15 that the full mirror completed (dry run: "Mirror is up to date.") and that the three libraries open in Calibre on pyrite.
  Shipped on pyrite by 2026-11-16, each merged: Nautilus as file manager and portal file chooser (#3884); Papers as default PDF viewer and Zathura for LaTeX (#3885); declarative Zen (#3886); Zed, Calibre, Baobab and gdu (#3887); the `linux-workstation` module with Delta as `zed-delta` and Antigravity Hub (#3888); the Drive remote and Calibre mirror (#3889, #3890); Bitwarden Desktop (#3862).
  Not ticked: the verify is per bucket, and the buckets wait on 10.2's job catalogue.

## 11. Containers and VMs on Linux

- [ ] 11.1 Record the container and VM jobs stibnite's Colima, OrbStack and Podman Desktop serve, and choose native Linux implementations — verify: the job catalogue rows and a decision record.
  Decided 2026-11-15 by the operator: Incus for system containers and VMs, Podman with a Docker-compatible socket for compose, devcontainers and testcontainers, no Docker daemon or libvirt on pyrite, and heavy k3d or ctlptl work on magnetite's Docker over ssh.
  Not ticked: the job catalogue rows wait on 1.8.
- [x] 11.2 Declare the chosen runtime on pyrite — verify: `nix eval` of pyrite's configuration; pyrite's system builds on magnetite.
  Done 2026-11-16 (#3902): `modules/machines/nixos/pyrite/containers.nix` declares Incus on ZFS (`zroot/incus`, `incusbr0` at `10.0.100.1/24`) and Podman with `dockerCompat` and the Docker socket, on the nftables firewall, with the ZeroTier MSS clamp ported to both backends.
  pyrite's system built on magnetite and is deployed: an Incus container launched and resolved DNS, `podman run hello-world` ran, Docker Compose 5.7.0 talked to the Podman API, and both clamp VM tests passed on pyrite.

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
