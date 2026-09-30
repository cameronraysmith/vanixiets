{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  protobuf,
  cmake,
  pkg-config,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "omnigraph";
  version = "0.11.0";

  # rev is the v0.11.0 tag peel rather than tag = "v${version}": upstream's release builds stamp
  # OMNIGRAPH_SOURCE_VERSION with the source commit sha, which env below reads from src.rev.
  src = fetchFromGitHub {
    owner = "ModernRelay";
    repo = "omnigraph";
    rev = "1523b4ab43f16c6ed4802c21393e5bdb66c6622b";
    hash = "sha256-cdrDqvnmfEUJtx/T9ojVEYGmOv93RZzCO3z7KG+nYBU=";
  };

  cargoHash = "sha256-dumK9yeVHQtYG4g5WA+yw4a+5DQzxPoXHmpDMdBkYo8=";

  # Workaround for the stdarch/LLVM 21 signature mismatch on the AVX-512 VNNI intrinsics retyped by
  # https://github.com/llvm/llvm-project/pull/155194; the deleted lines are runtime-dispatch arms,
  # so removing them falls back to the AVX2 and scalar kernels.
  postPatch = ''
    lanceDistance="$cargoDepsCopy/source-registry-0/lance-linalg-11.0.0/src/distance"

    substituteInPlace "$lanceDistance/dot_u8.rs" \
      --replace-fail "return |a, b| unsafe { x86::dot_u8_avx512_vnni(a, b) };" ""

    substituteInPlace "$lanceDistance/l2_u8.rs" \
      --replace-fail "return |a, b| unsafe { x86::l2_u8_avx512_vnni(a, b) };" ""

    substituteInPlace "$lanceDistance/cosine_u8.rs" \
      --replace-fail "return |a, b| unsafe { x86::cosine_u8_accum_avx512_vnni(a, b) };" ""
  '';

  nativeBuildInputs = [
    protobuf
    cmake
    pkg-config
  ];

  cargoBuildFlags = [
    "-p"
    "omnigraph-cli"
    "-p"
    "omnigraph-server"
  ];

  env = {
    OMNIGRAPH_SOURCE_VERSION = finalAttrs.src.rev;
  }
  # ctor emits its constructor into __TEXT,__text_startup, past the +/-128 MiB reach of the ARM64
  # b/bl branching back into __text, and ld64's island pass skips that section; upstream's macos-14
  # release job sets the same flag. force-frame-pointers is restated because setting RUSTFLAGS
  # suppresses rather than merges with nixpkgs' [target.<triple>].rustflags.
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    RUSTFLAGS = "-C code-model=large -C force-frame-pointers=yes";
  };

  doCheck = false;

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/omnigraph" --help > /dev/null
    "$out/bin/omnigraph-server" --help > /dev/null

    runHook postInstallCheck
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    homepage = "https://github.com/ModernRelay/omnigraph";
    description = "Lakehouse graph database server and CLI";
    license = lib.licenses.mit;
    mainProgram = "omnigraph";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
