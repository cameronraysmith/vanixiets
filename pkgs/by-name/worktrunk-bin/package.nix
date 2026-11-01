{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
}:
let
  inherit (stdenv.hostPlatform) system;
  systemToPlatform = {
    "x86_64-linux" = {
      asset = "x86_64-unknown-linux-musl";
      hash = "sha256-DCU/IWmFzpzXsgKhFga1zmqpNLEBn9H7ubfOK0exx0o=";
    };
    "aarch64-linux" = {
      asset = "aarch64-unknown-linux-musl";
      hash = "sha256-ejNNLmTFd6/QJH4kEe/2czYKsfGIl1ZPLS5dU3T710s=";
    };
    "x86_64-darwin" = {
      asset = "x86_64-apple-darwin";
      hash = "sha256-IR+jWFr6DOJD3g8Af74ti4bFyIyF7aF9CTEbMuhTNxQ=";
    };
    "aarch64-darwin" = {
      asset = "aarch64-apple-darwin";
      hash = "sha256-ucPy+AcVVM+IUARm1l014YrV7a1XYkeaHxS83dWreII=";
    };
  };
  platform = systemToPlatform.${system} or (throw "worktrunk-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "worktrunk-bin";
  version = "0.81.0";

  src = fetchurl {
    url = "https://github.com/max-sixty/worktrunk/releases/download/v${finalAttrs.version}/worktrunk-${platform.asset}.tar.xz";
    hash = platform.hash;
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

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Git worktree manager for parallel branches and coding agents (prebuilt release binary)";
    homepage = "https://github.com/max-sixty/worktrunk";
    changelog = "https://github.com/max-sixty/worktrunk/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "wt";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
