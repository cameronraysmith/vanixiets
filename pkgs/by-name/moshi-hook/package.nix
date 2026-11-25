# moshi-hook - companion daemon and CLI bridging local coding agents to the
# Moshi mobile app.
#
# Vendor-binary packaging rather than a source build: moshi-hook has no public
# source repository. The vendor publishes only prebuilt per-platform tarballs
# under https://cdn.getmoshi.app/hook/<version>/. https://getmoshi.app/install.sh
# and the rjyo/moshi Homebrew tap's Linux formula fetch the plain
# `moshi-hook_<OS>_<arch>` tarballs this derivation pins. On macOS the tap
# instead ships a `moshi-hook-app_Darwin_<arch>` .app bundle; both kinds of
# asset are listed in the same checksums.txt.
#
# The vendor's checksums.txt is the hash source; realize-pin reads it rather
# than re-hashing downloads, which keeps the pinned digests provably equal to
# the ones the vendor published.
{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
}:
let
  inherit (stdenv.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "moshi-hook"; })
    pin
    pinPlan
    ;
  # Upstream names assets by `uname -s` and `uname -m` output rather than by
  # target triple: Darwin/Linux crossed with x86_64/arm64.
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "moshi-hook";
  inherit (pin) version;

  src = fetchurl {
    url = planned.${system}.url or (throw "moshi-hook: unsupported platform ${system}");
    hash = binaries.hashes.${system};
  };

  # The tarball holds the executable, README.md, and docs/ at its root with no
  # containing directory.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # The Linux assets are statically linked Go, so there is nothing to patchelf.
  # The darwin assets carry a Developer ID signature with the hardened runtime
  # (TeamIdentifier FL442366Y7); stripping rewrites the Mach-O and invalidates
  # that signature, after which macOS refuses to exec the binary.
  dontStrip = stdenv.hostPlatform.isDarwin;

  installPhase = ''
    runHook preInstall

    install -Dm755 moshi-hook $out/bin/moshi-hook
    # The vendor's own Homebrew formula installs this alias, and the documented
    # `moshi <dir>` tmux launcher is reachable only under that name.
    ln -s moshi-hook $out/bin/moshi

    install -Dm644 README.md -t $out/share/doc/moshi-hook
    install -Dm644 docs/*.md -t $out/share/doc/moshi-hook

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = { inherit pin pinPlan; };

  meta = {
    homepage = "https://getmoshi.app";
    description = "Daemon and CLI bridging local coding agents to the Moshi mobile app (prebuilt vendor binary)";
    longDescription = ''
      moshi-hook installs hook configuration into supported coding agents,
      serves the local Unix socket those hooks post events to, exposes a
      localhost gateway for the iOS app's diff and browser-preview features,
      and holds a WebSocket to Moshi for approval round-trips and status.
    '';
    downloadPage = "https://getmoshi.app/docs/hooks";
    license = lib.licenses.unfree;
    mainProgram = "moshi-hook";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
