# On-demand restore test of flake.modules.nixos.postgresql-backup (openspec
# change back-up-postgresql-off-host, design D12; tasks.md 5.1, 5.2). Rerun
# it on every change to the module.
#
# One systemd-nspawn container on a builder advertising uid-range
# (magnetite) runs PostgreSQL with magnetite's package, two databases from
# `ensureDatabases`, one owned by a role of its own, and the module with its
# restic repository overridden to the local path /var/lib/restic-test and a
# fixed password. The script dumps every database by hand, so an older dump
# exists, inserts a sentinel row, starts restic-backups-postgresql.service
# alone, records the row counts, drops both databases and the role, restores
# the latest snapshot with the job's wrapper `restic-postgresql`, loads
# globals.sql and then each dump, and compares.
#
# What it establishes: the job's prepare step dumps every database before
# restic reads the files, so the snapshot holds the sentinel written after
# the older dump; the snapshot holds exactly the dump files and globals.sql;
# a `pg_dump -C` dump restores its database and its rows after the roles
# are loaded (A161); a successful run writes the last-success series to its
# record under /var/lib and into node_exporter's textfile directory.
# The attribute prepareStartsNoDumps is the job with no prepare step, as in the
# dump-after-backup bug the survey found; its run must fail on the sentinel.
#
# What it does not establish: R2 (path-style addressing, the token's scope,
# egress), the real vars or their generators, the nightly timer, prune and
# check over many nights, memory on magnetite, or the dumps' dataset.
{ self, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      reference = self.nixosConfigurations.magnetite.config;
      inherit (self.lib.postgresqlBackup) location metricsDirectory seriesName;
      sentinel = "sentinel-written-after-the-older-dump";

      restoreTest =
        {
          name,
          mutant ? { },
          passthru ? { },
        }:
        pkgs.testers.runNixOSTest {
          inherit name passthru;
          requiredFeatures = {
            nixos-test = true;
            uid-range = true;
          };
          containers.db =
            { config, ... }:
            {
              imports = [
                self.modules.nixos.node-exporter-textfile
                self.modules.nixos.postgresql-collation
                self.modules.nixos.postgresql-backup
                mutant
              ];
              system.stateVersion = lib.trivial.release;
              vanixiets.postgresqlBackup.enable = true;
              services.postgresql = {
                enable = true;
                inherit (reference.services.postgresql) package;
                ensureDatabases = [
                  "alpha"
                  "beta"
                ];
              };
              services.prometheus.exporters.node.enable = true;
              environment.etc."restic-test-password".text = "restic-test-password";
              services.restic.backups.postgresql = {
                repository = lib.mkForce "/var/lib/restic-test";
                extraOptions = lib.mkForce [ ];
                passwordFile = "/etc/restic-test-password";
                environmentFile = null;
              };
              environment.variables.TEXTFILE = config.vanixiets.nodeExporter.textfileDirectory;
            };
          testScript = ''
            import json

            def sql(query, db="postgres"):
                return db_.succeed(
                    f"runuser -u postgres -- psql -X -q -A -t -v ON_ERROR_STOP=1 -d {db} -c \"{query}\""
                ).strip()

            db_ = db
            db.wait_for_unit("multi-user.target")
            db.wait_for_unit("postgresql.target")
            start = int(db.succeed("date +%s").strip())

            with subtest("seed two databases, a role and an older dump"):
                sql("CREATE ROLE app LOGIN PASSWORD 'app-password'")
                sql("ALTER DATABASE alpha OWNER TO app")
                sql("SET ROLE app; CREATE TABLE t (id int PRIMARY KEY, note text); INSERT INTO t SELECT g, md5(g::text) FROM generate_series(1, 500) g", "alpha")
                sql("CREATE TABLE u (id int); INSERT INTO u SELECT generate_series(1, 300)", "beta")
                db.succeed("systemctl start postgresqlBackup-alpha.service postgresqlBackup-beta.service postgresql-dump-globals.service")
                sql("SET ROLE app; INSERT INTO t VALUES (100000, '${sentinel}')", "alpha")

            with subtest("the backup job alone takes the snapshot"):
                db.succeed("systemctl start restic-backups-postgresql.service")
                recorded = {"alpha": sql("SELECT count(*) FROM t", "alpha"), "beta": sql("SELECT count(*) FROM u", "beta")}
                print(f"recorded row counts: {recorded}")

            with subtest("drop both databases and the role, then restore"):
                sql("DROP DATABASE alpha")
                sql("DROP DATABASE beta")
                sql("DROP ROLE app")
                db.succeed("restic-postgresql restore latest --target /restore")
                # globals.sql recreates the postgres role too, which exists:
                # its one error is expected, so no ON_ERROR_STOP here.
                db.succeed("runuser -u postgres -- psql -X -q -d postgres < /restore${location}/globals.sql")
                for name in ("alpha", "beta"):
                    db.succeed(f"runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1 -d postgres < /restore${location}/{name}.sql")

            with subtest("the restored data equals the recorded data"):
                assert sql("SELECT count(*) FROM pg_roles WHERE rolname = 'app'") == "1", "role app was not restored"
                assert sql("SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = 'alpha'") == "app", "alpha is not owned by app"
                restored = {"alpha": sql("SELECT count(*) FROM t", "alpha"), "beta": sql("SELECT count(*) FROM u", "beta")}
                print(f"restored row counts: {restored}")
                assert sql("SELECT count(*) FROM t WHERE note = '${sentinel}'", "alpha") == "1", "sentinel missing: the snapshot holds a dump older than the backup run"
                assert restored == recorded, f"restored {restored} != recorded {recorded}"

            with subtest("the snapshot holds exactly the dump files"):
                snapshots = json.loads(db.succeed("restic-postgresql snapshots --json"))
                assert len(snapshots) == 1, f"expected one snapshot, got {len(snapshots)}"
                paths = sorted(snapshots[0]["paths"])
                print(f"snapshot paths: {paths}")
                assert paths == ["${location}/alpha.sql", "${location}/beta.sql", "${location}/globals.sql"], paths

            with subtest("the run's time is recorded and published"):
                for path in ("${metricsDirectory}/backup.prom", "$TEXTFILE/postgresql-backup.prom"):
                    value = db.succeed(f"awk '$1 == \"${seriesName}\" {{ print $2 }}' {path}").strip()
                    print(f"{path}: {value}")
                    assert int(value) >= start, f"{path} holds {value}, before the test's start {start}"
          '';
        };
    in
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        postgresql-backup-restore = restoreTest {
          name = "postgresql-backup-restore";
          passthru.prepareStartsNoDumps =
            pkgs.runCommand "postgresql-backup-restore-prepare-starts-no-dumps"
              {
                failed =
                  pkgs.testers.testBuildFailure
                    (restoreTest {
                      name = "postgresql-backup-restore-prepare-starts-no-dumps";
                      mutant.services.restic.backups.postgresql.backupPrepareCommand = lib.mkForce null;
                    }).config.rawTestDerivation;
              }
              ''
                grep -F "sentinel missing" "$failed/testBuildFailure.log"
                echo "mutant prepareStartsNoDumps rejected on the sentinel"
                touch "$out"
              '';
        };
      };
    };
}
