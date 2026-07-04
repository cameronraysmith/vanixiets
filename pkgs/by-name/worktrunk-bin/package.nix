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
      hash = "sha256-2f3h+TbH33WXYPbrFuF45wOXM1h/HqmTEHbb4lb+b4U=";
    };
    "aarch64-linux" = {
      asset = "aarch64-unknown-linux-musl";
      hash = "sha256-nQiBZHkCDx2JiMlE59etNUQyjjDssdQuXudU3csXztQ=";
    };
    "x86_64-darwin" = {
      asset = "x86_64-apple-darwin";
      hash = "sha256-Hhhu1G5UlpXIsyX3KPbjhVflAAWuGnEDZQCZQflGjPk=";
    };
    "aarch64-darwin" = {
      asset = "aarch64-apple-darwin";
      hash = "sha256-X4seMCmoKlIb1XH4ixlkCnNjq5OyFUh6L2dP/Kx3K+k=";
    };
  };
  platform = systemToPlatform.${system} or (throw "worktrunk-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "worktrunk-bin";
  version = "0.65.0";

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
