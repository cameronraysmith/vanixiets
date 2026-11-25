{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
}:
let
  inherit (stdenv.hostPlatform) system;
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "worktrunk-bin"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "worktrunk-bin";
  inherit (pin) version;

  src = fetchurl {
    url = planned.${system}.url or (throw "worktrunk-bin: unsupported platform ${system}");
    hash = binaries.hashes.${system};
  };

  # cargo-dist archive unpacks to a single worktrunk-<triple>/ directory that
  # stdenv auto-selects as sourceRoot. Linux assets are statically linked musl,
  # so autoPatchelfHook is a defensive no-op kept for house-style consistency;
  # Darwin assets are ad-hoc-signed Mach-O needing no patching.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 wt $out/bin/wt
    install -Dm755 git-wt $out/bin/git-wt
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/wt";
  doInstallCheck = true;

  passthru = {
    inherit pin pinPlan;
    # Commit the release tag points at; structure-release-alignment-worktrunk
    # requires the worktrunk skills' apm.yml ref to equal it.
    sourceRev = pin.rev;
  };

  meta = {
    description = "Git worktree manager for parallel branches and coding agents (prebuilt release binary)";
    homepage = "https://github.com/max-sixty/worktrunk";
    changelog = "https://github.com/max-sixty/worktrunk/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "wt";
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
