# icp-cli-bin: prebuilt release binaries for icp-cli, the Internet Computer
# CLI (`icp`) that the dfinity/icskills skills drive. Nix pins it in place of
# the withheld autoupgrade-icp-cli skill, which curl-upgrades the binary from a
# SessionStart hook. nixpkgs carries no icp-cli.
#
# A proxy over upstream's cargo-dist release artifacts rather than a source
# build, as for mergify-cli-bin.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dbus,
  zlib,
  versionCheckHook,
}:

let
  inherit (stdenv.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "icp-cli-bin"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "icp-cli-bin";
  inherit (pin) version;

  # Each archive holds a single icp-cli-<triple>/ directory with the `icp`
  # binary, which stdenv's unpack descends into.
  src = fetchurl {
    url = planned.${system}.url or (throw "icp-cli-bin: unsupported platform ${system}");
    hash = binaries.hashes.${system};
  };

  dontConfigure = true;
  dontBuild = true;

  # Required, not defensive: the Linux artifacts are glibc-dynamic PIEs
  # (NEEDED: libz.so.1, libdbus-1.so.3, libgcc_s.so.1, libm.so.6, libc.so.6).
  # Darwin artifacts need no patching.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
    dbus # libdbus-1.so.3
    zlib # libz.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 icp $out/bin/icp
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/icp";
  doInstallCheck = true;

  passthru = { inherit pin pinPlan; };

  meta = {
    description = "Internet Computer CLI for building and deploying canisters (prebuilt release binary)";
    homepage = "https://github.com/dfinity/icp-cli";
    changelog = "https://github.com/dfinity/icp-cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "icp";
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
