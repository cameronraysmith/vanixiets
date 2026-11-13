# Upstream release binaries rather than a source build: no shared Hydra builds or
# caches the roughly 880-crate ThinLTO build, so every bump cost a local rebuild of
# well over an hour. The last source build is commit 61b6d92f.
{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
  versionCheckHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omnigraph";
  version = "0.15.0";

  src = finalAttrs.passthru.sources.${stdenv.hostPlatform.system};

  # Each archive unpacks to three top-level executables and no directory.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  # Upstream ships stripped binaries; the macOS ones carry a Developer ID
  # signature that stripping would invalidate.
  dontStrip = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin omnigraph omnigraph-server omnigraph-azure-admission
    runHook postInstall
  '';

  # `omnigraph --version` prints `omnigraph <version>`; omnigraph-server has no
  # --version flag, so it gets a --help smoke test.
  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  postInstallCheck = ''
    "$out/bin/omnigraph-server" --help > /dev/null
  '';

  passthru = {
    sources = {
      "x86_64-linux" = fetchurl {
        url = "https://github.com/ModernRelay/omnigraph/releases/download/v${finalAttrs.version}/omnigraph-linux-x86_64.tar.gz";
        hash = "sha256-1zEs5Jq8pHprtHlWtph9MvZQ+pFni+Gr0Q4Cgkk3uxU=";
      };
      "aarch64-linux" = fetchurl {
        url = "https://github.com/ModernRelay/omnigraph/releases/download/v${finalAttrs.version}/omnigraph-linux-arm64.tar.gz";
        hash = "sha256-+hCCY2uzkn1h3PnSK7TgjrD7RG0I50ZziGnkDDY7R1U=";
      };
      "aarch64-darwin" = fetchurl {
        url = "https://github.com/ModernRelay/omnigraph/releases/download/v${finalAttrs.version}/omnigraph-macos-arm64.tar.gz";
        hash = "sha256-x4PcnQ42YLdKnC5sVZG/Hk35p2POMilYUmwIcunKGuw=";
      };
    };
    # The release archives carry only the executables; the upstream agent skill
    # (deployed by modules/home/tools/omnigraph.nix) comes from the tagged tree.
    skillSrc = fetchFromGitHub {
      owner = "ModernRelay";
      repo = "omnigraph";
      tag = "v${finalAttrs.version}";
      hash = "sha256-fDjXKhh/jAXST0SGoPsGkFDIZtpGF9NxCxGd7H4snBA=";
    };
    updateScript = ./update.sh;
  };

  meta = {
    homepage = "https://github.com/ModernRelay/omnigraph";
    description = "Lakehouse graph database server and CLI";
    changelog = "https://github.com/ModernRelay/omnigraph/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "omnigraph";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
