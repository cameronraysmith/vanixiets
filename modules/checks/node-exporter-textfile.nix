# checks.x86_64-linux.node-exporter-textfile (F75): magnetite's node_exporter
# carries `--collector.textfile.directory` exactly once, on the host's one
# textfile directory, which systemd-tmpfiles creates for node_exporter's
# user, and the memory budget writes its own file there. The collation
# probe that also wrote one is gone (Q68a): no postgresql-collation unit,
# timer or writer remains, and the collector's sqlquery/postgresql-collation
# receiver feeds metrics/host. The mutant twoDirectories, magnetite with a
# second directory flag, must fail the assertion of
# modules/nixos/node-exporter-textfile.nix, as magnetite's node_exporter
# failed to start on 2026-11-19.
{ self, lib, ... }:
let
  inherit (self.lib.nodeExporterTextfile) flag;
  magnetite = self.nixosConfigurations.magnetite;
  cfg = magnetite.config;
  directory = cfg.vanixiets.nodeExporter.textfileDirectory;
  node = cfg.services.prometheus.exporters.node;
  execStartOf =
    system: toString system.config.systemd.services.prometheus-node-exporter.serviceConfig.ExecStart;
  flagCount = system: lib.length (lib.splitString flag (execStartOf system)) - 1;
  failingAssertions =
    system: map (a: a.message) (lib.filter (a: !a.assertion) system.config.assertions);
  isOurs = lib.hasPrefix "node-exporter-textfile:";

  twoDirectories = magnetite.extendModules {
    modules = [
      { services.prometheus.exporters.node.extraFlags = [ "${flag}=/run/another-textfile" ]; }
    ];
  };

  writesInto =
    unit: file:
    lib.hasInfix "${directory}/${file}" (toString cfg.systemd.services.${unit}.serviceConfig.ExecStart);

  clauses = [
    {
      label = "magnetite's node_exporter ExecStart carries ${flag} exactly once";
      holds = flagCount magnetite == 1 && lib.hasInfix "${flag}=${directory}" (execStartOf magnetite);
    }
    {
      label = "magnetite fails no textfile directory assertion";
      holds = !lib.any isOurs (failingAssertions magnetite);
    }
    {
      label = "systemd-tmpfiles creates ${directory} 0755 for node_exporter's user";
      holds =
        let
          rule = cfg.systemd.tmpfiles.settings."10-node-exporter-textfile".${directory}.d;
        in
        rule.user == node.user && rule.group == node.group && rule.mode == "0755";
    }
    {
      label = "the memory budget writes its own file into ${directory}";
      holds = writesInto "magnetite-memory-budget" "magnetite-memory-budget.prom";
    }
    # Q68a: collation drift moved to the collector's sqlquery receiver.
    {
      label = "the postgresql-collation probe is gone: no unit, timer or textfile writer, and sqlquery/postgresql-collation feeds metrics/host";
      holds =
        !(cfg.systemd.services ? postgresql-collation)
        && !(cfg.systemd.timers ? postgresql-collation)
        && !(lib.elem "postgresql-collation" cfg.vanixiets.nodeExporter.textfileWriters)
        &&
          lib.elem "sqlquery/postgresql-collation"
            cfg.services.opentelemetry-collector.settings.service.pipelines."metrics/host".receivers;
    }
    {
      label = "mutant twoDirectories (a second ${flag}) fails the assertion";
      holds = flagCount twoDirectories == 2 && lib.any isOurs (failingAssertions twoDirectories);
    }
  ];
  failing = map (c: c.label) (lib.filter (c: !c.holds) clauses);
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        node-exporter-textfile = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        node-exporter-textfile =
          assert lib.assertMsg (
            failing == [ ]
          ) "node-exporter-textfile check: ${lib.concatStringsSep "; " failing}";
          pkgs.runCommand "node-exporter-textfile" {
            meta.description = "evaluation check: one node_exporter textfile directory per host, a second directory flag rejected";
          } "touch $out";
      };
    };
}
