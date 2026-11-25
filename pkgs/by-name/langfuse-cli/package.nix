# The official Langfuse CLI (`langfuse api <resource> <action>`), from the npm
# registry tarball: it carries the bundled dist/cli.js and the compiled API
# contracts, and has no runtime dependencies, so it needs no lockfile and no
# build, only node.
#
# modules/apps/langfuse-query wraps it with a read-only allow-list; on its own
# it can call every write and delete operation the key permits.
#
# pin.json pins the version and the tarball's hash; Renovate proposes releases
# from the npm registry and `nix run .#realize-pin -- langfuse-cli <version>`
# realizes one. A new version can change the API contracts, so review the
# allow-list in modules/apps/langfuse-query.sh against them; the
# langfuse-query check builds from this package's contracts.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs_22,
  versionCheckHook,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "langfuse-cli"; })
    pin
    pinPlan
    ;
  planned = pinPlan pin.version;
in
stdenvNoCC.mkDerivation {
  pname = "langfuse-cli";
  inherit (pin) version;

  # The registry records only sha512 and sha1 digests of the tarball, so
  # pin.json's `tarball` hash is a prefetch of it.
  src = fetchurl {
    inherit (planned.artifacts.tarball.file) url;
    inherit (pin.artifacts.tarball.file) hash;
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/langfuse-cli
    cp -r bin dist package.json $out/lib/langfuse-cli/
    makeWrapper ${lib.getExe nodejs_22} $out/bin/langfuse \
      --add-flags $out/lib/langfuse-cli/bin/langfuse.mjs
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;

  passthru = {
    inherit pin pinPlan;
  };

  meta = {
    description = "Interact with the Langfuse API from the command line";
    homepage = "https://github.com/langfuse/langfuse-cli";
    changelog = "https://github.com/langfuse/langfuse-cli/releases/tag/v${pin.version}";
    downloadPage = "https://www.npmjs.com/package/@langfuse/cli";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "langfuse";
    platforms = lib.platforms.unix;
  };
}
