{
  lib,
  buildNpmPackage,
  fetchurl,
  jq,
  nodejs_22,
  runCommand,
}:

let
  version = "0.1.80";

  # The npm registry tarball carries the built dist/ tree but no lockfile, and
  # the GitHub repo carries a pnpm-lock.yaml that buildNpmPackage cannot read.
  # Splice in a package-lock.json generated from the published package.json with
  # devDependencies removed, so `npm ci` resolves runtime deps only. The scripts
  # block goes too: npmInstallHook's `npm pack` fires prepack/prepare, which run
  # `tsc` against a src/ tree the registry tarball does not ship, and npm 10
  # runs `prepare` even under --ignore-scripts.
  src = runCommand "lavish-axi-source-${version}" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/lavish-axi/-/lavish-axi-${version}.tgz";
        hash = "sha256-NOGOrEkheTuAxHTXojBxwJhx9ZhsMa2KwRy1x0HVT74=";
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies, .scripts)' $out/package.json > $out/package.json.stripped
    mv $out/package.json.stripped $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "lavish-axi";
  inherit version src;

  nodejs = nodejs_22;

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-1L4m0j4tk+82aHEFPQupfruvWhIx8yNqBJ7rLLz3G0U=";

  makeCacheWritable = true;

  dontNpmBuild = true;

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Editor and live preview server for HTML artifacts produced by agents";
    homepage = "https://github.com/kunchenguid/lavish-axi";
    changelog = "https://github.com/kunchenguid/lavish-axi/releases/tag/v${version}";
    downloadPage = "https://www.npmjs.com/package/lavish-axi";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "lavish-axi";
    platforms = lib.platforms.unix;
  };
}
