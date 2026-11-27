# OmniGraph cluster roots in the `sciexp` R2 bucket: how a root is named, which
# roots are retired, and which retired-looking root is kept as the way back.
#
# A root's name ends in the storage format its graphs were created at
# (`omnigraph version --json`, `internal_schema.writes` of the binary that
# created it), which is also the lowest format a binary must read to open it:
# `cookbooks-f17`. A cluster graph keeps that format for its whole life, and
# `omnigraph upgrade` refuses cluster graphs, so a binary that no longer reads
# it can only serve a new root. A deliberate fresh copy at the same format
# (to replay the seeds of example graphs) takes a revision suffix:
# `cookbooks-f17-r2`, `cookbooks-f17-r3`, and so on.
#
# A root that no host serves any more is retired by adding its name to
# `retired`. modules/terranix/cloudflare.nix then declares two lifecycle rules
# per retired root on `sciexp`, deleting objects older than one day under
#
#   omnigraph/clusters/<root>/                     the cluster state and graphs
#   omnigraph/clusters/_omnigraph-markers/<root>.  its bootstrap markers
#
# and they take effect once that terraform configuration is applied. The
# separators keep one root's prefixes from matching another's (`dev-graph/`
# never matches `dev-graph-v9/`). The markers may go only once the root is
# retired: the bootstrap refuses to start a configured root that has a marker
# but no cluster state, so a configured root's marker must outlive its data.
#
# `rollback` names roots kept intact as the way back after a host moved to a
# new root; a root leaves it for `retired` in a later change, once the new
# root has served long enough that nothing will roll back to it.
#
# `conflicts` lists every way the retired list would delete what a configured
# or rollback root still needs. The omnigraph module asserts it is empty for
# the root each host serves, and checks.x86_64-linux.omnigraph-retired-roots
# asserts it for the rollback roots and shows that each kind of conflict is
# reported.
#
# A root of the same name may also live on the serving host's disk, under
# `localDirectory`: `uriIn` maps a host's root store, "local" or "r2", and a
# root name to the root's location, and `rootOf` names the root of either
# location. A host serving a local root keeps the bucket's root of that name
# as its way back to R2, so the retired list must leave it alone as well.
{ lib, ... }:
let
  bucket = "sciexp";
  clustersPrefix = "omnigraph/clusters";
  markersPrefix = "${clustersPrefix}/_omnigraph-markers";

  # The object key prefixes a root owns in the bucket.
  prefixesOf = root: [
    {
      kind = "data";
      prefix = "${clustersPrefix}/${root}/";
    }
    {
      kind = "markers";
      prefix = "${markersPrefix}/${root}.";
    }
  ];

  # Two prefixes share objects when one starts with the other.
  overlap = a: b: lib.hasPrefix a b || lib.hasPrefix b a;
in
{
  flake.lib.omnigraphClusterRoots = rec {
    inherit bucket clustersPrefix markersPrefix;

    # Retired roots, deleted from `sciexp` by lifecycle rules.
    retired = [
      "dev-graph"
      "dev-graph-v9"
    ];

    # magnetite served dev-graph-v10, created by omnigraph 0.15 at storage
    # format 16, before it moved to cookbooks-f17; it stays intact until it
    # is moved to `retired`.
    rollback = [ "dev-graph-v10" ];

    # The name of a root whose graphs are created at `createdAtFormat`.
    name =
      {
        family,
        createdAtFormat,
        revision ? 1,
      }:
      assert lib.assertMsg (
        builtins.isInt revision && revision >= 1
      ) "omnigraphClusterRoots.name: revision must be a positive integer";
      "${family}-f${toString createdAtFormat}"
      + lib.optionalString (revision > 1) "-r${toString revision}";

    # The `s3://` URI of a root in the bucket.
    uri = root: "s3://${bucket}/${clustersPrefix}/${root}";

    # The directory holding local roots: beneath the omnigraph units'
    # StateDirectory, the only local path their sandbox lets them write.
    localDirectory = "/var/lib/omnigraph/clusters";

    # Where each serving host's root lives, "local" or "r2": the one setting
    # that moves a host between its disk and the bucket. The host's
    # vanixiets.omnigraphRootStore and the units its row in
    # flake.lib.observabilityHosts notifies both follow it, so switching
    # changes nothing else.
    stores = {
      magnetite = "local";
    };

    # The location of `root` in `store`: "local" for the serving host's
    # disk, "r2" for the bucket.
    uriIn =
      store: root:
      if store == "local" then
        "${localDirectory}/${root}"
      else if store == "r2" then
        uri root
      else
        throw "omnigraphClusterRoots.uriIn: the root store must be \"local\" or \"r2\", got ${builtins.toJSON store}";

    # The root name of a storage URI in this bucket's clusters prefix or in
    # localDirectory, or null for any other URI.
    rootOf =
      storageUri:
      let
        inBucket = builtins.match "s3://${bucket}/${clustersPrefix}/([^/]+)/*" storageUri;
        local = builtins.match "(file://)?${localDirectory}/([^/]+)/*" storageUri;
      in
      if inBucket != null then
        builtins.head inBucket
      else if local != null then
        builtins.elemAt local 1
      else
        null;

    # The lifecycle rules that delete one retired root, as
    # cloudflare_r2_bucket_lifecycle rules.
    lifecycleRules = lib.concatMap (
      root:
      map (p: {
        id = "omnigraph retired root ${root} ${p.kind}";
        enabled = true;
        conditions.prefix = p.prefix;
        delete_objects_transition.condition = {
          type = "Age";
          max_age = 86400; # 1 day
        };
      }) (prefixesOf root)
    ) retired;

    # Every way `retiredRoots` would delete objects of `keptRoots`, as
    # messages; empty when there is none. A kept root is named retired, or a
    # prefix of a retired root shares objects with a prefix of a kept root.
    conflicts =
      {
        retiredRoots ? retired,
        keptRoots,
      }:
      lib.concatMap (
        kept:
        lib.optional (lib.elem kept retiredRoots) "the root ${kept} is kept but listed as retired"
        ++ lib.concatMap (
          r:
          lib.concatMap (
            rp:
            map (
              kp:
              "the retired root ${r}'s prefix ${rp.prefix} shares objects with the kept root ${kept}'s prefix ${kp.prefix}"
            ) (lib.filter (kp: overlap rp.prefix kp.prefix) (prefixesOf kept))
          ) (prefixesOf r)
        ) (lib.remove kept retiredRoots)
      ) keptRoots;
  };
}
