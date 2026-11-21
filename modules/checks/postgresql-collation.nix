# checks.x86_64-linux.postgresql-collation (F61, Q68a): the collector's
# sqlquery/postgresql-collation receiver, flake.lib.postgresqlCollation's
# receiver in magnetite's otelcol-contrib, runs as a role holding no grant
# against a PostgreSQL started by nixpkgs' postgresqlTestHook over the
# databases of ./postgresql-collation/setup.sql, with `parked` parked, and
# its first export through the file exporter must be exactly
# ./postgresql-collation/expected.prom, written as
# name{attributes} value with each attribute value JSON-quoted, its @glibc@
# the glibc version magnetite's PostgreSQL is linked against: a drifted
# database 1, a matching one 0, one with no recorded version 0, the parked
# one absent, and a name with a quote and a backslash carried whole; the
# hook's own C-locale databases, test_db among them, record no version and
# report 0. Every point must be an int gauge with no unit, so the store
# keeps the name. The mutants, each of which must change the output:
# selfCompared (the recorded version compared with itself), parkedIgnored
# (the parked list not applied) and nullCounted (a null recorded version
# counted as drift).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite;
      postgresql = magnetite.config.services.postgresql.package;
      collector = magnetite.config.services.opentelemetry-collector.package;
      glibc = lib.versions.majorMinor magnetite.pkgs.glibc.version;
      collation = self.lib.postgresqlCollation;
      sql = builtins.readFile ../nixos/postgresql-collation/drift.sql;

      configWith =
        text:
        pkgs.writeText "postgresql-collation-collector.json" (
          builtins.toJSON {
            receivers.sqlquery = collation.receiver {
              datasource = "host=\${env:PGHOST} dbname=postgres user=probe sslmode=disable";
              parked = [ "parked" ];
              sql = text;
              collectionInterval = "1s";
            };
            exporters.file.path = "export.jsonl";
            service = {
              telemetry.metrics.level = "none";
              pipelines.metrics = {
                receivers = [ "sqlquery" ];
                exporters = [ "file" ];
              };
            };
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

      # The receiver's first export, one line per point.
      points = pkgs.writeText "postgresql-collation-points.jq" ''
        .resourceMetrics[].scopeMetrics[].metrics[]
        | if (.unit // "") != "" or (.gauge | not) then error("\(.name) is not a unitless gauge") else . end
        | .name as $name
        | .gauge.dataPoints[]
        | if has("asDouble") then error("\($name) has a double point") else . end
        | (.attributes | map({ (.key): .value.stringValue }) | add) as $a
        | "\($name){datname=\($a.datname | tojson),collversion_recorded=\($a.collversion_recorded | tojson),collversion_actual=\($a.collversion_actual | tojson)} \(.asInt // "0")"
      '';
      run = text: output: ''
        rm -f export.jsonl
        ${lib.getExe' collector "otelcol-contrib"} --config ${configWith text} > collector.log 2>&1 &
        pid=$!
        for _ in $(seq 60); do
          [ -s export.jsonl ] && [ "$(wc -l < export.jsonl)" -ge 1 ] && break
          sleep 1
        done
        kill "$pid"
        wait "$pid" || true
        if [ ! -s export.jsonl ]; then
          cat collector.log
          echo "FAIL: the receiver exported nothing in 60 s" >&2
          exit 1
        fi
        head -n 1 export.jsonl | jq -r -f ${points} | LC_ALL=C sort -u > ${output}
      '';

      expected = pkgs.replaceVars ./postgresql-collation/expected.prom { inherit glibc; };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        postgresql-collation = pkgs.stdenvNoCC.mkDerivation {
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
            pkgs.jq
          ];
          # initdb's own databases in the C locale, which records no
          # version; the server finds en_US.UTF-8 in the archive.
          LANG = "C";
          LOCALE_ARCHIVE = "${magnetite.pkgs.glibcLocales}/lib/locale/locale-archive";
          meta.description = "behavioural check: the collector's PostgreSQL collation drift receiver against a real server, with three mutants";
          checkPhase = ''
            runHook preCheck
            psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres -f ${./postgresql-collation/setup.sql}
            ${run sql "got.prom"}
            diff -u ${expected} got.prom
            echo "ok: the receiver's points"
            ${lib.concatStrings (
              lib.mapAttrsToList (name: text: ''
                ${run text "mutant.prom"}
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
