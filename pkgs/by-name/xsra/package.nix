# xsra - SRA sequence extraction tool
#
# Performant CLI to extract sequences from NCBI SRA archives
# with support for FASTA, FASTQ, and BINSEQ output formats.
# Depends on ncbi-vdb-sys which builds a vendored C library
# via configure/make during the cargo build phase.
#
# Source: https://github.com/ArcInstitute/xsra
{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  perl,
  which,
  nix-update-script,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "xsra";
  version = "0.2.27";

  src = fetchFromGitHub {
    owner = "ArcInstitute";
    repo = "xsra";
    tag = "xsra-${finalAttrs.version}";
    hash = "sha256-2E2a9rxOvcR3zr4vIjvFG9zSFy0BeoM3mWuwJEzR9kc=";
  };

  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [
    cmake
    perl
    which
  ];

  # ncbi-vdb-sys vendors an old zlib whose zutil.h defines fdopen as a macro,
  # conflicting with macOS SDK stdio.h. Patch the vendored copy after cargo
  # sets up the writable vendor directory.
  preBuild = lib.optionalString stdenv.hostPlatform.isDarwin ''
    sed -i '/define fdopen.*NULL/d' \
      ../cargo-vendor-dir/ncbi-vdb-sys-*/vendor/ncbi-vdb/libs/ext/zlib/zutil.h
  '';

  doCheck = false;

  passthru.updateScript = nix-update-script {
    extraArgs = [
      "--version-regex"
      "xsra-(.*)"
    ];
  };

  meta = {
    homepage = "https://github.com/ArcInstitute/xsra";
    description = "Performant CLI tool to extract sequences from SRA archives";
    changelog = "https://github.com/ArcInstitute/xsra/releases/tag/xsra-${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "xsra";
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
