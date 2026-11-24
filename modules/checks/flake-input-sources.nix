# checks.x86_64-linux.flake-input-sources: a link farm whose output refers to
# the source of every flake.lock node except the root, so that nixbot's upload
# of each built output's closure puts all locked input sources in our cache.
# A session that cannot fetch from GitHub can then evaluate the flake by
# substituting each input by its narHash.
#
# The sources come from the lock, not from walking `inputs`: two nodes follow
# the root (`follows = ""`), so a walk over `.inputs` reaches self, whose
# source changes with every commit. Fetching each node's `locked` attributes,
# as call-flake.nix does, gives the same store paths and depends only on
# flake.lock, read at evaluation only. Nodes of type `path` resolve against
# self and are skipped. Links are named by store path, which deduplicates
# nodes locking the same source. Sources are system-independent, so the check
# is on one system.
{ lib, ... }:
let
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  sources = lib.listToAttrs (
    map
      (
        node:
        let
          path = (builtins.fetchTree (removeAttrs node.locked [ "dir" ])).outPath;
        in
        lib.nameValuePair (builtins.unsafeDiscardStringContext (baseNameOf path)) path
      )
      (
        lib.filter (node: node.locked.type != "path") (
          lib.attrValues (removeAttrs lock.nodes [ lock.root ])
        )
      )
  );
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 3.4 s, slowest 12 s, 11 runs in 30 days
        flake-input-sources.class = "small";
      };
      checks = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        flake-input-sources = pkgs.linkFarm "flake-input-sources" sources;
      };
    };
}
