# The commit and the source hash are in pin.json: Renovate proposes the head
# of the branch it names, and realize-pin rewrites both. passthru.src is this
# fetch itself, so the realizer's src step hashes `.#agent-plugins-cloudflare.src`.
{ lib, fetchFromGitHub }:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json {
      name = "agent-plugins-cloudflare";
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
