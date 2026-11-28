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
# shares objects with the kept root's; while the separators keep
# `cookbooks-f17` from reaching `cookbooks-f17-r2`. It also pins the two
# prefixes a retired root's rules delete.
#
# It pins uriIn and rootOf for both root stores, and reads magnetite on
# both: as committed, on the store flake.lib.omnigraphClusterRoots.stores
# names for it, and on the other one, through extendModules with
# vanixiets.omnigraphRootStore forced to it and the notified units set to
# magnetite's row of flake.lib.observabilityHostsFor on that store, which
# is what the otel-collector agent role sets once `stores` names it. On
# each it reads only the values the way between the stores has failed on:
# the storage URI, omnigraph-server's R2 environment and environment file,
# the omnigraph-r2 generator, the backup's option, whether the backup's
# textfile is among the files the textfile directory's activation keeps
# (vanixiets.nodeExporter.textfiles), which local-root units
# are notified, and for each notified unit whether it is a service with an
# ExecStart, as the agent role asserts. It reads none of magnetite's
# assertions, whose evaluation all of them force, so the rest of the
# assertion set on the other store is not checked here.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      roots = self.lib.omnigraphClusterRoots;
      backup = self.lib.omnigraphBackup;
      magnetiteSystem = self.nixosConfigurations.magnetite;
      magnetiteRoot = roots.rootOf magnetiteSystem.config.services.omnigraph.storageUri;
      committedStore = roots.stores.magnetite;
      otherStore = if committedStore == "local" then "r2" else "local";
      otherUnits =
        (self.lib.observabilityHostsFor (roots.stores // { magnetite = otherStore; }))
        .magnetite.notifiedUnits;
      onOtherStore =
        (magnetiteSystem.extendModules {
          modules = [
            {
              vanixiets.omnigraphRootStore = lib.mkForce otherStore;
              services.observability-notify.units = lib.mkForce otherUnits;
            }
          ];
        }).config;
      facts =
        hostConfig:
        let
          server = hostConfig.systemd.services.omnigraph-server;
          units = hostConfig.services.observability-notify.units;
        in
        {
          storageUri = hostConfig.services.omnigraph.storageUri;
          serverR2Settings = lib.filter (
            name: lib.hasPrefix "AWS_" name || name == "OMNIGRAPH_CLUSTER_LEASE_SECONDS"
          ) (lib.attrNames server.environment);
          serverReadsR2Credential = lib.elem hostConfig.vanixiets.secrets.omnigraph-r2.files.env.path (
            lib.toList (server.serviceConfig.EnvironmentFile or [ ])
          );
          keepsR2Generator = hostConfig.vanixiets.secrets ? omnigraph-r2;
          backupEnabled = hostConfig.vanixiets.omnigraphBackup.enable;
          backupTextfileKept = lib.elem "${backup.writer}.prom" hostConfig.vanixiets.nodeExporter.textfiles;
          localRootUnitsNotified = lib.filter (unit: lib.elem unit units) backup.localRootUnits;
          notifiedWithoutExecStart = lib.filter (
            unit: !(hostConfig.systemd.services.${unit}.serviceConfig or { } ? ExecStart)
          ) units;
        };
      expectedFacts =
        store:
        let
          local = store == "local";
        in
        {
          storageUri = roots.uriIn store "cookbooks-f17";
          serverR2Settings = lib.optionals (!local) [
            "AWS_ENDPOINT_URL"
            "AWS_ENDPOINT_URL_S3"
            "AWS_REGION"
            "OMNIGRAPH_CLUSTER_LEASE_SECONDS"
          ];
          serverReadsR2Credential = !local;
          keepsR2Generator = true;
          backupEnabled = local;
          backupTextfileKept = local;
          localRootUnitsNotified = lib.optionals local backup.localRootUnits;
          notifiedWithoutExecStart = [ ];
        };
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
              dataPrefixShared = reports {
                retiredRoots = [ "cookbooks" ];
                keptRoots = [ "cookbooks/f17" ];
              };
              markerPrefixShared = reports {
                retiredRoots = [ "cookbooks" ];
                keptRoots = [ "cookbooks.f17" ];
              };
              separatedNames = reports {
                retiredRoots = [ "cookbooks-f17" ];
                keptRoots = [ "cookbooks-f17-r2" ];
              };
            };
            prefixes = map (rule: rule.conditions.prefix) (roots.lifecycleRulesOf [ "cookbooks-f17" ]);
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
              committedStoreIsTheSetting = magnetiteSystem.config.vanixiets.omnigraphRootStore == committedStore;
              committedUnitsAreTheRow =
                magnetiteSystem.config.services.observability-notify.units
                == self.lib.observabilityHosts.magnetite.notifiedUnits;
              ${committedStore} = facts magnetiteSystem.config;
              ${otherStore} = facts onOtherStore;
            };
          };
          expected = {
            inUse = [ ];
            reported = {
              keptRootRetired = true;
              dataPrefixShared = true;
              markerPrefixShared = true;
              separatedNames = false;
            };
            prefixes = [
              "omnigraph/clusters/cookbooks-f17/"
              "omnigraph/clusters/_omnigraph-markers/cookbooks-f17."
            ];
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
              committedStoreIsTheSetting = true;
              committedUnitsAreTheRow = true;
              local = expectedFacts "local";
              r2 = expectedFacts "r2";
            };
          };
        };
      };
    };
}
