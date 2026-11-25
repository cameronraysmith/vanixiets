# The commit and the source hash are in pin.json: Renovate proposes the head of
# the branch it names, and realize-pin rewrites both. The version shows the
# commit's first seven characters.
{
  fetchFromGitHub,
  lib,
  stdenvNoCC,
}:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "pi-agent-extensions"; })
    pin
    pinPlan
    ;
in
stdenvNoCC.mkDerivation {
  pname = "pi-agent-extensions";
  version = "0.1.0-unstable-${builtins.substring 0 7 pin.version}";

  src = fetchFromGitHub (
    (pinPlan pin.version).artifacts.src.sourceBuild.fetchFromGitHub
    // {
      inherit (pin.artifacts.src.sourceBuild) hash;
    }
  );

  # Prevent a stale direnv ctx in the debounce timer from crashing the agent.
  # Drop this patch when upstream carries an equivalent fix. It is applied as
  # is to every commit, so a commit that moves the code it touches fails the
  # build and the patch is rebased by hand.
  patches = [ ./direnv-stale-context.patch ];

  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall

    sourceNodeModules=$(find . -type d -name node_modules -print -quit)
    if [ -n "$sourceNodeModules" ]; then
      echo "pi-agent-extensions source contains node_modules: $sourceNodeModules" >&2
      exit 1
    fi

    mkdir -p "$out"
    cp -R . "$out/"

    runHook postInstall
  '';

  meta = {
    description = "Collection of Pi coding-agent extensions";
    homepage = "https://github.com/rytswd/pi-agent-extensions";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = lib.platforms.all;
  };

  passthru = {
    inherit pin pinPlan;
  };
}
