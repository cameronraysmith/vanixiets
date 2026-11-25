# perses-bin - upstream Perses release binaries with the plugin archives the
# release tarball ships in plugins-archive. nixpkgs carries 0.54.0, whose
# advisories 0.55.0 fixes; 0.55.1 adds further security fixes. pin.json holds
# the version and the release checksums file's hashes; realize-pin rewrites
# them per version.
#
# Only x86_64-linux and aarch64-darwin are packaged. On other systems this file
# yields null, as pkgs/by-name/greptimedb-bin does, so the package and its
# package-* check are absent there rather than throwing at evaluation.
#
# Both Linux binaries are statically linked, so no autoPatchelfHook.
#
# Source: https://github.com/perses/perses
{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
}:
let
  inherit (stdenv.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "perses-bin"; })
    pin
    pinPlan
    ;
  binaries = pin.artifacts.binaries.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binaries.platformBinaries;
in
if !(planned ? ${system}) then
  null
else
  stdenv.mkDerivation (finalAttrs: {
    pname = "perses-bin";
    inherit (pin) version;

    src = fetchurl {
      inherit (planned.${system}) url;
      hash = binaries.hashes.${system};
    };

    # The tarball has no top-level directory.
    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 perses $out/bin/perses
      install -Dm755 percli $out/bin/percli
      mkdir -p $out/share/perses
      cp -r plugins-archive $out/share/perses/plugins-archive
      runHook postInstall
    '';

    # plugins-archive holds one <Name>-<version>.tar.gz per plugin; the
    # curated selection (modules/checks/perses-lint.nix) picks archives by
    # name, so no name may appear twice.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      names=$(ls $out/share/perses/plugins-archive | sed -n 's/^\(.*\)-[0-9][0-9.]*\.tar\.gz$/\1/p' | sort)
      [ -n "$names" ] || { echo "perses-bin: plugins-archive holds no plugin archive"; exit 1; }
      dups=$(uniq -d <<<"$names")
      [ -z "$dups" ] || { echo "perses-bin: plugins-archive holds more than one archive of: $dups"; exit 1; }
      runHook postInstallCheck
    '';
    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgram = "${placeholder "out"}/bin/percli";
    versionCheckProgramArg = "version";

    passthru = {
      inherit pin pinPlan;
      # finalPackage, not placeholder "out": consumers outside this build need
      # the real store path.
      pluginsArchive = "${finalAttrs.finalPackage}/share/perses/plugins-archive";
    };

    meta = {
      description = "Perses dashboard server and percli (upstream release binaries with the tag's plugin archives)";
      homepage = "https://perses.dev/";
      changelog = "https://github.com/perses/perses/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.asl20;
      mainProgram = "perses";
      platforms = lib.attrNames planned;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  })
