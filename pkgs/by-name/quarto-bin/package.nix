# quarto-cli prebuilt binary (bundled tools incl. pandoc retained).
# version and per-platform SRI hashes live in manifest.json alongside this file.
#
# update: nix run .#update-quarto
# source: https://github.com/quarto-dev/quarto-cli
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zlib,
}:

let
  manifest = lib.importJSON ./manifest.json;
  inherit (stdenv.hostPlatform) system;
  entry = manifest.platforms.${system} or (throw "quarto-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "quarto-bin";
  version = manifest.version;

  src = fetchurl {
    url = "https://github.com/quarto-dev/quarto-cli/releases/download/v${finalAttrs.version}/quarto-${finalAttrs.version}-${entry.asset}.tar.gz";
    hash = entry.hash;
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

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Vendored upstream Quarto CLI (bundled tools incl. pandoc retained)";
    homepage = "https://quarto.org";
    license = lib.licenses.gpl2Plus;
    mainProgram = "quarto";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
