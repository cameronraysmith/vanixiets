# golem-binary - prebuilt full Golem CLI (bundled server)
#
# Per upstream docs there are two CLI variants:
#   - `golem`     : full version including a locally runnable Golem server
#   - `golem-cli` : lightweight version requiring an external Golem cluster
# This derivation packages the full `golem` binary from upstream's prebuilt
# release artifacts. The pname is `golem-binary` to disambiguate from the
# Rust source build at pkgs/disabled/golem/ (which would compile the entire
# workspace from source); the installed binary is named `golem` to match the
# command users invoke per upstream documentation.
#
# Source: https://github.com/golemcloud/golem
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
}:
let
  inherit (stdenv.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "golem-binary"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "golem-binary";
  inherit (pin) version;

  # A bare executable per platform; upstream publishes no checksum file for
  # these assets, so the pin's hashes are prefetched.
  src = fetchurl {
    url = planned.${system}.url or (throw "golem-binary: unsupported platform ${system}");
    hash = binaries.hashes.${system};
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/golem
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/golem";
  doInstallCheck = true;

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "Full Golem CLI (prebuilt) including a locally runnable Golem server";
    longDescription = ''
      Golem is an open source durable computing platform that makes it easy
      to build and deploy highly reliable distributed systems using WebAssembly.

      This package installs the full prebuilt `golem` binary from upstream
      release artifacts. Per upstream documentation, this is the recommended
      variant because it bundles a locally runnable Golem server alongside the
      CLI. The lightweight `golem-cli` variant (which requires an external
      Golem cluster) is not packaged here.

      The installed binary is `bin/golem` to match upstream's documented
      invocation (`golem ...`).
    '';
    homepage = "https://www.golem.cloud/";
    changelog = "https://github.com/golemcloud/golem/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "golem";
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
