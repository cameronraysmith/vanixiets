# Upstream release binaries rather than a source build: a source build compiles
# Zed's crates on every update, and on macOS it yields a bare executable with no
# app bundle, so `omnigraph studio`, which opens the app by its bundle identifier,
# could not hand a link to it. The macOS bundle is the signed and notarized one
# from the release.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  _7zz,
  python3,
  libGL,
  libxcb,
  libxkbcommon,
  vulkan-loader,
  wayland,
}:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "omnigraph-studio"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;

  appName = "Omnigraph Studio.app";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "omnigraph-studio";
  inherit (pin) version;

  src = finalAttrs.passthru.sources.${stdenv.hostPlatform.system};

  # The disk image is APFS, which undmg cannot read and 7-Zip can; it holds the
  # app bundle at its top level. The Linux tarball unpacks to its single
  # omnigraph-studio-<version>-linux-<arch> directory.
  sourceRoot = if stdenv.hostPlatform.isDarwin then "." else null;

  dontConfigure = true;
  dontBuild = true;
  # Upstream ships stripped binaries; the macOS bundle carries a Developer ID
  # signature that any change to the bundle would invalidate.
  dontStrip = true;
  dontFixup = stdenv.hostPlatform.isDarwin;

  nativeBuildInputs =
    lib.optionals stdenv.hostPlatform.isDarwin [ _7zz ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # The libraries the executable links; the rest of what it uses (TLS through
  # rustls, SQLite) is compiled into it.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libxcb
    libxkbcommon # libxkbcommon.so.0 and libxkbcommon-x11.so.0
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  # The graphics libraries the renderer (wgpu) opens with dlopen: no ELF entry
  # names them, so autoPatchelf alone would leave them off the search path.
  # libvulkan.so.1, libEGL.so.1 for the OpenGL ES fallback, and
  # libwayland-client.so.0 with libwayland-egl.so.1 on a Wayland session.
  runtimeDependencies = lib.optionals stdenv.hostPlatform.isLinux [
    libGL
    vulkan-loader
    wayland
  ];

  installPhase =
    if stdenv.hostPlatform.isDarwin then
      ''
        runHook preInstall
        mkdir -p $out/Applications
        cp -R "${appName}" $out/Applications/
        runHook postInstall
      ''
    else
      ''
        runHook preInstall
        mkdir -p $out
        cp -R bin share $out/
        runHook postInstall
      '';

  # The executable has no --version flag and opens a window on any run, so the
  # version is read from what the release packs around it: the bundle's
  # Info.plist on macOS, the tarball's top directory name on Linux. On Linux
  # the check also finds each library the renderer opens with dlopen on the
  # executable's RUNPATH, which autoPatchelf cannot check for them.
  doInstallCheck = true;
  nativeInstallCheckInputs = lib.optionals stdenv.hostPlatform.isDarwin [ python3 ];
  installCheckPhase =
    if stdenv.hostPlatform.isDarwin then
      ''
        runHook preInstallCheck
        found=$(python3 -c 'import plistlib, sys; print(plistlib.load(open(sys.argv[1], "rb"))["CFBundleShortVersionString"])' \
          "$out/Applications/${appName}/Contents/Info.plist")
        if [[ "$found" != "$version" ]]; then
          echo "Info.plist names version $found, expected $version" >&2
          exit 1
        fi
        runHook postInstallCheck
      ''
    else
      ''
        runHook preInstallCheck
        expected="omnigraph-studio-$version-linux-${stdenv.hostPlatform.uname.processor}"
        if [[ "$(basename "$sourceRoot")" != "$expected" ]]; then
          echo "tarball unpacked to $sourceRoot, expected $expected" >&2
          exit 1
        fi
        test -x "$out/bin/omnigraph-studio"
        runpath=$(patchelf --print-rpath "$out/bin/omnigraph-studio")
        for soname in libvulkan.so.1 libEGL.so.1 libwayland-client.so.0 libwayland-egl.so.1; do
          found=
          for dir in ''${runpath//:/ }; do
            if [[ -e "$dir/$soname" ]]; then found=1; fi
          done
          if [[ -z "$found" ]]; then
            echo "$soname is on no RUNPATH entry of omnigraph-studio: $runpath" >&2
            exit 1
          fi
        done
        runHook postInstallCheck
      '';

  passthru = {
    inherit pin pinPlan;
    sources = lib.mapAttrs (
      system: artifact:
      fetchurl {
        inherit (artifact) url;
        hash = pin.artifacts.binaries.platformBinaries.hashes.${system};
      }
    ) planned.binaries.platformBinaries;
  };

  meta = {
    homepage = "https://github.com/ModernRelay/omnigraph-studio";
    description = "Desktop client for OmniGraph servers";
    changelog = "https://github.com/ModernRelay/omnigraph-studio/releases/tag/v${finalAttrs.version}";
    # The application is GPL-3.0-or-later and its Inter font OFL-1.1; the
    # bundled Nucleo icons may be redistributed only inside the application.
    license = with lib.licenses; [
      gpl3Plus
      ofl
      unfreeRedistributable
    ];
    mainProgram = "omnigraph-studio";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
