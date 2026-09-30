{
  lib,
  buildNpmPackage,
  fetchurl,
  jq,
  makeWrapper,
  nodejs_22,
  runCommand,
}:

let
  version = "0.1.36";

  # The npm registry tarball carries the built dist/ tree but no lockfile, and
  # the GitHub repo carries a pnpm-lock.yaml that buildNpmPackage cannot read.
  # Splice in a package-lock.json generated from the published package.json with
  # devDependencies removed, so `npm ci` resolves runtime deps only. The scripts
  # block goes too: npmInstallHook's `npm pack` fires prepack/prepare, which run
  # `tsc` against a src/ tree the registry tarball does not ship, and npm 10
  # runs `prepare` even under --ignore-scripts.
  src = runCommand "chrome-devtools-axi-source-${version}" { nativeBuildInputs = [ jq ]; } ''
    mkdir -p $out
    tar -xzf ${
      fetchurl {
        url = "https://registry.npmjs.org/chrome-devtools-axi/-/chrome-devtools-axi-${version}.tgz";
        hash = "sha256-NbcygFwcRRdDx2jnwqGNFUKUqYI6lWS8mGBqVKRa+KY=";
      }
    } -C $out --strip-components=1
    jq 'del(.devDependencies, .scripts)' $out/package.json > $out/package.json.stripped
    mv $out/package.json.stripped $out/package.json
    cp ${./package-lock.json} $out/package-lock.json
  '';
in
buildNpmPackage {
  pname = "chrome-devtools-axi";
  inherit version src;

  nodejs = nodejs_22;

  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-rYv7X3C4OQr2PbUO0RNaCRIIRpHzqVi/0nxfgE619i0=";

  makeCacheWritable = true;

  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # dist/src/client.js spawns the bridge with `npx -y chrome-devtools-mcp@latest`
  # unless CHROME_DEVTOOLS_AXI_MCP_PATH overrides it, so npx must be on PATH
  # independently of whatever node the caller happens to have.
  postInstall = ''
    wrapProgram $out/bin/chrome-devtools-axi \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}
  '';

  passthru.updateScript = ./update.sh;

  meta = {
    description = "AXI-compliant chrome-devtools-mcp wrapper with combined operations and TOON output";
    homepage = "https://github.com/kunchenguid/chrome-devtools-axi";
    changelog = "https://github.com/kunchenguid/chrome-devtools-axi/releases/tag/chrome-devtools-axi-v${version}";
    downloadPage = "https://www.npmjs.com/package/chrome-devtools-axi";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    mainProgram = "chrome-devtools-axi";
    platforms = lib.platforms.unix;
  };
}
