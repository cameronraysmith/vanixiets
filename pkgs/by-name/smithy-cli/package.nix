{
  lib,
  stdenv,
  fetchzip,
  jdk17,
  writeShellApplication,
  curl,
  jq,
  common-updater-scripts,
}:
let
  # Map nix platform to smithy release naming
  platformNames = {
    "aarch64-darwin" = "darwin-aarch64";
    "x86_64-linux" = "linux-x86_64";
    "aarch64-linux" = "linux-aarch64";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "smithy-cli";
  version = "1.65.0";

  src =
    finalAttrs.passthru.sources.${stdenv.hostPlatform.system}
      or (throw "${finalAttrs.pname}: unsupported platform ${stdenv.hostPlatform.system}");

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    ./install -i $out -b $out/bin
    ln -sf ${jdk17}/bin/java $out/bin/java
    runHook postInstall
  '';

  passthru = {
    sources = {
      "aarch64-darwin" = fetchzip {
        url = "https://github.com/smithy-lang/smithy/releases/download/${finalAttrs.version}/smithy-cli-${platformNames."aarch64-darwin"}.zip";
        hash = "sha256-PBOxXHKd9nSQVD/P/KBxaffQvM9aYnzMwcBvshUMr9M=";
      };
      "x86_64-linux" = fetchzip {
        url = "https://github.com/smithy-lang/smithy/releases/download/${finalAttrs.version}/smithy-cli-${platformNames."x86_64-linux"}.zip";
        hash = "sha256-tPrkbzqGX0hNeDZG2JKbqTHJqMi5ssX62Ya6stSb1O8=";
      };
      "aarch64-linux" = fetchzip {
        url = "https://github.com/smithy-lang/smithy/releases/download/${finalAttrs.version}/smithy-cli-${platformNames."aarch64-linux"}.zip";
        hash = "sha256-C8QcFjsY/SQRjhP4nRUEbm1aLMAav+gPRUGlwoVRRWs=";
      };
    };
    updateScript = lib.getExe (writeShellApplication {
      name = "update-smithy-cli";
      runtimeInputs = [
        curl
        jq
        common-updater-scripts
      ];
      text = ''
        NEW_VERSION=$(curl --silent https://api.github.com/repos/smithy-lang/smithy/releases/latest | jq '.tag_name' --raw-output)

        if [[ "${finalAttrs.version}" = "$NEW_VERSION" ]]; then
          echo "The new version same as the old version."
          exit 0
        fi

        for platform in ${lib.escapeShellArgs finalAttrs.meta.platforms}; do
          update-source-version "smithy-cli" "$NEW_VERSION" --ignore-same-version --source-key="sources.$platform"
        done
      '';
    });
  };

  meta = {
    description = "CLI for the Smithy IDL (Interface Definition Language)";
    homepage = "https://smithy.io";
    changelog = "https://github.com/smithy-lang/smithy/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "smithy";
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
