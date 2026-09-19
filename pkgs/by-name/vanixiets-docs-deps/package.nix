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
  pname = "vanixiets-docs-deps";
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
    # bun.nix registers the workspace's own package as a cache entry sourced
    # from the whole ./packages/docs tree, so every documentation content edit
    # changed the bun cache and forced all of bun2nix's non-substitutable
    # per-package derivations to rebuild. bun only needs the manifest to
    # resolve the workspace entry, and the override's argument is deliberately
    # discarded so the content tree leaves the dependency graph entirely.
    overrides."@vanixiets/docs" =
      _:
      lib.fileset.toSource {
        root = ../../../packages/docs;
        fileset = ../../../packages/docs/package.json;
      };
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
    if [ ! -d packages/docs/node_modules ]; then
      echo "error: packages/docs/node_modules not populated by bun install; aborting" >&2
      exit 1
    fi
    mkdir -p $out/packages/docs
    cp -R node_modules $out/node_modules
    cp -R packages/docs/node_modules $out/packages/docs/node_modules
    runHook postInstall
  '';

  meta = {
    description = "Hermetic node_modules tree for packages/docs (semantic-release runtime)";
    license = lib.licenses.mit;
  };
}
