# credit to mirkolenz' derivation for installing the prebuilt binary
# https://github.com/NixOS/nixpkgs/pull/447265
# https://github.com/mirkolenz/nixos/tree/main/pkgs/derivations/claude-code-bin
#
# fetches platform-specific binaries from the official gcs release bucket.
# version and SRI hashes tracked in pin.json alongside this file.
#
# update: nix run .#update-claude-code
# source: https://github.com/anthropics/claude-code
{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  makeBinaryWrapper,
  installShellFiles,
  bubblewrap,
  socat,
  procps,
  ripgrep,
}:
let
  inherit (stdenvNoCC.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "claude-code"; })
    pin
    pinPlan
    ;
  binary = pin.artifacts.binary.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binary.platformBinaries;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "claude-code";
  inherit (pin) version;

  src = fetchurl {
    url = planned.${system}.url or (throw "claude-code: unsupported platform ${system}");
    hash = binary.hashes.${system};
  };

  dontUnpack = true;
  dontBuild = true;
  __noChroot = stdenvNoCC.hostPlatform.isDarwin;

  # otherwise the bun runtime is executed instead of the binary (on linux)
  dontStrip = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isElf [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall

    installBin $src
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            procps
            ripgrep
          ]
          ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }

    runHook postInstall
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  doInstallCheck = true;

  strictDeps = true;

  passthru = {
    inherit pin pinPlan;
    updateScript = ./update.sh;
  };

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://claude.com/product/claude-code";
    changelog = "https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "claude";
    platforms = lib.attrNames binary.platforms;
  };
})
