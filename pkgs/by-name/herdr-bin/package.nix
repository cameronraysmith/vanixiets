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
      asset = "herdr-linux-x86_64";
      hash = "sha256-uWWsr/wsIvVLbmxkr3z46Yo/SsJiJjCgWZxnpLnYplQ=";
    };
    "aarch64-linux" = {
      asset = "herdr-linux-aarch64";
      hash = "sha256-PXV6wwxjHnncRQOMPsxkI/4TqJ+c/6D0Fa7dLCfxV2w=";
    };
    "x86_64-darwin" = {
      asset = "herdr-macos-x86_64";
      hash = "sha256-V4D6B9u5p4155S0guGphAT9sugJmfyC2z4lmMBUJCEY=";
    };
    "aarch64-darwin" = {
      asset = "herdr-macos-aarch64";
      hash = "sha256-FvRlPwSR6h59K0a1sCVC8Y4bguiNqvnikAVy5btjTfg=";
    };
  };
  platform = systemToPlatform.${system} or (throw "herdr-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "herdr-bin";
  version = "0.7.1";

  src = fetchurl {
    url = "https://github.com/ogulcancelik/herdr/releases/download/v${finalAttrs.version}/${platform.asset}";
    hash = platform.hash;
  };

  # Bare single-binary release asset (no archive). Linux assets are statically
  # linked musl, so autoPatchelfHook is a defensive no-op kept for house-style
  # consistency; Darwin assets are ad-hoc-signed Mach-O needing no patching.
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/herdr
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/herdr";
  doInstallCheck = true;

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Terminal workspace manager and multiplexer for AI coding agents (prebuilt release binary)";
    homepage = "https://herdr.dev";
    changelog = "https://github.com/ogulcancelik/herdr/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Plus;
    mainProgram = "herdr";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
