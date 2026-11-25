# The ModernRelay/omnigraph-cookbooks source tree. magnetite's omnigraph
# cluster takes the `dev` graph's schema and stored queries from its
# dev-graph/ directory, and checks.x86_64-linux.omnigraph-dev-graph-seed loads
# that directory's seed. The output is the fetched tree unchanged, so its hash
# is the one realize-pin computes and the seed and the schema come from one
# store path.
#
# The commit and the source hash are in pin.json: Renovate proposes the head
# of the branch it names, and realize-pin rewrites both. passthru.src is this
# fetch itself, so the realizer's src step hashes `.#omnigraph-cookbooks.src`.
{ lib, fetchFromGitHub }:
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json {
      name = "omnigraph-cookbooks";
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
      meta = {
        description = "Example omnigraph schemas, stored queries and seed data";
        license = lib.licenses.mit;
      };
    }
  );
in
self
