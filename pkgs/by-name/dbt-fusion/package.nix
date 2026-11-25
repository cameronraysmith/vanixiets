# dbt-fusion - Next-generation engine for dbt
#
# dbt Fusion is the next-generation dbt CLI, offering faster execution
# and enhanced capabilities for data transformation workflows.
#
# This derivation uses pre-built binaries from dbt Labs CDN. pin.json follows
# the `latest` channel of the vendor's versions.json, and realize-pin reads each
# tarball's hash from the `.sha256` file published beside it.
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
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "dbt-fusion"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
stdenv.mkDerivation {
  pname = "dbt-fusion";
  inherit (pin) version;

  src = fetchurl {
    url = planned.${system}.url or (throw "dbt-fusion: unsupported platform ${system}");
    hash = binaries.hashes.${system};
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

  passthru = { inherit pin pinPlan; };

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
    platforms = lib.attrNames binaries.platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
