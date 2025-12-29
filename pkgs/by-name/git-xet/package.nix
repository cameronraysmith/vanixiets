# git-xet - Git LFS custom transfer agent for HuggingFace Hub
#
# Implements the Xet protocol for chunk-based deduplication when
# transferring large files (models, datasets) to HuggingFace Hub.
# Works alongside git-lfs as a custom transfer agent.
#
# Source: https://github.com/huggingface/xet-core
{
  lib,
  stdenv,
  fetchzip,
  writeShellApplication,
  curl,
  jq,
  common-updater-scripts,
  # Runtime dependencies for binary patching
  openssl,
  autoPatchelfHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "git-xet";
  version = "0.2.0";

  src =
    finalAttrs.passthru.sources.${stdenv.hostPlatform.system}
      or (throw "${finalAttrs.pname}: unsupported platform ${stdenv.hostPlatform.system}");

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
  ];

  buildInputs = [ openssl ];

  installPhase = ''
    runHook preInstall
    install -Dm755 git-xet $out/bin/git-xet
    runHook postInstall
  '';

  # Patch macOS binary to use Nix's OpenSSL instead of Homebrew's
  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    install_name_tool -change \
      /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib \
      ${openssl.out}/lib/libssl.3.dylib \
      $out/bin/git-xet
    install_name_tool -change \
      /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib \
      ${openssl.out}/lib/libcrypto.3.dylib \
      $out/bin/git-xet
    # Also patch for x86_64 Homebrew path (/usr/local/opt)
    install_name_tool -change \
      /usr/local/opt/openssl@3/lib/libssl.3.dylib \
      ${openssl.out}/lib/libssl.3.dylib \
      $out/bin/git-xet
    install_name_tool -change \
      /usr/local/opt/openssl@3/lib/libcrypto.3.dylib \
      ${openssl.out}/lib/libcrypto.3.dylib \
      $out/bin/git-xet
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/git-xet --version | grep -q "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  passthru = {
    sources = {
      "x86_64-linux" = fetchzip {
        url = "https://github.com/huggingface/xet-core/releases/download/git-xet-v${finalAttrs.version}/git-xet-linux-x86_64.zip";
        hash = "sha256-8FxDWkx+s2+0VF9bAuaP0Aiz+6g6noGeN2x7RLMciqg=";
        stripRoot = false;
      };
      "aarch64-linux" = fetchzip {
        url = "https://github.com/huggingface/xet-core/releases/download/git-xet-v${finalAttrs.version}/git-xet-linux-aarch64.zip";
        hash = "sha256-iwt35AA7ERv2xN6+IMR7Io0X1VQl8N/dTX/lCZjGwNI=";
        stripRoot = false;
      };
      "x86_64-darwin" = fetchzip {
        url = "https://github.com/huggingface/xet-core/releases/download/git-xet-v${finalAttrs.version}/git-xet-macos-x86_64.zip";
        hash = "sha256-Zhhm1SQ1oypisG+ecaeI6StIzsJCFMXzHC4xmCFQm8k=";
        stripRoot = false;
      };
      "aarch64-darwin" = fetchzip {
        url = "https://github.com/huggingface/xet-core/releases/download/git-xet-v${finalAttrs.version}/git-xet-macos-aarch64.zip";
        hash = "sha256-LD2ufQ4hnPbdAUjmCPIzxYr/WpuCF7tLbu3MbhiLwn4=";
        stripRoot = false;
      };
    };
    updateScript = lib.getExe (writeShellApplication {
      name = "update-git-xet";
      runtimeInputs = [
        curl
        jq
        common-updater-scripts
      ];
      text = ''
        # git-xet uses prefixed tags like "git-xet-v0.2.0"
        NEW_VERSION=$(curl --silent https://api.github.com/repos/huggingface/xet-core/releases \
          | jq -r '[.[] | select(.tag_name | startswith("git-xet-v"))] | .[0].tag_name' \
          | sed 's/^git-xet-v//')

        if [[ "${finalAttrs.version}" = "$NEW_VERSION" ]]; then
          echo "The new version same as the old version."
          exit 0
        fi

        for platform in ${lib.escapeShellArgs finalAttrs.meta.platforms}; do
          update-source-version "git-xet" "$NEW_VERSION" --ignore-same-version --source-key="sources.$platform"
        done
      '';
    });
  };

  meta = {
    description = "Git LFS custom transfer agent for HuggingFace Hub with chunk-based deduplication";
    longDescription = ''
      git-xet implements the Xet protocol for efficient file transfers to HuggingFace Hub.
      It provides chunk-based deduplication, avoiding redundant transfers of shared content
      across models and datasets. Works alongside git-lfs as a custom transfer agent.

      After installation, run 'git-xet install' to configure git to use the Xet protocol.
    '';
    homepage = "https://github.com/huggingface/xet-core";
    changelog = "https://github.com/huggingface/xet-core/releases/tag/git-xet-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "git-xet";
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
