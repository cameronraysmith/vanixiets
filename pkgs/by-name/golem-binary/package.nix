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
  openssl,
  zlib,
  versionCheckHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "golem-binary";
  version = "1.5.10";

  src =
    finalAttrs.passthru.sources.${stdenv.hostPlatform.system}
      or (throw "${finalAttrs.pname}: unsupported platform ${stdenv.hostPlatform.system}");

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
    openssl
    zlib
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
    sources = {
      "x86_64-linux" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-x86_64-unknown-linux-gnu";
        hash = "sha256-dPFhDs5HS1KM5GO30MpSwRTetnovDx5JWAoYKJLFWVI=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-aarch64-unknown-linux-gnu";
        hash = "sha256-YjEj9bW47S3BBfBSkT/o16goUUnHn3hO/bODbY1fF8I=";
      };
      "x86_64-darwin" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-x86_64-apple-darwin";
        hash = "sha256-P1iYd69btlxejdbKARsS6B0dAlMZNNOfTyTVWm/5KGI=";
      };
      "aarch64-darwin" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-aarch64-apple-darwin";
        hash = "sha256-sUmvxYPEcXHmkoaOJ1RMRoP/q74gztKGYiUwASUqgK8=";
      };
    };
    updateScript = ./update.sh;
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
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
