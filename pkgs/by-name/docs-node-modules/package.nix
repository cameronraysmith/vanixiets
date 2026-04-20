{
  inputs,
  lib,
  stdenv,
  ...
}:
let
  bun2nix = inputs.bun2nix.packages.${stdenv.system}.default;
in
stdenv.mkDerivation {
  pname = "docs-node-modules";
  version = "0.0.0";

  src = lib.fileset.toSource {
    root = ../../..;
    fileset = lib.fileset.unions [
      ../../../package.json
      ../../../bun.lock
      ../../../bun.nix
      ../../../packages/docs/package.json
    ];
  };

  nativeBuildInputs = [ bun2nix.hook ];

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ../../../bun.nix;
  };

  # Skip lifecycle (postinstall) scripts. semantic-release, its @semantic-release/*
  # plugins, semantic-release-monorepo, and semantic-release-major-tag are pure JS
  # — none require a postinstall native build.
  dontRunLifecycleScripts = true;

  # The bun2nix hook materialises node_modules via bunNodeModulesInstallPhase
  # using the default --linker=isolated layout. That layout places real packages
  # under the monorepo-root node_modules/.bun/ and links direct deps (including
  # workspace-visible dev deps) into the monorepo-root node_modules/ via relative
  # symlinks. Preserving the symlink structure (plain cp -R) keeps Node.js module
  # resolution intact for tools invoked via node_modules/.bin/.
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R node_modules $out/node_modules
    runHook postInstall
  '';

  meta = {
    description = "Hermetic node_modules tree for packages/docs (semantic-release runtime)";
    license = lib.licenses.mit;
  };
}
