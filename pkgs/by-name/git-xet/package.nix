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
  # Runtime dependencies for binary patching
  openssl,
  autoPatchelfHook,
  zlib,
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

  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
    zlib # libz.so.1
  ];

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
        hash = "sha256-B3H2XuhZYBqNmgMl1R/fBlneGhBrfZvE8oESDE7NFvA=";
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
    updateScript = ./update.sh;
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
