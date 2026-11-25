# ic-wasm-bin: prebuilt release binaries for ic-wasm, the Internet Computer
# canister Wasm post-processor (metadata, shrinking, instrumentation) that
# icp-cli recipes and the dfinity/icskills skills invoke. Nix pins it in place
# of the withheld autoupgrade-icp-cli skill, which curl-upgrades it from a
# SessionStart hook. nixpkgs carries no ic-wasm.
#
# A proxy over upstream's cargo-dist release artifacts rather than a source
# build, as for icp-cli-bin.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
}:

let
  inherit (stdenv.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "ic-wasm-bin"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ic-wasm-bin";
  inherit (pin) version;

  # Each archive holds a single ic-wasm-<triple>/ directory with the `ic-wasm`
  # binary, which stdenv's unpack descends into.
  src = fetchurl {
    url = planned.${system}.url or (throw "ic-wasm-bin: unsupported platform ${system}");
    hash = binaries.hashes.${system};
  };

  dontConfigure = true;
  dontBuild = true;

  # Required, not defensive: the Linux artifacts are glibc-dynamic PIEs
  # (NEEDED: libgcc_s.so.1, libm.so.6, libc.so.6). Darwin artifacts need no
  # patching.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 ic-wasm $out/bin/ic-wasm
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/ic-wasm";
  doInstallCheck = true;

  passthru = { inherit pin pinPlan; };

  meta = {
    description = "Internet Computer canister Wasm transformer (prebuilt release binary)";
    homepage = "https://github.com/dfinity/ic-wasm";
    changelog = "https://github.com/dfinity/ic-wasm/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "ic-wasm";
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
