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
Every line number cited below against a `clan_lib/` or `clan_cli/` path is keyed to the clan-core revision pinned in `flake.lock`, `d332b6935fbebebc0ca151efe0b3144f8dcd9d96`, and not to whatever a local clone has checked out; the same holds for `src/nixos-anywhere.sh` at 1.13.0 and for disko at the revision that lock resolves.

This document is the working-note home for the path.
Promoting it to published reference documentation under `docs/reference/` is a separate, deferred follow-on change and is out of scope for Phase 6.

Phase 7 of the change is where this path is executed: the change plans one destructive install (task 7.3), and the second proving install that once followed it is dropped because the install of 2026-07-19 already demonstrated the path (D29).
The attempt of 2026-07-30 ran that step and aborted at the FIDO2 enrollment, so task 7.3 is re-run against the disk that attempt left behind; what it left, and what the re-run therefore has to clear, is stated under "Why the wipe is a step, not an assumption" below.
This note records the path and the reasons its steps are shaped as they are.

## Booting with no token in hand: an empty PIN reaches the passphrase prompt

This is stated ahead of everything about the install because the operator who needs it is standing at a locked machine rather than working down the page.

With both tokens enrolled and neither one seated, stage 1 does not ask for the passphrase and it does not fail.
It renders `Please enter LUKS2 token PIN` on the internal panel, and it stays there: there is no device-absent timeout, nothing falls through on its own, and the prompt names no credential other than the PIN.
Press Enter on an empty PIN.
The passphrase prompt appears in its place, the clan-vars ZFS root passphrase unlocks the container, and the machine boots normally.
This was performed on the machine with neither token present.

The keypress is the whole of the fallback, so a prompt naming only the PIN is not evidence that the passphrase path is gone, and a machine whose tokens are lost or left behind is not a machine that cannot be booted.
The passphrase is readable from stibnite with `clan vars get pyrite zfs/key` and from the `pyrite/zfs-root` password-manager entry, and it is typed at pyrite's own console, which has no network and no shell until the prompt is answered, so it has to be carried to the machine rather than looked up from it.
The USB-C keyboard prerequisite below applies to this boot exactly as it applies to the install's first boot: if the internal SPI keyboard does not bind, the keypress is unreachable without an external keyboard.

## Prerequisites before the first install

The fleet SSID must be broadcasting and the machine's clan vars must be generated and committed before the install runs.
The fleet network is the pre-existing household network `furtadosmith`, which the operator decided to use as the fleet network rather than standing up a distinct SSID (D14), so no router work is required and the network is already broadcasting.
Phase 5 covers the rest: run `clan vars generate pyrite` from the admin box and commit the generated vars — the sops machine key, the ZeroTier identity and IP, the ZFS root passphrase, and the wifi SSID and PSK — along with the sops recipient changes.
The wifi credentials are shared clan vars under `vars/shared/wifi.fleet/`, so the reinstalled machine associates with no operator typing credentials into it; if the vars are absent the NetworkManager profile interpolates empty strings and association fails silently at first boot, with nothing at eval time to catch it.

A USB-C keyboard, or a USB-C-to-USB-A adapter for a USB-A keyboard, must be physically in the room before any boot in this procedure, and this is a gate rather than a recommendation.
A MacBookPro14,1 has USB-C ports only and no USB-A port, so an adapter cannot be improvised at the moment it is needed.
The moment it is needed is the stage-1 unlock prompt: if the internal SPI keyboard does not bind on a given boot, the external keyboard is the only way to answer it, and until it is answered the machine has no reachable state at all — no network, no shell, and no initrd ssh, since `boot.initrd.network.enable` is forced false.
How long that prompt waits before giving up is not established: the `boot.zfs.passwordTimeout = 0` unbounded wait belonged to the ZFS-native design and does not carry over to `systemd-cryptsetup`, whose query timeout under this configuration was not verified (D1's design records the same non-claim).
The gate does not rest on the answer, and it holds harder if the wait turns out to be bounded rather than infinite.
Confirm the keyboard or adapter is on hand before booting the installer, not after a prompt goes unanswered.
The mechanism, and why the two keyboards reach the initrd by different routes, is in "USB-C keyboard is a first-boot prerequisite" below.

Neither YubiKey is needed for the install, and neither should be seated in pyrite while it runs.
`enrollFido2 = false` (`modules/machines/nixos/pyrite/disko.nix:106`) keeps every FIDO2 step out of the generated disko script, so the install neither reads a token nor asks for one.
Both tokens are enrolled afterward, on the booted machine, by "Key lifecycle: YubiKey enrollment, header backup, and revocation" below — YubiKey-A by "Enrolling the first token", YubiKey-B by the subsection after it.
The reasons for that shape, and the recorded failure that produced it, are under "The install is non-interactive after the wipe" below.

The clan-vars ZFS root passphrase must be in the operator's possession, at the machine, before the install's reboot lands, and this is a gate of the same order as the keyboard.
It is the container's only credential until the first token is enrolled, and it is typed at pyrite's own stage-1 prompt, on a machine that has no network, no shell, and nothing to read it off.
It is readable from stibnite with `clan vars get pyrite zfs/key` and from the `pyrite/zfs-root` password-manager entry; retrieve it before starting the install rather than after the prompt is on screen.
The install reboots the machine on its own about six seconds after the install phase reports done ("The install ends by rebooting pyrite" below), so the window between starting the install and needing the passphrase is the length of the install and no longer.

The tokens' FIDO2 client PINs are needed at the post-boot enrollments and not during the install.
Nothing in this repository records a PIN: it is not a clan var, and the `pyrite/zfs-root` password-manager entry holds the ZFS passphrase, the slot inventory, and the header backup rather than the tokens' PINs.
Wrong guesses are budgeted rather than free — `ykman fido info` prints the remaining attempt count, read as eight of eight on both tokens on 2026-07-30 — and exhausting it blocks the token's FIDO2 application until that application is reset, which erases the credentials it holds.
An exhausted or forgotten PIN now costs a failed enrollment on a running machine rather than a post-wipe abort, which is what deferring the enrollment bought.

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

The naive invocation does not work, and the reason is worth recording because one of the two obstacles is silent rather than loud.
`nix build .#nixosConfigurations.pyrite.config.system.build.installTest` fails at evaluation on a `boot.zfs.devNodes` conflict — `disko/lib/tests.nix:201` sets `/dev` at normal priority against the host module's `/dev/disk/by-id`.
Behind that, `passwordFile` and `additionalKeyFiles` both name `/run/partitioning-secrets/zfs/key`, which clan-cli materialises only during a real install, so `cryptsetup luksAddKey` would read a file that does not exist.
A third obstacle applied while `enrollFido2` was true and no longer does: `disko/lib/types/luks.nix:275-302` sent the script into `wait_for_token`, which polls `ls /dev/hidraw*`, and `installTest` passes no `enableCanokey` — disko's own FIDO2 coverage sets it explicitly and `installTest` has no way to — so the test VM had no token to find and the run hung rather than failing.
With `enrollFido2 = false` that block is not emitted at all, and the `enrollFido2` line in the expression below is a restatement of the real configuration's value rather than a divergence from it, retained so the test stays runnable if enrollment is ever moved back into the install.

The test therefore runs against a configuration that overrides exactly those four attributes and nothing else, of which three are live divergences and one is a restatement.
pyrite has no checkout of this repository, so the tree has to be put there first — pushing the bookmark and cloning it is what leaves a revision the runbook can name, which `rsync` does not:

```bash
# host: stibnite
jj bookmark set pyrite-baremetal-nixos -r @-
jj git push -b pyrite-baremetal-nixos
jj log -r @- --no-graph -T 'commit_id'   # the revision the clone must land on
```

The bookmark move is not optional and it is the step most easily skipped.
`jj git push -b` pushes wherever the bookmark points; it does not advance the bookmark to the chain tip, so a bookmark left where it was last set publishes a revision that predates every change since, and the clone below then puts that stale tree on pyrite as the tree under test.
Setting it to `@-` immediately before the push is what makes the pushed revision the one being read.

```bash
# host: pyrite (installed)
git clone --branch pyrite-baremetal-nixos --single-branch \
  https://github.com/cameronraysmith/vanixiets.git /root/vanixiets
cd /root/vanixiets
git rev-parse HEAD
sha256sum modules/machines/nixos/pyrite/disko.nix flake.lock
```

Confirm three things match stibnite's before going further: the two hashes, and `git rev-parse HEAD` equal to the commit id `jj log -r @-` printed on stibnite.
The hashes establish that the layout and the lock are the ones that were written; the commit-id equality is what catches the whole tree being stale, which the hashes cannot, since a bookmark left behind can still carry a matching `disko.nix`.
Neither is the derivation path, which differs legitimately between a dirty colocated worktree and a clean checkout, so a mismatch there is a prompt to diff rather than a failure.

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
        machine.succeed("zfs get -H -o value acltype zroot/root | grep -x posix")
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

The criterion is `exit=0` with no failing assertion in `/root/pyrite-luks-vmtest.log`.
`/root/pyrite-luks-vmtest-result` resolves to a store path that is empty, because this nixpkgs revision's NixOS test driver writes no `log.html` into `$out`, so the out-link's contents are not a criterion.
The test driver aborts the derivation on the first failing step, so a non-zero exit names the failing command in the log and there is nothing to interpret in a green run.
`meta.timeout = 600` in disko's harness is a Hydra hint that `nix build` does not enforce; the enforced limits are the driver's 900-second per-command defaults, so an OCR misread of the passphrase prompt surfaces as a fifteen-minute hang rather than an error.

Each override is a stated divergence rather than a convenience.
`boot.zfs.devNodes` resolves the conflict in pyrite's favour and not the harness's, which is the point: keeping `/dev/disk/by-id` is what forces the booted VM's `zfs-import-zroot` to find the pool through the dm udev rules' `dm-name-cryptroot` symlink, and forcing the harness value `/dev` would sidestep the mechanism the test exists to check.
disko justifies `/dev` on the grounds that `/dev/disk/by-id` is empty in QEMU VMs, which holds for virtio disks, whose by-id entries QEMU does not supply, and not for device-mapper nodes, whose symlinks the dm udev rules produce.
`boot.initrd.systemd.enable` is stated explicitly to name the property under test — the prompt is systemd's `systemd-ask-password` rather than the scripted initrd's — and not because anything else would leave it off.
disko does set it, at `lib/types/luks.nix:354` under `lib.mkIf config.enrollFido2`, which emits nothing here; but it was never the only definition site, and an earlier revision of this note said it was.
`modules/system/initrd-networking.nix:7` sets it plainly in `flake.modules.nixos.base`, which pyrite imports at `modules/machines/nixos/pyrite/default.nix:26`, so the real machine has systemd stage 1 with or without the enrollment.
The two key files are deliberately different so that the `cryptsetup luksAddKey` branch stays live instead of short-circuiting on `--test-passphrase`, and under `enrollFido2 = false` that is a branch the real install does not take: the same file fills `passwordFile` and `additionalKeyFiles`, so `luks.nix:258`'s guard succeeds against the slot `luksFormat` just created and `:259` never runs.
The harness writes both with `echo -n`, which is what makes the post-boot `--test-passphrase` check severe against the trailing-newline failure D27 turns on — a failure that now surfaces as an extra keyslot rather than a dead one, per the keyslot criterion under `## Verifying the install` below.

What a green run establishes is bounded, and the boundary matters.
It establishes that the LUKS2 container is created on the ESP's sibling with the nested `zfs` content registering `/dev/mapper/cryptroot` as the pool's vdev, that a passphrase slot added through `additionalKeyFiles` opens the container, that stage 1 renders the prompt and the typed passphrase unlocks it, that `zpool import -d /dev/disk/by-id` finds the pool, and that `ashift`, `xattr`, `acltype`, and `encryption=off` read back as declared.
It establishes nothing about the FIDO2 tap, and neither does the install: with `enrollFido2 = false` the `systemd-cryptenroll` call, the `--wipe-slot=0` that removed the throwaway format key, and the `fido2-device=auto` crypttab option are absent from both, and the container is formatted directly with the passphrase rather than through the format-then-add-then-wipe ordering.
The token path is exercised for the first time by the post-boot enrollment in "Key lifecycle" below, on hardware, and nothing before that point says anything about it.
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
Booting one of them and proceeding would run the `blkdiscard` and then fail at `zpool create`, on a machine that has nothing to fall back to.
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
`7.1.3` means the machine came up on a `*_latest_kernel` specialisation, on which `boot.supportedFilesystems.zfs = false` leaves no `zfs` module and no `zpool`: proceeding from there runs the `blkdiscard` and then fails at `zpool create` on a machine with no fallback OS and nothing to boot.
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

### The install is non-interactive after the wipe

Nothing in the disko phase prompts for anything, and the terminal that starts the install does not have to stay attended.
`enrollFido2 = false` (`modules/machines/nixos/pyrite/disko.nix:106`) removes every interactive element from the generated script: read against the built `disko --mode disko` for this machine, `systemd-cryptenroll`, `--wipe-slot`, `wait_for_token`, `/dev/hidraw`, `SLOT_ZERO_TO_DELETE`, `openssl rand`, and `systemd-ask-password` each occur zero times in its 564 lines.
The container is formatted with the clan-vars passphrase directly — `cryptsetup -q luksFormat "/dev/disk/by-partlabel/disk-primary-zfs" --key-file <(set +x; echo -n "$(cat /run/partitioning-secrets/zfs/key)"; set -x)` — and the `additionalKeyFiles` branch that follows is dormant, because its `cryptsetup open --test-passphrase` guard (`lib/types/luks.nix:258`) succeeds against the slot `luksFormat` just created.
The four `fido2` strings that remain in the script are inert `enrollFido2=''` and `declare -a extraFido2EnrollArgs=()` declarations that disko emits for every option name regardless of value.

What the operator's presence is required for is the reboot that ends the install, not the install itself.
The stage-1 passphrase prompt appears about six seconds after the install phase reports done ("The install ends by rebooting pyrite" below), on a machine with no network and no shell, and it is answered by hand.
Be at the machine, with the passphrase, before the install finishes.

The enrollment was deferred rather than declined, and the reason is a recorded failure.
On 2026-07-30 the install ran with `enrollFido2 = true` and `systemd-cryptenroll` returned `FIDO_ERR_OPERATION_DENIED` (0x27) after the token had already accepted the PIN, leaving a formatted container, no enrolled token, and no operating system.
Several explanations are excluded by evidence: a wrong PIN would have returned `FIDO_ERR_PIN_INVALID`, a touch timeout has a dedicated `FIDO_ERR_ACTION_TIMEOUT` branch in systemd that did not fire, resident-key storage was not requested, exactly one FIDO2 device answered, and post-hoc `ykman fido info` on that token reported eight of eight PIN attempts remaining, no forced PIN change, a minimum PIN length of 4, and 99 credential slots free.
The leading explanation is a declined or timed-out user-presence check: the operator was present, but the touch had to land on the token in pyrite while the PIN prompt was relayed over ssh to stibnite, and which machine's token to press was not clear at the time.
That is not decisively established, and the deferral does not rest on establishing it.
What the deferral rests on is the shape of the failure rather than its cause: disko runs the enrollment as a bare body command under the `set -efux` of `lib/default.nix:1012`, after `luksFormat` at `:244` has already replaced the container, with no retry and no fallback, so any failure of the tap is unrecoverable in place on a machine with no fallback OS.
Run on the booted system instead, the same failure costs one re-run.

disko's own guard is not what makes an install-time enrollment safe, and it should not be read as a reason to move the enrollment back.
`wait_for_token` (`lib/types/luks.nix:277-292`) gates on `ls /dev/hidraw* &>/dev/null` at `:283`, a bare node-existence test with no capability check of any kind, which would pass on a mouse or a wireless receiver.
On this machine with no token seated it does not false-pass, and an earlier revision of this note said it did: pyrite's internal Apple SPI keyboard has no `hidraw` node at all — it appears in `/proc/bus/input/devices` with `Phys=applespi/input0` and handlers `sysrq kbd event5 leds` — so with nothing seated the loop polls forever and the install hangs after the wipe rather than aborting after it.
During the 2026-07-30 attempt both `/dev/hidraw0` and `/dev/hidraw1` were the YubiKey itself, and the trace line `+ ls /dev/hidraw0 /dev/hidraw1` is post-glob expansion under `set -x` rather than evidence of a second device.
Both outcomes are post-wipe, and they differ in what it takes to leave them.
The indefinite poll is recoverable in place: the loop breaks as soon as `ls /dev/hidraw*` succeeds (`:282-290`, the break at `:285`), so seating a token resumes a run it had stranded.
The enrollment abort is the outcome with no recovery in place, and it is the one the deferral is against.
A correct guard would be `systemd-cryptenroll --fido2-device=list` or `fido2-token -L`, and reaching it needs a change to disko rather than an `extraFido2EnrollArgs` value, which cannot influence the guard.

### The gates, the wipe, and the install

The first gate confirms a build host answers before anything is destroyed:

```bash
# host: stibnite
# Confirm an x86_64-linux builder answers, BEFORE the wipe.
sudo nix store info --store ssh-ng://builder@magnetite
```

Require the `Version:` and `Trusted:` lines to appear.
A non-zero exit, or an `ssh: connect to host` line, means there is no reachable x86_64-linux builder; restore ZeroTier connectivity to magnetite before proceeding.
This is checked rather than assumed because the failure is silent in the expensive direction, and the mechanism is worth stating exactly, since the fallback is decided by a probe rather than by a setting.
clan passes no `--build-on` unless the operator supplies one (`clan_lib/machines/install.py:215-216`), so nixos-anywhere runs at its default `auto`, and `checkBuildLocally` (`src/nixos-anywhere.sh:611-652` at 1.13.0) resolves it by attempting a trivial `x86_64-linux` derivation on stibnite.
If any x86_64-linux builder answers that attempt the mode becomes `local`; if none does, it becomes `remote`, which in nixos-anywhere means the target machine — the installer ISO, whose disk has just been discarded, over WiFi, in a tmpfs-backed live environment, fetching pyrite's entire closure.
Only magnetite over the mesh, which this gate checks, can satisfy the probe: stibnite's local `nix-rosetta-builder` advertises `aarch64-linux` only (the `nix.buildMachines` block in `modules/machines/darwin/stibnite/default.nix`), and pyrite, the fleet's other x86_64-linux builder, is the machine being installed.
So with magnetite unreachable, the fallback is the ISO and not stibnite, and starting the Rosetta builder does not change that.
If this gate fails, restore magnetite before proceeding; do not reason past the gate on the assumption that stibnite will build it locally regardless.
`ping6 -c 3 fddb:4344:343b:14b9:399:930f:39db:40d2` is a cheaper liveness check that needs no sudo, but ICMP does not prove the store is answering and does not replace the probe above.

Three further gates precede the wipe, and all three are hard stops rather than advisories: if any does not pass, do not run the `blkdiscard`.
They are stated here in full because the operator standing at the machine is reading this page and nothing else.
No token gate appears among them.
The install neither reads a token nor asks for one, and the token checks that used to stand here — exactly one device answering, and its remaining PIN-attempt count — have moved to "Enrolling the first token" in the key-lifecycle section below, where they are read immediately before the enrollment they gate.

The first proves on the admin box that every secret whose silent absence costs pyrite its network or its remote access is present, decryptable, and encrypted to pyrite:

Save it to a file and run it with an explicit `bash`; do not paste it into the shell.
stibnite's interactive shell is fish, which supports neither the `<<'SH'` heredoc an earlier revision of this block used nor `$?`, so a pasted form errors on its first line and a `$?` result line reports nothing.
Writing it to `/tmp/pyrite-secrets-gate.sh` and invoking `bash /tmp/pyrite-secrets-gate.sh` from the repository root is correct under any interactive shell, and it is also what keeps the loop's `exit 1` arms from closing the operator's own shell — the shell needed to read the failure.

```bash
# host: stibnite -- /tmp/pyrite-secrets-gate.sh, run from the repository root
#   as: bash /tmp/pyrite-secrets-gate.sh
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
```

The single line `PRE-INSTALL SECRETS GATE: PASS` is the pass, and nothing else is.
Do not read the absence of a visible error as the pass, and do not add an exit-status line: a status echoed after the `bash` invocation reports the wrapper rather than the gate, and in fish it reports nothing at all.
`set -euo pipefail` is what makes the first three statements stop the run: they carry no `|| exit` of their own, so without it a missing or misnamed `sops/secrets/pyrite-age.key/secret` prints one error line, falls through into the loop, and terminates on `clan vars check pyrite`, whose exit status is independent of `sops/secrets/` — leaving the operator looking at a successful last command having just walked through the early-return branch this gate exists to close.

The machine age key is the branch this gate exists to close.
clan supplies `--extra-files` itself — `clan_lib/machines/install.py:160-167` passes it unconditionally, populated at `:143-148` into the machine's `clan.core.vars.sops.secretUploadDirectory`, which pyrite evaluates to `/var/lib/sops-nix`, the same path `config.sops.age.keyFile` reads `key.txt` from — so the delivery is by construction.
What is not by construction is the one branch that skips it without raising: `clan_lib/vars/secret_modules/sops.py:250-260` returns early when `has_secret` is false, and `has_secret` is the literal predicate `(secret_path / "secret").exists()` (`clan_cli/secrets/secrets.py:371-372`), so a missing or misnamed `sops/secrets/pyrite-age.key/secret` writes no `key.txt`, raises nothing, and takes the install green.
With no `key.txt` on the installed machine sops-nix decrypts nothing: the deployed ZeroTier identity secret is unreadable, so `zerotierone` starts with no identity and mints a fresh one that cinnabar has not authorized, and `pyrite.zt` resolves to an address no live node holds.
The fleet WiFi vars fail by the same silent path and compound it, because WiFi is this machine's only NIC — `clanServices/wifi/default.nix:126-141` reads the sops-nix paths at runtime into the NetworkManager secrets file, an unreadable file yields empty strings, and the interface never associates with no assertion and no eval-time error.
The machine is then console-only, with no route to it but its own keyboard.
A file that exists but does not decrypt is loud instead, since `decrypt_secret` raises and the install aborts before nixos-anywhere runs, which is why the file test is the arm that closes the silent branch and the decrypt arms cover the rest.

The recipient arm is not redundant with the decrypt arm, and that distinction is the point of the check rather than a flourish: a var the operator can read but pyrite cannot is exactly the shape of the WiFi failure above, and only the recipient arm catches it.
Two secrets correctly lack `pyrite` as a recipient and must not be added to one to make a naive sweep pass — `sops/secrets/pyrite-age.key` is admin-only by design, which is the chicken-and-egg `--extra-files` exists to break, and `vars/per-machine/pyrite/emergency-access/password` carries `deploy = false`.
`zfs/key` is in the list for a different reason than the others: it travels the separate automatic `--disk-encryption-keys` channel (`install.py:169-182`), and if it is absent `run_generators` mints a fresh passphrase, so the container is created under a credential the operator never recorded and cannot type at the initrd prompt.
`openssh/ssh.id_ed25519` is in the list because `modules/system/ssh-known-hosts.nix:66-72` and `modules/home/core/ssh.nix:107-110` both pin `pyrite.zt` to the public half read back out of the flake, so a host key that fails to land yields a machine that is up and on the mesh and that the admin box refuses on key mismatch.

The second records the identity of whatever is on the disk now, which is the baseline the post-install create-path checks compare against:

```bash
# host: pyrite (installer)
# Both read only: neither needs a key and neither imports or opens anything.
# Record whatever each prints, including nothing.
zpool import                                    # importable pools and their GUIDs
cryptsetup luksUUID /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2
```

Take both here because after the wipe there is nothing left to read them from.
Write the values down somewhere that is not the installer: on stibnite, or on paper.
The block above is labelled `host: pyrite (installer)`, and this note sanctions running installer blocks at pyrite's own console — so a value that exists only in that console's scrollback is destroyed by the reboot into the installed system, which is precisely when the post-install comparison needs it.
A tmpfs-backed live environment keeps no file across that reboot either, so a redirect into the installer's filesystem is not a record.

The `luksUUID` arm is the live one on the install ahead, and it is new to this revision.
The attempt of 2026-07-30 reached `luksFormat` before it aborted, so p2 carries a LUKS2 container: a `blkdiscard` that does not reach the media leaves that header probing, disko's format gate `! blkid || ! cryptsetup isLuks` (`lib/types/luks.nix:202`) evaluates false, `luksFormat` is skipped, and the install proceeds inside the old container under a UUID the post-install check can catch and nothing else on this page can.
The `zpool import` arm may now print nothing, and that is a recording rather than a failure: that same attempt wiped the disk and reformatted p2, and no pool was created inside the new container, since the nested `zfs` content's `_create` is spliced after the enrollment that aborted (`:303`).
Whether any of the pre-D1 pool's tail labels survived that sequence has not been established, which is exactly why the arm is still read.
If it does list a `zroot`, the surviving-pool skip described under "Why the wipe is a step" below is live and the GUID is the only thing that discriminates it.

The third confirms the installer is on the network and stays there:

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

The wipe has a precondition it did not have before, and skipping it fails the wipe rather than corrupting it.
disko opens the container with `--persistent` immediately after `luksFormat`, and the 2026-07-30 abort left `cryptroot` active as `dm-0`; `blkdiscard` refuses a device that has an open device-mapper holder.
The mapping exists only in the installer session that aborted, so a reboot clears it and `cryptsetup status cryptroot` reporting no such device is the pass either way.

```bash
# host: pyrite (installer)
# 1a. Close the mapping the 2026-07-30 attempt left open. Harmless if nothing
#     is open: `close` on an absent mapping is a no-op error, and the lsblk
#     line is what settles it. blkdiscard fails on a busy device.
cryptsetup status cryptroot
cryptsetup close cryptroot || true
lsblk /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1   # no dm holder

# 1b. Wipe the target disk at every offset. THIS IS THE POINT OF NO RETURN.
#     This is the last step whose success the operator can observe before the
#     install commits, and it is what destroys the LUKS2 header the 2026-07-30
#     attempt left behind -- without which disko skips luksFormat entirely and
#     the install lands inside the old container.
#     This by-id path names pyrite's internal NVMe. Run it in a shell on
#     the booted installer -- over ssh from stibnite or at pyrite's own
#     console -- never in a stibnite shell, where the same command finds
#     stibnite's own devices.
#     -f is part of the command rather than an escalation to reach for if the
#     plain form is rejected: without it blkdiscard refuses a disk that still
#     carries a partition signature and discards nothing. See below.
blkdiscard -f /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1
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
A network failure at that moment would land after the disk is already discarded, on a machine whose only NIC is wireless, which is a worse place to discover a missing 78.9 MiB than before the wipe.
`nix path-info` exiting 0 against the path is the confirmation; the operator realised it ahead of the install, so this is a recorded step of the path rather than an open action.

`blkdiscard` is on the installer's PATH (it ships in `util-linux`, folded into every NixOS system's `environment.systemPackages`); Phase 7 confirms this on the machine with a two-command check before relying on it, together with `blockdev --getss /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1` to record the logical sector size the `ashift = "12"` decision assumes.
The by-id form is used there as everywhere else in this note, including for the reads.
`/dev/nvme0n1` and `/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1` name the same device on pyrite, but the short name is a kernel enumeration order rather than an identity, it resolves on stibnite to a different disk entirely, and the controller exposes a second namespace whose by-id name ends `_2` and must never be written.
A measurement taken against a name that does not identify the disk is not evidence about the disk, even when it is read-only.

`blkdiscard` from util-linux 2.42 refuses the bare invocation against a disk that still carries a signature, and `-f` is what makes it run.
Without the flag it prints the signature line — `contains existing partition (gpt).` — then `This is destructive operation, data will be lost! Use the -f option to override.`, and exits having discarded nothing.
With the flag it prints `Operation forced, data will be lost!` and performs the discard.
Both lines are warnings in form and only one of them reports something that happened, so the refusal is the easier of the two to walk past: it names the obstacle, offers no result, and leaves behind a disk carrying every signature the wipe exists to destroy.
The wipe of 2026-07-19 was verified complete afterward: zero non-zero bytes in the first 64 MiB, no filesystem or pool signatures, no GPT, and the offset that run's APFS container occupied reading zeros.
That APFS observation describes the disk as it stood before that install and not as it stands now — that install is what replaced APFS, and what p2 holds today is stated under "Why the wipe is a step, not an assumption" below.
The check that settles whether a wipe took is the post-wipe verification above, not the command's output.

The wipe uses `blkdiscard`, not `sgdisk --zap-all` and not `wipefs -a` on the whole disk.
This follows the form clan-core's own encrypted-root guide prescribes at `docs/src/guides/disk-encryption.md:84-88`.
Under D1's container the reason is restated rather than carried across from the ZFS-native layout, because what survives a partial wipe is no longer a pool.
Partition 2's `fstype` is now `crypto_LUKS` and not `zfs_member`, so disko's `disk-deactivate.jq` cannot reach its `zpool destroy -f` and `zpool labelclear -f` branch at `:7-9` for that partition at all — the branch is unreachable by type.
What runs instead is the bare `wipefs --all -f` partition arm at `:42-45`, which erases the primary LUKS2 signature while leaving the secondary header and the whole 16 MiB keyslot area intact, so the old passphrase and the old FIDO2 enrollment survive a wipe that reads as complete.
Zapping the GPT first is worse still: with no partition table there are no children for `lsblk` to report, so even that arm never runs, and the next install finds a valid header and skips `luksFormat` (`lib/types/luks.nix:202`) — the tautological green the create-path criterion forbids, produced by the step meant to prevent it.
The FIDO2 skip at `:276` that an earlier revision named alongside it is not in the script at all under `enrollFido2 = false`; the enrollment is now a post-boot step, which lands on whatever header is live and cannot itself distinguish a fresh container from a survivor.
`blkdiscard` against the `_1` namespace path destroys the header, the keyslot area, and every label at every offset, and has no such hole.

If `blkdiscard` is ever unavailable, the fallback order is absolute, and under D1's container it is no longer the ZFS one.
It is written out here as a labelled block for the same reason every other destructive step is: it names pyrite's internal disk, it runs on the installer and nowhere else, and stibnite has a device namespace of its own in which the same commands find stibnite's disk without complaint.

```bash
# host: pyrite (installer)
# FALLBACK ONLY, if blkdiscard is unavailable. Destroys the same disk blkdiscard
# does. The order is absolute: each step destroys the magic the step above it
# depends on.
disk=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1

zpool labelclear -f "$disk-part2"
zpool import                                    # must now list no zroot
cryptsetup luksErase --batch-mode "$disk-part2"
dd if=/dev/zero of="$disk-part2" bs=1M count=32
sgdisk --zap-all "$disk"
wipefs -a "$disk"
```

The block serves two disk states and only one of them is the disk in front of the operator today, so two of its steps are each a no-op in the other's state and that is deliberate rather than redundant.
p2 now holds the LUKS2 container the 2026-07-30 attempt created (task 7.16), so `luksErase` is the live arm.
`labelclear` is retained because whether any of the pre-D1 pool's tail labels survived that reformat has not been established, and on a disk where they did it is the only arm that reaches them.
On a disk in the other state — a pre-D1 `zroot` with no header — the arms swap and `luksErase` reports that the device is not a valid LUKS device.
Run both in the order given; neither destroys the magic the other probes for.
Close `cryptroot` first here too, for the same reason the `blkdiscard` block does: `luksErase` and the overwrite both act on a partition an open mapping is holding.

`labelclear` is first because it is the only step in this block that reaches the tail of the partition, and it is the step whose omission produces the failure the wipe exists to foreclose.
ZFS writes four vdev labels: L0 and L1 at the head, L2 and L3 at the tail.
`vdev_label_offset` (`module/zfs/vdev_label.c:163-171`) places labels 2 and 3 at `psize - VDEV_LABELS * sizeof(vdev_label_t) + l * sizeof(vdev_label_t)`, and with `vdev_label_t` at 256 KiB (`include/sys/vdev_impl.h:537-543`) and `VDEV_LABEL_END_SIZE = 2 * sizeof(vdev_label_t)` (`:561`), that is the last 512 KiB of the partition.
The `dd` step in the block above covers the head of the partition and cannot reach them, `wipefs -a` on the whole disk reports and erases signatures at offsets libblkid knows and does not touch partition-interior ones, and disko then recreates a deterministic layout at identical offsets — so `zpool import -N -f "zroot"` at `lib/types/zpool.nix:298` finds the surviving tail labels, succeeds, and `:299` logs "not creating zpool zroot as a pool with that name already exists" while never applying `ashift`.
That is the surviving-pool skip, produced by a fallback that reported success at every step.
The `zpool import` on the line after `labelclear` is what settles it, and it has to run there rather than at the end: after `sgdisk --zap-all` there is no `$disk-part2` node left to read.

`luksErase` precedes the overwrite because it needs a header that still probes, and every step below it destroys the magic that probe depends on.
The 32 MiB overwrite follows because it covers both LUKS2 headers and the whole default 16 MiB keyslot area, rather than the primary signature alone.
Both partition-scoped steps precede the zap for the reason the ZFS-era order recorded, that a partition-scoped step depends on the partition table the zap destroys, and the zap precedes the whole-disk `wipefs` for the same reason.

The fallback's pass criterion is not the post-wipe verification above, and running arm 1a against it produces a false failure.
Arm 1a requires the disk's first 64 MiB to read as zeroes, which a `blkdiscard` achieves and this sequence does not: it zeroes p2's head, not the ESP region, so on a correctly-executed fallback arm 1a fails and the operator either halts on a successful wipe or concludes the criterion does not apply and proceeds with no check at all.
The criterion for this block is instead its own three readings: `zpool import` listing no `zroot` immediately after `labelclear`, then `wipefs -n "$disk"` printing nothing, then `sgdisk -p "$disk"` opening with "Creating new GPT entries in memory." and listing no partitions.
Arms 1b and 1c are those last two; arm 1a is the one that does not carry over.

### Why the wipe is a step, not an assumption

The wipe is not there because the run is create-only.
The default disko mode destroys before it creates: `clan_lib/machines/install.py` passes no `--disko-mode`, so nixos-anywhere's default selects disko's `diskoScript`, which composes `_legacyDestroy` then `_create` then `_mount` (D8).
So on the happy path the wipe is belt-and-braces, and it is retained anyway for three reasons.
`_legacyDestroy` runs without `set -e`, so a destroy that fails silently falls through to `_create`, where a surviving Apple GPT causes `sgdisk --clear` to be skipped, the subsequent `sgdisk --new` calls re-typecode Apple's partitions in place, `mkfs.vfat` is skipped on an ESP already reporting a type, and the machine boots Apple's 300 MiB ESP rather than the declared layout.
The explicit wipe is also the only step whose success the operator can independently observe before committing to an irreversible install.
And clan-core's own encrypted-root guide prescribes a manual `blkdiscard` before `clan machines install` for exactly this scenario, so upstream treats a pre-wipe as normal practice here rather than as belt-and-braces.

There is a fourth reason, and on any run where the previous install's container could survive it is stronger than the three above.
Under D1 the surviving artifact is the LUKS2 header rather than a pool, and it gates two create-path skips in sequence.
`lib/types/luks.nix:202` skips `luksFormat` against a header that still probes, and `:258`'s `cryptsetup open --test-passphrase` then adds no key, because the surviving container already opens under the same clan-vars passphrase the new format would have used.
So the install can complete, boot, and unlock with the expected passphrase while running inside a container a previous attempt created, and no credential check anywhere on this page distinguishes the two.
A third skip existed while `enrollFido2` was true — `:276`'s `systemd-cryptenroll | grep -qw fido2` — and it is not emitted now.
Deferring the enrollment removes that particular false green and leaves the container's identity as the only thing that catches the rest, which is why `cryptsetup luksUUID` is now read before the wipe as well as after.
Only once the container opens does the pool question arise at all — the vdev is `/dev/mapper/cryptroot`, which does not exist while the container is closed — and there disko's `lib/types/zpool.nix:298` tries `zpool import -N -f "zroot"` before it considers creating anything, and `:299` logs "not creating zpool zroot as a pool with that name already exists" while never re-applying `ashift`.
The wipe is what forecloses the whole chain, which makes it load-bearing rather than belt-and-braces on any run that follows an earlier install.
Which arm of that chain is live on this machine depends on what the disk actually holds, and that has changed twice.
The disk does not hold APFS: the install of 2026-07-19 replaced it with a pre-D1 `zroot` (task 7.16), and the attempt of 2026-07-30 replaced that in turn — it wiped the disk and reformatted p2 as a LUKS2 container before aborting at the enrollment, leaving a valid header with the clan-vars passphrase in a keyslot and no pool inside it.
So the container arm is the live one on the install ahead, and it is live in both of its steps: a `blkdiscard` that does not reach the media leaves that header probing, `luksFormat` is skipped, and the `--test-passphrase` guard then adds nothing because the surviving slot already opens under the same credential.
The discriminating check is therefore `cryptsetup luksUUID` differing from the pre-wipe baseline, which is why that reading was added to the second pre-wipe gate above.
The pool arm may or may not be live: whether any of the pre-D1 pool's tail labels survived the 2026-07-30 sequence has not been established, so `zpool import` is still read before the wipe, and `zpool history zroot` opening with a create entry timestamped inside the install session is still required afterward.

### What `--yes` does and does not do, and how the keys are supplied

`--disk-encryption-keys` is not passed by hand.
clan-cli appends it automatically from the `neededFor = "partitioning"` generator — the ZFS root-key generator declared in the disko layout — so the create-time keyfile reaches the installer without the operator naming it.

`--yes` confirms the install but does not auto-accept the vars-generator prompts.
The install path calls `run_generators` without `auto_accept_prompts`, whose default is `False`, so an install run with Phase 5 incomplete stops interactively on the admin box asking for the fleet SSID and PSK rather than failing.
Phase 5.2 front-loads vars generation precisely so this ordering is already right and the install does not stop to prompt.

### The install ends by rebooting pyrite

The last phase of the install reboots the machine, and it does so on its own rather than on the operator's initiative.
`clan machines install` passes `--no-reboot` only when it is asked for: `no_reboot` defaults to `False` (`clan_lib/machines/install.py:75`) and the flag is appended only when it is set (`:184-185`).
With no `--phases` given either, clan runs `kexec`, `disko`, `install`, `reboot` in turn as four separate invocations (`:253`), so the reboot phase is part of every install this path performs.
nixos-anywhere's reboot phase (`src/nixos-anywhere.sh:915-929` at 1.13.0) unmounts `/mnt`, disables swap, exports the pools so the next boot needs no forced import, then backgrounds `nohup sh -c 'sleep 6 && reboot'` at `:924` and blocks until the machine stops answering ssh.
About six seconds after the install phase reports done, therefore, pyrite reboots itself, and stibnite prints "Waiting for the machine to become unreachable due to reboot" and then "Done!" for a machine that is already booting.
That reboot is the first boot, and it is what the next section is about.

## The first boot, and proving the passphrase path

The install leaves behind a machine that has never been unlocked and exactly one credential able to unlock it: the clan-vars ZFS root passphrase, in the single keyslot `luksFormat` created.
That credential has to be exercised before anything in the key-lifecycle section below is run (task 7.5).
There is no token path to exercise yet, because the header carries no FIDO2 credential, so this is one boot rather than two and the token path is proven later, under "Proving the token unlock and the passphrase fallback".

The boot has already started by the time this section is read.
The install's reboot phase fires it about six seconds after the install phase completes, unattended, with the external installer SSD still attached and no token anywhere near the machine — so when stibnite prints "Done!" the operator's next move is to go to the machine, not to power anything on.
Better still, be there before it fires: the disko phase no longer requires the operator's presence, so nothing else in this procedure puts a person at the machine, and the stage-1 prompt has to be answered when it appears rather than found afterward having already timed out.
The installer SSD cannot be removed before this boot, because the ISO on it is the running root right up to the reboot.
Which device the machine comes back on is therefore not settled in advance.
If it reaches the stage-1 unlock prompt on its own panel, that is the installed system and the boot under test; answer the prompt as below.
If it returns to the installer's GNOME session instead, that is a boot-device selection rather than a failed install: shut down, remove the SSD, and boot again, and the choice is then unambiguous.
The SSD comes out at the next shutdown either way.

No token is seated for this boot, and none is needed.

Stage 1 renders a `systemd-ask-password` prompt on the internal panel and it asks for the passphrase directly.
It does not ask for a PIN, it does not wait for a token, and there is no pause before it appears.
That is what a correct install looks like here, and an earlier revision of this note described the opposite — PIN, then touch, then a second boot whose thirty seconds of silence read as the fallback working — so an operator following that text would read a correct install as a failed one.
The header holds one keyslot and it is a `password` slot, so neither of the two paths that could read a token out of it has anything to read.
The token-plugin path at systemd 260.2 `src/cryptsetup/cryptsetup.c:2691` runs first and is attempted, since both its gates hold on this machine, and it finds no `systemd-fido2` token in the header, so it falls through.
`determine_token_type` then returns `_TOKEN_TYPE_INVALID` rather than `TOKEN_FIDO2`, since it selects FIDO2 only when `arg_fido2_device` or `arg_fido2_device_auto` is set (`:2551-2560`, the return at `:2555`) and `crypttabExtraOpts` evaluates to `[]`, so the unlock falls through to the key file and the passphrase.
It is the empty header rather than the empty crypttab that makes this a passphrase boot: after the enrollments in "Key lifecycle" below, the same `[]` crypttab produces a PIN-and-touch boot.
Neither shows the operator anything, so the prompt described above is what this boot looks like.
The thirty-second silence and the "Timed out waiting for security device" message belong to systemd's own FIDO2 path, which no state of this machine takes, so they are not expected on this boot or on any later one.

Answering the prompt is the first exercise of the human path: a mixed-case hyphenated six-word string typed at the Apple SPI keyboard through `systemd-ask-password-console`, with plymouth deliberately off (D11).
The credential itself is proven byte-exact against the repository — `cryptsetup open --test-passphrase` against the header still on this disk returned "Key slot 1 unlocked" for a keyfile whose sha256 matches `clan vars get pyrite zfs/key` — so a prompt that refuses the passphrase is evidence about the typing or the keyboard rather than about the var.
The USB-C keyboard or adapter has to be in the room already rather than sourced now: if the internal SPI keyboard does not bind on this boot, the external keyboard is the only way to answer the prompt, and until it is answered the machine has no reachable state at all.
Do not count on the prompt waiting indefinitely while the keyboard is fetched — how long `systemd-cryptsetup` waits under this configuration was never measured, and the ZFS-native design's unbounded wait does not carry over to it.

This boot is not optional and it is not a formality.
Until the first token is enrolled the passphrase is the container's only credential, so an install whose passphrase has not been typed once is an install whose recoverability is assumed rather than observed.
The failure class is concrete rather than hypothetical: D27's trailing-newline defect lands exactly here, and the VM test in "Validating the LUKS2 layout in a VM" above exercises it only against the harness's own key files, never against the clan var that fills this container's keyslots.
Under `enrollFido2 = false` that defect changes shape rather than disappearing: `luksFormat` strips a trailing newline through `$(cat ...)` while `luks.nix:258`'s guard hands the same file to `cryptsetup` verbatim, so a newline-bearing artifact adds a second, dead keyslot instead of making the only one dead.
The typed passphrase opens the container either way, and the keyslot criterion under `## Verifying the install` is where the difference shows up.

Carry the passphrase to the machine before the install finishes rather than looking it up once the prompt is on screen: a machine sitting at the stage-1 prompt has no network, no shell, and no way to read anything off itself.
It is readable from stibnite with `clan vars get pyrite zfs/key` and from the `pyrite/zfs-root` password-manager entry.

This boot must have succeeded before `## Verifying the install` is read as a pass, and before any block in "Key lifecycle" below is run.
Every enrollment in that section authorizes itself with the passphrase — `systemd-cryptenroll --fido2-device=auto` does not add a slot to a container it cannot open — so an operator who reaches those blocks without having typed the passphrase once is building on a credential that has never been demonstrated.

## Verifying the install

These checks run on the installed machine after the first boot, and they are what decides whether the install is accepted at all.
They are here rather than only in `tasks.md` because the operator standing at the machine is reading this page.
Checks 2, 3, and 7 are the create-path discrimination and they are the ones that can fail in the direction that looks like success.
Check 7 is the sharpest of them on this run: if `blkdiscard` does not reach the media, the LUKS2 header the 2026-07-30 attempt left behind still probes, `luksFormat` is skipped, and the install lands inside that container under its original UUID.
Checks 2 and 3 cover the pool arm, which is live only if any of the pre-D1 pool's tail labels survived that attempt — unestablished, which is why the pre-wipe `zpool import` is recorded and compared rather than assumed empty.

```bash
# host: pyrite (installed), in a root shell (sudo -i)
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2

# 1. The declared geometry landed: a 1G EF00 ESP plus a 100% sibling, and
#    nothing of Apple's layout re-typecoded in place. -p reads and reports only.
sgdisk -p /dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1

# 2. The pool was created by this run. The first entry must be a `zpool create`
#    whose timestamp falls inside this install session.
zpool history zroot | head -5

# 3. The pool GUID differs from the pre-wipe baseline recorded off the installer.
zpool get -H -o value guid zroot

# 4. The keyslot set. One `password` row at slot 0 and no `fido2` row. See
#    below on the second `password` row a trailing newline would add.
systemd-cryptenroll "$part2"

# 5. The container. LUKS2, with no tokens at all -- both tokens are enrolled
#    later, on the running system.
cryptsetup luksDump "$part2"

# 6. Pool and dataset properties.
zpool get ashift zroot
zfs get xattr,acltype,encryption zroot/root

# 7. The container's identity: the header-backup filename, and the discriminator
#    against the header the 2026-07-30 attempt left on this disk. It must differ
#    from the pre-wipe baseline recorded off the installer.
cryptsetup luksUUID "$part2"
```

`zpool history` is the severe arm rather than a formality: ZFS stores the history inside the pool, so it is provenance that survives export and import rather than a log of the current session.
Under the surviving-pool failure no `zpool create` runs at all, the opening entry is the pre-D1 create carrying its older timestamp, and this run appears only as import and `zfs set` entries.
The GUID reading corroborates it from the other side, because `zpool create` mints a fresh GUID: a value equal to the pre-wipe baseline means the pool was reused whatever else the run reports.
That baseline is the one the second pre-wipe gate above records, which is why it has to have been written down off the installer — the reboot into this system destroys the installer's console scrollback.

Every check above reaches the container through `$part2`.
`tasks.md` 7.6 states the keyslot gate against `/dev/disk/by-partlabel/disk-primary-zfs` instead; the two are the same partition, since disko's partlabel is `${_parent.type}-${_parent.name}-${name}` (`lib/types/gpt.nix:146`), which for this layout is `disk-primary-zfs`.
Either name is correct and the by-id one is used here so that one variable names the container throughout the page.

The expected keyslot reading is one `password` row at slot 0 and nothing else, and that expectation rests on one assumption worth naming.
`enrollFido2 = false` makes `autogeneratedPassword` false (`lib/types/luks.nix:12`), which resolves `formatKeyFile` to the `passwordFile` form rather than to an ephemeral `openssl rand -hex 32` (`:32-33`), so `luksFormat` puts the clan-vars passphrase itself in slot 0; there is no throwaway hex, no `SLOT_ZERO_TO_DELETE`, and no `--wipe-slot=0`.
`passwordFile` and `additionalKeyFiles` then name the same file, so `:258`'s `cryptsetup open --test-passphrase` succeeds against the slot just created and `:259`'s `luksAddKey` never runs.
That last step holds only if clan-cli materialises the var to `/run/partitioning-secrets/zfs/key` byte-identically to what the generator wrote, which strips the trailing newline with `tr -d "\n"` (`disko.nix:46`), and whether it does has not been verified.

A second `password` row is therefore a measurement rather than a failed install.
It means the guard failed, `luksAddKey` ran, and the materialised file carried a trailing newline that the format path had already stripped through `$(cat ...)` — so slot 0 holds the typeable passphrase and slot 1 holds a variant that opens for nobody.
The first boot has already settled which is live, since what was typed at the prompt is the stripped form.
If two rows appear, confirm the live slot with `cryptsetup open --test-passphrase --key-slot=0 "$part2"`, wipe the dead one with `systemd-cryptenroll "$part2" --wipe-slot=1`, and record the correction in the `pyrite/zfs-root` slot inventory before the header backup is taken.
Either layout is recoverable with the passphrase; only the slot map differs, which is why the inventory rather than the row count is what has to be right.

The keyslot reading is not a wipe discriminator under this shape and must not be read as one.
An occupied slot 0 is what a correct format produces here, so the arms that discriminate a skipped format are check 7's `luksUUID` against the pre-wipe baseline and, if the pre-wipe `zpool import` listed anything, checks 2 and 3.

`zfs get encryption zroot/root` must return `off`, and that is a positive check rather than an absence: it is what distinguishes D1's layout from LUKS layered underneath a still-encrypted dataset.
`ashift` must return `12`, and `xattr` and `acltype` must return `sa` and `posix`.
OpenZFS accepts `posixacl` as an input alias for `acltype` and reports the property as `posix`, so `posix` is the value to require.
`luksUUID` is both recorded and compared, which is a change from an earlier revision of this note: the disk carries the LUKS2 container the 2026-07-30 attempt created, so there is an earlier UUID for it to differ from, and a post-install value equal to the pre-wipe baseline means `luksFormat` was skipped against a surviving header (`lib/types/luks.nix:202`) and the container in front of the operator is the old one.
It is also what the header-backup filename and the `pyrite/zfs-root` entry name the container by, which is how a stale backup is identified without decrypting it.

## clan subcommands that are skipped, and why

`clan init`, `clan machines create`, and `clan templates apply disk` are all skipped, even though the upstream physical-machine guide directs them.
The first two write through `InventoryStore` against this repository's nix-declared inventory, which owns the machine binding and the inventory entry already (registration tasks 4.1 and 4.2).
`clan templates apply disk` writes `machines/pyrite/disko.nix`, which clan-core would auto-import alongside this repository's own `modules/machines/nixos/pyrite/disko.nix`, producing a duplicate disko module.
The machine is fully declared in nix, so none of the three has anything to add and each would fight the declaration.

## Build host behaviour

stibnite's remote linux builder `magnetite-builder` is preferred, but it is reachable only over the ZeroTier mesh.
Where the build lands when it is not reachable is decided by nixos-anywhere's `--build-on auto` probe rather than by a preference order, and the resolution is in the pre-wipe builder gate above.
In short: `checkBuildLocally` attempts a trivial `x86_64-linux` derivation on stibnite, and any x86_64-linux builder that answers — magnetite over the mesh, or pyrite once it is installed and reachable — makes the mode `local`, while none answering makes it `remote`, which is the target machine rather than stibnite.
The Rosetta builder advertises `aarch64-linux` only (the `nix.buildMachines` block in `modules/machines/darwin/stibnite/default.nix`), so it never satisfies the probe, and during pyrite's own install off the mesh the closure is built on the installer ISO.
That is the outcome the pre-wipe gate exists to prevent, and it is why the gate is a stop rather than an advisory.
Wherever it is built, the closure is what nixos-anywhere pushes to the target; the build-host choice affects only where it is built.

## USB-C keyboard is a first-boot prerequisite

A MacBookPro14,1 has USB-C ports only and no USB-A port.
A USB-C keyboard, or a USB-C-to-USB-A adapter for a USB-A keyboard, must be physically present before the first boot after the install, not sourced after a failed boot.
The internal keyboard is SPI-attached and reaches the stage-1 passphrase prompt through the profile's force-loaded SPI modules; if that path does not bind on the first boot, an external USB keyboard answers the prompt through `usbhid`, `hid-generic`, and `hid-apple`, which reach the initrd through udev autoloading rather than force-loading.
That recovery path is available only if the adapter or keyboard is already on hand, which on a USB-C-only machine cannot be improvised at the prompt, and it is not underwritten by any measured prompt timeout: `systemd-cryptsetup`'s query timeout under this configuration was not verified, so the keyboard being in the room is the whole of the guarantee.

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

## Key lifecycle: YubiKey enrollment, header backup, and revocation

D1's move to a LUKS2 container places a discrete header at the head of the container partition, and that header holds every keyslot, so losing or corrupting it loses the pool no matter how many credentials are enrolled or how many tokens are in hand (D26).
Under the prior ZFS-native encryption there was no such header to lose, so this maintenance is new material rather than an inherited practice.
The container is partition 2 of the internal disk, so every command below targets the by-id `-part2` path the install's other `cryptsetup` steps use:

```bash
# host: pyrite (installed), in a root shell (sudo -i)
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2
```

Every block in this section runs on pyrite, on the installed system, against that path — with the single exception of the Bitwarden upload and the transfer that feeds it, which happen at stibnite and are called out where they appear.
Every `cryptsetup` and `systemd-cryptenroll` call below requires root, so enter a root shell once with `sudo -i` and run the pyrite blocks inside it; `$part2` is a shell variable and does not survive a change of shell.

The order of the subsections that follow is normative rather than editorial, and the rule is stated in `specs/encrypted-zfs-root/spec.md`: the header backup is taken once the container's keyslots reach their intended state, which is after both tokens are enrolled and not before.
The install now leaves the header with a single passphrase slot, so a backup taken early records a container with no token in it at all, and restoring it later silently un-enrolls both (D26) while the `pyrite/zfs-root` slot inventory continues to describe a container the attached backup does not match.
Enroll A, enroll B, prove both unlock paths, then capture.

### Enrolling the first token

The install leaves the container with no FIDO2 credential at all, so this is the enrollment that creates the token path, and it runs on the booted machine rather than inside the install.
Its whole value over the install-time form is that a failed touch costs one re-run: `systemd-cryptenroll` here is a command in a root shell on a working system, not a bare body command under disko's `set -efux` with a freshly formatted container behind it.

Three preconditions hold before the block runs, and each is a stop rather than an advisory.
The machine has booted and the passphrase has unlocked it, per "The first boot, and proving the passphrase path" above: the passphrase is the credential this enrollment authorizes itself with, and `--fido2-device=auto` does not add a slot to a container it cannot open.
`## Verifying the install` has passed against that container.
YubiKey-A is the only token seated and YubiKey-B is still in stibnite, because `--fido2-device=auto` resolves only where exactly one token answers and this layout passes no device path; with both seated the enrollment either refuses or lands against whichever token it resolved, and the serial recorded against the new index is then wrong, which no later reading of the header corrects, since the header carries the index and not the serial (D25).

```bash
# host: pyrite (installed), in a root shell (sudo -i), with YubiKey-A the only
# token seated.
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2

# Confirm exactly one FIDO2 device answers, and read its remaining PIN-attempt
# count before typing a PIN. libfido2 is in this machine's closure
# (modules/machines/nixos/pyrite/default.nix:301-315); yubikey-manager is
# deliberately not, so ykman is fetched.
fido2-token -L
nix-shell -p yubikey-manager --run 'ykman list; ykman fido info'

# Enroll it. This prompts for an existing credential first -- the passphrase --
# then for the token's FIDO2 client PIN, then for a physical touch on the token
# in pyrite. The touch is not announced and the prompt does not change when the
# PIN is accepted, so a run that appears to hang after the PIN is waiting for a
# finger.
systemd-cryptenroll "$part2" --fido2-device=auto

# Read the slot set back. One fido2 row must now be listed where none was.
systemd-cryptenroll "$part2"
```

Two lines that read as failures precede `ykman`'s output and are expected:

```
WARNING: PC/SC not available. Smart card (CCID) protocols will not function.
ERROR: Unable to list devices for connection
```

`pcscd` runs on neither the installer ISO nor the installed system — nothing in this repository enables `services.pcscd` — so `ykman`'s CCID transport is unavailable and says so, while the OTP/HID transport it actually uses here works.
`ykman` exits 0 regardless, and the lines below these two, reporting the token and its PIN-attempt count, are the answer.
Do not abort on the `ERROR:` line: it is a statement about a transport this procedure does not use.
Read the attempt count before typing a PIN rather than after, because exhausting it blocks the token's FIDO2 application until that application is reset, which erases the credentials it holds.

Whether a PIN is asked for at all depends on the token rather than on the configuration.
`cryptenroll.c:62` requests PIN and user presence both, and this call passes no argument to change it, but `libfido2-util.c:802-804` clears the PIN requirement when the token reports its `clientPin` option false — which is what an authenticator that supports PINs but has none set reports.
A token with no client PIN set therefore prompts only for the touch.

If the enrollment fails, nothing is lost.
The container is unchanged, the passphrase still opens it, and the command can be run again — which is the property the deferral was made to obtain, and the property the 2026-07-30 attempt did not have.
Record the index the read-back reports against YubiKey-A's serial in the `pyrite/zfs-root` entry, per the slot inventory below; both tokens report the same AAGUID, so the serial is what the record adds to what the header already carries, which is the keyslot each enrolled token authorizes.

### Enrolling the second token

Two YubiKey 5C Nano tokens unlock this container, and they are designated here so the slot inventory below has names to record against.
YubiKey-A is serial `32720759`, enrolled by "Enrolling the first token" above.
YubiKey-B is the token resident in stibnite, which is brought to pyrite only for this block.
The install touches neither: both enrollments are operations on the running system, for the reason recorded under "The install is non-interactive after the wipe".

This is not the "Replacing a lost token" procedure below, and that procedure's `--wipe-slot` must not be run here.
Nothing is being revoked at this point, and wiping YubiKey-A's slot to make room for B destroys a working credential.

Three preconditions hold before the block runs, and each is a stop rather than an advisory.
YubiKey-A is enrolled and the passphrase path has been exercised: the enrollment above read back a `fido2` row, and the passphrase unlocked the machine on the boot "The first boot, and proving the passphrase path" above requires, against a container `## Verifying the install` has passed.
This one is first because the block below asks the operator to remove YubiKey-A, which leaves the passphrase as the only credential still able to authorize anything.
YubiKey-A is physically removed and YubiKey-B is the only token seated, because `systemd-cryptenroll --fido2-device=auto` resolves only where exactly one token answers and this layout passes no device path; with both seated the enrollment either refuses or lands against whichever token it resolved, and the serial recorded against the new index is then wrong, which no later reading of the header corrects, since the header carries the index and not the serial (D25).
The clan-vars passphrase is in hand, at the machine, before the block starts: `--fido2-device=auto` does not add a slot to a container it cannot open, it prompts for an existing credential first, and with A removed the passphrase is the only credential still able to authorize the enrollment.
It is readable from stibnite with `clan vars get pyrite zfs/key` and from the `pyrite/zfs-root` password-manager entry, but it is typed at pyrite's own console, so it has to be carried there deliberately rather than looked up from the console after the prompt appears.

```bash
# host: pyrite (installed), in a root shell (sudo -i), with YubiKey-A removed
# and YubiKey-B the only token seated.
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2

# Read B's serial while it is the only token answering. This is the value the
# slot inventory records against the index the enrollment returns. The two
# PC/SC lines this prints first are expected here for the same reason they were
# at A's enrollment above; the serial line below them is the answer.
nix-shell -p yubikey-manager --run 'ykman list'

# Enroll it. This prompts for an existing credential first -- the passphrase --
# then for B's FIDO2 client PIN, then for a touch on B.
systemd-cryptenroll "$part2" --fido2-device=auto

# Read the slot set back. Two fido2 slots must now be listed where one was
# before, and the newly-appeared index is YubiKey-B's.
systemd-cryptenroll "$part2"
```

The read-back ties the new index to B's serial at the one moment B is the only token seated.
Both tokens report the same AAGUID and the header carries no serial for either index, so that association is what the record adds; the index itself is written into the `systemd-fido2` token each enrollment creates and can be read back at any time, as the slot inventory below sets out.
Record the index against B's serial in the `pyrite/zfs-root` entry per the slot inventory below.
The keyslots have now reached their intended state, which is the condition the header backup waits on.
The capture does not follow immediately: "Proving the token unlock and the passphrase fallback" comes next, and the two-boot proof that section ends with is the last prerequisite the backup depends on, per the order stated at the head of this section.

### Proving the token unlock and the passphrase fallback

Enrolling a token both puts a credential in the header and makes stage 1 use it; there is no second step and no configuration change between the enrollment and the next boot.
Two code paths in `systemd-cryptsetup` could read a FIDO2 slot out of the header, and on this machine the first of them does.
The first runs ahead of the unlock loop: `if (!key_file && use_token_plugins())` (systemd 260.2 `src/cryptsetup/cryptsetup.c:2691`) calls `crypt_activate_by_token_pin_ask_password`, which tries `crypt_activate_by_token_pin(..., CRYPT_ANY_TOKEN, ...)` at `:1557` and returns 0 on success without ever reaching the loop.
Both of its gates hold here: `boot.initrd.luks.devices.cryptroot.keyFile` evaluates to `null`, so the crypttab key-file field is `-`, and `use_token_plugins` (`:1484-1516`) returns `crypt_token_external_path()` at `:1512`, which is non-`NULL` because nixpkgs passes `--disable-external-tokens` only under `stdenv.hostPlatform.isStatic` (`pkgs/by-name/cr/cryptsetup/package.nix`).
The plugin then loads, because nixpkgs patches the lookup rather than the install path: `package.nix:45-48` applies `relative-token-path.patch`, which rewrites `crypt_token_load_external` in `lib/luks2/luks2_token.c` from a path built with `crypt_token_external_path()` to the bare `libcryptsetup-token-%s.so` and drops the following `assert(*buf == '/')`, so the `dlopen` resolves on the loader search path.
`nixos/modules/system/boot/systemd/fido2.nix:26-30` has already put `libcryptsetup-token-systemd-fido2.so` and `libfido2.so.1` into the initrd, under `boot.initrd.systemd.fido2.enable`, which defaults to `boot.initrd.systemd.package.withFido2` at `:12-15` and evaluates true here.
`crypt_token_external_path()` therefore decides whether external tokens are attempted at all, and no longer decides where the plugin is found.
An earlier revision of this section read that compile-time directory out of `libcryptsetup.so.12` with `strings`, found it empty, and concluded the plugin path could not apply.
The string is still there and still empty, and the patched code builds no path from it, so the measurement was of a value the load does not use.
The installed machine settles it: boots -5 through 0 log `Asking FIDO2 token for authentication` and `Please confirm presence on security token to unlock` while `crypttabExtraOpts` evaluates to `[]` and the generated crypttab carries no `fido2-device=`.
The second path is the loop's own, and this machine never reaches it with a FIDO2 device set: `determine_token_type` at `:2723` returns `TOKEN_FIDO2` only when `arg_fido2_device` or `arg_fido2_device_auto` is set (`:2551-2560`, the return at `:2555`), and those two variables are set by the crypttab option `fido2-device=` (`:394-405`) and, as a documented side effect, by `fido2-cid=` (`:424-426`).
disko emits `fido2-device=auto` from `crypttabExtraOpts` (`lib/types/luks.nix:348`) under `lib.mkIf config.enrollFido2`, so it emits nothing here, and the option is not added by hand either.
That is a decision rather than an omission, and an earlier revision of this section prescribed the opposite: it gave the line to add and told the reader to ship it after the enrollments.
Its purpose was to enable something that turns out to be already enabled, and setting it now would give `determine_token_type` a `TOKEN_FIDO2` to return and move the unlock onto systemd's own FIDO2 path, which is a different code path from the one both proofs below are taken on.
If a future nixpkgs moves the plugin off the loader search path, token unlock stops and the boot degrades to the passphrase prompt, which the second proof below establishes is reachable.
Upstream nixpkgs states at `nixos/modules/system/boot/luksroot.nix:614` that "usually, systemd will automatically detect the configuration at runtime, but if necessary, configure the corresponding crypttab(5) options with `boot.initrd.luks.devices.<name>.crypttabExtraOpts`".
The "usually" branch names the token-plugin path at `:2691`, and on this machine it is that branch that applies, leaving the "if necessary" branch unneeded.
The comment at `modules/machines/nixos/pyrite/default.nix:74-85` records against this machine both that `boot.initrd.luks.fido2Support` is unset and that `crypttabExtraOpts` is unset, and why each is deliberate.

Then prove both paths, on two boots.
With a token seated — either one, since both are enrolled by this point — stage 1 asks for its PIN and then waits for a touch, and the pool imports.
Then shut down, remove every token, and boot again.
The prompt reads "Please enter LUKS2 token PIN", and there is no device-absent timeout behind it: press Enter on an empty PIN and the passphrase prompt appears, after which the machine boots normally.
That keypress is the whole of the fallback and nothing on the screen names it, so it belongs in whatever the operator has in hand at the machine.
An operator holding the passphrase but neither token, reading a prompt that asks only for a PIN, could reasonably conclude the machine is unbootable.
The thirty-second udev wait on `arg_token_timeout_usec` (`src/cryptsetup/cryptsetup.c:122`) and the "Timed out waiting for security device" message that an earlier revision of this section described belong to systemd's own FIDO2 path, which this configuration does not take.
Both readings are required before the header backup below is taken.

### Capturing and storing the header backup

This runs after both enrollments above and after the unlock proof, never before them, so that the captured header is the three-credential one — YubiKey-A, YubiKey-B, and the passphrase — rather than the single-slot snapshot the install leaves, which a later restore would un-enroll both tokens from.
The backup is roughly 16 MiB — the LUKS2 header and its keyslot area — and it is key material, because it contains the keyslots themselves.
Capture it to RAM-backed tmpfs, transfer it off the machine from there, and remove it once the upload has landed.
The image is uploaded to the `pyrite/zfs-root` password-manager entry in the form it was captured, with no `age` layer over it (D31), so the file that leaves pyrite is the header itself and it carries the container's keyslots at every point on the way.
It therefore stays on tmpfs for the whole of its life on this machine.
Writing it to `/root` instead would put it on the pool, where `shred` cannot erase it: ZFS is copy-on-write, so an overwrite lands in new blocks and the original ones keep the data until they are reused.
The whole block runs in a root shell — enter one with `sudo -i` first and stay in it for the entire block — rather than under per-command `sudo`, because `luksUUID`, `luksHeaderBackup`, and `shred` all require root:

```bash
# host: pyrite (installed), in a root shell (sudo -i)
uuid=$(cryptsetup luksUUID "$part2")   # provenance: the container UUID
today=$(date +%F)                      # provenance: the capture date, YYYY-MM-DD

# cryptsetup opens the backup target with O_CREAT|O_EXCL and refuses a path that
# already exists, so the target must not pre-exist -- which rules out /dev/stdout.
# /dev/shm is tmpfs, so the image never touches persistent storage on pyrite.
backup=/dev/shm/pyrite-luks-header-$today-$uuid.img
cryptsetup luksHeaderBackup "$part2" --header-backup-file "$backup"

ls -l "$backup"
```

The trailing `ls -l` is the check that the file landed at the literal path the transfer below pulls from, and that its size is the roughly 16 MiB a LUKS2 header and keyslot area occupy.
It is worth the one line because the transfer runs from the other host, where a missing or truncated file appears only as an `scp` that failed for no stated reason.

The image is uploaded in the form it was captured, with no `age` layer over it, and that absence is a decision rather than an omission (D31).
Bitwarden encrypts attachments at rest, so the header is not stored unprotected; what it does not have is a factor independent of the vault, because the credential that opens the entry opens both the passphrase and the header on it.
That is accepted because the passphrase by itself opens the container, so whoever reaches the entry has the disk with or without the header.
An `age` layer would also be a second way to lose the header: it would encrypt the off-repository copy to the same key `vars/per-machine/pyrite/zfs/key/secret` is already encrypted to, putting it under exactly the dependency task 5.3 exists to break.
The capture date and container UUID travel in the filename so a stale attachment is identifiable from the entry's file list alone, and the UUID ties the backup to one `luksFormat`: a re-install mints a new UUID (task 7.6 records it), so a backup whose UUID no longer matches the live container restores nothing.

The image is captured on pyrite and the Bitwarden upload happens at stibnite, so it has to cross between the two hosts before anything can be uploaded or removed:

```bash
# host: stibnite
scp 'root@pyrite.zt:/dev/shm/pyrite-luks-header-*.img' ~/
```

The glob is expanded by root's shell on pyrite, and the path is quoted so that the local shell does not consume it first; `/dev/shm` is where the capture block put the file, which is the condition its own `ls -l` established.

`scp` encrypts the transfer, so the mesh hop needs nothing added to it.
What the transfer does not cover is the copy it lands: the file arriving on stibnite is the header image with nothing over it, and it is a full set of the container's keyslots for as long as it sits there, so upload it and remove it in one sitting rather than leaving it in the home directory.
Upload it to the machine's Bitwarden entry — the same `pyrite/zfs-root` entry that holds the passphrase — as a file attachment; the header is never committed to this repository and never placed in sops.
Bitwarden file attachments require a paid plan and the ~16 MiB backup is well within the per-attachment size limit, so confirm the account allows attachments before relying on this path.

Once the upload succeeds, remove the image from both hosts — the copy on stibnite and the original on pyrite's tmpfs:

```bash
# host: stibnite
rm ~/pyrite-luks-header-*.img
```

```bash
# host: pyrite (installed), in a root shell (sudo -i)
shred -u /dev/shm/pyrite-luks-header-*.img
```

Both removals are a security step rather than tidiness, since each file is the keyslot set itself and a copy left behind is a credential that opens the container.
On pyrite the file is on tmpfs, so `shred` is belt-and-suspenders — a plain `rm` releases the RAM backing as well — while on stibnite `rm` unlinks without overwriting, which is why the copy there is uploaded and removed in one sitting rather than left to be tidied later.
Stating both is what keeps a stray copy from being left on whichever host the operator was not thinking about.

### Restoring the header

Restoration reverses the capture and keeps the same tmpfs hygiene, since the image is key material on the way in as much as on the way out.
It needs the attachment off the `pyrite/zfs-root` entry and a tmpfs mount on the machine holding the container, which `/dev/shm` and `/run` both provide on any NixOS or rescue environment.
The attachment is downloaded wherever the vault is reachable and carried to that machine by whatever route it has — over the network if the machine is up, on removable media if it is not — and it is the container's keyslots for the whole of that journey, so it is removed from every hop once the restore has run:

```bash
# host: pyrite (installed), or whatever rescue environment holds the container,
# as root. The assignments are repeated here rather than inherited: this block
# can run in a rescue shell in which the section's opening block never ran.
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2
img=/dev/shm/pyrite-luks-header.img   # the downloaded attachment, placed on tmpfs

cryptsetup luksHeaderRestore "$part2" --header-backup-file "$img"
shred -u "$img"
```

`luksHeaderRestore` reads the backup file rather than creating it, so it carries none of the `O_EXCL` constraint the capture does, and it prompts before it overwrites the live header.

### The slot inventory and its provenance

Both YubiKey 5C Nano tokens report the same AAGUID — `ff4dac45-ede8-4ec2-aced-cf66103f4335`, read from `ykman fido info` on both on 2026-07-20 — and are physically identical, so once both are enrolled `systemd-cryptenroll "$part2"` lists two `fido2` slots and prints nothing that tells them apart.
The header does tell them apart.
Each enrollment writes a `systemd-fido2` token naming the keyslot it authorizes, and both the token list and that binding are readable at any time, with no token seated and without unlocking anything:

```bash
# host: pyrite (installed), in a root shell (sudo -i)
# The assignment is repeated here rather than inherited: this block is read back
# long after the enrollments, in a shell where nothing above it ran.
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2

cryptsetup luksDump "$part2"                    # the Tokens block names each token's keyslot
cryptsetup token export --token-id 0 "$part2"   # the same binding, with the credential
nix-shell -p yubikey-manager --run 'ykman list' # the serial of whichever token is seated
```

Read against the live container on 2026-07-31, `luksDump` reports token 0 binding keyslot 1 and token 1 binding keyslot 2, and each `token export` prints the matching `"keyslots":["1"]` and `"keyslots":["2"]` beside a `fido2-credential` that only the authenticator holding it can answer.
What the header does not carry is the serial, which is what `ykman list` supplies for whichever token is in hand, and the two are joined by the enrollment order this section imposes: each token is enrolled alone, YubiKey-A before YubiKey-B, so the first token entry is A's and the second is B's.

The map for this container is therefore that keyslot 0 holds the clan-vars ZFS root passphrase under argon2id, keyslot 1 holds YubiKey-A, serial `32720759`, and keyslot 2 holds YubiKey-B, serial `32720546`.
Record the same mapping in the `pyrite/zfs-root` Bitwarden entry, reading the indices back from `systemd-cryptenroll "$part2"` at the moment each token is enrolled (D25); the record is read without the machine, which the header is not.
Record alongside it the capture date and container UUID of the header backup currently attached, so the entry names both which credential occupies which slot and which `luksFormat` the stored backup belongs to.

### Re-taking after enrollment changes, and revocation

A header backup freezes the keyslot set exactly as it stood when taken, so restoring one that predates a revocation reinstates the revoked slot verbatim and decrypts the disk again (D26).
The backup is thus itself an enrolled credential, and the retention rule is not "keep them all": after any change to the enrolled set, take a fresh backup, upload it, and delete the superseded Bitwarden attachment, because a stale attachment is an un-revoked credential sitting in storage.
The triggers are every enrollment change without exception — any revocation, any future token added, and any credential removed — and each re-runs the capture above and updates the slot inventory.
Neither post-install enrollment is among them, because the ordering above puts both ahead of the first capture: the initial backup already records both tokens and the passphrase, so there is nothing to re-take for either.

Revocation removes one slot from the live header:

```bash
# host: pyrite (installed), in a root shell (sudo -i)
# The assignment is repeated here rather than inherited: this block is the one
# most likely to be run months later, in a shell where nothing above it ran.
part2=/dev/disk/by-id/nvme-APPLE_SSD_AP0512J_C08843605KKHV4MAK_1-part2

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
