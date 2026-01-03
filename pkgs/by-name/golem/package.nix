{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  rustPlatform,

  # nativeBuildInputs
  pkg-config,
  protobuf,

  # buildInputs
  fontconfig,
  openssl,

  redis,
  versionCheckHook,
  nix-update-script,
}:

let
  # Pre-fetch rusty_v8 static library that the v8 crate tries to download at build time
  # using the v8 crate version from Cargo.lock
  librusty_v8 = fetchurl {
    name = "librusty_v8-0.106.0";
    url = "https://github.com/denoland/rusty_v8/releases/download/v0.106.0/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a.gz";
    hash =
      {
        x86_64-linux = "sha256-jLYl/CJp2Z+Ut6qZlh6u+CtR8KN+ToNTB+72QnVbIKM=";
        aarch64-linux = "sha256-uAkBMg6JXA+aILd8TzDtuaEdM3Axiw43Ad5tZzxNt5w=";
        x86_64-darwin = "sha256-60aR0YvQT8KyacY8J3fWKZcf9vny51VUB19NVpurS/A=";
        aarch64-darwin = "sha256-pd/I6Mclj2/r/uJTIywnolPKYzeLu1c28d/6D56vkzQ=";
      }
      .${stdenv.hostPlatform.system} or (throw "Unsupported platform for librusty_v8");
    meta.sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };

  # Pre-fetch moonbit-wasm archive that moonbit-component-generator tries to download at build time
  # Version must match ARCHIVE_URL in moonbit-component-generator build.rs
  moonbitWasm = fetchurl {
    name = "moonbit-wasm-0.6.32.tar.gz";
    url = "https://github.com/moonbitlang/moonbit-compiler/releases/download/v0.6.32%2B6f48aae3f/moonbit-wasm.tar.gz";
    hash = "sha256-1z8ALklgWwo/0Wh+N0D7inUbhA3C7nImKOIIEXcTgEs=";
  };
in
rustPlatform.buildRustPackage rec {
  pname = "golem";
  version = "1.4.3";

  src = fetchFromGitHub {
    owner = "golemcloud";
    repo = "golem";
    tag = "v${version}";
    hash = "sha256-p8QeYFvs8uUoheUMI7j3RMv9vkc2yPxTBgEvw5yQn1g=";
  };

  patches = [
    ./fix-shadow-rs-nix-sandbox.patch
  ];

  # Replace placeholder version in Cargo.toml files
  # Ref: https://github.com/golemcloud/golem/blob/v1.4.3/Makefile.toml#L399
  postPatch = ''
    grep -rl --include 'Cargo.toml' '0\.0\.0' | xargs sed -i "s/0\.0\.0/${version}/g"

    # Patch moonbit-component-generator build.rs to use pre-fetched archive
    # instead of downloading from GitHub (blocked in Nix sandbox on Linux)
    for dir in $cargoDepsCopy/moonbit-component-generator-*/; do
      echo "Patching moonbit-component-generator in $dir for Nix sandbox..."
      patch -d "$dir" -p1 < ${./moonbit-nix-sandbox.patch}
    done
  '';

  nativeBuildInputs = [
    pkg-config
    protobuf
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    fontconfig
    (lib.getDev openssl)
  ];

  # Skip shadow-rs git describe in sandbox (falls back to version from Cargo.toml)
  GOLEM_BUILD_SKIP_SHADOW = "true";

  # Pre-downloaded V8 static library to avoid network access during build
  RUSTY_V8_ARCHIVE = librusty_v8;

  # Pre-downloaded moonbit-wasm archive to avoid network access during build
  MOONBIT_WASM_ARCHIVE = moonbitWasm;

  cargoHash = "sha256-WMeSVedrX1ADRcuv0vtGUvr/cHELgV8wy/onnM+JPUA=";

  # Tests are failing in the sandbox because of some redis integration tests
  doCheck = false;
  checkInputs = [ redis ];

  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  versionCheckProgram = [ "${placeholder "out"}/bin/golem-cli" ];
  doInstallCheck = true;

  passthru = {
    updateScript = nix-update-script { };
    inherit librusty_v8 moonbitWasm;
  };

  meta = {
    description = "Open source durable computing platform that makes it easy to build and deploy highly reliable distributed systems";
    changelog = "https://github.com/golemcloud/golem/releases/tag/${src.tag}";
    homepage = "https://www.golem.cloud/";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ kmatasfp ];
    mainProgram = "golem-cli";
    # Limited to platforms with pre-built librusty_v8
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    # Skip CI builds - V8 compilation requires more disk/memory than CI runners provide
    # Manual builds work fine: nix build .#golem
    hydraPlatforms = [ ];
  };
}
