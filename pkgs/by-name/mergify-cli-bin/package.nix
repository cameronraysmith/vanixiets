# mergify-cli-bin: prebuilt release binaries for the Mergify CLI, whose
# `mergify stack` subcommand drives stacked-pull-request landing.
#
# A proxy over upstream's release artifacts rather than a from-source build:
# the Rust workspace at crates/ carries a `0.0.0` placeholder in Cargo.toml and
# the real version is stamped into the binary at release time, so a source build
# cannot reproduce the version the CLI reports.
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
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "mergify-cli-bin"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "mergify-cli-bin";
  inherit (pin) version;

  src = fetchurl {
    url = planned.${system}.url or (throw "mergify-cli-bin: unsupported platform ${system}");
    hash = binaries.hashes.${system};
  };

  # Each archive holds the bare `mergify` binary at its root with no enclosing
  # directory, so stdenv's single-directory unpack detection has nothing to
  # descend into.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  # Required, not defensive: the Linux artifacts are glibc-dynamic PIEs
  # (NEEDED: libc.so.6, libdl.so.2, libgcc_s.so.1, libm.so.6, libpthread.so.0,
  # librt.so.1), so both the interpreter and the libgcc_s lookup need rewriting.
  # Darwin artifacts are ad-hoc-signed Mach-O and need no patching.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 mergify $out/bin/mergify
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/mergify";
  doInstallCheck = true;

  passthru = {
    inherit pin pinPlan;
    # Commit the release tag points at; structure-release-alignment-mergify-cli
    # requires the mergify-stack skill's apm.yml ref to equal it.
    sourceRev = pin.rev;
  };

  meta = {
    description = "Mergify CLI for stacked pull requests and CI insights (prebuilt release binary)";
    homepage = "https://github.com/Mergifyio/mergify-cli";
    changelog = "https://github.com/Mergifyio/mergify-cli/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "mergify";
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
