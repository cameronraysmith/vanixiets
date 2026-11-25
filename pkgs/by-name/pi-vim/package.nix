# lajarre/pi-vim, packaged from the published npm distribution.
#
# The npm tarball rather than fetchFromGitHub, for three independent reasons.
# The repository ships a top-level `doc/` directory, which stdenv's
# `forceShare = [ "man" "doc" "info" ]` silently relocates to share/doc during
# fixup; the tarball's `files` list excludes it. Upstream has 7 git tags against
# 24 npm versions with a hole from 0.3.2 to 0.13.0, so tracking tags would miss
# most releases; pin.json's source is the npm registry instead. And upstream
# publishes no GitHub releases, so a `changelog` meta line would 404.
#
# pin.json pins the version and the tarball's hash; Renovate proposes releases
# from the npm registry and `nix run .#realize-pin -- pi-vim <version>`
# realizes one. The registry publishes a sha512 dist.integrity and a sha1
# shasum but no sha256, so the hash is a prefetch of the tarball.
#
# The tarball unpacks to `package/`, hence sourceRoot.
#
# No postPatch. Up to 0.14.1, clipboard-mirror.ts called
# `import.meta.resolve("@earendil-works/pi-coding-agent")` at module top level.
# That throws under the Bun-compiled pi from llm-agents, which has no
# pi-coding-agent on disk, so the extension failed to load without a patch.
# 0.14.2 moves the call into a lazy try/catch
# (`tryResolvePiCodingAgentModuleUrl`). Under our pi the resolve still throws,
# and the argv[1] fallback hits the virtual `/$bunfs/root/pi`, so the function
# returns undefined and the extension loads pristine with the clipboard mirror
# off. No patch can enable the mirror there: its helper respawns
# `process.execPath --input-type=module -e`, and process.execPath is pi itself,
# not node, which rejects `--input-type`. A bare-specifier patch was measured
# failing the helper with exit code 1.
{
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  inherit ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "pi-vim"; })
    pin
    pinPlan
    ;
  planned = pinPlan pin.version;
in
stdenvNoCC.mkDerivation {
  pname = "pi-vim";
  inherit (pin) version;

  src = fetchurl {
    inherit (planned.artifacts.tarball.file) url;
    inherit (pin.artifacts.tarball.file) hash;
  };

  sourceRoot = "package";

  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    sourceNodeModules=$(find . -type d -name node_modules -print -quit)
    if [ -n "$sourceNodeModules" ]; then
      echo "pi-vim source contains node_modules: $sourceNodeModules" >&2
      exit 1
    fi

    mkdir -p "$out"
    cp -R . "$out/"

    runHook postInstall
  '';

  passthru = { inherit pin pinPlan; };

  meta = {
    description = "Vim-style modal editing for Pi's TUI editor";
    homepage = "https://github.com/lajarre/pi-vim";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
  };
}
