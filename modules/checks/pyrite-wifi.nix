{
  config,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = {
        # nixbot: 0 runs, too few to class (design D4)
        pyrite-wifi = {
          class = "medium";
          measured = false;
        };
      };
      checks.pyrite-wifi =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          kernel = cfg.boot.kernelPackages.kernel;
          tree = cfg.system.modulesTree;
          release = kernel.modDirVersion;
          normalize = name: builtins.replaceStrings [ "-" ] [ "_" ] name;
          # brcmfmac, the per-vendor sub-modules it request_module()s by firmware vendor,
          # and the brcmutil it links against.
          modules = [
            "brcmfmac"
            "brcmfmac-wcc"
            "brcmfmac-cyw"
            "brcmfmac-bca"
            "brcmutil"
          ];
          names = map normalize modules;
          stage1 = cfg.boot.initrd.kernelModules ++ cfg.boot.initrd.availableKernelModules;
          msgbuf = "drivers/net/wireless/broadcom/brcm80211/brcmfmac/msgbuf.c";
        in
        assert lib.assertMsg (
          !(lib.any (name: lib.elem (normalize name) names) cfg.boot.blacklistedKernelModules)
        ) "pyrite Wi-Fi: a blacklist blocks brcmfmac, a vendor sub-module or brcmutil";
        assert lib.assertMsg (!(lib.any (name: lib.elem (normalize name) names) stage1))
          "pyrite Wi-Fi: brcmfmac must stay out of stage 1, where its per-vendor sub-module cannot load and the failed attach unbinds the BCM4350, so the machine boots with no network device; boot.initrd.network.enable brings it in through nixpkgs' hardware/facter/networking/initrd.nix";
        pkgs.runCommand "pyrite-wifi" { nativeBuildInputs = [ pkgs.kmod ]; } ''
          set -euo pipefail
          export LC_ALL=C
          # Since 6.18.61's backport cc03f779a328 mapped msgbuf RX packet IDs DMA_FROM_DEVICE,
          # the BCM4350 firmware's reads of posted RX buffers fault under intel_iommu=on and
          # it stops answering dcmd queries. Upstream 7ed5dce55fa8 maps them bidirectionally
          # again; the selected kernel's source must carry it.
          tar -xJf ${kernel.src} --strip-components=1 linux-${kernel.version}/${msgbuf}
          test "$(tr -d ' \t\n' < ${msgbuf} | grep -oF \
            'msgbuf->rx_pktids=brcmf_msgbuf_init_pktids(NR_RX_PKTIDS,DMA_BIDIRECTIONAL);' | wc -l)" = 1
          echo 'msgbuf RX packet IDs are mapped DMA_BIDIRECTIONAL'
          dep=${tree}/lib/modules/${release}/modules.dep
          ${lib.concatMapStrings (m: ''
            name=${normalize m}
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$name")
            native=$(modinfo -b ${kernel.modules} -k ${release} -F filename "$name")
            echo "$name: $selected"
            test "$(readlink -f "$selected")" = "$(readlink -f "$native")"
            test "$(grep -c '^[^:]*/${m}\.ko[^:]*:' "$dep")" = 1
            grep '^kernel/[^:]*/${m}\.ko[^:]*:' "$dep"
          '') modules}
          # BCM4350 PCIe (14e4:43a3) as the PCI core announces it.
          selected=$(modinfo -b ${tree} -k ${release} -F filename \
            'pci:v000014E4d000043A3sv0000106Bsd00000000bc02sc80i00')
          echo "BCM4350: $selected"
          test "$(readlink -f "$selected")" = \
            "$(readlink -f "$(modinfo -b ${kernel.modules} -k ${release} -F filename brcmfmac)")"
          if find -L ${cfg.system.build.modulesClosure} -name 'brcm*.ko*' | grep .; then
            echo 'brcmfmac or brcmutil reached the initrd module closure' >&2
            exit 1
          fi
          mkdir -p "$out"
          modinfo -b ${tree} -k ${release} brcmfmac > "$out/modinfo"
        '';
    };
}
