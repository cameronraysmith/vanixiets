# dbt-fusion - Next-generation engine for dbt
#
# dbt Fusion is the next-generation dbt CLI, offering faster execution
# and enhanced capabilities for data transformation workflows.
#
# This derivation uses pre-built binaries from dbt Labs CDN.
#
# Source: https://github.com/dbt-labs/dbt-fusion
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

let
  inherit (stdenv.hostPlatform) system;
  systemToPlatform = {
    "x86_64-linux" = {
      name = "x86_64-unknown-linux-gnu";
      dbtHash = "sha256-VlIwh/2mekekqJ+kiAvqlSFdnBTroDtO7xiiJld9hvY=";
      lspHash = "sha256-LbgL1eadWmwqIo9uE0bQln1nbwdgihRbMYvB+dQ0Kz4=";
    };
    "aarch64-linux" = {
      name = "aarch64-unknown-linux-gnu";
      dbtHash = "sha256-GMTwo0lBJVtGeOBTjsQ5B2u92fBy+DsJw2HS1Fgk2d0=";
      lspHash = "sha256-7MHW8R/LYbuyv8jPqaVSLohnEbqzntfgK9lmFgf/80c=";
    };
    "x86_64-darwin" = {
      name = "x86_64-apple-darwin";
      dbtHash = "sha256-iTVqA7Kj0Klci3TKq6U/MX/ovU9lrnOd6yqxyRX6hUk=";
      lspHash = "sha256-SuYtO8guYNCZ+zKD1/clwOgMuAb9gx4MmWh7flsOfJQ=";
    };
    "aarch64-darwin" = {
      name = "aarch64-apple-darwin";
      dbtHash = "sha256-CHrRfeqAIiHdZNBfpKgID4v+Ri6tPwWiaelPaPhdpLU=";
      lspHash = "sha256-KhzUtvTTg7Kj5gk8CBMs33zPpSFQjg669dZBcY3QLNs=";
    };
  };
  platform = systemToPlatform.${system} or (throw "dbt-fusion: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "dbt-fusion";
  version = "2.0.0-preview.101";

  srcs = [
    (fetchurl {
      url = "https://public.cdn.getdbt.com/fs/cli/fs-v${finalAttrs.version}-${platform.name}.tar.gz";
      hash = platform.dbtHash;
    })
    (fetchurl {
      url = "https://public.cdn.getdbt.com/fs/lsp/fs-lsp-v${finalAttrs.version}-${platform.name}.tar.gz";
      hash = platform.lspHash;
    })
  ];

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -m755 -D dbt $out/bin/dbtf
    install -m755 -D dbt-lsp $out/bin/dbt-lsp
    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Next-generation engine for dbt";
    longDescription = ''
      dbt Fusion is the next-generation dbt CLI offering faster execution
      and enhanced capabilities for data transformation workflows.
      Includes both the dbtf CLI and dbt-lsp language server.
    '';
    homepage = "https://github.com/dbt-labs/dbt-fusion";
    changelog = "https://github.com/dbt-labs/dbt-fusion/blob/main/CHANGELOG.md";
    license = lib.licenses.elastic20;
    mainProgram = "dbtf";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
