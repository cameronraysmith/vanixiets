# hindsight - CLI and TUI client for the Hindsight semantic memory system.
#
# Upstream's own installer at https://hindsight.vectorize.io/get-cli downloads a
# prebuilt binary per platform from the GitHub release, and this follows it: the
# four assets are the same artifacts the vendor ships, pinned by hash instead of
# fetched at install time.
#
# Building from source is possible and was tried first, but it is a poor trade
# here. hindsight-cli path-depends on hindsight-clients/rust, whose build.rs
# generates that client's entire API surface with progenitor at build time and
# locates its OpenAPI input by walking two parents up to
# hindsight-docs/static/openapi.json. That makes the whole monorepo the build
# input -- a 219 MB source derivation, most of it documentation -- and upstream
# gitignores the CLI's Cargo.lock, so the resolution would have to be vendored
# and regenerated here on every bump. The release assets cost four hashes.
#
# Source: https://github.com/vectorize-io/hindsight
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  openssl,
  versionCheckHook,
}:
let
  inherit (stdenv.hostPlatform) system;
  # Upstream names its assets by its own os-arch labels rather than by target
  # triple, and ships them as bare executables rather than archives.
  systemToPlatform = {
    "x86_64-linux" = {
      asset = "linux-amd64";
      hash = "sha256-vofGNxT/BGrI7WaEZcoMh1+U5v8Kie2D2n6zhzExl68=";
    };
    "aarch64-linux" = {
      asset = "linux-arm64";
      hash = "sha256-E9AB1eONniAHqjwQbfuCMyVX3Wx6rlPB8m5uDxvwYaE=";
    };
    "x86_64-darwin" = {
      asset = "darwin-amd64";
      hash = "sha256-pYqVd8ha16qSRIHPKiXTmWGjiDLSlimjR06ItLCYjHo=";
    };
    "aarch64-darwin" = {
      asset = "darwin-arm64";
      hash = "sha256-nNBxkvA4xgUBJCZIwlBBvXBzBP946CYlFdr1+4MsR/Q=";
    };
  };
  platform = systemToPlatform.${system} or (throw "hindsight: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "hindsight";
  version = "0.10.2";

  src = fetchurl {
    url = "https://github.com/vectorize-io/hindsight/releases/download/v${finalAttrs.version}/hindsight-${platform.asset}";
    hash = platform.hash;
  };

  # The asset is a bare executable, so there is nothing to unpack and stdenv's
  # source-root detection has nothing to detect.
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # The Linux assets are dynamically linked, not static: reqwest resolves to
  # native-tls, which is openssl off darwin, so the binary wants libssl.so.3 and
  # libcrypto.so.3 plus libgcc_s.so.1. The darwin assets need nothing, native-tls
  # using Security.framework there.
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    openssl
    stdenv.cc.cc.lib
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/hindsight
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.updateScript = ./update.sh;

  meta = {
    homepage = "https://github.com/vectorize-io/hindsight";
    description = "CLI and TUI client for the Hindsight semantic memory system (prebuilt release binary)";
    changelog = "https://github.com/vectorize-io/hindsight/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "hindsight";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
