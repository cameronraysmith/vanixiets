# checks.x86_64-linux.postgresql-backup-obligations: the judge of
# flake.lib.postgresqlBackupObligations (modules/nixos/postgresql-backup.nix,
# openspec change back-up-postgresql-off-host, design D15) accepts a host
# whose dumps, restic paths, prepare step and notified units cover its
# backup set, and a host whose parked database is left out; it finds exactly
# one problem in each mutant, each mutant changing one fact of the accepted
# host: a database without a dump (missingDatabase), a dump with a timer of
# its own (dumpTimer), compressed dumps (compressed), a dump file restic does
# not upload (pathMissing), a dump the prepare step does not start
# (prepareMissing), a dump unit no failure notice names (unitNotNotified), a
# PostgreSQL host with the backup off that is not awaiting its secrets
# (notEnabled), a host still listed as awaiting its secrets with the backup
# on (awaitingButEnabled), and a host with the backup on whose vars are not
# in the repository (secretsMissing). A host awaiting its secrets with the
# backup off, and a host without PostgreSQL, give no problem.
#
# Per-host facts are asserted by modules/checks/machines.nix on every
# nixos-<host> and darwin-<host> check, which already evaluates the
# configuration. No host is evaluated here; the fixtures are literals, so the
# check runs on x86_64-linux only.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = self.lib.postgresqlBackupObligations;
      location = "/var/backup/postgresql-nightly";
      databases = [
        "gitea"
        "nixbot"
      ];
      units = map (db: "postgresqlBackup-${db}") databases ++ [ "postgresql-dump-globals" ];
      prepare = lib.concatMapStringsSep "\n" (unit: "systemctl start --wait ${unit}.service") units;
      accepted = {
        postgresql = {
          enable = true;
          ensureDatabases = databases;
        };
        enable = true;
        awaiting = false;
        secretsGenerated = true;
        parked = [ ];
        postgresqlBackup = {
          inherit databases location;
          compression = "none";
        };
        services = lib.genAttrs units (_: {
          startAt = [ ];
        });
        restic = {
          paths = map (db: "${location}/${db}.sql") databases ++ [ "${location}/globals.sql" ];
          backupPrepareCommand = prepare;
        };
        notifiedUnits = [ "restic-backups-postgresql" ] ++ units;
      };
      with' = f: accepted // f accepted // { problems = 1; };
      cases = {
        accepted = accepted // {
          problems = 0;
        };
        parkedLeftOut = accepted // {
          postgresql = accepted.postgresql // {
            ensureDatabases = databases ++ [ "parked" ];
          };
          parked = [ "parked" ];
          problems = 0;
        };
        awaitingSecrets = accepted // {
          enable = false;
          awaiting = true;
          secretsGenerated = false;
          problems = 0;
        };
        noPostgresql = accepted // {
          postgresql.enable = false;
          enable = false;
          problems = 0;
        };
        missingDatabase = with' (a: {
          postgresql = a.postgresql // {
            ensureDatabases = databases ++ [ "omnigent" ];
          };
        });
        dumpTimer = with' (a: {
          services = a.services // {
            postgresqlBackup-nixbot.startAt = [ "*-*-* 01:15:00" ];
          };
        });
        compressed = with' (a: {
          postgresqlBackup = a.postgresqlBackup // {
            compression = "zstd";
          };
        });
        pathMissing = with' (a: {
          restic = a.restic // {
            paths = lib.remove "${location}/globals.sql" a.restic.paths;
          };
        });
        prepareMissing = with' (a: {
          restic = a.restic // {
            backupPrepareCommand = "systemctl start --wait postgresqlBackup-gitea.service postgresql-dump-globals.service";
          };
        });
        unitNotNotified = with' (a: {
          notifiedUnits = lib.remove "postgresqlBackup-gitea" a.notifiedUnits;
        });
        notEnabled = with' (_: {
          enable = false;
        });
        awaitingButEnabled = with' (_: {
          awaiting = true;
        });
        secretsMissing = with' (_: {
          secretsGenerated = false;
        });
      };
      wrong = lib.filterAttrs (
        _: case: lib.length (o.problems (removeAttrs case [ "problems" ])) != case.problems
      ) cases;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        postgresql-backup-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.postgresql-backup-obligations =
        assert lib.assertMsg (
          wrong == { }
        ) "postgresql-backup-obligations: the judge misjudges ${toString (lib.attrNames wrong)}";
        pkgs.runCommand "postgresql-backup-obligations" { } "touch $out";
    };
}
