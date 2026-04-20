{
  inputs,
  lib,
  nodejs-slim,
  stdenv,
  svgo,
  chromium,
  ffmpeg,
  jq,
  makeWrapper,
  makeFontsConf,
  runCommand,
  typstWithPackages,
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
    nodejs-slim
    typstWithPackages
    svgo
    jq
  ];

  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ../../../bun.nix;
  };

  dontUseBunBuild = true;
  dontUseBunInstall = true;

  # Skip miniflare's external fetch to workers.cloudflare.com/cf.json during
  # astro build; the placeholder fallback is sufficient for the prerender pass
  # and avoids a TLS warning in hermetic (no-CA-bundle) sandbox builds.
  env.CLOUDFLARE_CF_FETCH_ENABLED = "false";

  buildPhase = ''
    runHook preBuild

    # Mirror just docs-linkcheck's diagram compilation so the nix-built
    # artifact matches the deployed site with diagrams present (they are
    # gitignored; only .typ sources are in git).
    cd packages/docs
    mkdir -p public/diagrams
    (
      cd diagrams
      for typ in *.typ; do
        [ -f "$typ" ] || continue
        name="''${typ%.typ}"
        typst compile --format svg "$typ" "../public/diagrams/$name.svg"
      done
    )
    for svg in public/diagrams/*.svg; do
      [ -f "$svg" ] || continue
      svgo --quiet "$svg" -o "$svg"
    done
    # Use node (not bun) to invoke astro: bun's incomplete `ws` shim causes the
    # @cloudflare/vite-plugin module-init path to hang in the nix build env
    # (cold cache triggers warning-emitting branch that warm host-cache skips).
    node ./node_modules/.bin/astro build
    cd ../..

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R packages/docs/dist $out/dist
    cp -R packages/docs/.wrangler $out/.wrangler
    cp packages/docs/wrangler.jsonc $out/wrangler.jsonc
    # Reproducibility: rewrite sandbox-specific absolute paths in the emitted
    # wrangler.json to stable relative values. These fields are never dereferenced
    # downstream — wrangler.unstable_readConfig rederives them from the file path
    # it is handed — but stripping the build-time /nix/var/nix/builds/... strings
    # makes the derivation output bit-identical across rebuilds.
    jq '.configPath = "./wrangler.jsonc" | .userConfigPath = "./wrangler.jsonc"' \
      $out/dist/server/wrangler.json > $out/dist/server/wrangler.json.tmp
    mv $out/dist/server/wrangler.json.tmp $out/dist/server/wrangler.json
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

  passthru.tests.linkcheck = finalAttrs.finalPackage.overrideAttrs (old: {
    pname = "${old.pname}-linkcheck";
    env = (old.env or { }) // {
      CHECK_LINKS = "true";
    };
    meta = old.meta // {
      description = "Internal link validation for vanixiets-docs via starlight-links-validator";
    };
  });

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
      # Provide pre-built CF Worker bundle for the CI webServer (astro preview →
      # miniflare/workerd). finalPackage has a nested layout ({dist/client/,
      # dist/server/, .wrangler/, wrangler.jsonc}); astro preview reads
      # .wrangler/deploy/config.json to locate dist/server/wrangler.json via
      # @cloudflare/vite-plugin's getWorkerConfigs().
      mkdir -p packages/docs
      cp -r ${finalAttrs.finalPackage}/dist packages/docs/dist
      cp -r ${finalAttrs.finalPackage}/.wrangler packages/docs/.wrangler
      chmod -R u+w packages/docs/dist packages/docs/.wrangler

      cd packages/docs
      # Run Playwright via node — bun's child_process.fork() IPC
      # is incompatible with Playwright's worker model.
      # CI=true: chromium-only projects, playwright manages webServer lifecycle via
      # playwright.config webServer command (bun run preview:ci → astro preview).
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
