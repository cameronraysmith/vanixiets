# pyrite-baremetal-nixos Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Add pyrite, an Apple MacBookPro14,1, to the vanixiets clan as the fleet's first bare-metal NixOS machine with a natively-encrypted ZFS root unlocked by a passphrase typed on the internal keyboard, and produce a bare-metal install path that is re-runnable rather than a one-off manual sequence. Provide a local graphical desktop session — a stock GNOME desktop under GDM, proven on this hardware from the installer ISO — so the machine is usable on its own screen away from the mesh and from a build host.

**Architecture:** A per-host deferred module at `modules/machines/nixos/pyrite/` importing `nixos-hardware.nixosModules.apple-macbook-pro-14-1` with two unwanted firmware pulls disabled, a sibling `disko.nix` declaring a `zroot` pool with an explicit `ashift` on a namespace-explicit by-id device and an `aes-256-gcm` root dataset created from a clan partitioning secret and flipped to a boot-time prompt, a static facter report at `machines/pyrite/facter.json`, a stock GNOME desktop under GDM enabled by the two system options `services.displayManager.gdm.enable = true` and `services.desktopManager.gnome.enable = true`, a `modules/clan/inventory/services/wifi.nix` instance carrying the fleet SSID and PSK as sops-encrypted clan vars, and `clan machines install` against a booted stock installer ISO preceded by an explicit disk wipe. See `design.md` for the decisions, the adversarial verdicts, the mkForce invariant, and the open risks; see `specs/` for the requirements.

**Tech Stack:** nix (flake-parts, import-tree, deferred module composition), clan-core, disko, ZFS native encryption, nixos-facter (consumed statically), jj (development join).

## Approach and sequencing

Evaluation-first, then secrets, then install.

The change's former highest-risk unknown — whether a passphrase-prompted dataset can be created during a non-interactive install — is settled and no longer gates the work. `keylocation` is not one of disko's one-time properties, so the dataset is created from a keyfile through clan's ordinary `neededFor = "partitioning"` channel and a `postCreateHook` flips it to `prompt`. This is disko's own documented idiom, it is idempotent across re-runs, and it needs no spike. The earlier plan's Task 1 has been removed rather than reordered.

Tasks 1 through 4 are pure evaluation work and produce no irreversible effects. The machine must evaluate — module, disko, and registration complete — before any install or hardware detection runs. Task 4's ordering is load-bearing in a way that is easy to get wrong: `machines/pyrite/` is not an inert data directory, because clan-core `readDir`-scans it and injects an inventory machine per subdirectory, so the facter report must land in the same commit as the module and the registrations rather than ahead of them. This is why the report is staged inside this change directory while the change is in flight.

Task 5 runs before Task 7 because the machine age key, the ZeroTier address, and the disk passphrase do not exist until `clan vars generate` has run, and the `.sops.yaml` bridge recipient depends on the first. Step 5.3 is not bookkeeping: the operator types the generated passphrase at every boot, and although Step 5.2 commits it as a sops-encrypted var, that var is encrypted to exactly one human key — so the pool is lost only if that key is lost together with every copy held outside the repository, and Step 5.3 is what keeps the second term of that conjunction non-empty.

Task 6 produces the deliverable that outlives this machine. The repository's only recorded `clan machines install` invocation lives in terranix as a cloud-only `null_resource`, so without Task 6 pyrite ships as a manual install and the next bare-metal host starts from nothing. Its first step is a disk wipe, which is a step rather than an assumption because disko's create phase skips `sgdisk --clear` when `blkid` succeeds and pyrite carries an Apple GPT today.

Task 7 is the only irreversible task, and its point of no return is the `blkdiscard` wipe that opens 7.3, not 7.4: by 7.4 macOS is already gone. The firmware-extraction risk that once gated this is disproven: no component's firmware comes from the local macOS install. Step 7.12 re-runs the install including the wipe, which is what converts "it installed" into "the install path works" — a re-run against a surviving pool reuses the pool and skips every dataset create, so it would go green while proving nothing.

Task 8 is a standing constraint rather than a step: the flake does not move between now and the install. `flake.nix:70` floats `clan-core` on `main.tar.gz`, so an update can move the transitive `nixpkgs_2` node and with it nixos-anywhere's version — currently 1.13.0, the version every mechanic in D13 was verified against — while no `nixos-anywhere` node appears in the diff, because `flake.lock` has none to move. If the flake must move first, re-verify D8 and D13 against the resulting version before Task 7.

Integration is jj-native onto the `pyrite-baremetal-nixos` chain in a development join — no git worktree, no autonomous PR; commits are routed onto the chain by the orchestrator.

Out of scope: audio (not a deferred work item; revisit if mainline lands the amplifier init, since pinning the kernel backward for it is ruled out), hibernation (deferred, which is what makes keeping `forceImportRoot = true` costless), the `d3cold` suspend workaround, gating `base`'s cloud-VM initrd assumptions fleet-wide, regenerating facter reports on this hardware, a terranix entry, the pre-existing justfile defects a new machine walks into, and the niri Wayland session and its shell assembly (deferred to a reversible follow-up deployed via `clan machines update`; GNOME under GDM is the desktop this change ships, per D19).

---

## Task 1: Flake input scaffolding (tasks.md §1)

- [ ] **Step 1:** Add `nixos-hardware` to `flake.nix` with `inputs.nixpkgs.follows = "nixpkgs"`.
- [ ] **Step 2:** Run `nix flake check` with the input added and unused.
- [ ] **Step 3:** Route the commit onto the chain.

## Task 2: The pyrite host module (tasks.md §2)

- [ ] **Step 1:** Write `modules/machines/nixos/pyrite/default.nix` after the electrum shape, importing the nixos-hardware profile.
- [ ] **Step 2:** Disable `networking.enableB43Firmware` and `hardware.facetimehd.enable` with plain `false`, commenting the b43 misdetection.
- [ ] **Step 3:** Set the bootloader, `boot.zfs.devNodes = "/dev/disk/by-id"`, hostname, stateVersion, and the `cameron` user wiring.
- [ ] **Step 4:** Disable `boot.initrd.network.ssh` only — never `mkForce` `boot.initrd.kernelModules`. State `hardware.enableRedistributableFirmware = true` and `hardware.cpu.intel.updateMicrocode = true` explicitly rather than inheriting facter's bare-metal `mkDefault`s, keep `forceImportRoot = true` with its comment, set no `hostId`, and enable no plymouth. Set `services.mbpfan.aggressive = false`; the `mbpfan` and `tlp` enables stay at the profile's `mkDefault true` and are deliberately not restated in the module. Enable a stock GNOME desktop with `services.displayManager.gdm.enable = true` and `services.desktopManager.gnome.enable = true` — system-level, with no home-manager desktop configuration, and no plymouth (D11 stands; GDM is a stage-2 display manager that does not touch the initrd passphrase path). See D19.
- [ ] **Step 5:** Route the commit onto the chain.

## Task 3: The disko layout (tasks.md §3)

- [ ] **Step 1:** Write `modules/machines/nixos/pyrite/disko.nix` assigning into the host module's namespace with no import statement.
- [ ] **Step 2:** Set the `_1` device path, the `ashift = "12"` pool option, and the ESP's `type = "EF00"` and `size = "1G"`, each with the comment its footgun earns. Declare the ESP's sibling `zfs` partition at `size = "100%"` carrying `content = { type = "zfs"; pool = "zroot"; }` — the vdev the pool is created on.
- [ ] **Step 3:** Declare the four datasets; add the `neededFor = "partitioning"` xkcdpass generator, writing to `$out/key` with `runtimeInputs = [ pkgs.coreutils pkgs.xkcdpass ]`; set the `root` dataset's encryption, `keyformat = "passphrase"`, create-time `file://` keylocation, and the `postCreateHook` flip to `prompt`.
- [ ] **Step 4:** Confirm `nix eval .#nixosConfigurations.pyrite.config.system.build.toplevel.drvPath` succeeds.
- [ ] **Step 5:** Route the commit onto the chain.

## Task 4: Registration (tasks.md §4)

- [ ] **Step 1:** Edit `modules/clan/machines.nix`, `modules/clan/inventory/machines.nix`, and `modules/clan/inventory/services/users/cameron.nix`.
- [ ] **Step 2:** Create `modules/clan/inventory/services/wifi.nix` instancing clan-core's wifi service for pyrite, after `zerotier.nix`'s shape. import-tree discovers the file, so no import line is added.
- [ ] **Step 3:** Add `"pyrite"` alphabetically to both hardcoded lists in `modules/checks/structure/flake-shape.nix`.
- [ ] **Step 4:** Move the staged `pyrite-facter.json` to `machines/pyrite/facter.json` and git-track it, in one commit with Tasks 2, 3, and Steps 1 and 3 above.
- [ ] **Step 5:** Run `nix flake check`, confirming the auto-emitted `nixos-pyrite` check builds.

## Task 5: Secrets and ZeroTier vars (tasks.md §5)

- [ ] **Step 1:** Stand up the dedicated fleet SSID on the router. An operator action outside the repository, and a prerequisite rather than a parallel step: Step 2's prompts take their values from it. Generate the PSK with `xkcdpass` on the admin box, configure the router to serve a distinct SSID with `wpa-psk` security and that PSK, and confirm it is broadcasting.
- [ ] **Step 2:** `clan vars generate pyrite`; commit vars, sops machine key, ZeroTier identity/IP, the zfs passphrase, and the fleet SSID and PSK. The wifi service adds two prompts, which take Step 1's values and do not generate them; a re-run does not re-prompt without `--regenerate`.
- [ ] **Step 3:** Record the generated passphrase in the password manager under `pyrite/zfs-root` before first boot, and verify the entry against `clan vars get pyrite zfs/key`. The committed var is encrypted to exactly one human key, so a copy outside the repository is what keeps a lost age key from being a lost pool.
- [ ] **Step 4:** Add the `&pyrite` anchor and the `*pyrite` bridge recipient to `.sops.yaml`; `just update-all-keys`; confirm existing machines still decrypt the bridge secret.
- [ ] **Step 5:** `clan machines update cinnabar` to admit the peer. This touches the fleet coordinator.

## Task 6: The recorded install path (tasks.md §6)

- [ ] **Step 1:** Write the install artifact: `blkdiscard` the `_1` path first, then `clan machines install` with `--update-hardware-config` at its default. Not `sgdisk --zap-all` — see design.md D8.
- [ ] **Step 2:** Document why the wipe is a step, that `--disk-encryption-keys` is appended automatically, the ISO prerequisites, the skipped clan subcommands, the build-host fallback, and the USB-C keyboard prerequisite.
- [ ] **Step 3:** Route the commit onto the chain.

## Task 7: Install and post-install (tasks.md §7)

- [ ] **Step 1:** Boot the ISO and authorize a key; confirm `blkdiscard` is present and record `blockdev --getss /dev/nvme0n1`.
- [ ] **Step 2:** This is the point of no return: it opens with the wipe, then runs `--phases disko` alone (`_legacyDestroy → _create → _mount` per D8, so macOS is destroyed here), and checks `sgdisk -p` shows the declared geometry while a bare `zpool import` finds no pool. The geometry check is the severe test of the disko declaration, run against the already-wiped disk rather than as a safeguard for macOS.
- [ ] **Step 3:** Run the full recorded path. macOS is already gone from Step 2's wipe; this completes the install.
- [ ] **Step 4:** Confirm boot, the stage-1 prompt on the internal keyboard, and root unlock; verify `keylocation=prompt`, `keyformat=passphrase`, `ashift=12`.
- [ ] **Step 5:** Confirm `wlp2s0` associated unattended with no credential typed into the installed system, the mesh is joined, the onion service is published, and sshd host certificates are present. The vars carry the credentials, so the association holds only if Task 5's Step 2 ran and was committed before the deploy; without it the profile interpolates empty strings and association fails silently. The onion service has the same dependency on Step 2, through a different var.
- [ ] **Step 6:** Add the `.zt` records to `cinnabar/zt-dns.nix`, `ssh-known-hosts.nix`, and `home/core/ssh.nix`; redeploy cinnabar; commit `inventory.json`.
- [ ] **Step 7:** Re-run the install from a fresh ISO boot including the wipe, and repeat the Step 4 property checks.
- [ ] **Step 8:** Confirm the machine reaches an interactive GNOME session: after Step 4's unlock and once boot completes, the GDM greeter renders on the internal Retina panel and authenticating `cameron` with the clan-generated user password (`clan vars get pyrite user-password-cameron/user-password`) reaches an interactive shell whose Activities overview responds. `systemctl is-active display-manager` returning `active` is necessary but not sufficient — `i915` KMS can leave the panel blank on the installed 6.18.37 kernel, and a session can restart-loop back to the greeter — so acceptance is a rendered greeter plus a reached, interactive shell. No audio and no network are involved, which is the travel-readiness point. See D19, Goal 5.
- [ ] **Step 9:** Confirm enabling GDM did not perturb the stage-1 passphrase prompt: Step 4's ZFS prompt still renders on the internal keyboard in initrd and unlocks before any graphical target starts. This holds structurally — the prompt is a stage-1 initrd event and `display-manager` is a stage-2 unit ordered after `systemd-user-sessions.service`, and GDM enables no plymouth, decidable off the hardware by `nix eval .#nixosConfigurations.pyrite.config.boot.plymouth.enable` returning `false`. See D11, D19.
- [ ] **Step 10:** Run the steady-state `clan machines update pyrite` bare — no `--target-host`, no `--build-host` — as the travel-readiness acceptance check. Confirm `getent hosts pyrite.zt` resolves to the `fddb:` ZeroTier address before running, since a `--target-host root@<lan-ip>` run would bypass the mesh, and deploy from a revision that actually changes pyrite's toplevel so `readlink /run/current-system` moves, since a same-revision run moves no closure and proves only that the connection opened. See D17, D18.

## Task 8: Hold the flake steady until the install lands (tasks.md §8)

- [ ] **Step 1:** Do not `nix flake update` before Phase 7. `clan-core` floats on `main.tar.gz` and carries nixos-anywhere's version transitively, with no node in `flake.lock` to make the move visible.
- [ ] **Step 2:** If the flake must move first, re-verify design.md D8 and D13 against the resulting nixos-anywhere version.
