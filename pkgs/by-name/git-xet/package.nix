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
  fetchurl,
  unzip,
  # Runtime dependencies for binary patching
  openssl,
  autoPatchelfHook,
  zlib,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "git-xet"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "git-xet";
  inherit (pin) version;

  src =
    finalAttrs.passthru.sources.${stdenv.hostPlatform.system}
      or (throw "${finalAttrs.pname}: unsupported platform ${stdenv.hostPlatform.system}");

  # The release zip holds the bare `git-xet` executable at its root, with no
  # directory for stdenv to select as sourceRoot.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [
    unzip
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
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
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/git-xet --version | grep -q "${finalAttrs.version}"
    runHook postInstallCheck
  '';

  passthru = {
    inherit pin pinPlan;
    sources = lib.mapAttrs (
      system: platform:
      fetchurl {
        inherit (platform) url;
        hash = binaries.hashes.${system};
      }
    ) planned;
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
