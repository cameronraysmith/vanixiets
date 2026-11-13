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
in
# Linux 6.18.60 -> 6.18.63 revalidation: the patch target drivers/bluetooth/hci_bcm.c
# is byte-identical. The only change compiled into this hci_uart.ko is two bounds
# checks in hci_bcsp.c, a protocol the BCM serdev path never uses; it alone moves
# the srcversion. Every other change under drivers/bluetooth and drivers/tty (btusb,
# bfusb, btnxpuart, btrsi, hci_nokia, hci_vhci, serial_core, 8250 and other serial
# drivers) is in-kernel only and not part of this module. The prepared .config and
# autoconf.h differ only in the release and rustc version strings.
assert lib.assertMsg (kernel.version == "6.18.63" && release == "6.18.63")
  "hci-uart-macbook: only Linux 6.18.63 has been checked; revalidate source, prepared configuration, ABI and effective module selection before updating";
kernel.stdenv.mkDerivation {
  pname = "hci-uart-macbook";
  version = "0-unstable-2026-09-14-${release}";
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

  unpackPhase = ''
    runHook preUnpack
    mkdir bluetooth unpatched
    tar -xJf "$src" --strip-components=3 -C bluetooth linux-${kernel.version}/drivers/bluetooth
    cp -r bluetooth/. unpatched/
    echo '7745ad8c06dd7145004524e35f31f7860d067cc3521ea30a5588085155c2e683  bluetooth/hci_bcm.c' | sha256sum -c -
    runHook postUnpack
  '';
  patchPhase = ''
    runHook prePatch
    patch --batch --fuzz=0 -d bluetooth -p1 < ${./hci-uart-macbook.patch}
    python3 - <<'PY'
    from pathlib import Path
    old = Path('unpatched/hci_bcm.c').read_text()
    new = Path('bluetooth/hci_bcm.c').read_text()
    call = '\terr = dev->set_device_wakeup(dev, powered);\n\tif (err)\n\t\tgoto err_revert_shutdown;\n\n'
    cleanup = 'err_revert_shutdown:\n\tdev->set_shutdown(dev, !powered);\n'
    assert old.count(call) == old.count(cleanup) == 1
    assert new == old.replace(call, "").replace(cleanup, "")
    for p in Path('unpatched').rglob('*'):
        if p.is_file() and p.name != 'hci_bcm.c':
            assert p.read_bytes() == (Path('bluetooth') / p.relative_to('unpatched')).read_bytes(), p
    assert new.count('bdev->set_device_wakeup(bdev, false)') == 1
    assert new.count('bdev->set_device_wakeup(bdev, true)') == 1
    print('exact six-line historical omission; other driver sources and suspend/resume unchanged')
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
    flagsArray=()
    concatTo flagsArray makeFlags makeFlagsArray
    make "''${flagsArray[@]}" KBUILD_OUTPUT="$PWD/prepared" -C "$PWD/prepared" \
      -j"$NIX_BUILD_CORES" M="$PWD/bluetooth" V=1 hci_uart.ko
    test "$(find bluetooth -name '*.ko' | wc -l)" -eq 1
    python3 - <<'PY'
    from pathlib import Path
    expected = {'hci_ldisc.o', 'hci_serdev.o', 'hci_h4.o', 'hci_bcsp.o', 'hci_ll.o', 'hci_bcm.o', 'hci_qca.o'}
    actual = {Path(s).name for s in Path('bluetooth/hci_uart.mod').read_text().split()}
    assert actual == expected, actual
    print('all seven native UART constituent objects retained')
    PY
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 bluetooth/hci_uart.ko "$out/lib/modules/${release}/updates/bluetooth/hci_uart.ko"
    runHook postInstall
  '';
  # nixpkgs' kmod aggregator requires a kmodigest certificate beside every
  # external module; signing must follow stripping, so it runs here.
  postFixup = ''
    export LC_ALL=C
    module="$out/lib/modules/${release}/updates/bluetooth/hci_uart.ko"
    ${lib.getExe buildPackages.kmodigest} "$module"
    test -s "$module.cer"
    test "$(find "$out" -type f | wc -l)" -eq 2
    test "$(modinfo -F name "$module")" = hci_uart
    test "$(modinfo -F srcversion "$module")" = 08EDC4DC96F685051041C6D
    case "$(modinfo -F vermagic "$module")" in
      '${release} '*) ;;
      *) echo 'Module/kernel release mismatch' >&2; exit 1 ;;
    esac
    missing=$(comm -23 \
      <(nm -u --format=posix "$module" | awk '{print $1}' | sort -u) \
      <(awk '{print $2}' ${kernelBuild}/Module.symvers | sort -u))
    test -z "$missing" || { echo "Unresolved kernel symbols: $missing" >&2; exit 1; }
    test -n "$(nm -u "$module")"
    if readelf -S "$module" | grep -q '\.debug_info'; then
      echo 'Diagnostic DWARF remains in module output' >&2
      exit 1
    fi
    if grep -aFq "$NIX_BUILD_TOP/" "$module"; then
      echo 'Build-directory reference remains in module output' >&2
      exit 1
    fi
  '';

  passthru = { inherit kernel; };
  meta = {
    description = "Experimental BCM UART power-transition wake omission for Pyrite's checked kernel";
    homepage = "https://github.com/leifliddy/macbook12-bluetooth-driver";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
