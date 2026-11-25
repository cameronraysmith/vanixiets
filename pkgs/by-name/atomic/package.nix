# atomic is Bastani's terminal coding agent, packaged from the published npm
# distribution. The previous release-archive split launcher (a bun --compile
# binary) could not resolve @earendil-works/* extension imports: its bundle
# selects loader-virtual-modules' virtualModules map, which omits the pi
# coding-agent specifiers, while the npm dist selects the _aliases map, which
# carries @earendil-works/pi-coding-agent. Every pi-ecosystem extension that
# value-imports that scope is a fatal load error under the old binary and
# loads cleanly under this one.
#
# The npm tarball ships dist/ prebuilt (upstream's prepublishOnly runs
# `bun run build` plus a shrinkwrap generator), so nothing is compiled here.
# Its dependency closure is installed from the shipped npm-shrinkwrap.json by
# `nodeModules-<system>`, one fixed-output derivation per supported system
# that runs `npm ci` with network, because the shrinkwrap generator omits
# `integrity` for the workspace-internal @bastani/* entries and nixpkgs'
# prefetch-npm-deps refuses such a lockfile. Each tree's hash pins what npm
# fetched. The main derivation copies the host's tree, runs `npm rebuild` for
# the dependencies' install scripts (protobufjs and @google/genai) and
# installs the package as npmInstallHook would.
#
# Every hash lives in pin.json (`src`, the registry tarball, and the derived
# `nodeModules-<system>` trees), which realize-pin rewrites per version.
# source: https://github.com/bastani-inc/atomic
{
  lib,
  stdenv,
  stdenvNoCC,
  nodejs_22,
  cacert,
  fetchurl,
  jq,
  makeBinaryWrapper,
  fd,
  git,
  ripgrep,
  runCommand,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "atomic"; })
    pin
    pinPlan
    ;
  planned = (pinPlan pin.version).artifacts;

  # npm installs only the optional packages (@bastani/atomic-natives-*,
  # @mariozechner/clipboard-*) that match the platform it targets, so each
  # supported system has its own node_modules tree and hash. The explicit
  # target makes each tree independent of the host that builds it, so
  # realize-pin computes every system's hash on one machine.
  npmTargets = {
    x86_64-linux = [
      "--os=linux"
      "--cpu=x64"
      "--libc=glibc"
    ];
    aarch64-linux = [
      "--os=linux"
      "--cpu=arm64"
      "--libc=glibc"
    ];
    aarch64-darwin = [
      "--os=darwin"
      "--cpu=arm64"
    ];
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "atomic";
  inherit (pin) version;

  src = fetchurl {
    inherit (planned.src.file) url;
    inherit (pin.artifacts.src.file) hash;
  };
  sourceRoot = "package";

  nativeBuildInputs = [
    nodejs_22
    makeBinaryWrapper
    writableTmpDirAsHomeHook
  ];
  # node as a host input lets fixup patch dist/'s `#!/usr/bin/env node`
  # shebangs, and the prebuilt native addons are installed unstripped, as
  # buildNpmPackage does.
  buildInputs = [ nodejs_22 ];
  dontStrip = true;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    cp -R ${finalAttrs.passthru."nodeModules-${stdenv.hostPlatform.system}"} node_modules
    chmod -R u+w node_modules
    patchShebangs node_modules
    npm rebuild --legacy-peer-deps --offline --no-progress
    patchShebangs node_modules
    runHook postBuild
  '';

  # atomic resolves fd and rg from PATH and otherwise downloads a release
  # binary from GitHub at first use; since 0.9.72 it does the same for git
  # (a portable dugite-native build, whenever no git >= 2.30.0 is on PATH).
  # PATH is suffixed so the caller's own tools still win.
  installPhase = ''
    runHook preInstall
    packageOut=$out/lib/node_modules/@bastani/atomic
    mkdir -p "$(dirname "$packageOut")"
    cp -R . "$packageOut"
    makeWrapper ${lib.getExe nodejs_22} $out/bin/atomic \
      --add-flags "$packageOut/dist/cli.js" \
      --set ATOMIC_SKIP_VERSION_CHECK 1 \
      --suffix PATH : ${
        lib.makeBinPath [
          fd
          git
          ripgrep
        ]
      }
    runHook postInstall
  '';

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  # --version (versionCheckHook) proves dist/cli.js and its node_modules
  # closure load; --help additionally proves the CLI surface imports.
  postInstallCheck = ''
    "$out/bin/atomic" --help | grep -q "AI coding assistant"
  '';

  strictDeps = true;

  passthru =
    let
      # `npm ci` from the tarball's shrinkwrap for one target, with network.
      # --legacy-peer-deps: from 0.9.71 atomic depends on
      # @modelcontextprotocol/ext-apps 2.x, whose required peers the
      # shrinkwrap omits, and nothing in dist/ imports ext-apps; the flag
      # installs exactly the shrinkwrap's tree. The published package.json
      # keeps devDependencies the shrinkwrap does not cover, which `npm ci`
      # would refuse as out of sync; dist/ is prebuilt, so they are dropped
      # here, and only node_modules leaves this derivation.
      nodeModules =
        system: target:
        stdenvNoCC.mkDerivation {
          pname = "atomic-node-modules-${system}";
          inherit (finalAttrs) version src sourceRoot;

          nativeBuildInputs = [
            nodejs_22
            jq
            writableTmpDirAsHomeHook
          ];

          # In the Linux sandbox node's default store does not verify the
          # registry's chain (UNABLE_TO_GET_ISSUER_CERT_LOCALLY); the CA bundle
          # added through NODE_EXTRA_CA_CERTS does.
          env.NODE_EXTRA_CA_CERTS = "${cacert}/etc/ssl/certs/ca-bundle.crt";

          dontConfigure = true;

          buildPhase = ''
            runHook preBuild
            jq 'del(.devDependencies)' package.json > package.json.tmp
            mv package.json.tmp package.json
            npm ci ${lib.escapeShellArgs target} --ignore-scripts --legacy-peer-deps --no-audit --no-fund --no-progress
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            cp -R node_modules $out
            runHook postInstall
          '';

          dontFixup = true;

          impureEnvVars = lib.fetchers.proxyImpureEnvVars;
          outputHash = pin.artifacts."nodeModules-${system}".sourceBuild.hash;
          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
        };
    in
    lib.mapAttrs' (
      system: target: lib.nameValuePair "nodeModules-${system}" (nodeModules system target)
    ) npmTargets
    // {
      inherit pin pinPlan;

      # doInstallCheck runs against $out while it is still being built and
      # still writable. This runs the same CLI against the finished,
      # read-only store path.
      tests.help =
        runCommand "atomic-test-help"
          {
            meta.timeout = 60;
          }
          ''
            export HOME="$PWD/home"
            mkdir -p "$HOME"

            ${lib.getExe finalAttrs.finalPackage} --help > help.txt

            grep -q "AI coding assistant" help.txt
            grep -q "atomic \[options\] \[--\] \[@files\.\.\.\] \[messages\.\.\.\]" help.txt
            grep -q "Install extension source and add to settings" help.txt

            touch "$out"
          '';
    };

  meta = {
    description = "Coding agent CLI with read, bash, edit, write tools and session management";
    homepage = "https://github.com/bastani-inc/atomic";
    changelog = "https://github.com/bastani-inc/atomic/releases/tag/${finalAttrs.version}";
    # LICENSE is the MIT text plus a clause requiring a product above 100
    # million monthly active users or $20 million monthly revenue to display
    # 'Atomic' in its interface. That condition is not part of MIT and has no
    # SPDX identifier, so lib.licenses.mit would misstate the terms; the
    # repository's package.json nonetheless declares MIT and GitHub reports
    # the license as NOASSERTION.
    license = {
      shortName = "MIT-with-atomic-attribution";
      fullName = "MIT License with Atomic attribution requirement";
      url = "https://github.com/bastani-inc/atomic/blob/main/LICENSE";
      free = true;
      redistributable = true;
    };
    # dist/ is prebuilt upstream and the napi natives ship prebuilt binaries
    # through the platform optionalDependencies.
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "atomic";
    platforms = lib.attrNames npmTargets;
    maintainers = [ ];
  };
})
