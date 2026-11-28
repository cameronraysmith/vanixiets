# PostgreSQL collation version drift on the fleet's PostgreSQL hosts (F61).
# On 2026-11-19 every database on magnetite recorded glibc collation version
# 2.42 while the deployed glibc provided 2.44, so their indexes on
# en_US.UTF-8 text were stale, and nothing noticed until pg_dump warned.
# The collector's sqlquery receiver runs ./postgresql-collation/drift.sql
# every 60 s over the local socket and emits the gauge
# vanixiets_postgresql_collation_drift{datname, collversion_recorded,
# collversion_actual}, 1 for a drifted database and 0 otherwise; the agent
# fragment of the otel-collector clan service adds the receiver on every
# host running PostgreSQL (Q68a), and fleet-alert's PostgresqlCollationDrift
# fires on the 1s (modules/nixos/fleet-alert/rules.nix). Until Q68a a
# systemd probe wrote the same series to node_exporter's textfile collector.
# A parked service's database is left out through
# vanixiets.postgresqlCollation.parkedDatabases, which that service's module
# sets while it is off, so reviving it brings its database back under the
# alert. checks.x86_64-linux.postgresql-collation runs the receiver against
# a real PostgreSQL with its mutants.
{ lib, ... }:
let
  seriesName = "vanixiets_postgresql_collation_drift";

  literal = s: "'${builtins.replaceStrings [ "'" ] [ "''" ] s}'";

  # The receiver, with the query as an argument so the check can build its
  # mutants from the same text. The parked names are SQL literals in the
  # query, so the receiver needs no parameter.
  receiver =
    {
      datasource,
      parked,
      sql ? builtins.readFile ./postgresql-collation/drift.sql,
      collectionInterval ? "60s",
    }:
    {
      driver = "postgres";
      inherit datasource;
      collection_interval = collectionInterval;
      queries = [
        {
          sql =
            builtins.replaceStrings
              [ "@parked@" ]
              [
                (lib.concatMapStringsSep ", " literal (lib.naturalSort parked))
              ]
              sql;
          metrics = [
            {
              metric_name = seriesName;
              description = "1 when the database's recorded collation version differs from the system's.";
              value_column = "drift";
              value_type = "int";
              data_type = "gauge";
              attribute_columns = [
                "datname"
                "collversion_recorded"
                "collversion_actual"
              ];
            }
          ];
        }
      ];
    };

  module = {
    options.vanixiets.postgresqlCollation.parkedDatabases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Databases of parked services, which the collation drift receiver leaves out; a service's module sets its database here only while the service is off.";
    };
  };
in
{
  flake.lib.postgresqlCollation = {
    inherit seriesName receiver;
  };

  flake.modules.nixos.postgresql-collation = module;
}
