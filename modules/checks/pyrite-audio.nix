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
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 3.8 s, slowest 118 s, all 7 runs 2026-09-17..2026-10-07
        pyrite-audio.class = "small";
      };
      checks.pyrite-audio =
        let
          machine = config.flake.nixosConfigurations.pyrite;
          cfg = machine.config;
          pkgs = machine.pkgs;
          kernel = cfg.boot.kernelPackages.kernel;
          replacement =
            cfg.boot.kernelPackages.callPackage ../../pkgs/kernel-modules/snd-hda-macbookpro.nix
              { };
          tree = cfg.system.modulesTree;
          release = kernel.modDirVersion;
          modulePath = "lib/modules/${release}/updates/codecs/cirrus/snd-hda-codec-cs8409.ko";
        in
        assert lib.assertMsg (lib.elem replacement cfg.boot.extraModulePackages)
          "pyrite audio: Apple replacement missing from extraModulePackages";
        assert lib.assertMsg (
          !(lib.any (name: lib.elem name cfg.boot.blacklistedKernelModules) [
            "snd_hda_codec_cs8409"
            "snd-hda-codec-cs8409"
          ])
        ) "pyrite audio: blacklisting the shared CS8409 name blocks the replacement";
        pkgs.runCommand "pyrite-audio" { nativeBuildInputs = [ pkgs.kmod ]; } ''
          set -euo pipefail
          export LC_ALL=C
          expected=${replacement}/${modulePath}
          for query in snd_hda_codec_cs8409 'hdaudio:v10138409r00100100a01'; do
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$query")
            echo "$query: $selected"
            test "$(readlink -f "$selected")" = "$expected"
          done
          dep=${tree}/lib/modules/${release}/modules.dep
          test "$(grep -c 'cs8409' "$dep")" = 1
          grep '^updates/codecs/cirrus/snd-hda-codec-cs8409.ko:' "$dep"
          native=$(modinfo -b ${kernel.modules} -k ${release} -F filename snd_hda_codec_cs8409)
          test "$(modinfo -F vermagic "$expected")" = "$(modinfo -F vermagic "$native")"
          test "$(modinfo -F depends "$expected" | tr ',' '\n' | sort)" = \
            "$(modinfo -F depends "$native" | tr ',' '\n' | sort)"
          for name in snd snd_hda_core snd_hda_codec snd_hda_codec_generic \
            snd_hda_codec_cs420x snd_hda_codec_cs421x snd_hda_codec_hdmi snd_hda_codec_intelhdmi; do
            selected=$(modinfo -b ${tree} -k ${release} -F filename "$name")
            native=$(modinfo -b ${kernel.modules} -k ${release} -F filename "$name")
            test "$(readlink -f "$selected")" = "$(readlink -f "$native")"
          done
          mkdir -p "$out"
          cp ${replacement}/share/snd-hda-macbookpro/source-sha256 "$out/source-sha256"
          modinfo "$expected" > "$out/modinfo"
        '';
    };
}
