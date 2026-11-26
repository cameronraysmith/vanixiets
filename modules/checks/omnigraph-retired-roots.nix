# Structural check: the lifecycle rules that delete retired OmniGraph cluster
# roots from the `sciexp` bucket (modules/terranix/cloudflare.nix, from
# flake.lib.omnigraphClusterRoots.retired) cannot reach a root still in use.
#
# A root is in use while a host serves it, from the bucket or from its disk
# under the same name, or while it is kept as the way back
# (flake.lib.omnigraphClusterRoots.rollback). Every host that serves a root
# in the bucket or under localDirectory asserts at evaluation, in the
# omnigraph module, that the retired list leaves its root alone, so a host
# configured onto a retired root fails to evaluate. This check holds the
# rollback roots and magnetite's root to the same rule, and shows on fixed
# lists that each way of reaching a kept root is reported: the kept root
# itself listed as retired, and a retired root whose data or marker prefix
# shares objects with the kept root's; while the separators keep `dev-graph`
# from reaching `dev-graph-v10`. It also pins the two prefixes each retired
# root's rules delete.
#
# It pins uriIn and rootOf for both root stores, and evaluates magnetite
# with vanixiets.omnigraphRootStore forced to "local" through extendModules,
# reading only the storage URI, omnigraph-server's environment and the
# generator names from that evaluation: the root keeps its name on disk, no
# R2 setting reaches the server, and the omnigraph-r2 generator stays. It
# reads none of magnetite's assertions, whose evaluation all of them force.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      roots = self.lib.omnigraphClusterRoots;
      magnetiteSystem = self.nixosConfigurations.magnetite;
      magnetiteRoot = roots.rootOf magnetiteSystem.config.services.omnigraph.storageUri;
      onDisk =
        (magnetiteSystem.extendModules {
          modules = [ { vanixiets.omnigraphRootStore = lib.mkForce "local"; } ];
        }).config;
      reports = args: roots.conflicts args != [ ];
    in
    {
      # 0.2 s: three --rebuild runs on magnetite's store, 2026-11-25.
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-retired-roots.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-retired-roots = self.lib.mkStructuralCheck pkgs {
          name = "omnigraph-retired-roots";
          actual = {
            inUse = roots.conflicts {
              keptRoots = roots.rollback ++ lib.optional (magnetiteRoot != null) magnetiteRoot;
            };
            reported = {
              keptRootRetired = reports {
                retiredRoots = [ "cookbooks-f17" ];
                keptRoots = [ "cookbooks-f17" ];
              };
              rollbackRootRetired = reports {
                retiredRoots = roots.retired ++ roots.rollback;
                keptRoots = roots.rollback;
              };
              dataPrefixShared = reports {
                retiredRoots = [ "cookbooks" ];
                keptRoots = [ "cookbooks/f17" ];
              };
              markerPrefixShared = reports {
                retiredRoots = [ "cookbooks" ];
                keptRoots = [ "cookbooks.f17" ];
              };
              separatedNames = reports {
                retiredRoots = [ "dev-graph" ];
                keptRoots = [ "dev-graph-v10" ];
              };
            };
            prefixes = map (rule: rule.conditions.prefix) roots.lifecycleRules;
            locations = {
              local = roots.uriIn "local" "cookbooks-f17";
              r2 = roots.uriIn "r2" "cookbooks-f17";
              rootOfLocal = roots.rootOf (roots.uriIn "local" "cookbooks-f17");
              rootOfFileUri = roots.rootOf "file:///var/lib/omnigraph/clusters/cookbooks-f17/";
              rootOfR2 = roots.rootOf (roots.uriIn "r2" "cookbooks-f17");
              rootOfOtherDirectory = roots.rootOf "/var/lib/omnigraph/elsewhere/cookbooks-f17";
              otherStoreRejected = !(builtins.tryEval (roots.uriIn "hetzner" "cookbooks-f17")).success;
            };
            magnetite = {
              r2StorageUri = magnetiteSystem.config.services.omnigraph.storageUri;
              localStorageUri = onDisk.services.omnigraph.storageUri;
              localServerSettings = lib.filter (
                name: lib.hasPrefix "AWS_" name || name == "OMNIGRAPH_CLUSTER_LEASE_SECONDS"
              ) (lib.attrNames onDisk.systemd.services.omnigraph-server.environment);
              localKeepsR2Generator = onDisk.clan.core.vars.generators ? omnigraph-r2;
            };
          };
          expected = {
            inUse = [ ];
            reported = {
              keptRootRetired = true;
              rollbackRootRetired = true;
              dataPrefixShared = true;
              markerPrefixShared = true;
              separatedNames = false;
            };
            prefixes = lib.concatMap (root: [
              "omnigraph/clusters/${root}/"
              "omnigraph/clusters/_omnigraph-markers/${root}."
            ]) roots.retired;
            locations = {
              local = "/var/lib/omnigraph/clusters/cookbooks-f17";
              r2 = "s3://sciexp/omnigraph/clusters/cookbooks-f17";
              rootOfLocal = "cookbooks-f17";
              rootOfFileUri = "cookbooks-f17";
              rootOfR2 = "cookbooks-f17";
              rootOfOtherDirectory = null;
              otherStoreRejected = true;
            };
            magnetite = {
              r2StorageUri = "s3://sciexp/omnigraph/clusters/cookbooks-f17";
              localStorageUri = "/var/lib/omnigraph/clusters/cookbooks-f17";
              localServerSettings = [ ];
              localKeepsR2Generator = true;
            };
          };
        };
      };
    };
}
