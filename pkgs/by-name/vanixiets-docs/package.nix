{
  inputs,
  lib,
  bun,
  nodejs-slim,
  stdenv,
  svgo,
  jq,
  autoPatchelfHook,
  makeFontsConf,
  dejavu_fonts,
  mesa,
  typstWithPackages,
  vanixiets-docs-deps,
  ...
}:
let
  playwrightDriver = inputs.playwright-web-flake.packages.${stdenv.system}.playwright-driver;

  # Browsers come from playwright-web-flake on both platforms. The Linux tree
  # used to be synthesised from nixpkgs chromium on the theory that Chrome for
  # Testing binaries crash in a nix build sandbox; a differential experiment on
  # x86_64-linux disproved that (see logs/playwright-nix-architecture-survey.md
  # and the commit that removed the wrapper). The single real sandbox failure
  # was WebKit's missing EGL display, addressed by linuxBrowserEnv below.
  playwrightBrowsers = playwrightDriver.browsers;

  # Linux-only browser environment. Everything here is required for the
  # hermetic sandbox and is deliberately absent on darwin, which has neither
  # WPE/EGL nor an unwrapped headless shell in this path.
  #
  # __EGL_VENDOR_LIBRARY_FILENAMES + LD_LIBRARY_PATH: WPE WebKit aborts with
  #   "Could not create EGL display: no supported platform available" because
  #   the sandbox has no /dev/dri and playwright-web-flake ships no software
  #   EGL vendor. Pointing libglvnd at mesa's llvmpipe vendor JSON is the
  #   minimal sufficient fix. WEBKIT_DISABLE_COMPOSITING_MODE=1 does NOT work
  #   (tested negative control); do not substitute it for this.
  # FONTCONFIG_FILE: chrome-headless-shell is unwrapped upstream, and with no
  #   fontconfig it renders zero-height text rather than failing loudly.
  # PLAYWRIGHT_HOST_PLATFORM_OVERRIDE: the fork drops webkit revisionOverrides,
  #   so webkit's browser directory is resolved under the ubuntu-24.04 name.
  linuxBrowserEnv = lib.optionalAttrs stdenv.hostPlatform.isLinux {
    FONTCONFIG_FILE = "${makeFontsConf { fontDirectories = [ dejavu_fonts ]; }}";
    PLAYWRIGHT_HOST_PLATFORM_OVERRIDE = "ubuntu-24.04";
    __EGL_VENDOR_LIBRARY_FILENAMES = "${mesa}/share/glvnd/egl_vendor.d/50_mesa.json";
    LD_LIBRARY_PATH = lib.makeLibraryPath [ mesa ];
  };

  # Linux nix-build sandbox rejects the prebuilt @cloudflare/workerd-linux-64
  # glibc ELF (PT_INTERP=/lib64/ld-linux-x86-64.so.2 is absent). Rewrite
  # PT_INTERP + RUNPATH against stdenv glibc + libstdc++. Both `astro build`
  # (via @cloudflare/vite-plugin loading miniflare) and `astro preview`
  # (miniflare's webServer) spawn this binary.
  patchBundledWorkerd = lib.optionalString stdenv.hostPlatform.isLinux ''
    shopt -s nullglob
    for binary in node_modules/.bun/@cloudflare+workerd-linux-64@*/node_modules/@cloudflare/workerd-linux-64/bin/workerd; do
      # bun's isolated linker ships files r-xr-xr-x; patchelf needs u+w.
      chmod u+w "$binary"
      autoPatchelf "$binary"
    done
  '';

  # Consume the vanixiets-docs-deps output instead of calling bun2nix here.
  # bun2nix's per-package derivations set allowSubstitutes = false and
  # preferLocalBuild, so every consumer of bun2nix.hook forces its coordinator
  # to build the whole bun cache locally whenever those build-time-only paths
  # are absent. Routing every docs derivation through the one substitutable
  # deps output keeps that cache in a single build graph.
  # The tree is copied rather than symlinked because astro writes into
  # node_modules/.astro and vite into node_modules/.vite during the build.
  materialiseNodeModules = ''
    # stdenv points HOME at the non-existent /homeless-shelter; astro's
    # telemetry notice and vite's cache both write under $HOME.
    export HOME=$(mktemp -d)
    cp -R ${vanixiets-docs-deps}/node_modules node_modules
    cp -R ${vanixiets-docs-deps}/packages/docs/node_modules packages/docs/node_modules
    chmod -R u+w node_modules packages/docs/node_modules
  '';
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
    nodejs-slim
    typstWithPackages
    svgo
    jq
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  # Patch the bundled workerd binary manually in buildPhase; $out has no ELFs.
  dontAutoPatchelf = true;

  preBuild = materialiseNodeModules;

  # Skip miniflare's external fetch to workers.cloudflare.com/cf.json during
  # astro build; the placeholder fallback is sufficient for the prerender pass
  # and avoids a TLS warning in hermetic (no-CA-bundle) sandbox builds.
  env.CLOUDFLARE_CF_FETCH_ENABLED = "false";

  buildPhase = ''
    runHook preBuild
    ${patchBundledWorkerd}
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
    # @astrojs/cloudflare 14.x drives a static (assets-only) build, so
    # @cloudflare/vite-plugin emits wrangler.json into the client output dir
    # (dist/client) rather than the server dir it used pre-14.
    jq '.configPath = "./wrangler.jsonc" | .userConfigPath = "./wrangler.jsonc"' \
      $out/dist/client/wrangler.json > $out/dist/client/wrangler.json.tmp
    mv $out/dist/client/wrangler.json.tmp $out/dist/client/wrangler.json
    runHook postInstall
  '';

  passthru.tests.unit = stdenv.mkDerivation {
    pname = "vanixiets-docs-unit";
    version = finalAttrs.version;
    inherit (finalAttrs) src;

    nativeBuildInputs = [
      nodejs-slim
    ];

    preBuild = materialiseNodeModules;

    buildPhase = ''
      runHook preBuild
      cd packages/docs
      node ./node_modules/.bin/vitest run
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
      bun
      nodejs-slim
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

    dontAutoPatchelf = true;

    preBuild = materialiseNodeModules;
    __darwinAllowLocalNetworking = true;

    env = {
      CI = "true";
      # Engine coverage is platform-split. The split lives in the project
      # list only: no spec is deleted, skipped, or weakened on either platform.
      #
      # x86_64-linux: chromium + firefox + webkit, all 27 specs passing.
      #
      # aarch64-darwin: chromium + webkit. WebKit is net-new coverage here —
      # this check was chromium-only before. Firefox is excluded because it
      # cannot *launch* inside a darwin `nix build`:
      #
      #   browserType.launch: Failed to launch the browser process
      #   [err] *** You are running in headless mode.
      #   [err] Could not find profile folder.
      #
      # That is a launch defect of the darwin build environment, not a
      # product defect and not a flaky spec. Three hypotheses were ruled out
      # by direct experiment:
      #   - darwin sandbox: this host has `sandbox = false`, so the build is
      #     not sandboxed at all, and the failure still reproduces;
      #   - concurrency: reproduced at workers = 1;
      #   - HOME: reproduced with a stable, writable HOME under /private/tmp.
      # Decisively, the same firefox binary from the same browsers tree passes
      # outside the build: `nix develop -c just docs-test` is 27/27 green on
      # darwin with all 9 firefox specs included. Firefox on darwin is
      # therefore covered; what is absent is only its hermetic re-run.
      # Remaining unexplored candidates — CoreFoundation environment, the
      # getpwuid-derived home of the build user, app-bundle launch
      # requirements — have no bounded cost, so they were not pursued. Add
      # "firefox" back to the darwin list the moment one of them pans out.
      PLAYWRIGHT_PROJECTS =
        if stdenv.hostPlatform.isDarwin then "chromium,webkit" else "chromium,firefox,webkit";
      PLAYWRIGHT_BROWSERS_PATH = "${playwrightBrowsers}";
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    }
    // linuxBrowserEnv;

    buildPhase = ''
      runHook preBuild
      ${patchBundledWorkerd}
      # Provide pre-built CF Worker bundle for the CI webServer (astro preview →
      # miniflare/workerd). finalPackage has a nested layout ({dist/client/,
      # .wrangler/, wrangler.jsonc}); astro preview reads
      # .wrangler/deploy/config.json to locate dist/client/wrangler.json via
      # @cloudflare/vite-plugin's getWorkerConfigs() (assets-only static build).
      mkdir -p packages/docs
      cp -r ${finalAttrs.finalPackage}/dist packages/docs/dist
      cp -r ${finalAttrs.finalPackage}/.wrangler packages/docs/.wrangler
      chmod -R u+w packages/docs/dist packages/docs/.wrangler

      cd packages/docs
      # Size the worker pool to the cores nix actually granted this build
      # (`--cores`, else every core on the builder) rather than a fixed 3.
      # Measured on magnetite (16 cores) over 27 tests: 3 workers 23.2-23.8s,
      # 6 -> 20.3s, 9 -> 21.2s, 12 -> 18.4s, 16 -> 17.7-19.0s. The floor is the
      # shared astro-preview/miniflare boot plus firefox and webkit cold start,
      # so the curve flattens quickly, but nothing is gained by leaving cores idle.
      #
      # NIX_BUILD_CORES is a CPU quantity sizing a memory-bound workload, so the
      # RAM arithmetic has to hold too. Peak resident set of every browser
      # process during a full 27-test, three-engine run at 18 workers,
      # sampled at 0.3 s on stibnite: 6.97 GiB across 54 processes, largest
      # single process 0.54 GiB. That is ~0.39 GiB per worker, plus well under
      # 1 GiB for node, astro preview and miniflare. Against the actual
      # x86_64-linux builders: magnetite at 16 workers needs ~6.2 GiB of its
      # 30.6 GiB (~20 GiB free at the 2026-09-02 audit), and pyrite-builder at
      # 4 workers needs ~1.6 GiB of 15 GiB -- a run there passed at 4 workers
      # in 29.2 s. The demand is ~0.4 GiB per core and both builders supply
      # >= 1.9 GiB per core, a ~5x margin, so no ceiling is imposed here.
      # Re-do this arithmetic (and consider min(NIX_BUILD_CORES, N)) before
      # adding an x86_64-linux builder with less than ~0.5 GiB of RAM per core;
      # on this fleet the failure past the memory edge is an unresponsive
      # machine, not a slow build.
      export PLAYWRIGHT_WORKERS="''${NIX_BUILD_CORES:-3}"
      # Run Playwright via node — bun's child_process.fork() IPC
      # is incompatible with Playwright's worker model.
      # PLAYWRIGHT_PROJECTS selects the engines; playwright manages the webServer
      # lifecycle via playwright.config webServer (bun run preview:ci → astro preview).
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
