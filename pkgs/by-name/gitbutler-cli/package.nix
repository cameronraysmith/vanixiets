# gitbutler-cli - the `but` CLI for GitButler
#
# Builds only the `but` binary from the gitbutler workspace,
# without the Tauri desktop application or frontend assets.
#
# Source: https://github.com/gitbutlerapp/gitbutler
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
rustPlatform.buildRustPackage {
  pname = "gitbutler-cli";
  version = "0.19.1";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    rev = "release/0.19.1";
    hash = "sha256-ZCjlN8DF/l1v4AHk2CPB8VcaSuRLVIuOWPUfSn59LiE=";
  };

  # Use importCargoLock (via cargoLock) instead of fetchCargoVendor (via
  # cargoHash) to bypass two Linux-specific fetchCargoVendor bugs:
  #   1. Python wrapper bug: python3.withPackages binary wrapper fails to
  #      find the requests module on x86_64-linux.
  #   2. File collision bug: create-vendor tries to copy file-id-0.2.3
  #      twice from different sources, causing FileExistsError.
  #
  # The lockfile is pre-patched to deduplicate file-id and gix-trace
  # entries that appeared from both crates.io and git sources.
  # cargoPatches applies the same deduplication to the source Cargo.lock
  # so it matches the pre-patched ./Cargo.lock used for vendoring.
  cargoPatches = [ ./deduplicate-vendor-sources.patch ];

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "gix-0.78.0" = "sha256-q1401HbPAPg0AsmhVCnRMLLWVTvbWz8otoK1QeIOQGw=";
      "claude-agent-sdk-rs-0.6.3" = "sha256-v9Jv+NRCrpkRukLX81OrWHSfFlAV+4M90ybUyu82aW8=";
      "tauri-plugin-trafficlights-positioner-1.0.1" =
        "sha256-4VjU7Vf+zznk7qqyaum+bLuslVNxeGSoxDPz8QQp0pk=";
      "file-id-0.2.3" = "sha256-QjLAL4j0l+NK0wdKQ6RGpo0ZhLEW8qvhxSQq0rtvNFc=";
    };
  };

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
    changelog = "https://github.com/gitbutlerapp/gitbutler/releases/tag/release/0.19.1";
    license = lib.licenses.fsl11Mit;
    mainProgram = "but";
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
}
