{
  lib,
  buildNpmPackage,
  fetchurl,
  jq,
  nodejs_22,
  runCommand,
}:

let
  version = "0.2.6";

  # The npm registry tarball carries the built dist/ tree but no lockfile, and
  # the GitHub repo carries a pnpm-lock.yaml that buildNpmPackage cannot read.
  # Splice in a package-lock.json generated from the published package.json with
  # devDependencies removed, so `npm ci` resolves runtime deps only. The scripts
  # block goes too: npmInstallHook's `npm pack` fires prepack/prepare, which run
  # `tsc` against a src/ tree the registry tarball does not ship, and npm 10
  # runs `prepare` even under --ignore-scripts.
  src = runCommand "tasks-axi-source-${version}" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/tasks-axi/-/tasks-axi-${version}.tgz";
        hash = "sha256-kzQv5sga9RZpvYonP56ImjY0KISHc8yQe64fcak5Cdk=";
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies, .scripts)' $out/package.json > $out/package.json.stripped
    mv $out/package.json.stripped $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "tasks-axi";
  inherit version src;

  nodejs = nodejs_22;

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-N9bIdO9/lrRBqkVLpClUNgkwel7xVr7/1plBunk8lh8=";

  makeCacheWritable = true;

  dontNpmBuild = true;

  passthru.updateScript = ./update.sh;

  meta = {
    description = "Agent-ergonomic CLI for task and backlog management with pluggable backends";
    homepage = "https://github.com/kunchenguid/tasks-axi";
    changelog = "https://github.com/kunchenguid/tasks-axi/releases/tag/v${version}";
    downloadPage = "https://www.npmjs.com/package/tasks-axi";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "tasks-axi";
    platforms = lib.platforms.unix;
  };
}
