{
  lib,
  buildNpmPackage,
  fetchurl,
  jq,
  nodejs_22,
  runCommand,
}:

let
  version = "0.1.55";

  # The npm registry tarball carries the built dist/ tree but no lockfile, and
  # the GitHub repo carries a pnpm-lock.yaml that buildNpmPackage cannot read.
  # Splice in a package-lock.json generated from the published package.json with
  # devDependencies removed, so `npm ci` resolves runtime deps only. The scripts
  # block goes too: npmInstallHook's `npm pack` fires prepack/prepare, which run
  # `tsc` against a src/ tree the registry tarball does not ship, and npm 10
  # runs `prepare` even under --ignore-scripts.
  src = runCommand "quota-axi-source-${version}" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/quota-axi/-/quota-axi-${version}.tgz";
        hash = "sha256-0hgvH5/v4LQtS4rggaDpv61v/63SzEpCQRnLpiu4YTE=";
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies, .scripts)' $out/package.json > $out/package.json.stripped
    mv $out/package.json.stripped $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "quota-axi";
  inherit version src;

  nodejs = nodejs_22;

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-9Cd9vcmduY+A187D0u/V4aY3OEZQEmharIOlYZ36OF4=";

  makeCacheWritable = true;

  dontNpmBuild = true;

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Report LLM subscription quota windows to agents";
    homepage = "https://github.com/kunchenguid/quota-axi";
    changelog = "https://github.com/kunchenguid/quota-axi/releases/tag/v${version}";
    downloadPage = "https://www.npmjs.com/package/quota-axi";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "quota-axi";
    platforms = lib.platforms.unix;
  };
}
