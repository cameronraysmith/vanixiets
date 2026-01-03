# golem-cli - CLI for Golem durable computing platform
#
# Golem is an open source durable computing platform for building and
# deploying highly reliable distributed systems using WebAssembly.
#
# This derivation uses pre-built binaries from GitHub releases.
# For source build, see the golem package (requires shadow-rs patching).
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
  writeShellApplication,
  curl,
  jq,
  common-updater-scripts,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "golem-cli";
  version = "1.4.2";

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
    install -Dm755 $src $out/bin/golem-cli
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/golem-cli";
  doInstallCheck = true;

  passthru = {
    sources = {
      "x86_64-linux" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-cli-x86_64-unknown-linux-gnu";
        hash = "sha256-EEHyNjHWIwMOJxiuTVIG3V2CEn6iGe6SRt8TI7UU348=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-cli-aarch64-unknown-linux-gnu";
        hash = "sha256-CEKOsq+PoXMuu5l08kemIJZmQwLgrGTDeVFQH85yl6c=";
      };
      "x86_64-darwin" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-cli-x86_64-apple-darwin";
        hash = "sha256-z8xH5aUOIBr9/1FiGnMtCZTQ9Dc3KSX4nmPbsgHoWQo=";
      };
      "aarch64-darwin" = fetchurl {
        url = "https://github.com/golemcloud/golem/releases/download/v${finalAttrs.version}/golem-cli-aarch64-apple-darwin";
        hash = "sha256-KB7pI2Z+eWoEWOYFUnQ1x3EawVmr/fa5koLP7A8/MkA=";
      };
    };
    updateScript = lib.getExe (writeShellApplication {
      name = "update-golem-cli";
      runtimeInputs = [
        curl
        jq
        common-updater-scripts
      ];
      text = ''
        NEW_VERSION=$(curl --silent https://api.github.com/repos/golemcloud/golem/releases/latest \
          | jq -r '.tag_name' \
          | sed 's/^v//')

        if [[ "${finalAttrs.version}" = "$NEW_VERSION" ]]; then
          echo "The new version same as the old version."
          exit 0
        fi

        for platform in ${lib.escapeShellArgs finalAttrs.meta.platforms}; do
          update-source-version "golem-cli" "$NEW_VERSION" --ignore-same-version --source-key="sources.$platform"
        done
      '';
    });
  };

  meta = {
    description = "CLI for Golem durable computing platform";
    longDescription = ''
      Golem is an open source durable computing platform that makes it easy
      to build and deploy highly reliable distributed systems using WebAssembly.

      The golem-cli provides commands for:
      - Managing components (WebAssembly modules)
      - Managing workers (running instances)
      - Invoking worker functions
      - Connecting to Golem Cloud or self-hosted Golem
    '';
    homepage = "https://www.golem.cloud/";
    changelog = "https://github.com/golemcloud/golem/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "golem-cli";
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
