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
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "uncomment-bin"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "uncomment-bin";
  inherit (pin) version;

  src = fetchurl {
    url = planned.${system}.url or (throw "uncomment-bin: unsupported platform ${system}");
    hash = binaries.hashes.${system};
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

  passthru = { inherit pin pinPlan; };

  meta = {
    description = "Fast tree-sitter based tool to remove comments from source code";
    homepage = "https://github.com/polylint/uncomment";
    changelog = "https://github.com/polylint/uncomment/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "uncomment";
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
