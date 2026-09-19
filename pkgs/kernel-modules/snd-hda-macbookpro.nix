{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
  kmod,
}:
let
  moduleName = "snd-hda-codec-cs8409";
  kernelBuild = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
  appleFlags = "-DAPPLE_PINSENSE_FIXUP -DAPPLE_CODECS -DCONFIG_SND_HDA_RECONFIG=1 -Wno-unused-variable -Wno-unused-function";
in
assert lib.assertMsg (kernel.version == "6.18.52")
  "snd-hda-macbookpro: only Linux 6.18.52 has been checked; revalidate the source/header layout and module selection before changing this boundary";
stdenv.mkDerivation {
  pname = "snd-hda-macbookpro";
  version = "0-unstable-2026-09-06-${kernel.modDirVersion}";

  src = fetchFromGitHub {
    owner = "davidjo";
    repo = "snd_hda_macbookpro";
    rev = "89b22ff90b86468b186706861dd18663562defa7";
    hash = "sha256-5iDybAlRG5HldUA24L9+rSlgEiUPZg50K8IYC+Lie4U=";
  };

  nativeBuildInputs = [ kmod ] ++ kernel.moduleBuildDependencies;
  hardeningDisable = [ "pic" ];
  dontConfigure = true;
  # Kernel modules are relocatable ELF, not executables for patchelf.
  dontPatchELF = true;
  # The RPATH audit also invokes patchelf; postFixup checks the stripped module directly.
  noAuditTmpdir = true;
  stripDebugList = [ "lib/modules" ];
  stripDebugFlags = [ "--strip-debug" ];
  disallowedReferences = [ kernel.dev ];

  postPatch = ''
    grep -Fx 'KBUILD_EXTRA_CFLAGS = "${appleFlags}"' Makefile
    mkdir -p build
    tar -xJf ${kernel.src} --strip-components=2 -C build linux-${kernel.version}/sound/hda
    for path in Makefile common/Makefile codecs/Makefile codecs/cirrus/Makefile \
      codecs/cirrus/cs8409.c codecs/cirrus/cs8409.h codecs/generic.h common/hda_auto_parser.h; do
      test -f "build/hda/$path" || { echo "Unsupported kernel HDA layout: $path" >&2; exit 1; }
    done
    # A same-version build can still panic with a different internal struct layout (#193).
    # https://github.com/davidjo/snd_hda_macbookpro/issues/193
    cmp build/hda/codecs/generic.h ${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/sound/hda/codecs/generic.h
    cmp build/hda/common/hda_auto_parser.h ${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/sound/hda/common/hda_auto_parser.h
    cp makefiles/Makefile build/hda/Makefile
    cp makefiles/Makefile_common build/hda/common/Makefile
    cp makefiles/Makefile_codecs build/hda/codecs/Makefile
    cp makefiles/Makefile_cirrus build/hda/codecs/cirrus/Makefile
    for header in cirrus_apple.h patch_cirrus_boot84.h patch_cirrus_new84.h \
      patch_cirrus_real84.h patch_cirrus_hda_generic_copy.h patch_cirrus_real84_i2c.h; do
      cp "patch_cirrus/$header" build/hda/codecs/cirrus/
    done
    patch --batch --fuzz=0 -d build/hda -p1 < patch_cs8409.c.diff
    patch --batch --fuzz=0 -d build/hda -p1 < patch_cs8409.h.diff
    (cd build/hda && sha256sum codecs/generic.h common/hda_auto_parser.h \
      codecs/cirrus/*.h codecs/cirrus/cs8409.c codecs/cirrus/cs8409-tables.c) > source-sha256
  '';

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    kernelBuild
  ];
  buildPhase = ''
    runHook preBuild
    test "$(cat ${kernelBuild}/include/config/kernel.release)" = "${kernel.modDirVersion}"
    grep -qx 'CONFIG_SND_HDA_CODEC_CS8409=m' ${kernelBuild}/.config
    grep -qx 'CONFIG_SND_HDA_RECONFIG=y' ${kernelBuild}/.config
    grep -qx 'CONFIG_SND_HDA=m' ${kernelBuild}/.config
    flagsArray=()
    concatTo flagsArray makeFlags makeFlagsArray
    make "''${flagsArray[@]}" -j"$NIX_BUILD_CORES" M="$PWD/build/hda" \
      CFLAGS_MODULE='${appleFlags}' modules
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 build/hda/codecs/cirrus/${moduleName}.ko \
      "$out/lib/modules/${kernel.modDirVersion}/updates/codecs/cirrus/${moduleName}.ko"
    install -Dm644 source-sha256 "$out/share/snd-hda-macbookpro/source-sha256"
    runHook postInstall
  '';
  postFixup = ''
    export LC_ALL=C
    module="$out/lib/modules/${kernel.modDirVersion}/updates/codecs/cirrus/${moduleName}.ko"
    if grep -aFq "$NIX_BUILD_TOP/" "$module"; then
      echo 'Build-directory reference remains in module output' >&2
      exit 1
    fi
    test "$(modinfo -F name "$module")" = snd_hda_codec_cs8409
    case "$(modinfo -F vermagic "$module")" in
      '${kernel.modDirVersion} '*) ;;
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
  '';

  passthru = { inherit kernel; };
  meta = {
    description = "Apple CS8409 initialization module for pyrite's checked Linux kernel";
    homepage = "https://github.com/davidjo/snd_hda_macbookpro";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
