# checks.x86_64-linux.postgresql-collation (F61): the collation drift probe
# of modules/nixos/postgresql-collation.nix, built with magnetite's
# PostgreSQL and glibc's locales, run as a role holding no grant against a
# PostgreSQL started by nixpkgs' postgresqlTestHook over the databases of
# ./postgresql-collation/setup.sql, with `parked` parked, must write exactly
# ./postgresql-collation/expected.prom, its @glibc@ the glibc version
# magnetite's PostgreSQL is linked against: a drifted database 1, a matching
# one 0, one with no recorded version 0, the parked one absent, and a name
# with a quote and a backslash escaped; the hook's own C-locale databases,
# test_db among them, record no version and write 0. The mutants, each of which must
# change the output: selfCompared (the recorded version compared with
# itself), parkedIgnored (the parked list not applied) and nullCounted (a
# null recorded version counted as drift).
#
# At evaluation it also relates the parked list to cognee's switch:
# magnetite, cognee parked, parks exactly the database cognee's module
# names, and magnetite with cognee enabled parks nothing, so reviving
# cognee brings its database under PostgresqlCollationDrift.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite;
      postgresql = magnetite.config.services.postgresql.package;
      glibc = lib.versions.majorMinor magnetite.pkgs.glibc.version;
      collation = self.lib.postgresqlCollation;
      sql = builtins.readFile ../nixos/postgresql-collation/drift.sql;

      probeWith =
        text:
        lib.getExe (
          collation.probe {
            inherit pkgs postgresql;
            sql = text;
          }
        );
      mutate =
        name: from: to:
        assert lib.assertMsg (lib.hasInfix from sql)
          "postgresql-collation check: mutant ${name} found nothing to replace";
        builtins.replaceStrings [ from ] [ to ] sql;
      mutants = {
        selfCompared =
          mutate "selfCompared" "recorded IS DISTINCT FROM actual"
            "recorded IS DISTINCT FROM recorded";
        parkedIgnored = mutate "parkedIgnored" "WHERE datname <> ALL" "WHERE true OR datname <> ALL";
        nullCounted = mutate "nullCounted" "recorded IS NOT NULL AND " "";
      };

      parked = pkgs.writeText "postgresql-collation-parked.json" (builtins.toJSON [ "parked" ]);
      expected = pkgs.replaceVars ./postgresql-collation/expected.prom { inherit glibc; };

      parkedOf = system: system.config.vanixiets.postgresqlCollation.parkedDatabases;
      revived = magnetite.extendModules {
        modules = [ { vanixiets.cognee.enable = lib.mkForce true; } ];
      };
      clauses = [
        {
          label = "magnetite, cognee parked, parks exactly cognee's database";
          holds = parkedOf magnetite == [ magnetite.config.services.cognee.database.name ];
        }
        {
          label = "magnetite with cognee enabled parks nothing";
          holds = parkedOf revived == [ ];
        }
      ];
      failing = map (c: c.label) (lib.filter (c: !c.holds) clauses);
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        postgresql-collation =
          assert lib.assertMsg (
            failing == [ ]
          ) "postgresql-collation check: ${lib.concatStringsSep "; " failing}";
          pkgs.stdenvNoCC.mkDerivation {
            name = "postgresql-collation";
            dontUnpack = true;
            dontConfigure = true;
            dontBuild = true;
            dontInstall = true;
            doCheck = true;
            nativeCheckInputs = [
              postgresql
              pkgs.postgresqlTestHook
              pkgs.diffutils
            ];
            # initdb's own databases in the C locale, which records no
            # version; the server finds en_US.UTF-8 in the archive.
            LANG = "C";
            LOCALE_ARCHIVE = "${magnetite.pkgs.glibcLocales}/lib/locale/locale-archive";
            meta.description = "behavioural check: the PostgreSQL collation drift probe against a real server, with three mutants";
            checkPhase = ''
              runHook preCheck
              psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres -f ${./postgresql-collation/setup.sql}
              PGUSER=probe ${probeWith sql} ${parked} > got.prom
              diff -u ${expected} got.prom
              echo "ok: the probe's textfile"
              ${lib.concatStrings (
                lib.mapAttrsToList (name: text: ''
                  PGUSER=probe ${probeWith text} ${parked} > mutant.prom
                  if diff -u ${expected} mutant.prom; then
                    echo "FAIL: mutant ${name} was accepted" >&2
                    exit 1
                  fi
                  echo "mutant ${name} rejected"
                '') mutants
              )}
              mkdir -p "$out"
              cp got.prom "$out/"
              runHook postCheck
            '';
          };
      };
    };
}
