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
  nix-update-script,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "xsra";
  version = "0.2.27";

  src = fetchFromGitHub {
    owner = "ArcInstitute";
    repo = "xsra";
    tag = "xsra-${finalAttrs.version}";
    hash = lib.fakeHash;
  };

  cargoLock.lockFile = ./Cargo.lock;

  postPatch = ''
    ln -sf ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [
    cmake
    perl
  ];

  env.NIX_CFLAGS_COMPILE = lib.optionalString stdenv.cc.isClang "-Wno-error=implicit-function-declaration";

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
