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
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "omnigraph"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "omnigraph";
  inherit (pin) version;

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
    inherit pin pinPlan;
    sources = lib.mapAttrs (
      system: artifact:
      fetchurl {
        inherit (artifact) url;
        hash = pin.artifacts.binaries.platformBinaries.hashes.${system};
      }
    ) planned.binaries.platformBinaries;
    # The release archives carry only the executables; the upstream agent skill
    # (deployed by modules/home/tools/omnigraph.nix) comes from the tagged tree.
    skillSrc = fetchFromGitHub (
      planned.skillSrc.sourceBuild.fetchFromGitHub
      // {
        inherit (pin.artifacts.skillSrc.sourceBuild) hash;
      }
    );
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
