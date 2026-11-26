# The ModernRelay/omnigraph-cookbooks source tree. magnetite's omnigraph
# cluster serves each cookbook directory as the example graph
# `cookbook-<directory>`, with that directory's schema and stored queries,
# and loads its seed into a newly created root;
# checks.x86_64-linux.omnigraph-cookbook-seeds loads every seed into the same
# configuration in the sandbox. The output is the fetched tree unchanged, so
# its hash is the one realize-pin computes and the seeds and the schemas come
# from one store path.
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
