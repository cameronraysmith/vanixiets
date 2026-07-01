# uncomment-bin: prebuilt release binaries for the "uncomment" tree-sitter
# comment remover. Packages upstream's GoReleaser (cargo-zigbuild) artifacts
# whose asset stem is exactly the Rust target triple, rather than building the
# Rust source.
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
      name = "x86_64-unknown-linux-gnu";
      hash = "sha256-eoMb0G0wCLOjIQczGGzUjpAtwfuv7DLMdS+4iZhoAlc=";
    };
    "aarch64-linux" = {
      name = "aarch64-unknown-linux-gnu";
      hash = "sha256-QI+2+iSQVHO9PihNACxX/JjqZJp7bOYtgrKzqS1ISoE=";
    };
    "x86_64-darwin" = {
      name = "x86_64-apple-darwin";
      hash = "sha256-iJGed8UCX/fptnlfvnu/S86e2g/41HVKHKW1uwDej+I=";
    };
    "aarch64-darwin" = {
      name = "aarch64-apple-darwin";
      hash = "sha256-A6AKGfwKlL1PbXUMsZWmp3IBc4+bfaCbZSL1rkGTjkM=";
    };
  };
  platform = systemToPlatform.${system} or (throw "uncomment-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "uncomment-bin";
  version = "3.0.3";

  src = fetchurl {
    url = "https://github.com/Goldziher/uncomment/releases/download/v${finalAttrs.version}/uncomment-${platform.name}.tar.gz";
    hash = platform.hash;
  };

  # GoReleaser packs the binary plus LICENSE/README/CHANGELOG loose at the
  # archive root, so stdenv's single-directory unpack detection does not apply.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # Linux artifacts are dynamically-linked glibc PIEs (NEEDED: libc, libpthread,
  # libdl only -- no libgcc_s/libstdc++/openssl); autoPatchelfHook rewrites the
  # interpreter with no extra buildInputs. Darwin artifacts are ad-hoc signed
  # Mach-O and need no patching.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 uncomment $out/bin/uncomment
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/uncomment";
  doInstallCheck = true;

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Fast tree-sitter based tool to remove comments from source code";
    homepage = "https://github.com/Goldziher/uncomment";
    changelog = "https://github.com/Goldziher/uncomment/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "uncomment";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
