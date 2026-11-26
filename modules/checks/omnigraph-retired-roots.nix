# Structural check: the lifecycle rules that delete retired OmniGraph cluster
# roots from the `sciexp` bucket (modules/terranix/cloudflare.nix, from
# flake.lib.omnigraphClusterRoots.retired) cannot reach a root still in use.
#
# A root is in use while a host serves it or while it is kept as the way back
# (flake.lib.omnigraphClusterRoots.rollback). Every host that serves a root in
# the bucket asserts at evaluation, in the omnigraph module, that the retired
# list leaves its root alone, so a host configured onto a retired root fails
# to evaluate. This check holds the rollback roots and magnetite's root to the
# same rule, and shows on fixed lists that each way of reaching a kept root is
# reported: the kept root itself listed as retired, and a retired root whose
# data or marker prefix shares objects with the kept root's; while the
# separators keep `dev-graph` from reaching `dev-graph-v10`. It also pins the
# two prefixes each retired root's rules delete.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      roots = self.lib.omnigraphClusterRoots;
      magnetiteRoot = roots.rootOf self.nixosConfigurations.magnetite.config.services.omnigraph.storageUri;
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
          };
        };
      };
    };
}
