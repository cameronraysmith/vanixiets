---
title: Adding a bare-metal MacBookPro14,1 as a NixOS machine to the vanixiets clan
status: working-note
source-issue: CAM-31
supersedes-note: partially superseded by pyrite-hardware-inventory.md
---

# Adding a bare-metal MacBookPro14,1 as a NixOS machine to the vanixiets clan

## Provenance and supersession

This report was produced before the machine was booted.
Its hardware section reasons from a third-party MacBookPro14,1 dump corpus and from kernel source, not from the unit itself.
Live recon on 2026-07-16 (CAM-31) subsequently observed the actual machine and closed most of the section 7 unknowns.

Where this report and `pyrite-hardware-inventory.md` disagree, the inventory note wins, because it records observation and this one records inference.
Three specific corrections are already known and are recorded in the inventory note's "Corrections to prior inference" section: the b43 eval-failure claim in section 5, the audio conclusion in section 6, and the nixos-facter availability assumed throughout section 3.

Everything outside section 1 and section 6 — in particular the clan-core install mechanics of section 3, the file set of section 2, and the nixos-hardware profile audit of section 5 — remains the grounding for the `pyrite-baremetal-nixos` OpenSpec change.

## Original report

This note synthesizes seven survey agents and five adversarial verifiers investigating whether and how an Apple MacBookPro14,1 (2017 13-inch, non-Touch-Bar) can join the vanixiets clan at `/Users/crs58/projects/vanixiets` as a NixOS machine.
It is decision-ready in the sense that every technical question research can settle has been settled with a file path or a command; the questions research cannot settle are enumerated in sections 7 and 8.

All evidence below was read at vanixiets' pinned revisions: nixpkgs `e8273b29fe1390ec8d4603f2477357555291432e` (nixos-unstable-small, 2026-07-01, version `26.11pre1025900`, default x86_64-linux kernel 6.18.37) and clan-core `d332b6935fbebebc0ca151efe0b3144f8dcd9d96` (2026-07-03).
Where a source tree is ephemeral (`/tmp/klinux`, `/tmp/mbp2016`, `/tmp/lfw`), the note names the command that reproduces it.

## 1. Hardware ground truth

Five claims went to adversarial verification.
Four came back confirmed; one came back refuted, and the refutation matters for the configuration surface rather than for the install decision.

### The four confirmed verdicts

The audio codec is a Cirrus CS8409, mainline Linux cannot drive its speakers, and an out-of-tree module is required — **confirmed**.
This is not inference: a real MacBookPro14,1 dmesg (`/tmp/mbp2016/MacBookPro14,1/dmesg:848-854`) reads `snd_hda_codec_cirrus hdaudioC0D0: autoconfig for CS8409: line_outs=2 (0x24/0x25/...) type:speaker`, with `Internal Mic=0x44` and `Mic=0x3c`.
The dump directory is keyed on `/sys/class/dmi/id/product_name` by the corpus's own `get-info.sh:13`, and the same directory's `dmesg:64` confirms `DMI: Apple Inc. MacBookPro14,1/Mac-B4831CEBD52A0C4C`.
The refutation lens assigned to this claim — that CS8409 is a T2-era-only codec and the 14,1 really carries a CS4208 driven by mainline `patch_cirrus` — failed on every branch.
CS4208 binding is impossible because `cs420x.c:771-773` binds only codec IDs `0x10134206/0x10134207/0x10134208` while CS8409 is `0x10138409`; and the CS4208 Apple SSID table (`cs420x.c:578-589`) tops out at `SND_PCI_QUIRK(0x106b, 0x7b00, "MacBookPro 12,1", CS4208_MBP11)` with no 13,x or 14,x entry.

WiFi works with in-tree `brcmfmac` and redistributable firmware, requiring no extraction from macOS — **confirmed**, and this is the verdict that governs irreversibility.
The chip is a BCM4350 (`lspci:443-444`, `[14e4:43a3] rev 05`, subsystem Apple `[106b:0170]`), matching `BRCM_PCIE_4350_DEVICE_ID 0x43a3` in the pinned kernel's `brcm_hw_ids.h:75`.
The decisive structural fact is that `pcie.c:2726` classifies the 4350 as `WCC` with `fw_seed = false`, whereas 4355, 4364, 4377, 4378, 4387, and 43752 are `WCC_SEED` — and the seed chips are precisely the ones with no linux-firmware blob and therefore the macOS-extraction cases.
The verifier fetched upstream `WHENCE` at the exact tag nixpkgs pins (`linux-firmware` 20260622, per `pkgs/by-name/li/linux-firmware/package.nix:27`) and found `brcm/brcmfmac4350-pcie.bin` and `brcm/brcmfmac4350c2-pcie.bin` present at `WHENCE:2914-2915` under a redistributable licence, while `brcmfmac4364|4377|4387|4355` returned zero hits.
The blob is not unfree-gated: `lib/licenses/licenses.nix:1539-1544` marks `unfreeRedistributableFirmware` as `redistributable = true` with no `free = false`, and `nixos/modules/profiles/installation-device.nix` reaches `installer/scan/detected.nix:5-8`, which sets `hardware.enableRedistributableFirmware = true` — so the official installer ISO already carries it.
End-to-end proof exists on real hardware: `dmesg:876` `using brcm/brcmfmac4350c2-pcie for chip BCM4350/5`, `:894` firmware version `7.35.180.133`, `:979` `wlan0: link becomes ready`.

The internal keyboard and trackpad work via mainline `applespi`, and the nixos-hardware profile brings them up in stage-1 initrd — **confirmed**, and confirmed by construction rather than argument.
There is no device table to exclude the 14,1: `applespi.c:1906-1910` matches solely on ACPI HID `APP000D` with no DMI table at all, and the driver header (`applespi.c:9-13`) states that USB keyboard pins are connected only on MacBookAir6/7 and MacBookPro12, so "all others need this driver" — the 14,1 is necessarily SPI-attached.
The strongest available refutation (that `applespi` needs a pinctrl/GPIO module that is not a symbol dependency and would therefore never be auto-pulled into initrd) was itself refuted from source: `applespi.c:1727,1736,1748` use an ACPI GPE (`acpi_evaluate_integer(spi_handle, "_GPE", ...)`, `acpi_install_gpe_handler`, `acpi_enable_gpe`), which is core ACPI and built in.
The verifier then built the actual closure against vanixiets' pinned nixpkgs, producing `/nix/store/il4ng48dbi2qj5l64kjmsv61f048dh6w-linux-6.18.37-modules-shrunk` containing `applespi.ko.xz`, `spi-pxa2xx-platform.ko.xz`, `spi-pxa2xx-core.ko.xz`, `intel-lpss-pci.ko.xz`, `intel-lpss.ko.xz`, `applesmc.ko.xz`, `led-class.ko.xz`, `crc16.ko.xz`, alongside `dm-crypt.ko.xz` and `nvme.ko.xz`.
The keyboard registers the `kbd` VT handler (`hwinfo.txt:1747-1748`, `handlers = sysrq kbd event5 leds`), which is what a console passphrase prompt reads.
A LUKS prompt on the internal keyboard is therefore expected to work without an external USB keyboard.

clan-core at the pinned revision provides a documented path for a physical machine, and vanixiets can adopt it without architectural change — **confirmed**, with one named sub-clause refuted (see section 3).

### The refuted verdict: "no T1, no T2, therefore standard controller and easiest tier"

This claim is a conjunction, and it fails.
The T1 and T2 halves survive: `/tmp/mbp2016/README.md:402-406` documents the T1 as the USB `iBridge` device present only on Touch Bar models, and the Touch Bar and Touch ID status rows (`README.md:266-267`, `:281`) enumerate 13,2 / 13,3 / 14,2 / 14,3 / 16,1 / 16,2 with 14,1 absent.
T2 begins at 15,x (`README.md:157`), corroborated by NVMe device IDs: 14,1 and 14,2 both carry `[106b:2003]` while the T2-era 15,1 carries `[106b:2005]`, the ID gated in `drivers/nvme/host/pci.c:3991-3996` behind `NVME_QUIRK_SINGLE_VECTOR | 128_BYTES_SQES | SHARED_TAGS | SKIP_CID_GEN | IDENTIFY_CNS`.
So `apple-bce` is irrelevant and no T2 Startup Security Utility gate exists.

What is refuted is "standard controller" and the implied "no Apple-specific storage or boot quirk".
The controller is an Apple-vendor device, not a standard one: `lspci:383` reads `01:00.0 Mass storage controller [0180]: Apple Inc. Device [106b:2003]` — PCI class `0x0180`, not `0x0108` (NVM Express).
The pinned kernel carries an explicit `{ PCI_DEVICE(PCI_VENDOR_ID_APPLE, 0x2003) }` at `pci.c:3990` precisely because the generic class catch-all at `pci.c:3997` would not match it.
It carries no quirk flags, so boot works unquirked (`dmesg:699-705` shows `nvme0n1` with partitions p1..p7) — but "no driver_data" is not "standard controller".

And there is a documented Apple-specific quirk naming this model by name.
`/tmp/mbp2016/README.md:213-215`: "Models with Apple's NVMe controller (MacBookPro13,1, MacBookPro13,2, MacBookPro14,1 and MacBookPro14,2) require disabling the `d3cold` PCIe power state for the NVMe controller to successfully wake up again", with `:218` giving `echo 0 > /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed` and `:222` noting resume is still slow, "up to a minute".
nixos-hardware's own README concedes the same at `apple/macbook-pro/14-1/README.md:16` and `:19`.
A second Apple-specific quirk, unrelated to T1/T2, is auto-boot on lid open (`README.md:460-462`), fixed only by writing an EFI variable.

**What settles the remaining uncertainty on-device.**
The Startup Security Utility sub-claim is the one item marked low confidence and unverifiable from local sources: `rg -i 'startup security|secure boot|firmware password'` over both nixos-hardware's `apple/` tree and the mbp2016 corpus returns zero hits.
That Startup Security Utility is T2-only is general knowledge, not grounded here.
What is grounded is that a real 14,1 boots a custom EFI chain (`dmesg:2`, `Command line: \EFI\linux\vmlinuz.new.efi.5k2`).
A pre-T2 EFI firmware password could still be set on this specific unit and would block external boot.
The single observation that settles it: boot the NixOS installer from USB while holding Option at power-on.
If the USB appears in the boot picker and boots, no firmware password is in play and the boot half of the claim is settled empirically.

One methodological correction worth preserving.
The survey inferred "no T1" partly from the 14,1 `lsusb` showing only root hubs.
That inference is invalid standing alone: the verifier found that MacBookPro14,3 — a Touch Bar / T1 model — *also* enumerates only root hubs in its dump, which is evidently partial (its `lspci` lists no NVMe either).
The no-T1 conclusion is sound, but it rests on the README status rows and the PCIe FaceTime camera (`14e4:1570` present on 13,1 and 14,1, absent on 14,2 and 14,3), not on `lsusb` absence.

### Summary of the machine

MacBookPro14,1, board `Mac-B4831CEBD52A0C4C`, Intel i5-7360U (Kaby Lake), two Thunderbolt 3 ports, function keys.
No T1, no T2.
Storage: Apple NVMe `106b:2003`, unquirked at boot, needing a `d3cold` workaround at suspend.
WiFi: Broadcom BCM4350, in-tree `brcmfmac`, redistributable firmware.
Bluetooth: Broadcom over UART via serdev (`hci_uart_bcm`), needing `BT_HCIUART_BCM` which the pinned nixpkgs already sets (`common-config.nix:1242-1248`); the `.hcd` patch is optional because `btbcm.c:669-691` logs "firmware Patch file not found" and returns 0 regardless.
Input: SPI via `applespi`, mandatory, mainlined.
Camera: PCIe FaceTime HD `14e4:1570`, packaged in nixpkgs, firmware fetched from Apple's CDN rather than the local macOS install.
Audio: CS8409 with an SSM3515-class amplifier, requiring an out-of-tree module; internal microphone does not work even then.

The irreversibility question — is it safe to wipe macOS — resolves cleanly to yes.
No component's firmware comes from the local macOS install.
WiFi blobs ship in linux-firmware; Bluetooth needs no blob; the camera firmware is fetched from `updates.cdn-apple.com`; the audio module is source, not a blob.

## 2. The vanixiets integration problem

This is the architectural crux, and the first thing to say is that the machine would be the first of its kind in this fleet.
`git log --all --diff-filter=A --name-only -- 'modules/machines/nixos/*'` yields exactly six names ever created: cinnabar, electrum, galena, gcp-vm (deleted), magnetite, scheelite.
All six are cloud VMs.
Every hardware assumption in the repo is therefore untested on physical hardware.
`orb-nixos` appears in `.sops.yaml:19` and `scripts/sops/*` as a host age key but has no machine module and no `nixosConfiguration`; it is a local OrbStack VM key, not a counterexample.

### The minimal file set

The authoritative recipe is not documentation — it is the magnetite introduction commit sequence, recoverable with `git log --all --oneline -S 'magnetite' --name-only --reverse`, which runs: terranix server definition, machine module, disko, `clan/machines.nix` plus `inventory/machines.nix`, `inventory/services/users/cameron.nix`, `clan vars generate` commits, Cloudflare DNS, `inventory.json`, then `lib/hosts.nix` plus `ssh-known-hosts.nix` plus `home/core/ssh.nix` plus cinnabar's `zt-dns.nix`, and finally the `.sops.yaml` bridge recipient.

Hand-written, in order:

1. `modules/machines/nixos/<name>/default.nix` — the host module.
2. `modules/machines/nixos/<name>/disko.nix` — with a real `/dev/disk/by-id/...` path, not `/dev/sda`.
3. `modules/clan/machines.nix` — `<name> = { imports = [ config.flake.modules.nixos."machines/nixos/<name>" ]; };`.
4. `modules/clan/inventory/machines.nix` — `tags` (must include `nixos` and `peer`), `machineClass = "nixos"`, `description`, `deploy.targetHost`.
5. `modules/clan/inventory/services/users/cameron.nix` — add `roles.default.machines."<name>" = { };`.
6. `modules/checks/structure/flake-shape.nix` — add to both hardcoded `expected` lists (`:30-40` and `:46-52`), alphabetically.
7. `.sops.yaml` — a `&<name>` anchor after `clan vars generate`, plus `*<name>` in the `secrets/bridge/.*` rule, then re-encrypt `secrets/bridge/crs58-age-key.enc`.

Post-deploy, once the ZeroTier address is known: `modules/lib/hosts.nix`, `modules/system/ssh-known-hosts.nix`, `modules/home/core/ssh.nix`, and cinnabar's `modules/machines/nixos/cinnabar/zt-dns.nix`.
That last one is load-bearing and easy to miss — cinnabar is the coordinator, and it learns about a new machine *only* through the hand-maintained dnsmasq address list in `zt-dns.nix`.
ZeroTier membership itself is automatic via the `peer` tag; the `allowedIps` list in `inventory/services/zerotier.nix:14-20` holds only darwin and external members, so a NixOS peer needs no entry there.

Generated by tooling, not authored: `machines/<name>/facter.json`, `sops/machines/<name>/key.json`, `sops/secrets/<name>-age.key/`, `vars/per-machine/<name>/**`, `vars/shared/zerotier-{identity,ip}-<name>*/`, `vars/shared/user-password-cameron/user-password-hash/machines/<name>`, and `inventory.json`.

Two mechanical traps beyond the file set.
`justfile:35` hardcodes `nixos_hosts=(cinnabar electrum galena scheelite)` in `check-uncached-machine` — magnetite is already missing, so that recipe errors on the fleet's newest machine and would error on a new one too.
`just build-all` (`justfile:646-649`) builds only four of nine machines.
`just test-quick` (`justfile:615,621`) references `.#checks.aarch64-darwin.secrets-generation`, which does not exist in the enumerated darwin check set.
These are pre-existing defects, surfaced here because a new machine walks into them; fixing them is a separate change.

A new machine automatically acquires exactly one check — its `nixos-<name>` toplevel build, emitted programmatically at `modules/checks/machines.nix:30-34`.
`structure-inventory-class-discovery` and `machine-registry-completeness` (`modules/checks/validation.nix:598`) are computed and pass automatically for a correctly-placed machine.
Only `flake-shape.nix` carries literals.

### Where bare metal diverges

The terranix coupling is narrower than it looks.
`modules/terranix/hetzner.nix` does exactly four things: creates an `hcloud_server` (`:60-68`), mints a deploy SSH key (`:42-56`), writes a Cloudflare A record pointing at the server's `ipv4_address` (`:71-78`), and runs a `null_resource` invoking `clan machines install <name> --update-hardware-config nixos-facter --target-host root@<ip> -i <key> --yes` (`:81-90`).
Everything else in the file set above is provider-agnostic.
Terranix supplies only machine existence, an IPv4, a DNS record, and the install trigger.

Bare metal substitutes each of those with a manual act: physically boot an installer with SSH reachable, type a LAN address into `--target-host`, skip DNS entirely if the machine is ZeroTier-only, and run `clan machines install` by hand.
There is no non-terranix invocation site for the install command anywhere in the repo — the `null_resource` is the only one.

The real divergences are in the machine module, and there are five.

**Hardware module.** Every NixOS host imports `inputs.srvos.nixosModules.server`; the Hetzner ones additionally import `inputs.srvos.nixosModules.hardware-hetzner-cloud`, which per `nixos/hardware/hetzner-cloud/default.nix:9-30` supplies `qemu-guest.nix`, cloud-init, `boot.growPartition`, `boot.loader.grub.devices = ["/dev/sda"]`, `useNetworkd = true`, and `useDHCP = false`.
A bare-metal host gets none of that and must state each explicitly.
`galena` is the in-repo precedent for a NixOS host without an srvos hardware module: `modules/machines/nixos/galena/default.nix:21-23` carries a note forbidding the Hetzner module and `:45-48` sets `grub.enable = lib.mkForce false` with systemd-boot instead.
`nixos-hardware` is not a flake input (`rg -i 'nixos-hardware' flake.nix flake.lock` returns nothing) and would have to be added; it declares only `nixpkgs`, so repo convention gives `nixos-hardware.inputs.nixpkgs.follows = "nixpkgs"` mirroring disko at `flake.nix:83-84`.
import-tree needs no registration for a new input — `flake.nix:6` threads `inputs` into every auto-discovered module.

**Disk device path.** Every existing disko layout hardcodes `device = "/dev/sda"` (`cinnabar/disko.nix:9`) and sets `boot.zfs.devNodes = "/dev/disk/by-path"` with an in-repo comment justifying it "for cloud VMs" (`cinnabar/default.nix:39-40`).
Neither transfers.
The device is `/dev/nvme0n1`, and `by-id` is the bare-metal norm.

**Initrd assumptions in the fleet-wide base.** `modules/system/initrd-networking.nix:36-39` unconditionally sets `boot.initrd.kernelModules = ["virtio_pci" "virtio_net"]` and `:24-32` enables initrd SSH unlock on port 2222, on `flake.modules.nixos.base`, which every NixOS host imports.
On a roaming laptop with a real NIC this is inert but pointless: remote unlock over a network the machine has not joined is not a plan.
The machine needs either a per-machine override or `base` needs a `lib.mkIf` gate.
This is the one place the fleet's cloud-VM assumption leaks into the shared layer rather than a per-machine one.

**ZFS force-import.** `modules/system/zfs-force-import.nix:19-21` sets `boot.zfs.forceImportRoot = true` fleet-wide via `base`.
Every existing layout is ZFS-on-single-disk.
Whether the laptop uses ZFS at all is an open decision (section 8).

**Bootstrap reachability.** Every inventory entry uses `deploy.targetHost = "root@<name>.zt"`, which only works after the machine has already joined the mesh.
Cloud hosts bootstrap via terranix's IP-based install and then switch to `.zt`.
Bare metal has the same two-phase shape but no automation for phase one.

Two power/suspend items have no fleet precedent at all: `rg` over the repo returns zero occurrences of `boot.extraModulePackages`, `boot.initrd.availableKernelModules`, and `boot.kernelParams`.
The audio module and the d3cold workaround would each be the first of their kind here.

## 3. clan-core install mechanics at the pinned revision

### The premise that vanixiets does not follow the machines/ convention is false

This was the sharpest correction the verification round produced, and it dissolves the problem the survey was commissioned to solve.
`ls machines/` returns cinnabar, electrum, galena, magnetite, scheelite — each containing exactly one file, `facter.json`.
`nix eval .#clanInternals.inventoryClass.relativeDirectory --raw` returns the empty string, so clan resolves `machines_dir` (`clan_lib/dirs/__init__.py:173-196`) to `<repo-root>/machines`, which is exactly where those files already are.
The repo already conforms.

The two conventions coexist because clan's Nix side degrades gracefully.
`nixosModules/machineModules/forName.nix:13-21` filters every `machines/<name>/{configuration,hardware-configuration,disko}.nix` import through `builtins.filter builtins.pathExists`, so their absence is silent.
`nixosModules/clanCore/nixos-facter.nix:5-10` sets `hardware.facter.reportPath = lib.mkIf (builtins.pathExists facterJson) facterJson` — an opt-in auto-import that costs nothing.
So `machines/` is a pure data directory (hardware reports) while module composition lives in `modules/`, and the deferred-module tree never collides with clan's path convention.
The darwin machines have no `machines/<name>/` directory at all, which is consistent: the tension is entirely about facter.json, and nix-darwin machines have none.

The one place a collision would occur is `clan templates apply disk`.
`clan_lib/templates/disk.py` hardcodes `disko_file_path = hw_config_path.parent.joinpath("disko.nix")`, writing `machines/<name>/disko.nix`, which `forName.nix` would then auto-import alongside vanixiets' own `modules/machines/nixos/<name>/disko.nix`.
That documented step must be skipped and disko hand-authored, as it already is for all five existing machines.

### clan flash versus clan machines install

The `clan flash` disjunct is refuted as a documented path.
`git grep -n 'clan flash' d332b693 -- '*.md'` returns zero hits at the pinned revision.
The word "flash" in `docs/src/getting-started/getting-started-physical.md:161` refers to `dd`.
`docs/src/concepts/templates.md:29,33` mentions `flash-installer` only as a name inside a sample `clan templates list` output tree, with no accompanying workflow.
The `clan flash` CLI exists (`clan_lib/flash/flash.py`, `clan_cli/flash/flash_cmd.py`) and does something other than its name suggests: `run_machine_flash` (`flash.py:80-186`) shells out to `disko-install`, formatting a disk and installing a machine's full closure directly onto it, rather than writing an installer image.
A key-baked clan-aware installer does exist as a comment in clan-core's own flake (`pkgs/installer/flake-module.nix:74-77`, `# $ clan flash write flash-installer --disk main /dev/sdX --yes`), but that machine is defined in clan-core's flake, not yours, and would require applying `templates/machine/flash-installer` into vanixiets.

`clan machines install` is documented end-to-end and is the path to use.
`docs/src/getting-started/getting-started-physical.md` gives: `wget` an upstream `nix-community/nixos-images` ISO and `dd` it (step 5), `ssh-copy-id` to the booted installer (step 8, with the explicit warning that "This authorizes your key for the running installer session only. It is not written to the USB drive, so repeat this step if you reboot the installer"), `clan machines init-hardware-config <name> --target-host root@<INSTALLER-IP>` (step 9), `clan templates apply disk` (step 10 — skip this), `clan machines install <name> --target-host root@<INSTALLER-IP>` (step 11), then `clan machines update` thereafter.
The command is a `nixos-anywhere --flake <flake>#<machine>` wrapper (`clan_lib/machines/install.py:154-243`); disko partitioning is delegated, not reimplemented.
Default phases are `["kexec", "disko", "install", "reboot"]`, run one at a time.
The target must already be a running Linux system reachable over SSH (`clan_cli/machines/cli.py:169-172`).
The same command shape is already in production in this repo at `modules/terranix/hetzner.nix:85`.

The documented `clan init` (step 1) and `clan machines create` (step 2) must also be skipped — the latter writes through `InventoryStore` (`clan_cli/machines/create.py:59-72`), conflicting with vanixiets' nix-declared inventory.

### Hardware detection: facter versus generate-config

Two commands exist, not one, and the default backend for both is `nixos-facter`.
`init-hardware-config` (`clan_lib/machines/hardware.py:113-183`) runs `nixos-anywhere --phases kexec --generate-hardware-config <backend> <path>`, kexecing the target into a temporary NixOS to gather info.
`update-hardware-config` (`:186-256`) does not kexec; it SSHes in, becomes root, and runs `nixos-facter` directly, capturing stdout.
Both back up an existing file to `.bak`, write, commit, evaluate the machine, and restore the backup on eval failure.

That last behavior imposes a real ordering constraint: the machine must already evaluate — module, disko, and `clan.machines` registration complete — before hardware detection runs.
This is a chicken-and-egg with disko, which needs a device path.
Two escapes: boot the installer first and read `lsblk -o NAME,SIZE,MODEL` and `ls /dev/disk/by-id` to hand-write disko before detection, or bootstrap facter.json with a throwaway disko and rewrite it after.
The first is cleaner and costs one extra boot.

clan-core supports hand-written `machines/<name>/hardware-configuration.nix` as an alternative (`forName.nix:13-21`) but warns if both it and facter.json exist (`nixos-facter.nix:11-24`).
This repo uses only facter.json, and the recommendation is to keep it that way — it preserves the convention and it is what `--update-hardware-config nixos-facter` produces.
Facter is what supplies `boot.initrd.availableKernelModules` (`nixos/modules/hardware/facter/disk.nix:26`, `keyboard.nix:19`) and `boot.kernelModules` (`virtualisation.nix:57`) on these machines, which the repo itself never sets.
Note that nixos-facter is not a flake input directly or transitively — `rg -i 'facter' flake.lock` returns nothing — because the facter NixOS modules are upstreamed into nixpkgs (`nixos/modules/module-list.nix:70`, `./hardware/facter`).

### Secret and host-key provisioning ordering

There is no chicken-and-egg here, and the survey's most useful correction to the stale in-repo guide is that the machine age key is *not* derived from the SSH host key.
`clan_lib/vars/secret_modules/sops.py:62-90` (`ensure_machine_key`) generates the keypair on the setup machine before install, encrypts the private half into `sops/secrets/<machine>-age.key` to the admin user plus `defaultGroups`, and registers the public half under `sops/machines/<machine>/`.
At install time, `install.py:126-165` runs the generators, then `populate_dir(..., phases=["activation","users","services"])` decrypts `<machine>-age.key` and writes it as `key.txt` into a temp tree rooted at the machine's `sops.secretUploadDirectory` (e.g. `/var/lib/sops-nix`), handed to nixos-anywhere as `--extra-files`.
Partitioning-phase secrets go separately via `--disk-encryption-keys /run/partitioning-secrets/...` (`install.py:170-182`).
So the order is: `clan vars generate` locally, keys exist in-repo encrypted, then `clan machines install` ships the private key in.
The correct way to recover a key from an already-deployed machine is `ssh root@<machine> 'cat /var/lib/sops-nix/key.txt | age-keygen -y'`, not `ssh-keyscan | ssh-to-age` (`packages/docs/src/content/docs/guides/host-onboarding.md` documents this explicitly).

That same guide is stale on layout: it documents flat `modules/machines/nixos/<hostname>.nix` files while the repo uses per-machine directories.

### ZeroTier enrollment

Admission is declarative and build-time, not runtime.
The controller (`clanServices/zerotier/default.nix:222-241`) folds over every inventory machine in the moon, controller, and peer roles, reads each one's `zerotier-ip-<name>-<instance>` public var via `clanLib.getPublicValue`, and emits a `zerotier-autoaccept-<instance>` systemd unit that runs `zerotier-members --network-id <id> allow --member-ip <ip>` for each (`:319-330`).
The consequence for a new machine is a specific extra step: add it to the inventory, `clan vars generate` mints its identity and IP, then **`clan machines update cinnabar`** to regenerate and re-run the autoaccept list.
Without that step the new peer is never admitted.
Exactly one controller is permitted (`:18-20`, `maxMachines = 1; minMachines = 1`).

ZeroTier IPs are non-secret shared vars available at eval time — `vars/shared/zerotier-ip-magnetite-zerotier/ip/value` equals `fddb:4344:343b:14b9:399:930f:39db:40d2`, identical to the hardcoded `modules/lib/hosts.nix:8`.
All consumers nonetheless hardcode across roughly seven nix files; `docs/notes/development/research/dynamize-zerotier-addresses.md` is the open plan to fix that.
A new machine adds to the hardcoding burden.

### Installing from stibnite (darwin)

No linux builder is required for `clan machines update`: `clan_lib/machines/update.py` defaults `build_host` to `target_host`, so the build runs on the target, and `docs/src/guides/build-host.md:11` confirms clan "evaluates your flake on your workstation, then builds and activates on `deploy.targetHost`".
ZeroTier is a first-class transport — the service exports `networking.module = "clan_lib.network.zerotier"` at priority 900 (`clanServices/zerotier/default.nix:25-33`).

For `clan machines install` the answer is: the question does not bind, because stibnite already has an x86_64-linux builder.
`modules/machines/darwin/stibnite/default.nix:171-193` provisions `nix-rosetta-builder` with 12 cores and 48 GiB, with the native `nix.linux-builder` disabled at `:169`.

The residual gap is honest and worth recording: nixos-anywhere's own `--build-on` default is unverified.
clan passes the flag only when explicitly set (`install.py:212-216`), and nixos-anywhere is resolved at runtime via `nix_shell(["nixos-anywhere"], cmd)` rather than vendored, with no local clone at `~/ghq/github.com/nix-community/nixos-anywhere`.
`docs/src/decisions/05-deployment-parameters.md:9` states "Install always evals locally and pushes the derivation to a remote system", which points one way, but that is a decision record, not the code path.
Passing `--build-on remote` explicitly sidesteps the question, and the rosetta builder covers it either way.
Nothing here blocks.

## 4. Reference implementations ranked

The ranking requested cannot be produced as posed, and this is a genuine gap rather than a shortfall of effort.
Seven of the eight named reference repositories do not exist locally.
`/Users/crs58/projects/nix-workspace/` does not exist as a directory at all; `ls /Users/crs58/projects/` returns `dlt-lance-hf-catalog`, `ldrf`, `sciexp`, `test-linkml`, `vanixiets`.
An exhaustive search (`fd -t d -d 3 -i 'dendritic|molybdenum|mic92|qubasa|pinpox|enzime|jfly|snow|onix|dotfiles' /Users/crs58/projects /Users/crs58/ghq`) surfaced only `/Users/crs58/ghq/github.com/Mic92/`, which holds `direnv-instant`, `niks3`, `nix-fast-build`, `sops-nix` — no dotfiles repo.
Per the reference-repository convention, this is surfaced rather than papered over with web lookups.

What can be ranked, from the two repos that do exist plus vanixiets itself:

1. **vanixiets' own magnetite commit sequence** is the best template for the clan/inventory/sops/vars skeleton, and `galena` is the best template for a NixOS host that does not import an srvos hardware module.
2. **clan-infra** contributes exactly two patterns and no more.
3. Everything else is not on disk.

clan-infra has no laptop at all.
Its eight machines are `web01` and `build-x86-01` (srvos `hardware-hetzner-online-amd`, Hetzner dedicated), `build01` (`hetzner-rx170`), `web02` and `jitsi01` (`vultr-vc2`), `storinator01` (a physical 45drives Q30), and `build02`/`build04` (Mac mini M4, `machineClass = "darwin"`).
The two Apple machines have only `configuration.nix` and `terraform-configuration.nix` — no facter.json, no disko, no LUKS, no nixos-hardware — because macOS manages its own disk and nix-darwin layers on top.
`rg -n 'nixos-hardware'` over clan-infra returns zero hits; `rg -ril 'asahi|apple/t2|nixos-hardware'` over clan-core returns zero hits.
Nobody in either repo imports an `apple/` profile, because nobody imports nixos-hardware at all.

The two patterns worth importing from clan-infra are both about intermittent connectivity, and both come from `build02`:

```nix
# clan-infra machines/build02/configuration.nix:13-15
# No public IP and often offline, so skip it in implicit `clan machines update`
clan.core.deployment.requireExplicitUpdate = true;
```

and, from `machines/flake-module.nix`, `build02.deploy.targetHost = "root@build02?ProxyJump=tunnel@web01.clan.lol"`.
None of vanixiets' four existing darwin machines set `requireExplicitUpdate`, which is worth confirming as deliberate.

**The single most useful verbatim example** is not a LUKS layout, because clan-infra has no LUKS — `rg -i 'luks|cryptsetup'` finds no LUKS disko layout, and neither does vanixiets.
clan-infra encrypts with ZFS native encryption keyed by a clan vars generator, which is the pattern to steal:

```nix
# clan-infra machines/web01/disko.nix
clan.core.vars.generators.zfs = {
  files.key.neededFor = "partitioning";
  script = ''
    dd if=/dev/urandom bs=32 count=1 | xxd -c32 -p > $out/key
  '';
};
```

consumed by the pool as:

```nix
zpool.zroot.datasets."root".options = {
  encryption = "aes-256-gcm";
  keyformat = "hex";
  keylocation = "file://${config.clan.core.vars.generators.zfs.files.key.path}";
};
```

The `neededFor = "partitioning"` marker is what routes the key through `clan machines install --disk-encryption-keys`, closing the loop described in section 3.
Note that this is a *keyfile* pattern designed for a server that unlocks over initrd SSH (clan-infra's `modules/initrd-networking.nix`, port 2222, imported only by the server hardware profiles and never by the darwin machines).
A laptop wants a passphrase prompt on the internal keyboard instead — which section 1 confirms works.
So the generator shape transfers; the key *delivery* does not, and that is a design decision rather than a copy.

The clan-infra Apple onboarding workflow (`README.md:338-360`) is three steps — `ssh customer@build04.clan.lol passwd`, install Nix via the nix-installer script, `clan machines update build04` — with no `clan flash`, no `clan machines install`, no nixos-anywhere.
That is the *nix-darwin* path and is not applicable here.

## 5. nixos-hardware apple-macbook-pro-14-1

The flake output attribute is `nixosModules.apple-macbook-pro-14-1` (`flake.nix:64`, `apple-macbook-pro-14-1 = import ./apple/macbook-pro/14-1;` inside the `nixosModules` block opened at `:37`; note `:42` shadows `import = path: path;` so the output is the raw path handed to the module system unevaluated).
Clone HEAD `fccfa903`, 2026-07-15.
The repo is live; this profile is bitrotted — `git log --follow -- apple/macbook-pro/14-1/` yields 13 commits, and the newest four are treewide sweeps (nixfmt 2025-06-04, symlink 2025-05-05, acpi_call drop 2024-12-02, gpu→cpu 2024-10-10).
The last model-specific attention is a 2024-06-23 to 2024-07-15 burst by Michael Paepcke; before that, the 2022-10-21 addition by Zane van Iperen.

The effective option set was evaluated empirically rather than inferred, against nixpkgs at HEAD with only the profile plus `hostPlatform`, `stateVersion`, and a dummy filesystem:

`boot.initrd.kernelModules = [applesmc applespi dm_mod i915 intel_lpss_pci spi_pxa2xx_platform]`; `boot.initrd.availableKernelModules` = the stock nixpkgs list, untouched; `boot.kernelParams = [i915.enable_guc=2 i915.enable_fbc=1 i915.enable_psr=2 intel_iommu=on ...]`; `boot.kernelPackages.kernel.version = 6.18.38`; `boot.blacklistedKernelModules = []`; `boot.kernelModules = [applesmc atkbd coretemp loop msr]`; `services.fstrim.enable = true`; `services.mbpfan.enable = true`; `services.tlp.enable = true`; `services.libinput.enable = true`; `hardware.facetimehd.enable = false` (with `allowUnfree = false`); `hardware.cpu.intel.updateMicrocode = true`; `hardware.enableRedistributableFirmware = true`; `networking.enableB43Firmware = true`; `console.font = null`; `console.earlySetup = false`; `hardware.intelgpu = {driver=i915; computeRuntime=legacy; vaapiDriver=intel-media-driver; loadInInitrd=true}`; `graphics.extraPackages = [intel-media-driver intel-compute-runtime-legacy1 vpl-gpu-rt]`; `systemd.services ? disable-nvme-d3cold = false`.
Plus the `environment.etc."libinput/local-overrides.quirks"` text at `14-1/default.nix:31-47`.

Prior agent claims, adjudicated:

| Claim | Verdict | Note |
|---|---|---|
| Kaby Lake / Intel CPU tuning | Partial, misleading | The import exists (`14-1/default.nix:10`) but `common/cpu/intel/kaby-lake/cpu-only.nix:1-5` is a pure passthrough to `common/cpu/intel/cpu-only.nix:3`, whose sole option is `updateMicrocode`. There is zero CPU tuning. All Kaby-Lake content is GPU-side (`common/gpu/intel/kaby-lake/default.nix:4-13`). |
| HiDPI console | Confirmed but inert | `common/hidpi.nix:14-17` is `lib.mkIf oldKernel` where `oldKernel = versionOlder kernel.version "6.8"` (`:10`). At 6.18.38 both options evaluate to their defaults. Dead code on any current nixpkgs. |
| SSD defaults | Confirmed, minimal | `common/pc/ssd/default.nix:4` is one line: `services.fstrim.enable = lib.mkDefault true`. No scheduler, no discard mount options. |
| mbpfan | Confirmed | `apple/default.nix:6`. |
| Intel microcode | Confirmed, set twice | `14-1/default.nix:53` and `common/cpu/intel/cpu-only.nix:3`. |
| WiFi firmware | Partial — two distinct paths | `:50` `enableB43Firmware` installs `b43Firmware_5_1_138` (`nixos/modules/hardware/network/b43.nix:29-31`), the legacy b43 blob. `:52` `enableRedistributableFirmware` installs `linux-firmware` (`all-firmware.nix:71-80`), which is the brcm blob the README credits. The b43 line is almost certainly vestigial. |
| facetimehd | Confirmed and gated | `apple/default.nix:4` gates on `config.nixpkgs.config.allowUnfree or false`. Re-evaluating with `allowUnfree = true` flipped it to true, added `facetimehd` to `boot.kernelModules`, and added `bdc_pci` to `blacklistedKernelModules`. |
| applespi et al. in stage-1 | Partial — the `availableKernelModules` half refuted | `14-1/default.nix:19-24` sets `boot.initrd.kernelModules` only. `rg availableKernelModules` across the entire import closure returns zero hits. The distinction is real: `kernelModules` force-loads in stage 1; `availableKernelModules` only makes present. |
| `intel_iommu=on` | Confirmed | `14-1/default.nix:25`, joined by three inherited i915 params. |
| `linuxPackages_latest` conditional | Confirmed as written, dead code | `:26` is `lib.mkIf (lib.versionOlder pkgs.linux.version "6.0") pkgs.linuxPackages_latest`. At current nixpkgs `pkgs.linux.version = 6.18.38`, so the `mkIf` never fires. Inoperative since the default kernel crossed 6.0. |
| disable-nvme-d3cold | Confirmed | Fully commented out at `:56-68` behind `# [Enable only if needed!]`. |

Three defects in the profile that a consumer inherits.

The `disable-nvme-d3cold.sh` script (still on disk, executable, reachable only from the commented `${./disable-nvme-d3cold.sh}` at `:65`) has a latent bug at line 12: `if [[ "$driver" -ne "nvme" ]]` uses the numeric `-ne` on strings, and inside `[[ ]]` both operands undergo arithmetic evaluation, so the bareword resolves to 0 and the guard can never trigger.
Anyone uncommenting the unit inherits a broken guard.

`14-1/default.nix:42-46` carries a `[MacBookPro Touchbar]` libinput quirk matching `0x05AC:0x8600` — that is the T1 iBridge, which this machine does not have.

The profile lacks the XHC1 wakeup-disable udev rule that two siblings carry (`11-5/default.nix:18-22` and `12-1/default.nix:31-33` both set `SUBSYSTEM=="pci", KERNEL=="0000:00:14.0", ATTR{power/wakeup}="disabled"`) despite its own README flagging suspend/resume at `:19`.

**The concrete adoption blocker, found empirically.**
`networking.enableB43Firmware = lib.mkDefault true` pulls the unfree `b43-firmware-5.100.138-zstd`.
With `allowUnfree = false` the verifier's eval hard-failed: "Refusing to evaluate package 'b43-firmware-5.100.138-zstd' ... because it has an unfree license".
vanixiets has no `allowUnfree` today, so importing this profile will break `nix flake check` until either `allowUnfree` is set or b43 is forced off.
The module closure built cleanly the moment b43 was forced off.
Since the survey and the verifier independently concluded the b43 line is vestigial for a BCM4350 machine, `networking.enableB43Firmware = lib.mkForce false` is the cheaper fix and does not drag unfree into the fleet — but note `hardware.facetimehd.enable` needs `allowUnfree` separately if the camera is wanted, so the two questions are linked.

Also note `hardware.enableRedistributableFirmware` is set at `mkDefault`, so any repo-wide `lib.mkForce false` would silently break WiFi.
No such force is known to exist in vanixiets, but this was not verified; check with `rg -n 'enableRedistributableFirmware' /Users/crs58/projects/vanixiets` before install.

## 6. Audio

The CS8409 premise was **confirmed**, so the out-of-tree module work item exists.
What follows is the packaging assessment, plus a correction to the assumption that motivated skipping it.

### The correction: nixos-hardware's own README is wrong about this

`apple/macbook-pro/14-1/README.md:3-4` states audio is "broken until https://github.com/NixOS/nixpkgs/pull/322968 lands in master".
That PR merged 2024-07-09 as nixpkgs `5952c36d59d5` and is a one-line change adding `SND_HDA_CODEC_CS8409 = whenAtLeast "6.6" module`, now at `pkgs/os-specific/linux/kernel/common-config.nix:629`.
It cannot fix Apple audio, because mainline CS8409 has no Apple support whatsoever.

This was verified directly against the pinned kernel, not against a 2022 snapshot (the survey flagged its own evidence here as low confidence because it had only egorenar's vendored table; the verifier closed that gap).
In `sound/hda/codecs/cirrus/cs8409-tables.c`, `rg -o 'SND_PCI_QUIRK\(0x[0-9a-f]+' | sort | uniq -c` returns exactly one vendor: 80 occurrences of `0x1028` (Dell), zero of `0x106b`.
`rg -in '0x106b|apple|macbook|imac'` across the whole `cirrus/` directory hits only `cs420x.c`.
The model list at `cs8409-tables.c:561-569` is entirely Dell platform codenames.
`cs8409_probe` (`cs8409.c:1425-1447`) binds on codec ID `0x10138409` alone, calls `snd_hda_pick_fixup` which matches nothing on an Apple machine, then falls through to `cs8409_parse_auto_config`.
Generic autoconfig cannot program the I2C-attached amplifiers, and no driver for them exists anywhere in the tree: `rg -ril 'ssm3515|tas5764|max98706' sound drivers` returns zero hits.

A hypothetical upstream fix via `SND_PCI_QUIRK` would also be structurally impossible: the 14,1's HDA PCI subsystem is Intel `[8086:7270]` (`lspci:357-358`), not Apple, so PCI-subsystem quirk matching cannot fire on this hardware.
That is precisely why davidjo dispatches on `codec->core.subsystem_id` instead (`patch_cirrus/cirrus_apple.h:2657-2673`).

The strings in the working 14,1's dmesg are davidjo's, not mainline's: `rg -ln 'cs_8409_interrupt_action|cs_8409_headset_type_detect_event'` hits only `davidjo/snd_hda_macbookpro/patch_cirrus/patch_cirrus_real84.h`, and the same grep over the pinned kernel's `sound/` returns nothing.
The one machine we have evidence of working audio on was running the out-of-tree module.

**Treat the nixos-hardware 14-1 profile as providing no audio support.**

### Scope: speakers only

`/tmp/mbp2016/README.md`, Audio section, verbatim: "With the MacBookPro14,1 the internal audio output is working, however the internal audio input is not working."
The 14,1's audio badge is "partially working" (yellow), unlike 13,1 / 13,3 / 14,3 which are green.
Do not plan for a working internal microphone.

### Which module

davidjo only.
egorenar is a dead vendored snapshot: a single commit dated 2022-05-21, no README, master only, and its highest version conditional anywhere is `KERNEL_VERSION(5, 13, 0)` (verified with `rg -o "KERNEL_VERSION\(...\)" | sort -u`).
It vendors kernel-internal headers (`hda_local.h`, `hda_generic.h`, `hda_jack.h`, `hda_auto_parser.h`) frozen at ~5.13 vintage; forcing it onto 6.18 risks silent struct mismatch rather than a clean compile error.
davidjo's tip is `cb27cc4`, 2026-05-04, actively maintained.
License is GPL v2 (`LICENSE:1-2`, `MODULE_LICENSE("GPL")` in both `patch_cirrus/cs8409.c:1486` and `patch_cirrus/patch_cs8409.c:1328`), so meta is clean.

### Whether 14,1 is covered — a residual uncertainty

This is the one soft spot in the audio story and it should not be smoothed over.
davidjo's active quirk table (`patch_cirrus/cirrus_apple.h:2279-2284`) lists exactly two live entries — `SND_PCI_QUIRK(0x106b, 0x3300, "MacBookPro 13,1", CS8409_MBP131)` and `SND_PCI_QUIRK(0x106b, 0x3900, "MacBookPro 14,3", CS8409_MBP143)` — with 14,2 and the iMacs commented out.
But `patch_cirrus_new84.h:1094-1103` maps `14,1 0x106b3300`, and the runtime dispatch comment at `cirrus_apple.h:2664-2665` reads `// macbook pro 14,1?13,1, 14,2` — the question mark is the author's.
The coherent reading is that 13,1 and 14,1 (both 13-inch non-Touch-Bar, 2016/2017) share SSID `0x106b3300`.
`new84.h:1089-1091` also references a dedicated `patch_cirrus_mb141_real84.h`, described as "only needed if wish to test the version using the mb141 logs".

Empirically this resolves in favour of coverage: the runtime gate at `cirrus_apple.h:2659-2673` returns `-ENODEV` for any unrecognized subsystem ID, and the real 14,1 dmesg shows the driver reaching autoconfig and handling jack events — so its SSID matched an accepted value.
The `0x3300`/`0x3600` path routes to `cs_8409_boot_setup_data_ssm3` (`new84.h:1133-1140`), the SSM3515 amplifier.
davidjo's README constrains support to three amplifier families: "Currently this works with MAX98706, SSM3515 and TAS5764L amplifiers. It will NOT work with other amplifiers as each amplifier requires specific programming."
No local evidence names the 14,1's amplifier directly.

### Packaging assessment

Feasible with moderate effort; the maintenance cost is patch fragility, not build mechanics.

The install script is unusable as-is and irrelevant: it exits 1 on NixOS before reaching any build step, because `install.cirrus.driver.sh:95-126` probes only `/usr/src/linux-headers-*`, `/usr/src/kernels/*`, `/usr/lib/modules/*`, and `/usr/src/kernel-headers-*`.
Its other impurities — `wget` from `cdn.kernel.org` at `:189`, `dnf install -y patch` at `:142`, DKMS symlinks into `/usr/src` (`dkms.sh:36-38`), `modules_install` plus `depmod -a` (`Makefile:20-22`) — are all avoidable because you would not run the script.

The build is more tractable than the survey's framing suggested.
davidjo needs the kernel *source subtree* `sound/hda`, not merely headers, because it patches the kernel's own `cs8409.c`/`cs8409.h` in place (`:274-291`, `patch -b -p1`).
But nixpkgs already provides `kernel.src` — the vanilla tarball — which replaces the `wget` exactly; davidjo's non-Ubuntu path explicitly "assume[s] the distribution kernel source is essentially the mainline kernel source" (`:184`).
And it builds only one module, not the whole snd-hda subsystem: `makefiles/Makefile_codecs` and `makefiles/Makefile_common` comment out every codec except `obj-y += cirrus/`, and `makefiles/Makefile_cirrus` builds only `snd-hda-codec-cs8409-y := cs8409.o cs8409-tables.o`.
The derivation reimplements the script's middle third as a `postPatch` (extract `sound/hda`, overlay `makefiles/*`, copy `patch_cirrus/*.h`, apply `patch_cs8409.c.diff` and `patch_cs8409.h.diff`) and then builds with the standard out-of-tree idiom.

**Where it cannot live.**
Not in `pkgs/by-name/`.
`modules/nixpkgs/per-system.nix:51-52` sets `pkgsDirectory = ../../pkgs/by-name` via `pkgs-by-name-for-flake-parts`, which callPackages each `package.nix` from top-level `pkgs` (`flake-module.nix:57-68`, `inputsScope = lib.makeScope pkgs.newScope (self: { inherit inputs; })`).
There is no top-level `kernel` attribute — `rg '^\s{2}kernel\s*=' pkgs/top-level/all-packages.nix` returns no match — because `kernel` exists only inside the `linuxPackagesFor` scope (`pkgs/top-level/linux-kernels.nix:263-274`).
Confirming this, `rg -ln "kernel|kernelPackages" pkgs/by-name/` over all 30 existing packages returns nothing.

The idiomatic placement is the pattern nixos-hardware itself uses at `mnt/reform/default.nix`:

```nix
boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ./lpc.nix { }) ];
```

where `./lpc.nix` takes `{ stdenv, lib, kernel, kernelModuleMakeFlags, ... }` supplied automatically from the linuxPackages scope.
nixpkgs' `pkgs/os-specific/linux/mbp-modules/mbp2018-bridge-drv/default.nix` shows the same signature plus the `broken = kernel.kernelOlder "5.4"` guard idiom, which maps well onto davidjo's narrow window.
So: a plain `.nix` file beside a NixOS module under `modules/nixos/hardware/`, instantiated with `config.boot.kernelPackages.callPackage`.
This keys it to the machine's actual kernel with no DKMS, at the cost of the free `package-<name>` check that `modules/checks/packages.nix:36-39` would otherwise derive.

**Kernel window is the real risk.**
davidjo's tested mainline target is exactly 6.17 (`install.cirrus.driver.sh:234-235`, `current_major=6`, `current_minor=17`); anything newer prints "Kernel version later than implemented version - there may be build problems" (`:267-269`).
nixpkgs' pinned default is 6.18.37/6.18.38.
The 6.17 structural break is real and kernel-side: the tree moved `sound/pci/hda` to `sound/hda` with a `codecs/cirrus/` subtree, and files were renamed (`patch_cs8409.c` → `cs8409.c`), which is why davidjo ships two parallel script and file sets and `exec`s the pre-617 script below 6.17 (`:40-43`).
The plan needs either a kernel pin at 6.17 for this machine or acceptance that the patches may fuzz-fail.
Since the patches are context diffs against a specific kernel's `cs8409.c`/`cs8409.h` (headers dated 2025-09-15/2025-11-02), drift is the standing maintenance cost.

**Module-name collision must be handled deliberately.**
Mainline builds `snd-hda-codec-cs8409` as a module (`common-config.nix:629`, from `sound/hda/codecs/cirrus/Makefile:6,10`), and davidjo installs a `.ko` of the same name under `/lib/modules/<ver>/updates/`.
That shadowing is a `depmod` search-order behaviour on a conventional distro; under Nix's `boot.extraModulePackages` it is not automatic.
Verify precedence or blacklist the in-tree module explicitly.
Note the real 14,1 dmesg shows the bound module as `snd_hda_codec_cirrus` (davidjo's patched name on the older tree), so confirm which name the 6.17+ path actually produces before writing a blacklist.

## 7. Blocking unknowns requiring on-device verification

Every item below is stated with the exact command to run from a live USB boot of the upstream `nix-community/nixos-images` installer.
Several of these are cheap enough to run in one sitting and would collapse most of the residual risk.

**Boot access.** Whether a pre-T2 EFI firmware password is set on this specific unit, blocking external boot.
Hold Option at power-on; if the USB appears in the boot picker and boots, this is settled.
This is the gating observation for the entire plan.

**WiFi from the installer.** Confirms the firmware chain end to end on this unit.
```
lspci -nn | grep -i network        # expect [14e4:43a3]
dmesg | grep -i brcmfmac           # expect "using brcm/brcmfmac4350c2-pcie" + "Firmware: BCM4350/5 wl0"
nmcli device wifi list             # the actual proof — networks returned
```

**Audio codec identity and subsystem ID.** The single load-bearing assumption for whether davidjo's dispatch accepts this machine.
```
cat /proc/asound/card0/codec#0 | head -5   # expect "Codec: Cirrus Logic CS8409", "Vendor Id: 0x10138409"
cat /proc/asound/card0/codec#0 | grep -i 'Subsystem Id'   # expect 0x106b3300 per davidjo's map
dmesg | grep -i -E 'cs8409|cirrus'         # which driver bound; expect no "Picked ID=" fixup
aplay -l && speaker-test -c2 -t wav        # if speakers are audible under stock mainline, the OOT workstream dies
```

**Disk identity for disko.** Needed before hardware detection can run (section 3's ordering constraint).
```
lsblk -o NAME,SIZE,MODEL
ls -l /dev/disk/by-id
lspci -nn | grep -i 'storage\|nvme'        # expect [106b:2003] class [0180], NOT [106b:2005]
```

**NIC name for the networkd match.** The skeleton's `matchConfig.Name = "en*"` is copied from cloud hosts and unverified here.
```
ip -4 addr
ip link
```

**Keyboard handler on this unit.** Confirms the LUKS-prompt conclusion on the actual hardware rather than on a corpus dump.
```
dmesg | grep -i applespi
cat /proc/bus/input/devices | grep -A5 'Apple SPI Keyboard'   # expect Handlers=... kbd ...
```

**T1 absence, confirmatory.** Weak evidence on its own (see section 1's methodological note) but free.
```
lsusb | grep 05ac:8600     # expect nothing
sudo dmidecode -s system-product-name   # expect MacBookPro14,1
```

**Bluetooth.** The one gap no local source closes: no dump shows `hci0` reaching up on a 14,1.
```
dmesg | grep -i -E 'hci_uart|btbcm|Bluetooth'
hciconfig -a
bluetoothctl show
```

**d3cold necessity.** Whether this unit's controller actually needs the workaround, and whether it helps.
```
cat /sys/bus/pci/devices/0000:01:00.0/d3cold_allowed   # expect 1
nvme get-feature /dev/nvme0 -f 0x0c                     # APST support
# then test suspend/resume with the value at 0 vs 1
```

**Installer as build host.** Only needed if the rosetta-builder route is skipped.
```
nix build --dry-run <trivial x86_64-linux derivation>
```

**Repo-side, not on-device but unverified.** Whether anything forces `enableRedistributableFirmware` off fleet-wide:
```
rg -n 'enableRedistributableFirmware' /Users/crs58/projects/vanixiets
```

## 8. Decision points for the human

These are the choices research cannot settle.
Each carries a recommendation and its rationale.

**Reachability model and hostname.** Is this a ZeroTier peer with `deploy.targetHost = "root@<name>.zt"` like magnetite, or LAN-only?
Recommendation: ZeroTier peer, following the fleet convention, with a two-phase bootstrap (IP-based install, then switch to `.zt`).
Rationale: every inventory entry already assumes `.zt` reachability, and the `peer` tag makes enrollment nearly free — the only extra step is `clan machines update cinnabar` to re-run autoaccept.

**Intermittent-connectivity handling.** A laptop is not a server.
Recommendation: set `clan.core.deployment.requireExplicitUpdate = true`, importing clan-infra's `build02` pattern.
Rationale: it is the one clan-infra pattern that addresses exactly this problem, and an often-offline machine silently failing implicit `clan machines update` is a recurring annoyance rather than a one-time cost.
Note that none of vanixiets' four darwin laptops set it, so confirm whether that omission is deliberate before diverging.

**Admin user.** `cameron` (all cloud machines) or `crs58` (only the legacy darwin laptops)?
Recommendation: `cameron`.
Rationale: the CLAUDE.md fleet table states `cameron` for new machines, and `inventory/services/users/cameron.nix` is the machine-list-driven service every NixOS host already uses.

**Filesystem and encryption.** ZFS-on-single-disk with native encryption (fleet convention), or ext4/LUKS?
Recommendation: ZFS with native encryption, keyed by a passphrase prompt rather than clan-infra's keyfile generator.
Rationale: `modules/system/zfs-force-import.nix:19-21` already forces `boot.zfs.forceImportRoot = true` fleet-wide via `base`, so a non-ZFS machine fights the shared layer; and section 1 confirms the internal keyboard works at the stage-1 prompt, which is what makes a passphrase viable on a laptop where initrd SSH unlock is not.
This is a genuine divergence from clan-infra's `neededFor = "partitioning"` keyfile pattern and should be made deliberately.

**Bootloader.** UEFI systemd-boot or GRUB?
Recommendation: systemd-boot, following galena's precedent (`galena/default.nix:45-48`).
Rationale: Apple hardware of this era boots UEFI; the GRUB-BIOS arrangement on cinnabar and magnetite is inherited from `hardware-hetzner-cloud` and does not transfer.

**b43 and allowUnfree.** The profile's unfree `b43Firmware` pull breaks `nix flake check`.
Recommendation: `networking.enableB43Firmware = lib.mkForce false` on this machine, and do not enable `allowUnfree` for this reason alone.
Rationale: two independent lines of evidence say b43 is vestigial for a BCM4350 machine driven by `brcmfmac`, and forcing it off keeps unfree out of the fleet.
The linked question is the FaceTime camera, which needs `allowUnfree` separately — decide whether the camera is worth it, and if so, enabling `allowUnfree` moots the b43 decision but drags the unfree blob in anyway.

**initrd networking in `base`.** Per-machine override, or gate the shared module?
Recommendation: gate `modules/system/initrd-networking.nix` behind an option and default it on for cloud hosts.
Rationale: this is the only place the fleet's cloud-VM assumption lives in the shared layer rather than a per-machine one, and a per-machine override leaves the next bare-metal host to rediscover it.
The counterargument — that touching `base` risks all five existing hosts — is real, and a per-machine `mkForce` is the lower-risk path if this change is meant to stay small.

**Audio scope.** Is working speaker output worth an out-of-tree kernel module with a 6.17-shaped kernel window?
Recommendation: defer.
Rationale: it is the single largest work item, it forces either a kernel pin or ongoing patch-fuzz maintenance, it delivers speakers but not the internal microphone, and none of it blocks the machine being a useful NixOS host.
Land the machine first; add audio as a separate change once the codec and subsystem ID are confirmed on-device.

**Suspend/resume scope.** Ship the d3cold workaround, or accept broken resume?
Recommendation: defer to a separate change, and confirm necessity on-device first.
Rationale: the nixos-hardware unit is commented out and its script's guard is broken, so shipping it means writing a corrected unit rather than copying one; and `README.md:222` says resume is slow even with the workaround.

**nixos-hardware as a flake input.** Add it, or rely on facter alone?
Recommendation: add it.
Rationale: the profile's `applespi` initrd list is exactly what makes the LUKS prompt work, and the verifier proved the closure builds correctly with vanixiets' pinned nixpkgs.
The alternative — hand-copying that list — duplicates upstream for no benefit.
Accept that the profile is bitrotted and carries three known defects (section 5), all of which are overridable.

## 9. Proposed work decomposition

Dependency-ordered.
Steps marked irreversible or risky are flagged inline.

**A. On-device reconnaissance.** Boot the installer, run the section 7 commands, record output.
No repo changes.
Depends on nothing.
This is the gate: if the Option-boot fails, everything downstream is blocked; if `speaker-test` works under stock mainline, unit F disappears.
Non-destructive — macOS untouched.

**B. Flake input and hardware module scaffolding.** Add `nixos-hardware` to `flake.nix` with `inputs.nixpkgs.follows`, and verify `nix flake check` still passes.
Depends on nothing.
Small and independently verifiable.

**C. Machine module, disko, and registration.** The section 2 file set items 1-6.
Depends on A (device path, NIC name) and B.
Includes the `mkForce false` on b43 and whatever initrd-networking handling the human chose.
Verification: `nix eval .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath` succeeds and `nix flake check` passes, meaning the machine evaluates before any hardware detection runs — this is the ordering constraint from section 3.

**D. Secrets and vars.** `clan vars generate`, then the `.sops.yaml` anchor plus bridge recipient plus re-encryption (file set item 7).
Depends on C (the machine must be registered for vars generation to target it).
Note the bridge re-encryption touches a shared secret; verify existing machines can still decrypt.

**E. Install.** `clan machines init-hardware-config <name> --target-host root@<installer-ip>`, then `clan machines install <name> --target-host root@<installer-ip>`, then commit `machines/<name>/facter.json` and `inventory.json`.
Then `clan machines update cinnabar` for ZeroTier admission, then the post-deploy address edits (`lib/hosts.nix`, `ssh-known-hosts.nix`, `home/core/ssh.nix`, `cinnabar/zt-dns.nix`).
Depends on A, C, D.

**Irreversible.** This wipes the disk.
Section 1 establishes that no firmware depends on the local macOS install, so the wipe is recoverable in the sense that nothing is permanently lost from the hardware — but macOS itself is gone until reinstalled from Internet Recovery.
Note also that `ssh-copy-id` authorizes the installer session only; a reboot of the installer requires repeating it.

**Risky, in the sense of touching a shared machine.** `clan machines update cinnabar` re-runs the ZeroTier controller's autoaccept unit on the fleet coordinator.

**F. Audio (deferred, conditional on A).** Package davidjo as a `config.boot.kernelPackages.callPackage` derivation beside a NixOS module under `modules/nixos/hardware/`, resolve the kernel window (pin 6.17 or accept fuzz risk), resolve the `snd-hda-codec-cs8409` name collision.
Depends on E and on A's codec/SSID confirmation.
This is the largest and least certain unit.

**G. Suspend/resume (deferred, conditional on A).** A corrected d3cold unit — the upstream script's `-ne` guard must be fixed to `!=` — plus optionally the XHC1 wakeup rule the profile omits.
Depends on E and on A's d3cold observation.

**H. Fleet hygiene (independent).** Fix `justfile:35` `check-uncached-machine` to include magnetite and the new machine, `just build-all` to cover all nine machines, and `just test-quick`'s reference to the non-existent `secrets-generation` check.
Depends on nothing; these are pre-existing defects surfaced by this work, not caused by it.
Can land before or after everything else.
