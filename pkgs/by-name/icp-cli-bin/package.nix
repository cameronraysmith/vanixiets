# icp-cli-bin: prebuilt release binaries for icp-cli, the Internet Computer
# CLI (`icp`) that the dfinity/icskills skills drive. Nix pins it in place of
# the withheld autoupgrade-icp-cli skill, which curl-upgrades the binary from a
# SessionStart hook. nixpkgs carries no icp-cli.
#
# A proxy over upstream's cargo-dist release artifacts rather than a source
# build, as for mergify-cli-bin.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dbus,
  zlib,
  versionCheckHook,
}:

let
  inherit (stdenv.hostPlatform) system;
  # Hashes are the release's per-asset .sha256 files converted to SRI, not
  # values guessed by a prefetch.
  systemToPlatform = {
    "x86_64-linux" = {
      triple = "x86_64-unknown-linux-gnu";
      hash = "sha256-XJq6C9Z2RQIneTh/ONI6UdFYYkGWzk66F1rroGXrIic=";
    };
    "aarch64-linux" = {
      triple = "aarch64-unknown-linux-gnu";
      hash = "sha256-UX5JRlIH5flwdF0D/s1oPJnuAiC8/wIhkpPqiIp8SgY=";
    };
    "x86_64-darwin" = {
      triple = "x86_64-apple-darwin";
      hash = "sha256-lsLxvEfICsrmy4RyYjGKCNDYjpIi1BzTnzymQGaiYBQ=";
    };
    "aarch64-darwin" = {
      triple = "aarch64-apple-darwin";
      hash = "sha256-PHIVbyDNIbjlFZn/NLSW8D60AJPfTt3zdOurOMjDZD0=";
    };
  };
  platform = systemToPlatform.${system} or (throw "icp-cli-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "icp-cli-bin";
  # Upstream tags carry a `v` prefix; the version here does not.
  version = "1.8.0";

  # Each archive holds a single icp-cli-<triple>/ directory with the `icp`
  # binary, which stdenv's unpack descends into.
  src = fetchurl {
    url = "https://github.com/dfinity/icp-cli/releases/download/v${finalAttrs.version}/icp-cli-${platform.triple}.tar.xz";
    hash = platform.hash;
  };

  dontConfigure = true;
  dontBuild = true;

  # Required, not defensive: the Linux artifacts are glibc-dynamic PIEs
  # (NEEDED: libz.so.1, libdbus-1.so.3, libgcc_s.so.1, libm.so.6, libc.so.6).
  # Darwin artifacts need no patching.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
    dbus # libdbus-1.so.3
    zlib # libz.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 icp $out/bin/icp
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/icp";
  doInstallCheck = true;

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Internet Computer CLI for building and deploying canisters (prebuilt release binary)";
    homepage = "https://github.com/dfinity/icp-cli";
    changelog = "https://github.com/dfinity/icp-cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    mainProgram = "icp";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
})
