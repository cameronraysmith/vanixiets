---
title: pyrite bare-metal install runbook
status: working-note
source-issue: CAM-32
---

# pyrite bare-metal install runbook

## Scope and provenance

This note records the re-runnable bare-metal install path for `pyrite`, an Apple MacBookPro14,1 enrolled as an encrypted-ZFS-root NixOS machine.
It is the recorded artifact Phase 6 of the pyrite-baremetal-nixos change (CAM-32) requires: the install is a recorded procedure in the repository, not something performed ad hoc.
The mechanics below were established by the change's design (see `openspec/changes/pyrite-baremetal-nixos/design.md`, decisions D8, D13, D18, D19) and its `bare-metal-install-path` spec, and they hold for nixos-anywhere 1.13.0, the version resolved through `clan-core.inputs.nixpkgs` at the current `flake.lock` (D13).
Do not run `nix flake update` before the install; an update can move nixos-anywhere's version with no visible entry in the lock, and every mechanic here was read from 1.13.0 (Phase 8, D13).

This document is the working-note home for the path.
Promoting it to published reference documentation under `docs/reference/` is a separate, deferred follow-on change and is out of scope for Phase 6.

Phase 7 of the change is where this path is executed, once: there is exactly one destructive install (task 7.3), and the second proving install that once followed it is dropped because the install of 2026-07-19 already demonstrated the path (D29). This note records the path and the reasons its steps are shaped as they are.

## Prerequisites before the first install

The fleet SSID must be broadcasting and the machine's clan vars must be generated and committed before the install runs.
The fleet network is the pre-existing household network `furtadosmith`, which the operator decided to use as the fleet network rather than standing up a distinct SSID (D14), so no router work is required and the network is already broadcasting.
Phase 5 covers the rest: run `clan vars generate pyrite` from the admin box and commit the generated vars — the sops machine key, the ZeroTier identity and IP, the ZFS root passphrase, and the wifi SSID and PSK — along with the sops recipient changes.
The wifi credentials are shared clan vars under `vars/shared/wifi.fleet/`, so the reinstalled machine associates with no operator typing credentials into it; if the vars are absent the NetworkManager profile interpolates empty strings and association fails silently at first boot, with nothing at eval time to catch it.

A USB-C keyboard, or a USB-C-to-USB-A adapter for a USB-A keyboard, must be physically in the room before any boot in this procedure, and this is a gate rather than a recommendation.
A MacBookPro14,1 has USB-C ports only and no USB-A port, so an adapter cannot be improvised at the moment it is needed.
The moment it is needed is the stage-1 passphrase prompt, which waits with an unbounded timeout: if the internal SPI keyboard does not bind on a given boot, the external keyboard is the only way to answer it, and until it is answered the machine has no reachable state at all.
Confirm the keyboard or adapter is on hand before booting the installer, not after a prompt goes unanswered.
The mechanism, and why the two keyboards reach the initrd by different routes, is in "USB-C keyboard is a first-boot prerequisite" below.

The install is driven from the admin box (stibnite).
The internal disk's namespace-explicit device path is `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1` — the `_1` namespace, matching the disko layout's `device`.
Substitute `<installer-ip>` throughout with the address the booted installer reports for its wireless interface.

## Which host runs which command

Every command block in this note opens with a `# host:` comment naming the machine that command runs on, and no block mixes hosts.
Three hosts appear: `stibnite` is the admin box, `pyrite (installer)` is pyrite running the booted installer ISO, and `pyrite (installed)` is pyrite running its own installed system.
The distinction is load-bearing rather than bookkeeping.
`blkdiscard` and every `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_...` path below name pyrite's internal disk, and stibnite has a device namespace of its own in which the same commands run against stibnite's disk without complaint.
The install steps that bracket the wipe run on stibnite, so an operator working down the page without reading the host lines is one paste away from discarding the wrong machine's disk.
Read the `# host:` line before typing anything.

## Validating the LUKS2 layout in a VM before the install

The container layout is exercised end to end in a QEMU VM before any hardware step, because the machine has no fallback OS and every mechanic D1 introduced is one whose omission is silent.
disko emits `system.build.installTest` for every machine that declares a layout: it formats the declared devices inside a test VM, mounts and unmounts them, destroys and recreates them, installs the bootloader, and boots the result.
The test runs on pyrite itself, against the currently installed system, and touches neither `zroot` nor the ESP — it builds derivations and runs QEMU against qcow2 files inside the build sandbox.
It must run before the installer ISO is booted, since booting the ISO takes away the machine that runs it.

pyrite is the only host in the fleet that can run it.
The derivation carries `requiredSystemFeatures = kvm nixos-test` and builds for `x86_64-linux`; `modules/system/magnetite-builder.nix:31-41` deliberately does not advertise `kvm`, so the scheduler will not route there, and the rosetta builder is an aarch64 VM that cannot KVM-accelerate an x86_64 guest.

The naive invocation does not work, and the reason is worth recording because three of the four obstacles are silent rather than loud.
`nix build .#nixosConfigurations.pyrite.config.system.build.installTest` fails at evaluation on a `boot.zfs.devNodes` conflict — `disko/lib/tests.nix:201` sets `/dev` at normal priority against the host module's `/dev/disk/by-id`.
Behind that, `passwordFile` and `additionalKeyFiles` both name `/run/partitioning-secrets/zfs/key`, which clan-cli materialises only during a real install, so `cryptsetup luksAddKey` would read a file that does not exist.
And `enrollFido2 = true` sends `disko/lib/types/luks.nix:275-302` into `wait_for_token`, which polls `ls /dev/hidraw*` forever; `installTest` passes no `enableCanokey`, so the test VM has no token to find and the run hangs rather than failing.
disko's own FIDO2 coverage sets `enableCanokey = true` explicitly and `installTest` has no way to.

The test therefore runs against a configuration that overrides exactly those four things and nothing else.
pyrite has no checkout of this repository, so the tree has to be put there first — pushing the bookmark and cloning it is what leaves a revision the runbook can name, which `rsync` does not:

```bash
# host: stibnite
jj git push -b pyrite-baremetal-nixos
```

```bash
# host: pyrite (installed)
git clone --branch pyrite-baremetal-nixos --single-branch \
  https://github.com/cameronraysmith/vanixiets.git /root/vanixiets
cd /root/vanixiets
git rev-parse HEAD
sha256sum modules/machines/nixos/pyrite/disko.nix flake.lock
```

Confirm the two hashes match stibnite's before going further; they, and not the derivation path, are what establish that the tree under test is the tree that was written.
The derivation path differs legitimately between a dirty colocated worktree and a clean checkout, so a mismatch there is a prompt to diff rather than a failure.

Write the test expression outside the repository:

```nix
# host: pyrite (installed) -- /root/pyrite-luks-vmtest.nix
let
  flake = builtins.getFlake (toString /root/vanixiets);
  lib = flake.inputs.nixpkgs.lib;
in
(flake.nixosConfigurations.pyrite.extendModules {
  modules = [
    {
      boot.zfs.devNodes = lib.mkForce "/dev/disk/by-id";
      disko.devices.disk.primary.content.partitions.zfs.content = {
        enrollFido2 = lib.mkForce false;
        passwordFile = lib.mkForce "/tmp/secret.key";
        additionalKeyFiles = lib.mkForce [ "/tmp/additionalSecret.key" ];
      };
      boot.initrd.systemd.enable = true;
      disko.tests.enableOCR = true;
      disko.tests.bootCommands = ''
        machine.wait_for_text("[Pp]assphrase for")
        machine.send_chars("secretsecret\n")
      '';
      disko.tests.extraChecks = ''
        machine.succeed("cryptsetup isLuks /dev/vda2")
        machine.succeed("test -e /dev/disk/by-id/dm-name-cryptroot")
        machine.succeed("zpool get -H -o value ashift zroot | grep -x 12")
        machine.succeed("zfs get -H -o value encryption zroot/root | grep -x off")
        machine.succeed("zfs get -H -o value xattr zroot/root | grep -x sa")
        machine.succeed("zfs get -H -o value acltype zroot/root | grep -x posixacl")
        machine.succeed("echo -n additionalSecret > /tmp/additionalSecret.key")
        machine.succeed("cryptsetup open --test-passphrase --key-file=/tmp/additionalSecret.key /dev/vda2")
      '';
    }
  ];
}).config.system.build.installTest
```

```bash
# host: pyrite (installed)
nix build --impure --expr 'import /root/pyrite-luks-vmtest.nix' -L \
  --out-link /root/pyrite-luks-vmtest-result 2>&1 | tee /root/pyrite-luks-vmtest.log
echo "exit=${PIPESTATUS[0]}"
```

The criterion is `exit=0` with `/root/pyrite-luks-vmtest-result` resolving to a store path containing `log.html`.
The test driver aborts the derivation on the first failing step, so a non-zero exit names the failing command in the log and there is nothing to interpret in a green run.
`meta.timeout = 600` in disko's harness is a Hydra hint that `nix build` does not enforce; the enforced limits are the driver's 900-second per-command defaults, so an OCR misread of the passphrase prompt surfaces as a fifteen-minute hang rather than an error.

Each override is a stated divergence rather than a convenience.
`boot.zfs.devNodes` resolves the conflict in pyrite's favour and not the harness's, which is the point: keeping `/dev/disk/by-id` is what forces the booted VM's `zfs-import-zroot` to find the pool through the dm udev rules' `dm-name-cryptroot` symlink, and forcing the harness value `/dev` would sidestep the mechanism the test exists to check.
disko justifies `/dev` on the grounds that `/dev/disk/by-id` is empty in QEMU VMs, which holds for virtio disks, whose by-id entries QEMU does not supply, and not for device-mapper nodes, whose symlinks the dm udev rules produce.
`boot.initrd.systemd.enable` is restored explicitly because `enrollFido2` was the only thing setting it, and the prompt under test is systemd's `systemd-ask-password` rather than the scripted initrd's.
The two key files are deliberately different so that the `cryptsetup luksAddKey` branch stays live instead of short-circuiting on `--test-passphrase`; the harness writes both with `echo -n`, which is what makes the post-boot `--test-passphrase` check severe against the trailing-newline failure D27 turns on.

What a green run establishes is bounded, and the boundary matters.
It establishes that the LUKS2 container is created on the ESP's sibling with the nested `zfs` content registering `/dev/mapper/cryptroot` as the pool's vdev, that a passphrase slot added through `additionalKeyFiles` opens the container, that stage 1 renders the prompt and the typed passphrase unlocks it, that `zpool import -d /dev/disk/by-id` finds the pool, and that `ashift`, `xattr`, `acltype`, and `encryption=off` read back as declared.
It establishes nothing about the FIDO2 tap: `enrollFido2` is off, so `systemd-cryptenroll`, the `--wipe-slot=0` that removes the throwaway format key, and the `fido2-device=auto` crypttab option are all absent, and because `enrollFido2` is what turns on the autogenerated format password, the test formats directly with the passphrase and never exercises the format-then-add-then-wipe ordering.
It establishes nothing about the clan vars path, since `passwordFile` is redirected away from it, nor about the `_1` namespace, Apple's ESP-by-type discovery, the SPI keyboard, the i915 framebuffer, `blkdiscard`, or the 4096-byte sector premise behind `ashift = 12` — QEMU reports 512-byte sectors and the check passes only because the value is explicit.
One reading is actively misleading: the harness asserts that a second format against a surviving container leaves the data intact, which is the same `luks.nix:202` skip the recorded `blkdiscard` exists to foreclose, asserted here as a pass.
A green run says nothing about the wipe and points the wrong way if read as such.

Memory is the only tight resource on pyrite: 16 G total against 4 concurrent build jobs, a live GNOME session, and ZFS ARC.
Run it with the desktop idle, or stop `display-manager` first, and drop to `-j 2` if the machine starts swapping.
Plan on 20 to 45 minutes, dominated by fetching the flake's input sources — pyrite holds its own system closure but none of the lock's sources, because that closure was built on stibnite and pushed.

## Boot the installer and authorize a key

The install artifact is an upstream stock NixOS graphical installer ISO, `dd`-written to external media, carrying no key, credential, or machine closure (D18).
The image whose behaviour was measured on this unit is `nixos-graphical-26.05.5092.4382ed2b7a68-x86_64-linux.iso`, sha256 `61f409eeabb54d5289b91ce384cc33a7b1f82ac1cb22707407bf56f8bc4b9758`; the machine's only NIC is a BCM4350 driven by `brcmfmac`, and this image was observed loading that firmware unaided, which is why it is preferred over an unverified image at the one moment the disk is about to be destroyed.

Boot media is required, and the reason is specific to this machine rather than general practice.
nixos-anywhere can kexec into its own installer from a running NixOS system, which would ordinarily make an ISO unnecessary, and a reader who knows that will otherwise read this step as superstition and skip it.
It is necessary here because pyrite's only physical NIC is WiFi — `wlp2s0`, with no ethernet port on the machine — and the kexec installer image cannot hold an 802.11 association.
Its network restoration is layer 3 only: `nix/kexec-installer/module.nix` runs `restore-network`, built from `restore_routes.py`, which replays the addresses and routes captured by `ip --json` into systemd-networkd units matched on MAC address, and nothing more.
The image force-disables NetworkManager (`nix/kexec-installer/module.nix:37`) and ships neither wpa_supplicant nor iwd — nixos-images' iwd configuration lives in `nix/image-installer/wifi.nix`, which the kexec installer does not import.
Kexecing therefore drops the association and leaves the machine with no path back onto the network, stranding the install.
The mesh is not an alternate route back in either: the kexec image carries none of pyrite's clan vars, including its ZeroTier identity.
The USB installer gives an environment with NetworkManager and `nmtui`, in which the operator re-associates by hand before the install begins.

Boot it with the Option key held at power-on; there is no firmware password.

Select `NixOS 26.05.5092.4382ed2b7a68 Installer GNOME (Linux LTS)` at the GRUB menu.
This is not cosmetic and it is the one menu choice that can destroy the disk.
The image presents four entries, read from `/iso/EFI/BOOT/grub.cfg` at `:68`, `:78`, `:88`, and `:98`: GNOME (Linux LTS), GNOME (Linux 7.1.3), Plasma (Linux LTS), and Plasma (Linux 7.1.3).
The two `7.1.3` entries are the `*_latest_kernel` specialisations, which import `nixos/modules/installer/cd-dvd/latest-kernel.nix`, whose `:4` sets `boot.supportedFilesystems.zfs = false` — so on those entries there is no `zfs` kernel module and no `zpool` on PATH.
Booting one of them and proceeding would run the `blkdiscard`, destroy macOS, and then fail at `zpool create` with nothing to fall back to.
The LTS entries carry `zfs.ko.xz`, `spl.ko.xz`, and `zpool` from `zfs-user-2.4.2` on kernel 6.18.38.
The GNOME LTS entry is GRUB's default — the config sets no `set default`, so entry 0 is selected, and `set timeout=10` means an unattended boot lands on it — but the menu is presented for ten seconds and a keypress can move off it, so the selection is confirmed rather than assumed.
The Plasma LTS entry would also pass the ZFS check; it is not chosen because it changes the desktop the recon was performed under for no gain.
Selecting LTS does not put the NIC at risk: the firmware closure is the identical store path across both specialisations and `brcmfmac` is present in the 6.18.38 `modules.dep`.

The menu label is gone once the machine has booted, so the selection is re-confirmed from inside the running installer, and this check is a hard gate on everything destructive that follows:

```bash
# host: pyrite (installer)
uname -r      # must report 6.18.38 -- NOT 7.1.3
```

`6.18.38` is the LTS entry and is the only value that permits the operator to continue.
`7.1.3` means the machine came up on a `*_latest_kernel` specialisation, on which `boot.supportedFilesystems.zfs = false` leaves no `zfs` module and no `zpool`: proceeding from there runs the `blkdiscard`, destroys macOS, and then fails at `zpool create` on a machine with no fallback OS and nothing to boot.
If `uname -r` reports `7.1.3`, reboot onto the LTS entry and repeat the key authorization below, which does not survive the reboot.
This one command stands in for the two positive checks it implies, `modprobe zfs` succeeding and `command -v zpool` resolving, and it is cheaper than either.

In the GNOME session the ISO presents, join the fleet SSID through the NetworkManager applet (or `nmtui`), and set a password for the `nixos` account with `passwd nixos` — the profile ships empty passwords and sshd refuses empty-password auth, so a password is required before ssh works.
sshd is already running on the stock installer; no `systemctl start sshd` is needed.

From the admin box, authorize a key against the running installer session:

```bash
# host: stibnite
ssh-copy-id nixos@<installer-ip>
```

Appending the public key directly is equivalent and is the form the recorded run used, from the machine's own GNOME session rather than from the admin box:

```bash
# host: pyrite (installer), from the GNOME session on the machine itself
curl -sSL https://github.com/cameronraysmith.keys >> ~/.ssh/authorized_keys
```

Either writes `/home/nixos/.ssh/authorized_keys` and authorizes the key for the running installer session only.
It is not written to the installer media, so it must be repeated if the installer is rebooted — including the reboot onto the LTS entry, if the machine came up on a `7.1.3` entry first.

Then place the same key for root:

```bash
# host: pyrite (installer)
sudo mkdir -p /root/.ssh && sudo cp ~/.ssh/authorized_keys /root/.ssh/
```

This is a standing prerequisite rather than a contingency for a particular invocation.
It defuses the `root@` rewrite failure mode described below: `src/nixos-anywhere.sh:978-983` rewrites `sshConnection` to `root@${sshHost}` whenever the `kexec` phase is absent, and it does so before `uploadSshKey` at `:983`, which wraps `ssh-copy-id` in an `until ... sleep 3` loop with no abort — so against a root account that has an empty password sshd refuses (`installation-device.nix:48`) and no authorized_keys, the install hangs indefinitely on "Uploading install SSH keys" rather than failing.
Authorizing root up front means that path terminates even if a `--phases` flag is ever passed by accident, which is a cheap hedge against a hang that would otherwise land after the irreversible wipe.
Like the `nixos` authorization, it does not persist to the media and must be repeated after any installer reboot.

The install targets `nixos@<installer-ip>`, not `root@`.
The stock installer autologins the `nixos` user, places it in `wheel`, and gives it passwordless sudo, while both `nixos` and `root` ship empty passwords that sshd refuses for password auth.
`root@` would therefore need a key hand-installed into `/root/.ssh` first, whereas `nixos@` needs only the key authorized in the GNOME session already open on the machine, and nixos-anywhere escalates to root through that passwordless sudo.
The installed system's `deploy.targetHost = "root@pyrite.zt"` (registration task 4.2) is a different thing entirely — it deploys over ZeroTier to the installed machine's own host key — and it stays as it is.

The live ISO is itself the installer environment (`VARIANT_ID=installer`), so nixos-anywhere's kexec phase is a no-op: it returns immediately when the target is already an installer, and the running live-CD ssh access is exactly and sufficiently what the install consumes.
This forecloses any "physical install, then update over the network" misconception — there is no second step.

Do not pass a `--phases` flag by hand, in any form, for any reason.
The prohibition is on operator-supplied flags only, and the distinction is not pedantry: clan itself passes phases one at a time internally, so a reader watching the install and seeing `--phases` on the wire must not conclude the rule is wrong or that the same flag is safe to add.
The mechanism is that any operator-supplied `--phases` value zeroes `phases[kexec]`, and `src/nixos-anywhere.sh:978-983` then rewrites `sshConnection` to `root@${sshHost}` whenever the `kexec` phase is absent.
It does so before `uploadSshKey` at `:983`, which wraps `ssh-copy-id` in an `until ... sleep 3` loop with no abort condition, against a root account whose empty password sshd refuses (`installation-device.nix:48`).
The result is an unbounded hang on "Uploading install SSH keys" rather than a failure, and it lands after the irreversible wipe, on a machine that no longer has an operating system to fall back to (D13).
Authorizing root up front, as above, is what makes that path terminate if the flag is ever passed by accident; it is a hedge, not a licence to pass one.

## The recorded install path

The path's first step wipes the disk explicitly, at every offset rather than only at the partition table, and only then invokes `clan machines install`.
The three steps do not run on one host: step 0 and step 2 run on stibnite, and step 1 runs on pyrite's booted installer.
They are written as separate blocks for that reason, and step 1 — together with the post-wipe verification that immediately follows it, which also runs on the installer — is the part that destroys a disk.

This install cannot be driven hands-off, and the operator has to plan on being at the machine for the whole disko phase rather than starting it and walking away.
Two prompts land in the middle of it and neither can be scheduled.
The FIDO2 enrollment asks for the token's PIN, and it asks on stibnite, over the pty `ssh -t` allocates for the disko phase — so the terminal that started the install has to stay attended.
That routing is conditional in two ways, and both are worth stating rather than assuming.

nixos-anywhere decides the flag once at startup from `[ -t 0 ]` (`src/nixos-anywhere.sh:35-38`) and re-passes it on every `runSsh` (`:472-482`), which is what carries the disko script at `:854`; clan inherits its own fd 0 into that process, since `clan_lib/cmd/__init__.py:388-399` leaves `input` at `None` and sets `needs_user_terminal=True`.
So the prompt lands on stibnite only while the install is launched from an interactive terminal.
Under `nohup`, a redirect, a `tmux send-keys` pipeline, or a CI runner, the flag becomes `-T` and `systemd-cryptenroll` falls through `ask_password_auto` (`ask-password-api.c:1141-1145`) to the ask-password agent, which prompts on pyrite's own console and waits with `until = USEC_INFINITY` rather than returning an error.
Neither branch aborts the script: a missing tty produces the same indefinite wait the touch does, not a post-wipe exit under `set -efux`.
Launch the install from an attended terminal and neither question arises.

Whether a PIN is asked for at all depends on the token rather than on the configuration.
`cryptenroll.c:62` requests PIN and user presence both, and the layout passes no `extraFido2EnrollArgs` to change it, but `libfido2-util.c:802-804` clears the PIN requirement when the token reports its `clientPin` option false — which is what an authenticator that supports PINs but has none set reports.
A token with no client PIN set therefore prompts only for the touch.
This runs in the safe direction, one fewer blocking prompt rather than one more, and the pre-wipe `ykman fido info` gate above is what settles it in advance: it is there to confirm the PIN is set, and its answer is also the answer to how many prompts to expect.

The touch is unconditional.
It is a physical press on the token seated in pyrite, at a moment that depends on how long `luksFormat` takes and is not announced in advance.
Both prompts fall after the wipe.
An unattended run reaches the touch, waits, and leaves the machine with a formatted container, no enrolled token, and no operating system.

```bash
# host: stibnite
# Confirm an x86_64-linux builder answers, BEFORE the wipe.
sudo nix store info --store ssh-ng://builder@magnetite
```

Require the `Version:` and `Trusted:` lines to appear.
A non-zero exit, or an `ssh: connect to host` line, means there is no reachable x86_64-linux builder; restore ZeroTier connectivity to magnetite before proceeding.
This is checked rather than assumed because the failure is silent in the expensive direction: nixos-anywhere runs at `--build-on auto`, so with no builder answering it does not fail, it falls back to building pyrite's entire closure on the installer ISO — on the machine whose disk has just been discarded, over WiFi, in a tmpfs-backed live environment.
`ping6 -c 3 fddb:4344:343b:14b9:399:930f:39db:40d2` is a cheaper liveness check that needs no sudo, but ICMP does not prove the store is answering and does not replace the probe above.

Four further gates precede the wipe, and all four are hard stops rather than advisories: if any does not pass, do not run the `blkdiscard`.
They are stated here in full because the operator standing at the machine is reading this page and nothing else.

The first confirms that exactly one FIDO2 token is seated and answering:

```bash
# host: pyrite (installer)
# The stock graphical ISO ships neither libfido2 nor yubikey-manager, so the
# tools are fetched into a shell. This needs network but no experimental-features
# flag. `nix run nixpkgs#libfido2` does not work at all -- the package declares no
# meta.mainProgram; the flake form is `nix shell nixpkgs#libfido2 -c fido2-token -L`.
nix-shell -p libfido2 yubikey-manager --run 'fido2-token -L; ykman fido info'
```

Require `fido2-token -L` to list exactly one device, and `ykman fido info` to report a PIN-attempt count, which is what confirms the client PIN is set.
Exactly one, because disko passes no device path and `systemd-cryptenroll --fido2-device=auto` resolves only where the choice is unambiguous; the second token is enrolled after the install, in the key-lifecycle section below.
With no network on the installer, `systemd-cryptenroll --fido2-device=list` is the in-closure substitute, since systemd is built `withFido2` and the call needs no privilege.
It answers the device-presence half and not the client-PIN half, so a pass on it alone leaves the PIN unverified and has to be recorded as such.

This is checked positively, and checked here, because disko's own guard does not hold on this machine and it fails in the direction that looks like success.
`wait_for_token` (`lib/types/luks.nix:277-292`) gates on `ls /dev/hidraw* &>/dev/null` at `:283`, a bare node-existence test with no capability check of any kind, and this machine's internal Apple SPI keyboard registers a `hidraw` node independently of any token — so the guard passes immediately with nothing seated at all.
`systemd-cryptenroll --fido2-device=auto` at `:295-300` then resolves nothing, and because that call is a body command rather than a condition, the script exits under the `set -efux` established at disko `lib/default.nix:1012` — after the `luksFormat` at `:244` has already replaced the container.
On a machine with no fallback OS that is an unrecoverable post-wipe abort, produced by the guard that appears to prevent it.

The second proves on the admin box that every secret whose silent absence costs pyrite its network or its remote access is present, decryptable, and encrypted to pyrite:

```bash
# host: stibnite, from the repository root
bash <<'SH'
set -euo pipefail
PYRITE_AGE_PUB=age1eajmgz9zvq639zjnmqcaklst6u3s7un8k68nd4klnnlswgtrnylq7twk4v

test -f sops/secrets/pyrite-age.key/secret
sops decrypt --input-type json --output-type binary sops/secrets/pyrite-age.key/secret >/dev/null
test "$(sops decrypt --input-type json --output-type binary sops/secrets/pyrite-age.key/secret | age-keygen -y /dev/stdin)" \
   = "$(jq -r '.[0].publickey' sops/machines/pyrite/key.json)"

for f in vars/shared/wifi.fleet/network-name \
         vars/shared/wifi.fleet/password \
         vars/shared/zerotier-identity-pyrite/identity-secret \
         vars/shared/user-password-cameron/user-password-hash \
         vars/per-machine/pyrite/openssh/ssh.id_ed25519 \
         vars/per-machine/pyrite/zfs/key; do
  test -f "$f/secret" || { echo "missing: $f/secret"; exit 1; }
  sops decrypt --input-type json --output-type binary "$f/secret" >/dev/null || { echo "undecryptable: $f"; exit 1; }
  test "$(jq -r --arg k "$PYRITE_AGE_PUB" '[.sops.age[]|select(.recipient==$k)]|length' "$f/secret")" = 1 \
    || { echo "pyrite not a recipient: $f"; exit 1; }
done

clan vars check pyrite
echo "PRE-INSTALL SECRETS GATE: PASS"
SH
echo "exit=$?"
```

Run it as a saved script or as the heredoc above, not as a paste, and take the `PASS` line as the pass rather than the absence of a visible error.
Three properties of the block are load-bearing.
`set -euo pipefail` is what makes the first three statements stop the run: they carry no `|| exit` of their own, so without it a missing or misnamed `sops/secrets/pyrite-age.key/secret` prints one error line, falls through into the loop, and terminates on `clan vars check pyrite`, whose exit status is independent of `sops/secrets/` — leaving the operator looking at a successful last command having just walked through the early-return branch this gate exists to close.
The heredoc is what keeps the loop's `exit 1` arms from closing the operator's own shell, which is the shell needed to read the failure.
And the trailing `PASS` line is the affirmative signal; `exit=0` alone is what the failing form also prints.

The machine age key is the branch this gate exists to close.
clan supplies `--extra-files` itself — `clan_lib/machines/install.py:162-168` passes it unconditionally, populated at `:141-147` into the machine's `clan.core.vars.sops.secretUploadDirectory`, which pyrite evaluates to `/var/lib/sops-nix`, the same path `config.sops.age.keyFile` reads `key.txt` from — so the delivery is by construction.
What is not by construction is the one branch that skips it without raising: `clan_lib/vars/secret_modules/sops.py:250-260` returns early when `has_secret` is false, and `has_secret` is the literal predicate `(secret_path / "secret").exists()` (`clan_cli/secrets/secrets.py:371-372`), so a missing or misnamed `sops/secrets/pyrite-age.key/secret` writes no `key.txt`, raises nothing, and takes the install green.
With no `key.txt` on the installed machine sops-nix decrypts nothing: the deployed ZeroTier identity secret is unreadable, so `zerotierone` starts with no identity and mints a fresh one that cinnabar has not authorized, and `pyrite.zt` resolves to an address no live node holds.
The fleet WiFi vars fail by the same silent path and compound it, because WiFi is this machine's only NIC — `clanServices/wifi/default.nix:126-141` reads the sops-nix paths at runtime into the NetworkManager secrets file, an unreadable file yields empty strings, and the interface never associates with no assertion and no eval-time error.
The machine is then console-only, with no route to it but its own keyboard.
A file that exists but does not decrypt is loud instead, since `decrypt_secret` raises and the install aborts before nixos-anywhere runs, which is why the file test is the arm that closes the silent branch and the decrypt arms cover the rest.

The recipient arm is not redundant with the decrypt arm, and that distinction is the point of the check rather than a flourish: a var the operator can read but pyrite cannot is exactly the shape of the WiFi failure above, and only the recipient arm catches it.
Two secrets correctly lack `pyrite` as a recipient and must not be added to one to make a naive sweep pass — `sops/secrets/pyrite-age.key` is admin-only by design, which is the chicken-and-egg `--extra-files` exists to break, and `vars/per-machine/pyrite/emergency-access/password` carries `deploy = false`.
`zfs/key` is in the list for a different reason than the others: it travels the separate automatic `--disk-encryption-keys` channel (`install.py:170-182`), and if it is absent `run_generators` mints a fresh passphrase, so the container is created under a credential the operator never recorded and cannot type at the initrd prompt.
`openssh/ssh.id_ed25519` is in the list because `modules/system/ssh-known-hosts.nix:66-72` and `modules/home/core/ssh.nix:107-110` both pin `pyrite.zt` to the public half read back out of the flake, so a host key that fails to land yields a machine that is up and on the mesh and that the admin box refuses on key mismatch.

The third records the GUID of the pool now on the disk, which is the baseline the post-install create-path check compares against:

```bash
# host: pyrite (installer)
# Lists importable pools and their GUIDs from the on-disk labels. Reads only:
# it needs no key and it does not import. Record the id printed for zroot.
zpool import
```

Take it here because after the wipe there is nothing left to read it from.
It is a real baseline rather than a formality: the disk carries a live pre-D1 `zroot` today, so a `blkdiscard` that does not reach the media leaves that pool's labels in place, disko's `lib/types/zpool.nix:298` `zpool import -N -f "zroot"` succeeds, and `:299` logs "not creating zpool zroot as a pool with that name already exists" while never applying `ashift`.
With the baseline recorded, the post-install `zpool get -H -o value guid zroot` discriminates that outcome from a genuine create; without it, that reading is a number with nothing to compare to.
There is no analogous baseline for `cryptsetup luksUUID` and none is invented, because this disk carries no LUKS header before the install.

The fourth confirms the installer is on the network and stays there:

```bash
# host: pyrite (installer)
nmcli connection show --active     # names the fleet network
ping -c 3 1.1.1.1                  # internet egress
```

```bash
# host: stibnite
ssh nixos@<installer-ip> true      # the admin box can still reach it
```

This is a gate rather than a convenience because the nix store is deliberately not staged across the reformat: roughly 21 G of closure is re-fetched over this link after the disk is gone.
WiFi is this machine's only NIC — there is no ethernet port, no fallback OS once `blkdiscard` runs, and the installer's association does not survive a reboot — so an association that drops after the wipe leaves a machine with no network, no operating system, and no recovery short of re-flashing the external SSD and booting it again.
It is also the one prerequisite that cannot be repaired remotely, because repairing it is what the remote path depends on.
Re-associate through `nmtui` in the installer's own session if this fails, and do not proceed until it passes.

```bash
# host: stibnite
# 0. Realise nixos-anywhere BEFORE the wipe. Substitutable from
#    cache.nixos.org: 22 paths, 78.9 MiB.
nix build --no-link /nix/store/2svzjf9qgwn6m2i69mqpjlb5n94dgm5g-nixos-anywhere-1.13.0
nix path-info /nix/store/2svzjf9qgwn6m2i69mqpjlb5n94dgm5g-nixos-anywhere-1.13.0
```

```bash
# host: pyrite (installer)
# 1. Wipe the target disk at every offset. THIS IS THE POINT OF NO RETURN:
#    macOS on the internal disk is destroyed here. This is the last step
#    whose success the operator can observe before the install commits.
#    This by-id path names pyrite's internal NVMe. Run it in a shell on
#    the booted installer -- over ssh from stibnite or at pyrite's own
#    console -- never in a stibnite shell, where the same command finds
#    stibnite's own devices.
blkdiscard /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1
```

Verify the wipe took, before running the install and while the machine can still be looked at:

```bash
# host: pyrite (installer)
disk=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1

# 1a. First 64 MiB reads as zeroes. Must print 0.
dd if="$disk" bs=1M count=64 status=none | tr -d '\0' | wc -c

# 1b. No filesystem, RAID, or partition-table signature anywhere. Must print nothing.
wipefs -n "$disk"

# 1c. No partition table. Must open with "Creating new GPT entries in memory."
#     and list no partitions. -p reads and reports only; it writes nothing.
sgdisk -p "$disk"
```

All three are required, because each is blind to what the others catch.
The `dd` arm is the only one that speaks to bulk content rather than to signatures, but it reads the head of the disk alone and says nothing about the secondary GPT at the tail.
`wipefs -n` probes every signature offset libblkid knows, including that secondary header, and reports magic rather than content, so it passes over a region that is nonzero but carries no recognised signature.
`sgdisk -p` is the arm that names a surviving partition table outright; on a wiped disk it announces that it is inventing GPT entries in memory, which is the pass, and a printed geometry with partitions listed is the failure.
A `blkdiscard` that reported success and left any of the three failing means the discard did not reach the media, and the install must not be started.

```bash
# host: stibnite
# 2. Install. --update-hardware-config is left at its default of `none`;
#    the committed machines/pyrite/facter.json is what the build consumes.
clan machines install pyrite \
  --target-host nixos@<installer-ip> \
  -i ~/.ssh/id_ed25519 \
  --yes
```

Step 0 is ordered ahead of the wipe rather than left to the install to resolve, because nixos-anywhere is fetched lazily and is first needed strictly after the point of no return.
clan resolves it at install time from a runtime-deps flake vendored inside the clan-cli derivation, not from the admin box's environment — `CLAN_PROVIDED_PACKAGES` is `age:git:nix` and does not include it — and the store path was not realised locally when this was checked.
A network failure at that moment would land after macOS is already destroyed, on a machine whose only NIC is wireless, which is a worse place to discover a missing 78.9 MiB than before the wipe.
`nix path-info` exiting 0 against the path is the confirmation; the operator realised it ahead of the install, so this is a recorded step of the path rather than an open action.

`blkdiscard` is on the installer's PATH (it ships in `util-linux`, folded into every NixOS system's `environment.systemPackages`); Phase 7 confirms this on the machine with a two-command check before relying on it, together with `blockdev --getss /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1` to record the logical sector size the `ashift = "12"` decision assumes.
The by-id form is used there as everywhere else in this note, including for the reads.
`/dev/nvme0n1` and `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1` name the same device on pyrite, but the short name is a kernel enumeration order rather than an identity, it resolves on stibnite to a different disk entirely, and the controller exposes a second namespace whose by-id name ends `_2` and must never be written.
A measurement taken against a name that does not identify the disk is not evidence about the disk, even when it is read-only.

`blkdiscard` from util-linux 2.42 prints `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1: contains existing partition (gpt).` and then performs the discard.
This is a warning, not a refusal, and it reads exactly like one — the message names the obstacle and offers no result, so an operator reasonably reads it as the reason nothing happened.
It was observed on the install and the wipe was verified complete afterward: zero non-zero bytes in the first 64 MiB, no filesystem or pool signatures, no GPT, and the offset the old APFS container occupied reading zeros.
Do not go looking for a `--force` flag on the strength of this message.
There is nothing to force and re-running the command changes nothing.
The check that settles it is the post-wipe verification above, not the command's output.

The wipe uses `blkdiscard`, not `sgdisk --zap-all` and not `wipefs -a` on the whole disk.
This follows the form clan-core's own encrypted-root guide prescribes at `docs/src/guides/disk-encryption.md:84-88`.
Under D1's container the reason is restated rather than carried across from the ZFS-native layout, because what survives a partial wipe is no longer a pool.
Partition 2's `fstype` is now `crypto_LUKS` and not `zfs_member`, so disko's `disk-deactivate.jq` cannot reach its `zpool destroy -f` and `zpool labelclear -f` branch at `:7-9` for that partition at all — the branch is unreachable by type.
What runs instead is the bare `wipefs --all -f` partition arm at `:42-45`, which erases the primary LUKS2 signature while leaving the secondary header and the whole 16 MiB keyslot area intact, so the old passphrase and the old FIDO2 enrollment survive a wipe that reads as complete.
Zapping the GPT first is worse still: with no partition table there are no children for `lsblk` to report, so even that arm never runs, and the next install finds a valid header, skips `luksFormat` (`lib/types/luks.nix:202`), and skips the FIDO2 enrollment (`:276`) — the tautological green the re-runnability criterion forbids, produced by the step meant to prevent it.
`blkdiscard` against the `_1` namespace path destroys the header, the keyslot area, and every label at every offset, and has no such hole.

If `blkdiscard` is ever unavailable, the fallback order is absolute, and under D1's container it is no longer the ZFS one.
It is written out here as a labelled block for the same reason every other destructive step is: it names pyrite's internal disk, it runs on the installer and nowhere else, and stibnite has a device namespace of its own in which the same commands find stibnite's disk without complaint.

```bash
# host: pyrite (installer)
# FALLBACK ONLY, if blkdiscard is unavailable. Destroys the same disk blkdiscard
# does. The order is absolute: each step destroys the magic the step above it
# depends on.
disk=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1

cryptsetup luksErase --batch-mode "$disk-part2"
dd if=/dev/zero of="$disk-part2" bs=1M count=32
sgdisk --zap-all "$disk"
wipefs -a "$disk"
```

Then run the post-wipe verification above against `$disk`, which is what settles whether the fallback took; the four commands report their own success and not the disk's state.
`luksErase` goes first because it needs a header that still probes, and every step below it destroys the magic that probe depends on.
The 32 MiB overwrite follows because it covers both LUKS2 headers and the whole default 16 MiB keyslot area, rather than the primary signature alone.
The zap precedes the whole-disk `wipefs` for the reason the ZFS-era order recorded, that a partition-scoped step depends on the partition table the zap destroys.
`zpool labelclear -f "$disk-part2"` is dropped from the order rather than reordered: under a container p2 holds no ZFS labels to clear, because they live inside the container and are unreachable without opening it, so the command that used to open this list would now succeed at nothing and read as progress.

### Why the wipe is a step, not an assumption

The wipe is not there because the run is create-only.
The default disko mode destroys before it creates: `clan_lib/machines/install.py` passes no `--disko-mode`, so nixos-anywhere's default selects disko's `diskoScript`, which composes `_legacyDestroy` then `_create` then `_mount` (D8).
So on the happy path the wipe is belt-and-braces, and it is retained anyway for three reasons.
`_legacyDestroy` runs without `set -e`, so a destroy that fails silently falls through to `_create`, where a surviving Apple GPT causes `sgdisk --clear` to be skipped, the subsequent `sgdisk --new` calls re-typecode Apple's partitions in place, `mkfs.vfat` is skipped on an ESP already reporting a type, and the machine boots Apple's 300 MiB ESP rather than the declared layout.
The explicit wipe is also the only step whose success the operator can independently observe before committing to an irreversible install.
And clan-core's own encrypted-root guide prescribes a manual `blkdiscard` before `clan machines install` for exactly this scenario, so upstream treats a pre-wipe as normal practice here rather than as belt-and-braces.

There is a fourth reason, and on any run where the previous install's container could survive it is stronger than the three above.
Under D1 the surviving artifact is the LUKS2 header rather than a pool, and it gates three create-path skips in sequence.
`lib/types/luks.nix:202` skips `luksFormat` against a header that still probes; `:257-258`'s `cryptsetup open --test-passphrase` then adds no key, because the old passphrase already opens the container; and `:276`'s `systemd-cryptenroll | grep -qw fido2` skips the FIDO2 enrollment against a token already recorded in that header.
So the second install can appear to have enrolled a token it never touched, which is a false green about the machine's own unlock credential.
Only once the container opens does the pool question arise at all — the vdev is `/dev/mapper/cryptroot`, which does not exist while the container is closed — and there disko's `lib/types/zpool.nix:298` tries `zpool import -N -f "zroot"` before it considers creating anything, and `:299` logs "not creating zpool zroot as a pool with that name already exists" while never re-applying `ashift`.
The wipe is what forecloses the whole chain, which makes it load-bearing rather than belt-and-braces on any run that follows an earlier install.
Which arm of that chain is live on this machine depends on what the disk actually holds, and it is not what an earlier revision of this note claimed.
The disk does not hold APFS: the install of 2026-07-19 replaced it, and p2 today carries a live pre-D1 `zroot` with ZFS labels and no LUKS header at all (task 7.16).
So none of the three container skips can occur on the single install ahead — they are recorded here as properties of the layout, for whoever reinstalls this machine later — while the pool arm is live, because a `blkdiscard` that does not reach the media leaves those labels in place.
The discriminating check is therefore `zpool history zroot` opening with a create entry timestamped inside the install session, and the pool GUID differing from the pre-wipe baseline task 7.2c records off `zpool import`'s listing before the disk is touched.
There is no `cryptsetup luksUUID` comparison to make, because there is no earlier container UUID on this disk; the UUID is recorded as the container's identity for the header-backup filename instead.

### What `--yes` does and does not do, and how the keys are supplied

`--disk-encryption-keys` is not passed by hand.
clan-cli appends it automatically from the `neededFor = "partitioning"` generator — the ZFS root-key generator declared in the disko layout — so the create-time keyfile reaches the installer without the operator naming it.

`--yes` confirms the install but does not auto-accept the vars-generator prompts.
The install path calls `run_generators` without `auto_accept_prompts`, whose default is `False`, so an install run with Phase 5 incomplete stops interactively on the admin box asking for the fleet SSID and PSK rather than failing.
Phase 5.2 front-loads vars generation precisely so this ordering is already right and the install does not stop to prompt.

## clan subcommands that are skipped, and why

`clan init`, `clan machines create`, and `clan templates apply disk` are all skipped, even though the upstream physical-machine guide directs them.
The first two write through `InventoryStore` against this repository's nix-declared inventory, which owns the machine binding and the inventory entry already (registration tasks 4.1 and 4.2).
`clan templates apply disk` writes `machines/pyrite/disko.nix`, which clan-core would auto-import alongside this repository's own `modules/machines/nixos/pyrite/disko.nix`, producing a duplicate disko module.
The machine is fully declared in nix, so none of the three has anything to add and each would fight the declaration.

## Build host behaviour

stibnite's remote linux builder `magnetite-builder` is preferred, but it is reachable only over the ZeroTier mesh.
An install driven from off the mesh therefore falls back to stibnite's local Rosetta builder, which builds the x86_64-linux closure locally under emulation.
Either way the closure is what nixos-anywhere pushes to the target; the build-host choice affects only where it is built.

## USB-C keyboard is a first-boot prerequisite

A MacBookPro14,1 has USB-C ports only and no USB-A port.
A USB-C keyboard, or a USB-C-to-USB-A adapter for a USB-A keyboard, must be physically present before the first boot after the install, not sourced after a failed boot.
The internal keyboard is SPI-attached and reaches the stage-1 passphrase prompt through the profile's force-loaded SPI modules; if that path does not bind on the first boot, an external USB keyboard answers the prompt through `usbhid`, `hid-generic`, and `hid-apple`, which reach the initrd through udev autoloading rather than force-loading.
The prompt waits with an unbounded timeout, so the recovery path is available — but only if the adapter or keyboard is already on hand, which on a USB-C-only machine cannot be improvised at the prompt.

## Verifying what is inside an initrd, and why the obvious check silently lies

Checking for a module's presence inside a NixOS initrd by piping it to `cpio -t` and grepping fails silently.
NixOS initrds are multi-segment: an uncompressed early cpio carrying CPU microcode, followed by the compressed main archive.
A naive `zstdcat … | cpio -t` reads only the first segment and lists a single entry, so a grep for an absent module returns zero hits — indistinguishable from a genuine absence.
This produced two near-miss false conclusions during the initrd-networking diagnosis, and the class recurs wherever an empty result is read as an absence.

Two disciplines defeat it.
Always include a positive control: grep for a module that must be present, such as `applespi`, and treat a zero-hit control as proof the listing itself failed rather than as evidence about the module under test.
And prefer the authoritative artifact over the archive — the `initrd-nixos.conf` the initrd derivation actually consumes, located via `nix derivation show` on the `drvPath` from `config.system.build.initialRamdisk`, then tied to the deployed system by comparing that derivation's output path against `readlink -f /run/current-system/initrd`.

The same class of error also reached a store path that had not been realised locally, where `find` and `ls` returned empty and read as evidence of absence.
The general rule is that an empty result is evidence only once the query itself has been shown to work.

## Key lifecycle: header backup, YubiKey enrollment, and revocation

D1's move to a LUKS2 container places a discrete header at the head of the container partition, and that header holds every keyslot, so losing or corrupting it loses the pool no matter how many credentials are enrolled or how many tokens are in hand (D26).
Under the prior ZFS-native encryption there was no such header to lose, so this maintenance is new material rather than an inherited practice.
The container is partition 2 of the internal disk, so every command below targets the by-id `-part2` path the install's other `cryptsetup` steps use:

```bash
# host: pyrite (installed), in a root shell (sudo -i)
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2
```

Every block in this section runs on pyrite, on the installed system, against that path — with the single exception of the Bitwarden upload and the transfer that feeds it, which happen at stibnite and are called out where they appear.
Every `cryptsetup` and `systemd-cryptenroll` call below requires root, so enter a root shell once with `sudo -i` and run the pyrite blocks inside it; `$part2` is a shell variable and does not survive a change of shell, and neither does the `$HOME` these paths would otherwise resolve against.

### Capturing and storing the header backup

The backup is roughly 16 MiB — the LUKS2 header and its keyslot area — and it is key material, because it contains the keyslots themselves.
Capture it to RAM-backed tmpfs, encrypt the copy that leaves the machine to the `&admin-user` recovery recipient, then remove the plaintext.
The whole block runs in a root shell — enter one with `sudo -i` first and stay in it for the entire block — rather than under per-command `sudo`.
`luksUUID`, `luksHeaderBackup`, and `shred` all require root, so per-command `sudo` would run them correctly and still leave `$HOME` bound to the operator's own home, writing the `.age` to `/home/cameron` while every later step in this section reaches for `/root`.
The destination is written out as a literal `/root` path rather than left to `$HOME` so that the block is correct even if it is run some other way:

```bash
# host: pyrite (installed), in a root shell (sudo -i)
uuid=$(cryptsetup luksUUID "$part2")   # provenance: the container UUID
today=$(date +%F)                      # provenance: the capture date, YYYY-MM-DD
backup=/root/pyrite-luks-header-$today-$uuid.age

# cryptsetup opens the backup target with O_CREAT|O_EXCL and refuses a path that
# already exists, so the target must not pre-exist -- which rules out /dev/stdout.
# /dev/shm is tmpfs, so the plaintext header never touches persistent storage.
tmp=/dev/shm/pyrite-luks-header.$$.img
cryptsetup luksHeaderBackup "$part2" --header-backup-file "$tmp"

age -r age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8 \
  -o "$backup" "$tmp"

shred -u "$tmp"
ls -l "$backup"
```

The trailing `ls -l` is the check that the file landed where the transfer below will look for it.
It is worth the one line because the failure it catches is quiet and its consequence is not: a `.age` written to `/home/cameron` leaves the `scp` failing against `/root`, and the `rm` at the end of this section then deletes from whichever home the operator was not in, retiring a file that is still on the disk.

The recipient is the `&admin-user` recovery key, the same human key that decrypts the machine's vars and that task 5.3 records as the sole human recipient of the passphrase var.
A header backup is worthless unless it can be decrypted, and the `&admin-user` private half is the one demonstrably in our custody, while the offline `&admin` key's private half is not reliably held.
Encrypting to `&admin-user` puts the header backup and the passphrase var under one key, which is acceptable here: an `&admin-user` compromise already yields the passphrase directly, the passphrase is itself a full unlock credential, so the header backup adds no incremental exposure.
On tmpfs the RAM backing is the real protection and `shred` is belt-and-suspenders — a plain `rm` would remove it as well — but the plaintext is gone before the operator moves on either way.
The capture date and container UUID travel in the filename so a stale backup is identifiable without decrypting it, and the UUID ties the backup to one `luksFormat`: a re-install mints a new UUID (task 7.6 records it), so a backup whose UUID no longer matches the live container restores nothing.

The `.age` is written on pyrite, and the Bitwarden upload happens at stibnite, so the file has to cross between the two hosts before anything can be uploaded or deleted:

```bash
# host: stibnite
scp 'root@pyrite.zt:/root/pyrite-luks-header-*.age' ~/
```

The remote path is spelled out as `/root` rather than `~` because the shell that expands it is root's on pyrite and the two only agree when the capture block above ran in a root shell, which is the condition its own `ls -l` established.

The `.age` file is ciphertext, so an ordinary copy over the mesh is sufficient and it can sit in the operator's home directory on stibnite until it is uploaded.
Upload it to the machine's Bitwarden entry — the same `pyrite/zfs-root` entry that holds the passphrase — as a file attachment, so that entry holds only ciphertext; the header is never committed to this repository and never placed in sops.
Bitwarden file attachments require a paid plan and the ~16 MiB backup is well within the per-attachment size limit, so confirm the account allows attachments before relying on this path.

Once the upload succeeds, delete the `.age` on both hosts — the copy on stibnite and the original on pyrite:

```bash
# host: stibnite
rm ~/pyrite-luks-header-*.age
```

```bash
# host: pyrite (installed), in a root shell (sudo -i)
rm /root/pyrite-luks-header-*.age
```

Both deletions are tidiness rather than a security step, since the `.age` is ciphertext throughout; the plaintext was already destroyed by the `shred` above, on tmpfs, before the file left the machine.
Stating both is what keeps a stray copy from being left on whichever host the operator was not thinking about.

### Restoring the header

Restoration reverses the capture and keeps the same tmpfs hygiene, since the decrypted header is again key material.
It needs the `&admin-user` identity, the same key that decrypts the machine's vars, and a tmpfs mount, which `/dev/shm` and `/run` both provide on any NixOS or rescue environment:

```bash
# host: pyrite (installed), or whatever rescue environment holds the container
age -d -i <admin-user-identity> pyrite-luks-header-<YYYY-MM-DD>-<luksUUID>.age \
  > /dev/shm/pyrite-luks-header.img
cryptsetup luksHeaderRestore "$part2" --header-backup-file /dev/shm/pyrite-luks-header.img
shred -u /dev/shm/pyrite-luks-header.img
```

`luksHeaderRestore` reads the backup file rather than creating it, so it carries none of the `O_EXCL` constraint the capture does, and it prompts before it overwrites the live header.

### The slot inventory and its provenance

Both YubiKey 5C Nano tokens report the same AAGUID and are physically identical, so once both are enrolled `systemd-cryptenroll "$part2"` lists two `fido2` slots with nothing in the header telling them apart (D25).
The slot index is therefore the only discriminator, and it cannot be reconstructed after the fact.
Record in the same `pyrite/zfs-root` Bitwarden entry the mapping from slot index to credential — YubiKey-A's serial, YubiKey-B's serial, and the passphrase slot — reading the actual indices back from `systemd-cryptenroll "$part2"` at the moment each is enrolled.
Record alongside it the capture date and container UUID of the header backup currently attached, so the entry names both which credential occupies which slot and which `luksFormat` the stored backup belongs to.

### Re-taking after enrollment changes, and revocation

A header backup freezes the keyslot set exactly as it stood when taken, so restoring one that predates a revocation reinstates the revoked slot verbatim and decrypts the disk again (D26).
The backup is thus itself an enrolled credential, and the retention rule is not "keep them all": after any change to the enrolled set, take a fresh backup, upload it, and delete the superseded Bitwarden attachment, because a stale attachment is an un-revoked credential sitting in storage.
The triggers are every enrollment change without exception — the second-YubiKey enrollment in task 7.12a, taken against the container the single install produces, any revocation, and any future token added — and each re-runs the capture above and updates the slot inventory.

Revocation removes one slot from the live header:

```bash
# host: pyrite (installed)
systemd-cryptenroll "$part2"                 # list the occupied slots and their types
systemd-cryptenroll "$part2" --wipe-slot=<n> # remove slot n, the lost credential
```

Replacing a lost token means wiping its slot, seating the replacement alone, re-enrolling with `systemd-cryptenroll "$part2" --fido2-device=auto`, then re-taking the header backup and destroying the previous one.
The passphrase slot is not wiped as part of this: it keeps the sequence survivable if the replacement enrollment fails partway, and it is what makes the procedure performable at all while no valid token is enrolled.

Have the clan-vars passphrase in hand, at the machine, before starting any enrollment.
`systemd-cryptenroll --fido2-device=auto` does not add a slot to a container it cannot open: it must first unlock the container with an existing credential, and it prompts for one.
This binds hardest at task 7.12a, whose whole procedure removes YubiKey-A so that `--fido2-device=auto` resolves unambiguously to YubiKey-B — which leaves the passphrase as the only credential still available to satisfy that unlock.
The passphrase lives in the `pyrite/zfs-root` password-manager entry (task 5.3) and is readable from stibnite with `clan vars get pyrite zfs/key`, but the enrollment is typed at pyrite's console, so it has to be carried there deliberately.
An operator who arrives at the console with both tokens and no passphrase cannot perform the step at all.
