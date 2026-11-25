# Devin CLI, vendored from nixpkgs pkgs/by-name/de/devin-cli.
#
# The derivation body is upstream's apart from reading its version and hashes
# from pin.json. It lives here because the pinned nixpkgs channel carries
# 3000.3.22 while the Outposts worker surface this repository declares
# (`services.devin-worker`) is documented against the 3000.6 CLI.
# modules/nixpkgs/compose.nix merges the by-name set into
# flake.overlays.default after the channel overlays, so this attribute shadows
# the channel's `devin-cli` on every machine and moves independently of the
# channel bump.
#
# The pin's source is the vendor's current/manifest.json, which names the
# latest version. Each release has its own <version>/manifest.json carrying
# the sha256 of every platform's tarball, which realize-pin reads rather than
# re-hashing downloads. Superseded releases can disappear: on 2026-11-25, with
# 3000.14.30821 current, 3000.11.3's tarballs and manifest answered 403, so an
# older pinned version builds only from a store or cache holding its sources.
#
# update: nix run .#realize-pin -- devin-cli <version>
{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  versionCheckHook,
}:

let
  inherit (stdenvNoCC.hostPlatform) system;
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "devin-cli"; })
    pin
    pinPlan
    ;
  binary = pin.artifacts.binary.platformBinaries;
  planned = (pinPlan pin.version).artifacts.binary.platformBinaries;
in

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "devin-cli";
  inherit (pin) version;

  outputs = [
    "out"
    "man"
    "doc"
  ];

  strictDeps = true;
  __structuredAttrs = true;

  src = fetchurl {
    url = planned.${system}.url or (throw "devin-cli: unsupported platform ${system}");
    hash = binary.hashes.${system};
  };

  sourceRoot = ".";

  nativeBuildInputs = [ installShellFiles ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    installBin ./bin/devin
    installManPage ./share/man/man1/*.1

    mkdir -p $out/share/doc

    mv ./share/devin/docs/* $out/share/doc

    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = { inherit pin pinPlan; };

  meta = {
    description = "Cognition's Devin Agent CLI";
    homepage = "https://devin.ai/cli";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = with lib.maintainers; [
      ethancedwards8
      nhshah15
    ];
    mainProgram = "devin";
    platforms = lib.attrNames binary.platforms;
  };
})
