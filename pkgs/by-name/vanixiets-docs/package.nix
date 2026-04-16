{
  inputs,
  lib,
  nodejs-slim,
  stdenv,
  chromium,
  ffmpeg,
  makeWrapper,
  makeFontsConf,
  runCommand,
  ...
}:
let
  bun2nix = inputs.bun2nix.packages.${stdenv.system}.default;
  playwrightDriver = inputs.playwright-web-flake.packages.${stdenv.system}.playwright-driver;

  # Nixpkgs chromium wrapper for nix build sandbox compatibility.
  # playwright-web-flake (post-PR#18) provisions chromium via pre-built
  # Chrome for Testing (CFT) binaries that crash in Linux nix sandboxes.
  # On Linux, wrap nixpkgs chromium with the directory layout Playwright
  # expects. On darwin, CFT works fine — use the original browsers.
  # Revision derived from browsersJSON for automatic version tracking.
  playwrightBrowsers =
    if stdenv.isLinux then
      let
        browsersJSON = playwrightDriver.passthru.browsersJSON;
        chromiumRevision = browsersJSON.chromium.revision;
        ffmpegRevision = browsersJSON.ffmpeg.revision;
        fontconfigFile = makeFontsConf { fontDirectories = [ ]; };
        # Playwright EXECUTABLE_PATHS differ by arch
        chromiumDir = if stdenv.hostPlatform.isx86_64 then "chrome-linux64" else "chrome-linux";
        headlessShellDir =
          if stdenv.hostPlatform.isx86_64 then
            "chrome-headless-shell-linux64"
          else
            "chrome-headless-shell-linux";
      in
      runCommand "playwright-browsers-nixpkgs"
        {
          nativeBuildInputs = [ makeWrapper ];
        }
        ''
          # Chromium
          mkdir -p $out/chromium-${chromiumRevision}/${chromiumDir}
          makeWrapper ${chromium}/bin/chromium \
            $out/chromium-${chromiumRevision}/${chromiumDir}/chrome \
            --set SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
            --set FONTCONFIG_FILE ${fontconfigFile}

          # Chromium headless shell
          mkdir -p $out/chromium_headless_shell-${chromiumRevision}/${headlessShellDir}
          makeWrapper ${chromium}/bin/chromium \
            $out/chromium_headless_shell-${chromiumRevision}/${headlessShellDir}/chrome-headless-shell \
            --set SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
            --set FONTCONFIG_FILE ${fontconfigFile}

          # ffmpeg
          mkdir -p $out/ffmpeg-${ffmpegRevision}
          ln -s ${ffmpeg}/bin/ffmpeg $out/ffmpeg-${ffmpegRevision}/ffmpeg-linux
        ''
    else
      playwrightDriver.browsers;
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
      PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
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
