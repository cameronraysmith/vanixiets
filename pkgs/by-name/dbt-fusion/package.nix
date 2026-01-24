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
      dbtHash = "sha256-2zuFr9xQVO1IH+W6knkGuLvPnDjr1r3mIZdEViyJSMw=";
      lspHash = "sha256-dxQdbjzgSkcksOMv/XwEwqD2FMamgGNf1rT7LtnWhws=";
    };
    "aarch64-linux" = {
      name = "aarch64-unknown-linux-gnu";
      dbtHash = "sha256-psVDdcSutI/8ceA7qDKVrmcGRnYbc9XgdCbBmLkqLH8=";
      lspHash = "sha256-93bk3zooHAmKvDXNtTqL+lY5EoNdhP2p9mGk6Is6e+g=";
    };
    "x86_64-darwin" = {
      name = "x86_64-apple-darwin";
      dbtHash = "sha256-HAqHVPw/F6/wiSbMsUbometO0ziwgEuRiANizpyaAyg=";
      lspHash = "sha256-82YVGXZGTAn19UodZWq9LGY/aYoyzg0Q3OeeNUbNUhE=";
    };
    "aarch64-darwin" = {
      name = "aarch64-apple-darwin";
      dbtHash = "sha256-IMILI/iFQ8nGagdTn510ZPsNHhrBDBXBZOTbPkox8jY=";
      lspHash = "sha256-F72H24DSGG2Rb9pR42TDdIJkQjTYVR1jUHj1JilKlmw=";
    };
  };
  platform = systemToPlatform.${system} or (throw "dbt-fusion: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "dbt-fusion";
  version = "2.0.0-preview.96";

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
