# quarto-cli prebuilt binary (bundled tools incl. pandoc retained).
# version and per-platform SRI hashes tracked in pin.json alongside this file.
#
# update: nix run .#realize-pin -- quarto-bin <version>
# source: https://github.com/quarto-dev/quarto-cli
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
  openssl,
}:

let
  inherit (stdenv.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "quarto-bin"; })
    pin
    pinPlan
    ;
  tarball = pin.artifacts.tarball.platformBinaries;
  planned = (pinPlan pin.version).artifacts.tarball.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "quarto-bin";
  inherit (pin) version;

  src = fetchurl {
    url = planned.${system}.url or (throw "quarto-bin: unsupported platform ${system}");
    hash = tarball.hashes.${system};
  };

  preUnpack = lib.optionalString stdenv.hostPlatform.isDarwin "mkdir ${finalAttrs.sourceRoot}";
  sourceRoot = lib.optionalString stdenv.hostPlatform.isDarwin "quarto-${finalAttrs.version}";
  unpackCmd = lib.optionalString stdenv.hostPlatform.isDarwin "tar xzf $curSrc --directory=$sourceRoot";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = stdenv.hostPlatform.isDarwin;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    zlib
    (lib.getLib openssl)
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share
    mv bin/* $out/bin
    mv share/* $out/share
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME=$(mktemp -d)
    $out/bin/quarto --version | grep -q "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  passthru = { inherit pin pinPlan; };

  meta = {
    description = "Vendored upstream Quarto CLI (bundled tools incl. pandoc retained)";
    homepage = "https://quarto.org";
    license = lib.licenses.gpl2Plus;
    mainProgram = "quarto";
    platforms = lib.attrNames tarball.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
