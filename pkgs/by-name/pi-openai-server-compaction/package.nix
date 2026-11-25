# The sole runtime dependency, `ws`, is deliberately not vendored: it is imported
# lazily (src/openai-ws-connection.ts) from a WebSocket transport that the
# isDirectOpenAIResponsesModel gate makes unreachable on the Codex provider, and
# its absence degrades to SSE rather than failing.
#
# The commit and the source hash are in pin.json: Renovate proposes the head of
# the branch it names, and realize-pin rewrites both. The version shows the
# commit's first seven characters.
{
  fetchFromGitHub,
  jq,
  lib,
  stdenvNoCC,
}:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json {
      name = "pi-openai-server-compaction";
    })
    pin
    pinPlan
    ;
in
stdenvNoCC.mkDerivation {
  pname = "pi-openai-server-compaction";
  version = "0.1.0-unstable-${builtins.substring 0 7 pin.version}";

  src = fetchFromGitHub (
    (pinPlan pin.version).artifacts.src.sourceBuild.fetchFromGitHub
    // {
      inherit (pin.artifacts.src.sourceBuild) hash;
    }
  );

  nativeBuildInputs = [ jq ];

  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  # atomic reads package.json#atomic before falling back to package.json#pi
  # (packages/coding-agent/src/core/package-manager-manifest.ts:24-27), while pi
  # reads only package.json#pi, so an empty `atomic.extensions` makes this
  # package contribute nothing to atomic while remaining fully active under pi.
  # atomic 0.9.13 omits @earendil-works/pi-coding-agent from its virtualModules
  # map and src/remote-compaction.ts imports that specifier as a value, so
  # without this block every atomic startup is a fatal extension-load error.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -R . "$out/"
    jq '. + {atomic: {extensions: []}}' package.json > "$out/package.json"

    runHook postInstall
  '';

  meta = {
    description = "Pi extension for OpenAI server-side compaction with Codex-quality continuity";
    homepage = "https://github.com/algal/pi-openai-server-compaction";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
  };

  passthru = {
    inherit pin pinPlan;
  };
}
