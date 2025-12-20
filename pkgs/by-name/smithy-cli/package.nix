{
  lib,
  stdenv,
  fetchzip,
  jdk17,
  nix-update-script,
}:
let
  pname = "smithy-cli";
  version = "1.65.0";

  # Map nix platform to smithy release naming (arch-os → os-arch)
  platformMap = {
    "aarch64-darwin" = {
      name = "darwin-aarch64";
      hash = "sha256-PBOxXHKd9nSQVD/P/KBxaffQvM9aYnzMwcBvshUMr9M=";
    };
    "x86_64-linux" = {
      name = "linux-x86_64";
      hash = "sha256-tPrkbzqGX0hNeDZG2JKbqTHJqMi5ssX62Ya6stSb1O8=";
    };
    "aarch64-linux" = {
      name = "linux-aarch64";
      hash = "sha256-C8QcFjsY/SQRjhP4nRUEbm1aLMAav+gPRUGlwoVRRWs=";
    };
  };

  platform =
    platformMap.${stdenv.hostPlatform.system}
      or (throw "smithy-cli: unsupported platform ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchzip {
    url = "https://github.com/smithy-lang/smithy/releases/download/${version}/smithy-cli-${platform.name}.zip";
    hash = platform.hash;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    ./install -i $out -b $out/bin
    ln -sf ${jdk17}/bin/java $out/bin/java
    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "CLI for the Smithy IDL (Interface Definition Language)";
    homepage = "https://smithy.io";
    changelog = "https://github.com/smithy-lang/smithy/releases/tag/${version}";
    license = lib.licenses.asl20;
    mainProgram = "smithy";
    platforms = lib.attrNames platformMap;
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
}
