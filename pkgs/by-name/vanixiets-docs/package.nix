{
  inputs,
  lib,
  nodejs-slim,
  stdenv,
  ...
}:
let
  bun2nix = inputs.bun2nix.packages.${stdenv.system}.default;
  playwrightDriver = inputs.playwright-web-flake.packages.${stdenv.system}.playwright-driver;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "vanixiets-docs";
  version = "0.0.0-development";

  src = lib.fileset.toSource {
    root = ../../..;
    fileset = lib.fileset.unions [
      ../../../package.json
      ../../../bun.lock
      ../../../packages/docs
    ];
  };

  nativeBuildInputs = [
    bun2nix.hook
  ];

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ../../../bun.nix;
  };

  dontUseBunBuild = true;
  dontUseBunInstall = true;

  env = {
    # Skip cloudflare adapter for nix build (produces static output)
    PLAYWRIGHT = "true";
  };

  buildPhase = ''
    runHook preBuild
    cd packages/docs
    bun run build
    cd ../..
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R packages/docs/dist/* $out/
    runHook postInstall
  '';

  passthru.tests.unit = stdenv.mkDerivation {
    pname = "vanixiets-docs-unit";
    version = finalAttrs.version;
    inherit (finalAttrs) src;

    nativeBuildInputs = [
      bun2nix.hook
    ];

    bunDeps = finalAttrs.bunDeps;
    dontUseBunBuild = true;
    dontUseBunInstall = true;
    dontRunLifecycleScripts = true;

    buildPhase = ''
      runHook preBuild
      cd packages/docs
      bun run test:unit
      cd ../..
      runHook postBuild
    '';

    installPhase = ''
      touch $out
    '';

    meta.description = "Vitest unit tests for vanixiets-docs";
  };

  passthru.tests.e2e = stdenv.mkDerivation {
    pname = "vanixiets-docs-e2e";
    version = finalAttrs.version;
    inherit (finalAttrs) src;

    nativeBuildInputs = [
      bun2nix.hook
      nodejs-slim
    ];

    bunDeps = finalAttrs.bunDeps;
    dontUseBunBuild = true;
    dontUseBunInstall = true;
    dontRunLifecycleScripts = true;
    __darwinAllowLocalNetworking = true;

    env = {
      CI = "true";
      PLAYWRIGHT_BROWSERS_PATH = "${playwrightDriver.browsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    };

    buildPhase = ''
      runHook preBuild
      # Provide pre-built dist for the CI webServer (bun run preview:ci → serve dist).
      mkdir -p packages/docs/dist
      cp -r ${finalAttrs.finalPackage}/* packages/docs/dist/

      export PATH="$PWD/node_modules/.bin:$PATH"

      cd packages/docs
      # Run Playwright via node — bun's child_process.fork() IPC
      # is incompatible with Playwright's worker model.
      # CI=true: chromium-only projects, playwright manages webServer lifecycle via
      # playwright.config webServer command (bun run preview:ci → serve dist -l 4321).
      ${nodejs-slim}/bin/node ./node_modules/@playwright/test/cli.js test
      cd ../..

      runHook postBuild
    '';

    installPhase = ''
      touch $out
    '';

    meta.description = "Playwright E2E tests for vanixiets-docs";
  };

  meta = {
    description = "Vanixiets documentation site built with Astro Starlight";
    license = lib.licenses.mit;
  };
})
