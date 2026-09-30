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
  # Hashes are the release's SHA256SUMS entries converted to SRI, not values
  # guessed by a prefetch: upstream publishes one hex line per asset.
  systemToPlatform = {
    "x86_64-linux" = {
      triple = "x86_64-unknown-linux-gnu";
      hash = "sha256-kH382b2ZvcQGF8DO5waumUFYKU7Ksorc6vQrNlKrshI=";
    };
    "aarch64-linux" = {
      triple = "aarch64-unknown-linux-gnu";
      hash = "sha256-3LQ+HnzWCoBmUHBzkp7Qj61g2NpGyZMzeAnTaGhOcc4=";
    };
    "x86_64-darwin" = {
      triple = "x86_64-apple-darwin";
      hash = "sha256-ODI9iZYNTYN4r9Stmj4opZoovDWD9ZhLs78/bUSXQRk=";
    };
    "aarch64-darwin" = {
      triple = "aarch64-apple-darwin";
      hash = "sha256-oPoA+cDjOnJIQ5FUt8ijta3AqFnMG7uZRbHVfKx4h1c=";
    };
  };
  platform = systemToPlatform.${system} or (throw "mergify-cli-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "mergify-cli-bin";
  # Bare calver with no `v` prefix, matching the upstream tag exactly.
  version = "2026.9.16.1";

  src = fetchurl {
    url = "https://github.com/Mergifyio/mergify-cli/releases/download/${finalAttrs.version}/mergify-${finalAttrs.version}-${platform.triple}.tar.gz";
    hash = platform.hash;
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

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Mergify CLI for stacked pull requests and CI insights (prebuilt release binary)";
    homepage = "https://github.com/Mergifyio/mergify-cli";
    changelog = "https://github.com/Mergifyio/mergify-cli/releases/tag/${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "mergify";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
