# lajarre/pi-vim, packaged from the published npm distribution.
#
# The npm tarball rather than fetchFromGitHub, for three independent reasons.
# The repository ships a top-level `doc/` directory, which stdenv's
# `forceShare = [ "man" "doc" "info" ]` silently relocates to share/doc during
# fixup; the tarball's `files` list excludes it. Upstream has 7 git tags against
# 24 npm versions with a hole from 0.3.2 to 0.13.0, so a tag-tracking
# nix-update-script would never fire. And upstream publishes no GitHub releases,
# so a `changelog` meta line would 404.
#
# The tarball unpacks to `package/`, hence sourceRoot; its sha256 is
# cross-checkable against the registry's published dist.integrity.
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
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-vim";
  version = "0.14.2";

  src = fetchurl {
    url = "https://registry.npmjs.org/pi-vim/-/pi-vim-${finalAttrs.version}.tgz";
    hash = "sha256-BJkHE2C/SIBYHyINCD971+ew+yDS+X0yU5xjkNks4rg=";
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

  meta = {
    description = "Vim-style modal editing for Pi's TUI editor";
    homepage = "https://github.com/lajarre/pi-vim";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
  };
})
