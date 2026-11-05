# perses-bin - upstream Perses release binaries with the plugin archives the
# release tag pins (scripts/plugin/plugin.yaml). nixpkgs carries 0.54.0, whose
# advisories 0.55.0 fixes; 0.55.1 adds further security fixes. sources.json
# holds the version, the release checksums file's hashes in SRI form and the
# plugin pins; update.sh rewrites all three together.
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
  sources = lib.importJSON ./sources.json;
  systemToAsset = {
    "x86_64-linux" = "linux_amd64";
    "aarch64-darwin" = "darwin_arm64";
  };
  inherit (stdenv.hostPlatform) system;
in
if !(systemToAsset ? ${system}) then
  null
else
  stdenv.mkDerivation (finalAttrs: {
    pname = "perses-bin";
    inherit (sources) version;

    src = fetchurl {
      url = "https://github.com/perses/perses/releases/download/v${finalAttrs.version}/perses_${finalAttrs.version}_${systemToAsset.${system}}.tar.gz";
      hash = sources.hashes.${system};
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

    # The tag's plugin.yaml and the tarball's plugins-archive are published
    # independently; each pinned archive must be present and no other.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      expected=$(printf '%s\n' ${
        lib.escapeShellArgs (lib.mapAttrsToList (n: v: "${n}-${v}.tar.gz") finalAttrs.passthru.plugins)
      } | sort)
      actual=$(ls $out/share/perses/plugins-archive | sort)
      if [ "$expected" != "$actual" ]; then
        echo "perses-bin: installed archives differ from passthru.plugins"
        diff <(echo "$expected") <(echo "$actual")
        exit 1
      fi
      runHook postInstallCheck
    '';
    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgram = "${placeholder "out"}/bin/percli";
    versionCheckProgramArg = "version";

    passthru = {
      inherit (sources) plugins;
      # finalPackage, not placeholder "out": consumers outside this build need
      # the real store path.
      pluginsArchive = "${finalAttrs.finalPackage}/share/perses/plugins-archive";
      updateScript = ./update.sh;
    };

    meta = {
      description = "Perses dashboard server and percli (upstream release binaries with the tag's plugin archives)";
      homepage = "https://perses.dev/";
      changelog = "https://github.com/perses/perses/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.asl20;
      mainProgram = "perses";
      platforms = lib.attrNames systemToAsset;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  })
