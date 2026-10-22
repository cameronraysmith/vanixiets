# checks.x86_64-linux.devloop-queries (design D14): binds the export queries
# and column grants of flake.lib.devloopCollection to the schema the nixbot
# input's migrations create, in a PostgreSQL started by nixpkgs'
# postgresqlTestHook with nixpkgs' postgresql_<postgresqlMajor>, the major
# devloop-collection's assertion binds to magnetite's package.
#
# Each run builds a fresh database: the input's migrations applied in
# lexical order, each with `psql -v ON_ERROR_STOP=1 --single-transaction`
# (the migrator's numeric order, one transaction per file, GR §1.3), the
# rendered grantSql, the fixture files, any mutant migration, then every
# entry of `roleQueries` as its role with its parameters bound through
# PREPARE … EXECUTE, and every entry of `assertions` over the results.
# Roles are LOGIN roles without a password, as on magnetite; the hook's
# initdb leaves local authentication at `trust`
# (postgres/postgres@REL_16_15:src/bin/initdb/initdb.c:2524-2532), so
# `psql -U <role>` opens a session as that role, and every privilege check
# runs against the role exactly as under magnetite's peer authentication.
#
# The clauses, each relating two independently defined values:
#   - marker: abandonMarker and the patch's production code (below);
#   - columns: the column names PostgreSQL returns for each rendered query
#     against the migrated schema, and the allow-list in schema.nix;
#   - abandoned: the query's value over fixture rows whose error text is
#     the patch's marker, the marker inside other text, other text and null,
#     and a failed row carrying the marker, and the fixture's expectation;
#   - error cells: every cell the attribute query returns, and the error
#     texts the fixtures stored, read back from the database;
#   - outputs_out: the query's value over a row whose outputs is null and
#     one whose outputs.out is a path, and the fixture's outputs;
#   - overlap: the rows returned for the fixture cursors, and the fixture
#     rows' ages relative to the cursors.
# Mutants, each of which must fail the run (D14): renameCached (a later
# migration renaming build_attributes.cached), selectError (a.error added to
# the attribute query's SELECT list), grantWithoutError (the collector's
# grant without build_attributes.error) and errorUnderAlias (a.error under
# the drv_path alias); the marker clause has two negative controls,
# markerLastCharacter and testLiteralsOnly. The real run's
# `pg_dump --schema-only` of the three tables is $out/schema.sql, compared
# at plan time with magnetite's dump.
#
# Task 4 (design D11): the reconcile's queries, reconcileQueries, run as
# devloop-reconcile over the fixed window of reconcile-fixtures.sql; the
# clauses relate their rows to that file's rows and verdicts, and the
# mutants reconcileGrantWithoutFinishedAt (the role's grant without
# build_attributes.finished_at) and currentFinishIgnoresDuplicates (a
# currentFinish explaining every key nixbot still has) must fail the run.
{
  self,
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { pkgs, system, ... }:
    let
      dc = self.lib.devloopCollection;
      inherit (self.lib.otelCollectorSchema.devloop) tables;
      postgresql = pkgs."postgresql_${dc.postgresqlMajor}";
      migrations = "${inputs.nixbot}/nixbot/nixbot/migrations";

      # psql variables set from fixture_clock before any query, each an SQL
      # timestamp expression over t0 rendered in the receiver's cursor form.
      clockVars = {
        cursor_old = "t0 - interval '10 minutes'";
        cursor_recent = "t0 - interval '1 minute'";
        window_start = "timestamptz '2026-10-20 00:00:00+00'";
        window_end = "timestamptz '2026-10-21 00:00:00+00'";
      };
      clockSql = pkgs.writeText "devloop-queries-clock.sql" (
        lib.concatStringsSep "\nUNION ALL\n" (
          lib.mapAttrsToList (
            name: expression:
            "SELECT '${name}=' || to_char((${expression}) AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS.US\"Z\"') FROM fixture_clock"
          ) clockVars
        )
        + ";\n"
      );

      # Loaded as postgres after the grants, in order.
      fixtureFiles = [
        ./devloop-queries/fixtures.sql
        ./devloop-queries/reconcile-fixtures.sql
      ];

      # Stored keys that nixbot's window lacks, as devloop-reconcile passes
      # them to currentFinish: restarted and finished later (explained),
      # restarted and unfinished (explained), equal to nixbot's (a duplicate,
      # unexplained), unknown to nixbot (unexplained), a build equal to
      # nixbot's (unexplained), an unknown build (unexplained), and a key
      # outside the window (ignored).
      reconcileKeys = [
        {
          build_id = 9102;
          attr = "checks.x86_64-linux.restarted";
          finished_at_us = 1792497600000000;
        }
        {
          build_id = 9102;
          attr = "checks.x86_64-linux.running";
          finished_at_us = 1792497600000000;
        }
        {
          build_id = 9101;
          attr = "checks.x86_64-linux.a";
          finished_at_us = 1792490400123456;
        }
        {
          build_id = 9101;
          attr = "checks.x86_64-linux.gone";
          finished_at_us = 1792501200000000;
        }
        {
          build_id = 9102;
          attr = null;
          finished_at_us = 1792494000000000;
        }
        {
          build_id = 9105;
          attr = null;
          finished_at_us = 1792494000000000;
        }
        {
          build_id = 9101;
          attr = "checks.x86_64-linux.a";
          finished_at_us = 1792627200000000;
        }
      ];

      # Each entry is one prepared statement run as one role, once per
      # execution; its result is $work/$db/<name>.<execution>.tsv.
      roleQueries = queries: [
        {
          name = "ci_attribute";
          role = "opentelemetry-collector";
          types = [ "text" ];
          sql = queries.ci_attribute;
          executions = {
            old = [ ":'cursor_old'" ];
            recent = [ ":'cursor_recent'" ];
          };
        }
        {
          name = "ci_build";
          role = "opentelemetry-collector";
          types = [ "text" ];
          sql = queries.ci_build;
          executions = {
            old = [ ":'cursor_old'" ];
            recent = [ ":'cursor_recent'" ];
          };
        }
        # The error texts the fixtures stored, read back as postgres: the
        # second value source of the error-cell clause.
        {
          name = "fixture_errors";
          role = "postgres";
          types = [ ];
          sql = "SELECT DISTINCT error FROM build_attributes WHERE error IS NOT NULL ORDER BY 1";
          executions.all = [ ];
        }
        {
          name = "reconcile_attributes";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).attributes;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
          ];
        }
        {
          name = "reconcile_builds";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).builds;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
          ];
        }
        {
          name = "reconcile_batch_builds";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).batchBuilds;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
          ];
        }
        {
          name = "reconcile_current_finish";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
            "jsonb"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).currentFinish;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
            "'${builtins.toJSON reconcileKeys}'"
          ];
        }
      ];

      queryFile =
        query: execution: arguments:
        let
          list = items: lib.optionalString (items != [ ]) "(${lib.concatStringsSep ", " items})";
        in
        pkgs.writeText "devloop-queries-${query.name}-${execution}.sql" ''
          PREPARE ${query.name}${list query.types} AS
          ${query.sql};
          EXECUTE ${query.name}${list arguments};
        '';

      header =
        table: lib.concatStringsSep "\t" ([ "body" ] ++ map (column: column.name) tables.${table}.columns);

      # Each script runs with $db set and returns non-zero on failure.
      assertions = [
        {
          label = "ci_attribute returns body and the allow-listed columns in order";
          script = ''[ "$(head -n 1 "$(result ci_attribute old)")" = ${lib.escapeShellArg (header "ci_attribute")} ]'';
        }
        {
          label = "ci_build returns body and the allow-listed columns in order";
          script = ''[ "$(head -n 1 "$(result ci_build old)")" = ${lib.escapeShellArg (header "ci_build")} ]'';
        }
        {
          label = "abandoned is true only for the ignored_failure row whose error is exactly the marker";
          script = ''
            [ "$(value ci_attribute old attr checks.x86_64-linux.marker abandoned)" = true ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.other-ignored abandoned)" = false ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.null-error abandoned)" = false ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.marker-in-text abandoned)" = false ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.failed-marker abandoned)" = false ]
          '';
        }
        {
          label = "no ci_attribute cell holds any error text the fixtures stored";
          script = ''
            errors=$(result fixture_errors all)
            [ "$(tail -n +2 "$errors" | wc -l)" -ge 4 ] &&
              ! tail -q -n +2 "$(result ci_attribute old)" "$(result ci_attribute recent)" |
              grep -qF -f <(tail -n +2 "$errors")
          '';
        }
        {
          label = "outputs_out is empty for a null outputs";
          script = ''
            [ "$(value ci_attribute old attr checks.x86_64-linux.other-ignored outputs_out)" = "" ] &&
              [ "$(value ci_attribute old attr checks.x86_64-linux.recent outputs_out)" = /nix/store/dddd-recent ]
          '';
        }
        {
          label = "with a cursor 10 min old, the rows tied with the cursor and the rows 4 min old are returned";
          script = ''
            value ci_attribute old attr checks.x86_64-linux.marker attr >/dev/null &&
              value ci_attribute old attr checks.x86_64-linux.other-ignored attr >/dev/null &&
              value ci_attribute old attr checks.x86_64-linux.null-error attr >/dev/null &&
              value ci_attribute old attr checks.x86_64-linux.recent attr >/dev/null &&
              value ci_build old build_id 101 build_id >/dev/null &&
              value ci_build old build_id 102 build_id >/dev/null
          '';
        }
        {
          label = "with a cursor 1 min old, the rows 4 min old are returned and the rows 7 min old are not";
          script = ''
            value ci_attribute recent attr checks.x86_64-linux.recent attr >/dev/null &&
              value ci_build recent build_id 102 build_id >/dev/null &&
              ! value ci_attribute recent attr checks.x86_64-linux.old attr >/dev/null &&
              ! value ci_build recent build_id 103 build_id >/dev/null
          '';
        }
        {
          label = "reconcile: attributes returns nixbot's (build_id, attr, finished_at) in the window, the start included, as devloop-reconcile";
          script = ''
            [ "$(tail -n +2 "$(result reconcile_attributes window)" | LC_ALL=C sort)" = ${
              lib.escapeShellArg (
                lib.concatStringsSep "\n" [
                  "9101\tchecks.x86_64-linux.a\t1792490400123456"
                  "9101\tchecks.x86_64-linux.cached\t1792490400123456"
                  "9106\tchecks.x86_64-linux.midnight\t1792454400000000"
                ]
              )
            } ]
          '';
        }
        {
          label = "reconcile: builds returns nixbot's (id, finished_at) in the window, the start included and the end excluded, as devloop-reconcile";
          script = ''
            [ "$(tail -n +2 "$(result reconcile_builds window)" | LC_ALL=C sort)" = ${
              lib.escapeShellArg (
                lib.concatStringsSep "\n" [
                  "9101\t1792490400123456"
                  "9102\t1792494000000000"
                  "9106\t1792454400000000"
                ]
              )
            } ]
          '';
        }
        {
          label = "reconcile: batchBuilds counts the one gitea-mq/batch/ build finished in the window as devloop-reconcile";
          script = ''[ "$(tail -n +2 "$(result reconcile_batch_builds window)")" = 1 ]'';
        }
        {
          label = "reconcile: currentFinish returns exactly the stored keys nixbot does not explain, as devloop-reconcile";
          script = ''
            [ "$(tail -n +2 "$(result reconcile_current_finish window)" | LC_ALL=C sort)" = ${
              lib.escapeShellArg (
                lib.concatStringsSep "\n" [
                  "9101\tchecks.x86_64-linux.a\t1792490400123456\t1792490400123456"
                  "9101\tchecks.x86_64-linux.gone\t1792501200000000\tabsent"
                  "9102\t\t1792494000000000\t1792494000000000"
                  "9105\t\t1792494000000000\tabsent"
                ]
              )
            } ]
          '';
        }
      ];

      replaceOnce =
        name: from: to: text:
        let
          replaced = builtins.replaceStrings [ from ] [ to ] text;
        in
        assert lib.assertMsg (replaced != text) "devloop-queries: mutant ${name} matched nothing";
        replaced;

      real = {
        inherit (dc) queries grantSql;
        afterFixtures = [ ];
      };
      mutants = {
        renameCached = real // {
          afterFixtures = [ ./devloop-queries/mutant-rename-cached.sql ];
        };
        selectError = real // {
          queries = dc.queries // {
            ci_attribute =
              replaceOnce "selectError" "SELECT '' AS \"body\",\n" "SELECT '' AS \"body\",\n  a.error,\n"
                dc.queries.ci_attribute;
          };
        };
        grantWithoutError = real // {
          grantSql =
            replaceOnce "grantWithoutError" ''"cached", "error", "drv_path"'' ''"cached", "drv_path"''
              dc.grantSql;
        };
        # The reconcile's grant without build_attributes.finished_at: its
        # attribute query must then be refused (design D10).
        reconcileGrantWithoutFinishedAt = real // {
          grantSql =
            replaceOnce "reconcileGrantWithoutFinishedAt"
              ''GRANT SELECT ("build_id", "attr", "finished_at") ON "build_attributes" TO "devloop-reconcile";''
              ''GRANT SELECT ("build_id", "attr") ON "build_attributes" TO "devloop-reconcile";''
              dc.grantSql;
        };
        # A currentFinish that explains every key nixbot still has, so a
        # duplicated stored row would pass C1 (design D11).
        currentFinishIgnoresDuplicates = real // {
          queries = dc.queries // {
            reconcile = dc.reconcileQueries // {
              currentFinish =
                replaceOnce "currentFinishIgnoresDuplicates"
                  "WHERE NOT c.present OR (c.current_us IS NOT NULL AND c.current_us <= c.finished_at_us)"
                  "WHERE NOT c.present"
                  dc.reconcileQueries.currentFinish;
            };
          };
        };
        errorUnderAlias = real // {
          queries = dc.queries // {
            ci_attribute =
              replaceOnce "errorUnderAlias" ''coalesce((a.drv_path)::text, ''') AS "drv_path"''
                ''coalesce((a.error)::text, ''') AS "drv_path"''
                dc.queries.ci_attribute;
          };
        };
      };

      # The marker clause (design D13, D15; plan review F11): the two values
      # are flake.lib.devloopCollection.abandonMarker and the text of the
      # nixbot patch magnetite applies. The marker must appear in the
      # patch's production code, the three added lines of outcome_status
      # (modules/nixos/nixbot-abandon-optional-attributes.patch:145-147), not
      # merely somewhere in the patch, where its test literals (:379, :451)
      # would satisfy a bare search.
      patchText = builtins.readFile ../nixos/nixbot-abandon-optional-attributes.patch;
      patchLines = lib.splitString "\n" patchText;
      productionContext =
        marker:
        lib.concatStringsSep "\n" [
          "+        return AttributeStatus.ignored_failure, ("
          "+            \"${marker}\""
          "+            if outcome == BuildOutcome.abandoned"
        ];
      markerHolds = text: marker: lib.hasInfix (productionContext marker) text;
      lastCharacterChanged =
        let
          stem = lib.substring 0 (lib.stringLength dc.abandonMarker - 1) dc.abandonMarker;
        in
        stem + (if lib.hasSuffix "x" dc.abandonMarker then "y" else "x");
      testLiterals = map (number: lib.elemAt patchLines (number - 1)) [
        379
        451
      ];
      markerClauses =
        assert lib.assertMsg (lib.all (line: lib.hasInfix "\"${dc.abandonMarker}\"" line) testLiterals)
          "devloop-queries: lines 379 and 451 of the abandonment patch no longer hold the marker's test literals; update testLiterals";
        [
          {
            label = "ok: the patch's production code returns abandonMarker as an abandoned attribute's error";
            holds = markerHolds patchText dc.abandonMarker;
          }
          {
            label = "mutant markerLastCharacter rejected: the production context with the marker's last character changed is not in the patch";
            holds = !markerHolds patchText lastCharacterChanged;
          }
          {
            label = "mutant testLiteralsOnly rejected: the patch's test literals (:379, :451) alone do not hold the production context";
            holds = !markerHolds (lib.concatStringsSep "\n" testLiterals) dc.abandonMarker;
          }
        ];

      # run_<name>: builds database <db>, runs every query and assertion;
      # returns 1 at the first failure.
      runFunction = name: db: run: ''
        run_${name}() {
          local db=${db}
          createdb -U postgres "$db" || return 1
          mkdir -p "$work/$db"
          for migration in ${migrations}/*.sql; do
            psql -X -q -v ON_ERROR_STOP=1 --single-transaction -U postgres -d "$db" -f "$migration" || return 1
          done
          sql_as postgres "$db" ${pkgs.writeText "devloop-queries-grants.sql" run.grantSql} || return 1
          ${lib.concatMapStrings (file: ''
            sql_as postgres "$db" ${file} || return 1
          '') (fixtureFiles ++ run.afterFixtures)}
          psql -X -q -A -t -v ON_ERROR_STOP=1 -U postgres -d "$db" -f ${clockSql} > "$work/$db/clock" || return 1
          clock_args=()
          while IFS= read -r line; do clock_args+=(-v "$line"); done < "$work/$db/clock"
          ${lib.concatMapStrings (
            query:
            lib.concatStrings (
              lib.mapAttrsToList (execution: arguments: ''
                psql -X -q -A -F "$tab" -P footer=off -v ON_ERROR_STOP=1 "''${clock_args[@]}" \
                  -U ${lib.escapeShellArg query.role} -d "$db" -f ${queryFile query execution arguments} \
                  > "$(result ${query.name} ${execution})" || return 1
              '') query.executions
            )
          ) (roleQueries run.queries)}
          ${lib.concatMapStrings (assertion: ''
            if ! { ${assertion.script}
            }; then
              echo ${lib.escapeShellArg "FAIL: ${assertion.label}"}
              return 1
            fi
            echo ${lib.escapeShellArg "ok: ${assertion.label}"}
          '') assertions}
        }
      '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        devloop-queries = pkgs.stdenvNoCC.mkDerivation {
          name = "devloop-queries";
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          dontInstall = true;
          doCheck = true;
          nativeCheckInputs = [
            postgresql
            pkgs.postgresqlTestHook
          ];
          checkPhase = ''
            runHook preCheck
            work=$(mktemp -d)
            tab=$'\t'

            sql_as() { psql -X -q -v ON_ERROR_STOP=1 -U "$1" -d "$2" -f "$3"; }
            # result NAME EXECUTION: the result file of one execution in $db.
            result() { echo "$work/$db/$1.$2.tsv"; }
            # value NAME EXECUTION KEYCOLUMN KEY COLUMN: COLUMN of the first
            # row whose KEYCOLUMN is KEY; exit 1 when there is none.
            value() {
              awk -F "$tab" -v k="$3" -v key="$4" -v c="$5" '
                NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; if (!(k in col) || !(c in col)) exit 2; next }
                $col[k] == key { print $col[c]; found = 1; exit }
                END { if (!found) exit 1 }
              ' "$(result "$1" "$2")"
            }

            ${lib.concatMapStrings (clause: ''
              if [ ${lib.boolToString clause.holds} != true ]; then
                echo ${lib.escapeShellArg "FAIL: ${clause.label}"}
                exit 1
              fi
              echo ${lib.escapeShellArg clause.label}
            '') markerClauses}

            psql -X -q -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
            CREATE ROLE "opentelemetry-collector" LOGIN;
            CREATE ROLE "devloop-reconcile" LOGIN;
            SQL

            ${runFunction "real" "nixbot" real}
            ${lib.concatStrings (lib.mapAttrsToList (name: run: runFunction name "nixbot_${name}" run) mutants)}

            run_real
            mkdir -p "$out"
            pg_dump -U postgres --schema-only -t builds -t build_attributes -t projects nixbot > "$out/schema.sql"

            ${lib.concatMapStrings (name: ''
              if output=$(run_${name} 2>&1); then
                echo "$output"
                echo "FAIL: mutant ${name} was accepted"
                exit 1
              fi
              echo "mutant ${name} rejected: $(grep -m 1 -E 'FAIL: |ERROR: ' <<< "$output")"
            '') (lib.attrNames mutants)}

            runHook postCheck
          '';
        };
      };
    };
}
