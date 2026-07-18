{
  config,
  inputs,
  ...
}:
let
  # Capture outer config for use in imports
  flakeModules = config.flake.modules.nixos;
  flakeUsers = config.flake.users;
in
{
  # Export host module to flake namespace
  flake.modules.nixos."machines/nixos/pyrite" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        inputs.home-manager.nixosModules.home-manager
        inputs.nixos-hardware.nixosModules.apple-macbook-pro-14-1
      ]
      ++ (with flakeModules; [
        base
        hm-sops-bridge
        ssh-known-hosts
      ]);

      # Make flake available to all modules (required by ssh-known-hosts)
      _module.args.flake = inputs.self;

      # System platform (Kaby Lake, Intel Iris Plus 640)
      nixpkgs.hostPlatform = "x86_64-linux";

      # Bootloader: UEFI with systemd-boot. canTouchEfiVariables writes the machine's
      # 8 MiB SPI boot ROM (not the disk the install wipes); an EFI write failing is
      # recoverable by an NVRAM reset, not a brick.
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;

      # by-id, not the fleet's by-path: the "more stable for cloud VMs" reasoning does
      # not transfer to a laptop with a stable by-id path, and by-id is the bare-metal
      # norm. ZFS scanning the 8 KiB nvme0n2 namespace on import is harmless; the hazard
      # is a write, and only the disko device writes. See D3.
      boot.zfs.devNodes = "/dev/disk/by-id";

      networking.hostName = "pyrite";

      system.stateVersion = "25.05";

      # Kept from base as a deliberate decision, not an inheritance (D6): an install
      # re-run touches the pool from the installer environment, and importing without
      # force after that lands the next boot in an emergency shell, which would defeat
      # this change's re-runnable-install acceptance criterion. Value equals base's, so
      # this restatement conflicts with nothing.
      boot.zfs.forceImportRoot = true;

      # networking.hostId: deliberately unset (D7). Inherit clan-core's
      # mkDefault "8425e349" (nixosModules/clanCore/zfs.nix:10), which matches the
      # install ISO and nixos-anywhere so the installer that creates the pool and the
      # system that imports it present the same hostid. Pinning a machine-specific
      # hostid would manufacture the mismatch that default exists to prevent.

      # boot.plymouth: deliberately left at its default false (D11). plymouth swaps the
      # passphrase prompt onto a different ask-password agent
      # (systemd-ask-password-console does not start while /run/plymouth/pid exists) and
      # a graphical stack whose interaction with i915 on this model is unverified. The
      # prompt is this machine's safety-critical path.

      # brcmfmac will not associate in initrd, so remote unlock over initrd SSH cannot
      # function; disabling it removes an advertised path that cannot work. mkForce
      # because base sets ssh.enable = true plainly. This is a distinct option from
      # boot.initrd.kernelModules, which MUST NOT be mkForce'd (see the design's
      # invariant): base's inert virtio pair is left alone.
      boot.initrd.network.ssh.enable = lib.mkForce false;

      # b43 is a silicon misdetection, not an evaluation workaround: enableB43Firmware
      # pulls b43Firmware_5_1_138 for the SoftMAC BCM43xx parts, but this machine's NIC
      # is a BCM4350 driven by brcmfmac, which that firmware does not serve. allowUnfree
      # is true fleet-wide so it evaluates; it is declined for the wrong silicon. Plain
      # false overrides the profile's lib.mkDefault true. See D5.
      networking.enableB43Firmware = false;
      # The FaceTime HD camera is out of scope. The fleet's allowUnfree would resolve the
      # profile's mkDefault to true, auto-enabling an out-of-tree kernel module and unfree
      # firmware on import; plain false keeps both out of the closure.
      hardware.facetimehd.enable = false;

      # Stated explicitly, not inherited from facter's bare-metal mkDefault branch (dead
      # on every existing cloud VM). The axis is redistributability, not freeness:
      # enableRedistributableFirmware puts linux-firmware into hardware.firmware
      # (all-firmware.nix:71-86,75), and linux-firmware carries the
      # brcm/brcmfmac4350*-pcie.bin blobs this machine's only NIC needs in order to probe.
      # false darkens the WiFi (its own default is enableAllFirmware, i.e. false).
      # linux-firmware is a redistributable proprietary blob that caches serve, so this is
      # not the decline 2.2 applies to non-redistributable firmware. See D15.
      hardware.enableRedistributableFirmware = true;
      hardware.cpu.intel.updateMicrocode = true;

      # The model profile already sets services.mbpfan.enable and services.tlp.enable via
      # mkDefault true, and both daemons are wanted (D16); restating a plain true would
      # only echo the default. The one line the module needs is the quieter fan curve:
      # mbpfan's own aggressive default is true (thresholds 55/58/78); false takes them to
      # 63/66/86 and is the only user-visible consequence of the daemon. mbpfan is not a
      # 2.2-style decline: its license is gpl3 (free, redistributable, in-tree,
      # cache-served), and beyond the applesmc the profile already force-loads it adds
      # only coretemp.
      services.mbpfan.aggressive = false;

      # Bridge NixOS-level sops to home-manager for user secret key delivery.
      # sopsIdentity defaults to flake.users.cameron.meta.sopsAgeKeyId
      # ("crs58" via alias-fold inheritance).
      hm-sops-bridge.users.cameron = { };

      # cameron is the preferred username on new machines and folds to crs58 by alias;
      # alias-keyed reads keep this call site ignorant of the alias->target relationship.
      # Infrastructure settings (useGlobalPkgs, extraSpecialArgs, etc.) are provided by
      # the cameron inventory service.
      home-manager.users.cameron = {
        imports = flakeUsers.cameron.modules;
      };
    };
}
