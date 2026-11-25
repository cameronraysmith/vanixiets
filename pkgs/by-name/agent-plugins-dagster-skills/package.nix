# The release version and the source hash are in pin.json: Renovate proposes
# upstream's GitHub releases, and realize-pin rewrites both. passthru.src is
# this fetch itself, so the realizer's src step hashes
# `.#agent-plugins-dagster-skills.src`.
{ lib, fetchFromGitHub }:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json {
      name = "agent-plugins-dagster-skills";
    })
    pin
    pinPlan
    ;

  self = fetchFromGitHub (
    (pinPlan pin.version).artifacts.src.sourceBuild.fetchFromGitHub
    // {
      inherit (pin.artifacts.src.sourceBuild) hash;
      passthru = {
        inherit pin pinPlan;
        src = self;
      };
    }
  );
in
self
