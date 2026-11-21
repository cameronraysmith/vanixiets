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
# `bun run build` plus a shrinkwrap generator), so nothing is compiled here:
# the build is `npm ci --ignore-scripts` + `npm rebuild` (which runs the
# dependencies' install scripts, e.g. protobufjs' postinstall) from the
# shipped npm-shrinkwrap.json, and the install hook packs
# the declared `files` and copies node_modules next to them.
#
# Pinning: the registry tarball by its sha256 (cross-checkable against the
# registry's published integrity) and the dependency closure by npmDepsHash
# over the shipped npm-shrinkwrap.json (lockfileVersion 3, 345 packages).
#
# Two upstream-shrinkwrap repairs live in npm-dist-repairs.patch:
#  - the prepublishOnly generator emits the workspace-internal @bastani/*
#    entries (the atomic-natives* platform set plus the atomic-ai, -tui,
#    -agent-core, -codemode, -schema and -telemetry forks) without
#    `integrity`, which nix's prefetch-npm-deps parser refuses outright
#    ("non-git dependencies should have associated integrity"); the patch adds
#    the registry's published sha512 for each. update.sh selects them by the
#    absence of `integrity` rather than by name, so the set tracks upstream.
#  - the published package.json retains devDependencies the generated
#    shrinkwrap does not cover, so `npm ci` tries to resolve them from the
#    registry and dies ENOTCACHED; dist/ is already built, so they are dead
#    weight and are removed.
#
# The repairs apply in postPatch rather than `patches` because this
# buildNpmPackage forwards `patches` to its internal fetchNpmDeps but strips it
# from the main derivation (observed: env.patches empty, the hook's
# lockfile-consistency check then fails), while postPatch reaches both.
#
# Version lives in manifest.json alongside this file; update.sh re-derives the
# tarball hash, the repairs patch, and npmDepsHash from the registry per bump.
# update: nix run .#update-atomic
# source: https://github.com/bastani-inc/atomic
{
  lib,
  buildNpmPackage,
  nodejs_22,
  fetchurl,
  makeBinaryWrapper,
  fd,
  git,
  ripgrep,
  runCommand,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:
let
  manifest = lib.importJSON ./manifest.json;
in
buildNpmPackage (finalAttrs: {
  pname = "atomic";
  inherit (manifest) version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@bastani/atomic/-/atomic-${finalAttrs.version}.tgz";
    hash = "sha256-Nb97/Kwx8K9pYO2EWvzGNirWbBngLdjR4Z/hSypiLcw=";
  };
  sourceRoot = "package";

  nodejs = nodejs_22;
  npmDepsHash = "sha256-zv9j4t6H/9kAUJFnSI//DznC47O8Id/rGDbI82wYpQk=";

  postPatch = ''
    patch -p1 < ${./npm-dist-repairs.patch}
  '';

  # From 0.9.71 atomic depends on @modelcontextprotocol/ext-apps 2.x, whose
  # required peers (@modelcontextprotocol/client and core) the shrinkwrap
  # omits, so `npm ci` and the install hook's `npm prune` try to resolve them
  # from the registry and die ENOTCACHED. Nothing in dist/ imports ext-apps,
  # so the peers are never loaded; skipping peer resolution installs exactly
  # the shrinkwrap's tree, which carries no `peer: true` entries for this flag
  # to drop. npmFlags reaches every npm call (ci, rebuild, prune).
  npmFlags = [ "--legacy-peer-deps" ];

  # dist/ is prebuilt in the tarball; there is nothing to npm-run.
  dontNpmBuild = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  # atomic resolves fd and rg from PATH and otherwise downloads a release
  # binary from GitHub at first use; since 0.9.72 it does the same for git
  # (a portable dugite-native build, whenever no git >= 2.30.0 is on PATH).
  # PATH is suffixed so the caller's own tools still win.
  postFixup = ''
    wrapProgram "$out/bin/atomic" \
      --set ATOMIC_SKIP_VERSION_CHECK 1 \
      --suffix PATH : ${
        lib.makeBinPath [
          fd
          git
          ripgrep
        ]
      }
  '';
  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = true;
  # --version (versionCheckHook) proves dist/cli.js and its node_modules
  # closure load; --help additionally proves the CLI surface imports.
  postInstallCheck = ''
    "$out/bin/atomic" --help | grep -q "AI coding assistant"
  '';

  strictDeps = true;

  passthru = {
    updateScript = ./update.sh;

    # doInstallCheck runs against $out while it is still being built and still
    # writable. This runs the same CLI against the finished, read-only store
    # path.
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
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    maintainers = [ ];
  };
})
