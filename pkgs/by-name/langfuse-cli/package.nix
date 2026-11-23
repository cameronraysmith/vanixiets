# The official Langfuse CLI (`langfuse api <resource> <action>`), from the npm
# registry tarball: it carries the bundled dist/cli.js and the compiled API
# contracts, and has no runtime dependencies, so it needs no lockfile and no
# build, only node.
#
# modules/apps/langfuse-query wraps it with a read-only allow-list; on its own
# it can call every write and delete operation the key permits.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs_22,
  versionCheckHook,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "langfuse-cli";
  version = "1.4.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@langfuse/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha256-gzEsfy4MsIn6fAWm4HUvnoAIclQABREDJcMnSoCRA78=";
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

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Interact with the Langfuse API from the command line";
    homepage = "https://github.com/langfuse/langfuse-cli";
    changelog = "https://github.com/langfuse/langfuse-cli/releases/tag/v${finalAttrs.version}";
    downloadPage = "https://www.npmjs.com/package/@langfuse/cli";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "langfuse";
    platforms = lib.platforms.unix;
  };
})
