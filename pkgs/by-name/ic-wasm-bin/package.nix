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
  # Hashes are the release's per-asset .sha256 files converted to SRI, not
  # values guessed by a prefetch.
  systemToPlatform = {
    "x86_64-linux" = {
      triple = "x86_64-unknown-linux-gnu";
      hash = "sha256-9tQNZ1lvvpGl8sLNusKs4WIwUkbdNbzTDjQjDn+R3/g=";
    };
    "aarch64-linux" = {
      triple = "aarch64-unknown-linux-gnu";
      hash = "sha256-WpvJ1HWrPrjr2sEKwqZWTjcpLgpHJTZG/lC/mQfe4qg=";
    };
    "x86_64-darwin" = {
      triple = "x86_64-apple-darwin";
      hash = "sha256-XWWCVJDBcr6rz0RElrbkfIKTlRvcDppScF37kku+Re0=";
    };
    "aarch64-darwin" = {
      triple = "aarch64-apple-darwin";
      hash = "sha256-mfPY2vFvh9UnhlKZx1ws/VC8ndS7FmRQq9H1ziYYmQo=";
    };
  };
  platform = systemToPlatform.${system} or (throw "ic-wasm-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "ic-wasm-bin";
  # Bare semver with no `v` prefix, matching the upstream tag exactly.
  version = "1.0.0";

  # Each archive holds a single ic-wasm-<triple>/ directory with the `ic-wasm`
  # binary, which stdenv's unpack descends into.
  src = fetchurl {
    url = "https://github.com/dfinity/ic-wasm/releases/download/${finalAttrs.version}/ic-wasm-${platform.triple}.tar.xz";
    hash = platform.hash;
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

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Internet Computer canister Wasm transformer (prebuilt release binary)";
    homepage = "https://github.com/dfinity/ic-wasm";
    changelog = "https://github.com/dfinity/ic-wasm/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "ic-wasm";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
