# uncomment-bin: prebuilt release binaries for the "uncomment" tree-sitter
# comment remover. Packages the archives upstream's publish workflow builds
# with plain `cargo build --release --target <triple>` (Linux inside
# manylinux_2_28 containers), whose asset stem is exactly the Rust target
# triple, rather than building the Rust source.
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
      hash = "sha256-Z+ifzX3TEnPYkQlEoFMuu4sqqhPPcWmEmjnbhiaX6Lk=";
    };
    "aarch64-linux" = {
      name = "aarch64-unknown-linux-gnu";
      hash = "sha256-y7WzLU8PXsOlpQ/9/HNQAwIxMr4Z9RY8J+rWeawI988=";
    };
    "x86_64-darwin" = {
      name = "x86_64-apple-darwin";
      hash = "sha256-mGb0VwG70Z4Jg/xVOO8W/JEV2ARMQCJYYZhS+Mlfc+A=";
    };
    "aarch64-darwin" = {
      name = "aarch64-apple-darwin";
      hash = "sha256-Vo0UinC5zjAzNDX/wGpkv3nnxSn5E/AMtq+2D3stWWE=";
    };
  };
  platform = systemToPlatform.${system} or (throw "uncomment-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "uncomment-bin";
  version = "3.12.1";

  src = fetchurl {
    url = "https://github.com/polylint/uncomment/releases/download/v${finalAttrs.version}/uncomment-${platform.name}.tar.gz";
    hash = platform.hash;
  };

  # Each archive holds only the bare `uncomment` binary at its root, with no
  # top-level directory, so stdenv's single-directory unpack detection does
  # not apply.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # Required, not defensive: the Linux artifacts are glibc-dynamic PIEs
  # (NEEDED: libc.so.6, libdl.so.2, libgcc_s.so.1, libm.so.6, libpthread.so.0),
  # so both the interpreter and the libgcc_s lookup need rewriting. Darwin
  # artifacts are ad-hoc signed Mach-O and need no patching.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

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
    homepage = "https://github.com/polylint/uncomment";
    changelog = "https://github.com/polylint/uncomment/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "uncomment";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
