{
  config,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.pyrite-wifi =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          kernel = cfg.boot.kernelPackages.kernel;
          replacement = cfg.boot.kernelPackages.callPackage ../../pkgs/kernel-modules/brcmfmac-vtd-rx.nix { };
          tree = cfg.system.modulesTree;
          release = kernel.modDirVersion;
          normalize = name: builtins.replaceStrings [ "-" ] [ "_" ] name;
          names = map (m: normalize (baseNameOf m)) replacement.modules;
          stage1 = cfg.boot.initrd.kernelModules ++ cfg.boot.initrd.availableKernelModules;
        in
        assert lib.assertMsg (lib.elem replacement cfg.boot.extraModulePackages)
          "pyrite Wi-Fi: brcmfmac VT-d RX replacement missing from extraModulePackages";
        assert lib.assertMsg (
          !(lib.any (
            name: lib.elem (normalize name) (names ++ [ "brcmutil" ])
          ) cfg.boot.blacklistedKernelModules)
        ) "pyrite Wi-Fi: a blacklist blocks the replacement or brcmutil";
        assert lib.assertMsg (
          !(lib.any (name: lib.elem (normalize name) (names ++ [ "brcmutil" ])) stage1)
        ) "pyrite Wi-Fi: brcmfmac must stay out of stage 1 (see boot.initrd.network.enable in pyrite)";
        pkgs.runCommand "pyrite-wifi" { nativeBuildInputs = [ pkgs.kmod ]; } ''
          set -euo pipefail
          export LC_ALL=C
          dep=${tree}/lib/modules/${release}/modules.dep
          ${lib.concatMapStrings (m: ''
            expected=${replacement}/lib/modules/${release}/updates/brcmfmac/${m}.ko
            name=${normalize (baseNameOf m)}
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$name")
            echo "$name: $selected"
            test "$(readlink -f "$selected")" = "$expected"
            test "$(grep -c '^[^:]*/${baseNameOf m}\.ko[^:]*:' "$dep")" = 1
            grep '^updates/brcmfmac/${m}.ko:' "$dep"
            native=$(modinfo -b ${kernel.modules} -k ${release} -F filename "$name")
            for field in name license vermagic depends parm alias firmware; do
              modinfo -F "$field" "$native" | sort > native-field
              modinfo -F "$field" "$expected" | sort > candidate-field
              diff -u native-field candidate-field
            done
          '') replacement.modules}
          # BCM4350 PCIe (14e4:43a3) as the PCI core announces it.
          selected=$(modinfo -b ${tree} -k ${release} -F filename \
            'pci:v000014E4d000043A3sv0000106Bsd00000000bc02sc80i00')
          echo "BCM4350: $selected"
          test "$(readlink -f "$selected")" = ${replacement}/lib/modules/${release}/updates/brcmfmac/brcmfmac.ko
          for name in brcmutil cfg80211 mmc_core; do
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$name")
            native=$(modinfo -b ${kernel.modules} -k ${release} -F filename "$name")
            test "$(readlink -f "$selected")" = "$(readlink -f "$native")"
            echo "preserved $name: $selected"
          done
          if find -L ${cfg.system.build.modulesClosure} -name 'brcm*.ko*' | grep .; then
            echo 'brcmfmac or brcmutil reached the initrd module closure' >&2
            exit 1
          fi
          mkdir -p "$out"
          for m in ${lib.concatStringsSep " " replacement.modules}; do
            modinfo ${replacement}/lib/modules/${release}/updates/brcmfmac/$m.ko
          done > "$out/modinfo"
        '';
    };
}
