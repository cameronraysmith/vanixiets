{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  cmake,
  perl,
  apple-sdk_15,
  curl,
  dbus,
  openssl,
  zlib,
  libiconv,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "gitbutler-cli";
  version = "0.19.1";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    tag = "release/${finalAttrs.version}";
    hash = "sha256-ZCjlN8DF/l1v4AHk2CPB8VcaSuRLVIuOWPUfSn59LiE=";
  };

  cargoPatches = [ ./deduplicate-vendor-sources.patch ];

  cargoHash = "sha256-F/x0S5Q+7VJ5mvmoITkAUx5ZYRncbFNpJPb0gKx1Hv8=";

  cargoBuildFlags = [ "-p=but" ];

  env = {
    RUSTFLAGS = "--cfg tokio_unstable";
    CHANNEL = "release";
  };

  nativeBuildInputs = [
    pkg-config
    cmake
    perl
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    curl
    zlib
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    dbus
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15
    libiconv
  ];

  doCheck = false;

  meta = {
    homepage = "https://gitbutler.com";
    description = "Git client for simultaneous branches on top of your existing workflow";
    changelog = "https://github.com/gitbutlerapp/gitbutler/releases/tag/release/${finalAttrs.version}";
    license = lib.licenses.fsl11Mit;
    mainProgram = "but";
    maintainers = with lib.maintainers; [ cameronraysmith ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
