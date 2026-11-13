{
  lib,
  buildPackages,
  kernel,
  kernelModuleMakeFlags,
  python3,
  kmod,
}:
let
  release = kernel.modDirVersion;
  kernelBuild = "${kernel.dev}/lib/modules/${release}/build";
  # Every module kbuild produces for this directory under CONFIG_BRCMFMAC=m: the core
  # driver and the three per-vendor sub-modules it request_module()s by firmware vendor.
  # Overriding all four keeps the core and the sub-modules that import its exports from
  # one build. brcmutil is not rebuilt: its sources are untouched by the patch and its
  # exports (and their modversion CRCs, taken from the kernel's own Module.symvers) are
  # what both the in-tree and this brcmfmac link against.
  modules = [
    "brcmfmac"
    "wcc/brcmfmac-wcc"
    "cyw/brcmfmac-cyw"
    "bca/brcmfmac-bca"
  ];
  updates = "$out/lib/modules/${release}/updates/brcmfmac";
in
# Linux 6.18.63 is the newest 6.18 release and does not carry 7ed5dce55fa8; the patch
# applies with --fuzz=0 to its msgbuf.c. When the kernel moves, check whether it includes
# 7ed5dce55fa8 ("wifi: brcmfmac: map msgbuf RX packet IDs bidirectional").
assert lib.assertMsg (kernel.version == "6.18.63" && release == "6.18.63")
  "brcmfmac-vtd-rx: only Linux 6.18.63 has been checked; once the kernel includes upstream 7ed5dce55fa8 drop this package from pyrite's boot.extraModulePackages instead of revalidating it";
kernel.stdenv.mkDerivation {
  pname = "brcmfmac-vtd-rx";
  version = "0-unstable-2026-10-21-${release}";
  src = kernel.src;

  # This C-only target needs neither the fabricated uname nor Rust compilation tools.
  nativeBuildInputs =
    builtins.filter (
      p:
      !(lib.elem (lib.getName p) [
        "uname"
        "rustc"
        "rust-bindgen-unwrapped"
      ])
    ) kernel.moduleBuildDependencies
    ++ [
      python3
      kmod
    ];
  inherit (kernel) hardeningDisable;
  dontConfigure = true;
  # Relocatable kernel ELF is not a patchelf/RPATH-audit input.
  dontPatchELF = true;
  noAuditTmpdir = true;
  stripDebugList = [ "lib/modules" ];
  stripDebugFlags = [ "--strip-debug" ];
  disallowedReferences = [
    kernel.dev
    kernel.src
  ];
  enableParallelBuilding = true;

  # brcmfmac's Makefiles include ../include (brcm80211/include), so the whole brcm80211
  # directory is unpacked and only brcmfmac/ is built.
  unpackPhase = ''
    runHook preUnpack
    mkdir brcm80211 unpatched
    tar -xJf "$src" --strip-components=6 -C brcm80211 \
      linux-${kernel.version}/drivers/net/wireless/broadcom/brcm80211
    cp -r brcm80211/. unpatched/
    echo 'd357eb0b6bbf1dba294e9680b679512dc56577e145c9558a21b705c6057baac7  brcm80211/brcmfmac/msgbuf.c' | sha256sum -c -
    runHook postUnpack
  '';
  patchPhase = ''
    runHook prePatch
    patch --batch --fuzz=0 -d brcm80211 -p6 < ${./brcmfmac-vtd-rx.patch}
    python3 - <<'PY'
    from pathlib import Path
    old = Path('unpatched/brcmfmac/msgbuf.c').read_text()
    new = Path('brcm80211/brcmfmac/msgbuf.c').read_text()
    rx = 'brcmf_msgbuf_init_pktids(NR_RX_PKTIDS,\n\t\t\t\t\t\t     DMA_{}DEVICE);'
    before = rx.format('FROM_')
    after = before.replace('DMA_FROM_DEVICE', 'DMA_BIDIRECTIONAL')
    assert old.count(before) == 1 and old.count(after) == 0
    assert new == old.replace(before, after)
    assert new.count('brcmf_msgbuf_init_pktids(NR_TX_PKTIDS,\n\t\t\t\t\t\t     DMA_TO_DEVICE);') == 1
    for p in Path('unpatched').rglob('*'):
        if p.is_file() and p.as_posix() != 'unpatched/brcmfmac/msgbuf.c':
            assert p.read_bytes() == (Path('brcm80211') / p.relative_to('unpatched')).read_bytes(), p
    print('RX packet IDs mapped DMA_BIDIRECTIONAL; TX and every other source unchanged')
    PY
    runHook postPatch
  '';
  makeFlags = kernelModuleMakeFlags;
  buildPhase = ''
    runHook preBuild
    cp -a ${kernelBuild} prepared
    chmod -R u+w prepared
    test "$(cat prepared/include/config/kernel.release)" = '${release}'
    sha256sum -c <<'HASHES'
    e436cfb17359ea48eae27d98e998b2e84c78dafa8351652da7cb34f8f8863d5d  prepared/.config
    e8369fae7c20eeb179ea6c453cf105ba4396770de60b87aa64e38587255c1409  prepared/Module.symvers
    ddf428e4209c2ce363817e3aed9cdb6778b5d7b556431a9c2a2dd74b598514d3  prepared/include/generated/autoconf.h
    HASHES
    # The in-tree module's bus and protocol support, which the override must match.
    for option in BRCMUTIL=m BRCMFMAC=m BRCMFMAC_PROTO_BCDC=y BRCMFMAC_PROTO_MSGBUF=y \
      BRCMFMAC_SDIO=y BRCMFMAC_USB=y BRCMFMAC_PCIE=y; do
      grep -qx "CONFIG_$option" prepared/.config
    done
    flagsArray=()
    concatTo flagsArray makeFlags makeFlagsArray
    make "''${flagsArray[@]}" KBUILD_OUTPUT="$PWD/prepared" -C "$PWD/prepared" \
      -j"$NIX_BUILD_CORES" M="$PWD/brcm80211/brcmfmac" V=1 modules
    test "$(find brcm80211 -name '*.ko' | wc -l)" -eq ${toString (lib.length modules)}
    python3 - <<'PY'
    from pathlib import Path
    expected = {
        'cfg80211.o', 'chip.o', 'fwil.o', 'fweh.o', 'p2p.o', 'proto.o', 'common.o',
        'core.o', 'firmware.o', 'fwvid.o', 'feature.o', 'btcoex.o', 'vendor.o',
        'pno.o', 'xtlv.o', 'bcdc.o', 'fwsignal.o', 'commonring.o', 'flowring.o',
        'msgbuf.o', 'sdio.o', 'bcmsdh.o', 'usb.o', 'pcie.o', 'of.o', 'dmi.o', 'acpi.o',
    }
    actual = {Path(s).name for s in Path('brcm80211/brcmfmac/brcmfmac.mod').read_text().split()}
    assert actual == expected, sorted(actual ^ expected)
    print('brcmfmac carries the configured BCDC, msgbuf, SDIO, USB and PCIe objects')
    PY
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    ${lib.concatMapStrings (m: ''
      install -Dm644 brcm80211/brcmfmac/${m}.ko "${updates}/${m}.ko"
    '') modules}
    runHook postInstall
  '';
  # nixpkgs' kmod aggregator requires a kmodigest certificate beside every
  # external module; signing must follow stripping, so it runs here.
  postFixup = ''
    export LC_ALL=C
    for module in ${lib.concatMapStringsSep " " (m: "${updates}/${m}.ko") modules}; do
      ${lib.getExe buildPackages.kmodigest} "$module"
      test -s "$module.cer"
      test "$(modinfo -F name "$module")" = "$(basename "$module" .ko | tr - _)"
      case "$(modinfo -F vermagic "$module")" in
        '${release} '*) ;;
        *) echo 'Module/kernel release mismatch' >&2; exit 1 ;;
      esac
      missing=$(comm -23 \
        <(nm -u --format=posix "$module" | awk '{print $1}' | sort -u) \
        <(awk '{print $2}' ${kernelBuild}/Module.symvers | sort -u))
      test -z "$missing" || { echo "Unresolved kernel symbols in $module: $missing" >&2; exit 1; }
      test -n "$(nm -u "$module")"
      if readelf -S "$module" | grep -q '\.debug_info'; then
        echo "Diagnostic DWARF remains in $module" >&2
        exit 1
      fi
      if grep -aFq "$NIX_BUILD_TOP/" "$module"; then
        echo "Build-directory reference remains in $module" >&2
        exit 1
      fi
    done
    test "$(find "$out" -type f | wc -l)" -eq ${toString (2 * lib.length modules)}
  '';

  passthru = { inherit kernel modules; };
  meta = {
    description = "brcmfmac with msgbuf RX packet IDs mapped bidirectionally (upstream 7ed5dce55fa8) for Pyrite's checked kernel";
    homepage = "https://git.kernel.org/torvalds/c/7ed5dce55fa8393972b1bf2bf5af1c818c5e7dc2";
    license = lib.licenses.isc;
    platforms = [ "x86_64-linux" ];
  };
}
