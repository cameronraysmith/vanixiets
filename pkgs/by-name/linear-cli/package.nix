# Upstream release binaries: 3.0 rewrote the CLI in Rust, replacing the Deno
# source build. This trusts upstream's release artifacts rather than building
# from source.
{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  autoPatchelfHook,
  versionCheckHook,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "linear-cli"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "linear-cli";
  inherit (pin) version;

  src = finalAttrs.passthru.sources.${stdenv.hostPlatform.system};

  dontConfigure = true;
  dontBuild = true;
  # The darwin binary carries an ad-hoc linker signature that stripping would
  # invalidate.
  dontStrip = true;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libgcc_s.so.1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 linear $out/bin/linear
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    inherit pin pinPlan;
    sources = lib.mapAttrs (
      system: artifact:
      fetchurl {
        inherit (artifact) url;
        hash = pin.artifacts.binaries.platformBinaries.hashes.${system};
      }
    ) planned.binaries.platformBinaries;
    # The release archives carry only the executable; the upstream agent skill
    # (flake.lib.linearSkills, apm-skills-compose) comes from the tagged tree.
    # It is fetched at the pin's `rev`, the tag commit, rather than at the
    # planned tag: structure-release-alignment-linear-cli compares `skillSrc.rev`
    # with the apm.yml ref, which realize-pin keeps equal to `rev` through the
    # pin's apmRef companion.
    skillSrc = fetchFromGitHub {
      inherit (planned.skillSrc.sourceBuild.fetchFromGitHub) owner repo;
      inherit (pin) rev;
      inherit (pin.artifacts.skillSrc.sourceBuild) hash;
    };
  };

  meta = {
    description = "Manage Linear issues from the command line";
    homepage = "https://github.com/schpet/linear-cli";
    changelog = "https://github.com/schpet/linear-cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.isc;
    mainProgram = "linear";
    platforms = builtins.attrNames finalAttrs.passthru.sources;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
