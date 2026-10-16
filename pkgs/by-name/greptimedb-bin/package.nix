# greptimedb-bin - upstream GreptimeDB release binary with the embedded dashboard
#
# The upstream release tarball is built with the `servers/dashboard` feature and
# embeds GreptimeDB's Perses-based web dashboard, which the nixpkgs source build
# omits. `passthru.embedsDashboard` records that property where the store
# module's evaluation-time assertion (R1.1) reads it; `passthru.dashboardVersion`
# is src/servers/dashboard/VERSION at the release tag, without its leading `v`,
# and update.sh refreshes it with the version. The `-bin` pname keeps this
# package from shadowing `pkgs.greptimedb` through the overlay merge
# (modules/nixpkgs/compose.nix).
#
# Only x86_64-linux is packaged. On other systems this file yields null, so the
# package and its package-* check are absent there rather than throwing at
# evaluation (as pkgs/by-name/radicle-desktop does for its single platform).
#
# Source: https://github.com/GreptimeTeam/greptimedb
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
}:
if stdenv.hostPlatform.system != "x86_64-linux" then
  null
else
  stdenv.mkDerivation (finalAttrs: {
    pname = "greptimedb-bin";
    version = "1.2.1";

    src = finalAttrs.passthru.sources.${stdenv.hostPlatform.system};

    # The tarball unpacks to a single greptime-linux-amd64-v<version>/ directory
    # holding only the `greptime` executable; stdenv selects it as sourceRoot.
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [ autoPatchelfHook ];

    buildInputs = [
      stdenv.cc.cc.lib # libgcc_s.so.1
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 greptime $out/bin/greptime
      runHook postInstall
    '';

    # `greptime --version` prints clap's long version, which ends in the line
    # `version: <version>`.
    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgram = "${placeholder "out"}/bin/greptime";
    doInstallCheck = true;

    passthru = {
      sources = {
        "x86_64-linux" = fetchurl {
          url = "https://github.com/GreptimeTeam/greptimedb/releases/download/v${finalAttrs.version}/greptime-linux-amd64-v${finalAttrs.version}.tar.gz";
          hash = "sha256-Bi1b6xPeSZHE/sIBsuUHFRi/TKjw1SlH66dXp0wqVCA=";
        };
      };
      embedsDashboard = true;
      dashboardVersion = "0.13.13";
      updateScript = ./update.sh;
    };

    meta = {
      description = "Cloud-native time-series database (upstream release binary with the embedded dashboard)";
      homepage = "https://greptime.com/";
      changelog = "https://github.com/GreptimeTeam/greptimedb/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.asl20;
      mainProgram = "greptime";
      platforms = builtins.attrNames finalAttrs.passthru.sources;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  })
