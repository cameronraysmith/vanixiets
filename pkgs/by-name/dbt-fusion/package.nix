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
      hash = "sha256-ZGEaODSDg+roakg0YRz8eG+WzbyQf735OCXFVg0gwZc=";
    };
    "aarch64-linux" = {
      name = "aarch64-unknown-linux-gnu";
      hash = "sha256-57iF2oEQkN+IYxuHkWdr7TGVO6xlMqf6DD+94WRaV60=";
    };
    "x86_64-darwin" = {
      name = "x86_64-apple-darwin";
      hash = "sha256-2+bf5n76s/Iml3nJVtCWWGbOp+iUWTg7bb5+ijNrr6A=";
    };
    "aarch64-darwin" = {
      name = "aarch64-apple-darwin";
      hash = "sha256-H/jpQhScnELgomQZ8pTDKT5QC4QmTMuVof+bZYXIjds=";
    };
  };
  platform = systemToPlatform.${system} or (throw "dbt-fusion: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "dbt-fusion";
  version = "2.0.6";

  src = fetchurl {
    url = "https://public.cdn.getdbt.com/fs/cli/fs-v${finalAttrs.version}-${platform.name}.tar.gz";
    inherit (platform) hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -m755 -D dbt $out/bin/dbtf
    runHook postInstall
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Next-generation engine for dbt";
    longDescription = ''
      dbt Fusion is the next-generation dbt CLI offering faster execution
      and enhanced capabilities for data transformation workflows.
      The language server ships inside the CLI as `dbtf lsp`; upstream no
      longer publishes a standalone dbt-lsp artifact.
    '';
    homepage = "https://github.com/dbt-labs/dbt-fusion";
    changelog = "https://github.com/dbt-labs/dbt-fusion/blob/main/CHANGELOG.md";
    license = lib.licenses.elastic20;
    mainProgram = "dbtf";
    platforms = lib.attrNames systemToPlatform;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
