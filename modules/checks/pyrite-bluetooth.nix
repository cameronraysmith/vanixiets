{
  config,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    lib.mkIf (system == "x86_64-linux") {
      checks.pyrite-bluetooth =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          kernel = cfg.boot.kernelPackages.kernel;
          replacement = lib.findFirst (
            p: (p.pname or "") == "hci-uart-macbook"
          ) null cfg.boot.extraModulePackages;
          tree = cfg.system.modulesTree;
          release = kernel.modDirVersion;
          protected = [
            "hci_uart"
            "bluetooth"
            "btbcm"
            "btqca"
            "pwrseq_core"
            "8250"
            "8250_dw"
            "intel_lpss"
            "intel_lpss_pci"
            "brcmfmac"
            "brcmutil"
          ];
        in
        assert lib.assertMsg (
          replacement != null
        ) "pyrite Bluetooth: persistent wake candidate missing from extraModulePackages";
        assert lib.assertMsg (
          replacement.kernel.drvPath == kernel.drvPath
        ) "pyrite Bluetooth: candidate must use the selected kernel";
        assert lib.assertMsg (
          !(lib.any (
            name: lib.elem (builtins.replaceStrings [ "-" ] [ "_" ] name) protected
          ) cfg.boot.blacklistedKernelModules)
        ) "pyrite Bluetooth: a blacklist blocks the candidate or a native dependency";
        assert lib.assertMsg (
          !(lib.any (
            name:
            lib.elem name [
              "hci_uart"
              "hci-uart"
            ]
          ) cfg.boot.initrd.kernelModules)
        ) "pyrite Bluetooth: the experiment must not introduce an initrd preload";
        pkgs.runCommand "pyrite-bluetooth" { nativeBuildInputs = [ pkgs.kmod ]; } ''
          set -euo pipefail
          export LC_ALL=C
          expected=${replacement}/lib/modules/${release}/updates/bluetooth/hci_uart.ko
          for query in hci_uart 'acpi:BCM2E7C:APPLE-UART-BLTH:'; do
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$query")
            echo "$query: $selected"
            test "$(readlink -f "$selected")" = "$expected"
          done
          dep=${tree}/lib/modules/${release}/modules.dep
          test "$(grep -c '^[^:]*\/hci_uart\.ko[^:]*:' "$dep")" = 1
          grep '^updates/bluetooth/hci_uart.ko:' "$dep"
          native=$(modinfo -b ${kernel.modules} -k ${release} -F filename hci_uart)
          for field in name license vermagic depends parm alias; do
            modinfo -F "$field" "$native" | sort > native-field
            modinfo -F "$field" "$expected" | sort > candidate-field
            diff -u native-field candidate-field
          done
          for name in bluetooth btbcm btqca pwrseq_core 8250 8250_dw intel_lpss intel_lpss_pci brcmfmac brcmutil; do
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$name")
            native=$(modinfo -b ${kernel.modules} -k ${release} -F filename "$name")
            if test "$native" = '(builtin)'; then
              test "$selected" = "$native"
            else
              test "$(readlink -f "$selected")" = "$(readlink -f "$native")"
            fi
            echo "preserved $name: $selected"
          done
          for name in zfs snd_hda_codec_cs8409; do
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$name")
            case "$(readlink -f "$selected")" in
              ${
                lib.concatMapStringsSep "|" (p: "${p}/*") (
                  lib.filter (p: p != replacement) cfg.boot.extraModulePackages
                )
              }) ;;
              *) echo "Lost existing extra module: $name" >&2; exit 1 ;;
            esac
            echo "preserved $name: $selected"
          done
          mkdir -p "$out"
          modinfo "$expected" > "$out/modinfo"
          cp "$dep" "$out/modules.dep"
        '';
    };
}
