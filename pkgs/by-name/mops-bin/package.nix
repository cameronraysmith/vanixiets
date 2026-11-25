# mops-bin: the Motoko package manager CLI (`mops`) from upstream's prebuilt
# release bundle. The icp-cli `@dfinity/motoko` recipe shells out to mops,
# which in turn downloads the moc and pocket-ic versions a project pins in its
# mops.toml [toolchain], so neither is packaged here. nixpkgs carries no mops.
#
# cli.tgz holds bundle/: cli.js with every npm dependency inlined, bin/mops.js
# importing it, the .wasm modules, declarations/ and templates/ cli.js reads
# at runtime. The declared `buffer` dependency is not shipped and not needed:
# its one bare `buffer` import resolves to node's builtin module. No build,
# only node (package.json engines: >=22).
#
# pin.json pins the version and cli.tgz's hash; Renovate proposes releases
# from the cli-v* GitHub releases and `nix run .#realize-pin -- mops-bin
# <version>` realizes one.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs_22,
  versionCheckHook,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "mops-bin"; })
    pin
    pinPlan
    ;
  planned = pinPlan pin.version;
in
stdenvNoCC.mkDerivation {
  pname = "mops-bin";
  inherit (pin) version;

  # The release publishes no checksum file, so pin.json's `cli` hash is a
  # prefetch of the asset; it equals the sha256 digest GitHub records for it.
  src = fetchurl {
    inherit (planned.artifacts.cli.file) url;
    inherit (pin.artifacts.cli.file) hash;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  # package.json maps both `mops` and `ic-mops` to bin/mops.js.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/mops-bin
    cp -r . $out/lib/mops-bin/
    for bin in mops ic-mops; do
      makeWrapper ${lib.getExe nodejs_22} $out/bin/$bin \
        --add-flags $out/lib/mops-bin/bin/mops.js
    done
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/mops";
  doInstallCheck = true;

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "Motoko package manager CLI (upstream prebuilt bundle)";
    homepage = "https://mops.one";
    changelog = "https://github.com/caffeinelabs/mops/releases/tag/${planned.tag}";
    license = lib.licenses.mit;
    mainProgram = "mops";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    # cli.js is a minified bundle and the .wasm modules are compiled code.
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    maintainers = with lib.maintainers; [ cameronraysmith ];
  };
}
