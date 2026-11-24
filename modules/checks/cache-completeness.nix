# checks.x86_64-linux.cache-completeness (F81): the probe of
# modules/nixos/cache-completeness.nix, built with magnetite's PostgreSQL,
# against nixbot's own schema (the pinned input's migrations) holding
# ./cache-completeness/fixture.sql, and a fixture cache served on loopback.
# Its first run only records since and passes. With since 10 hours back it
# must fail naming exactly missing-1, the one output in its window that the
# fixture cache answers 404 for, from a pull request's build reused for the
# default branch: not those of the build still settling, the one from before
# since, the pull request that has not landed, the push to another branch or
# the build still running, nor the failed attribute or the one without an
# output; and served-1 once although two builds recorded it. Capped at one
# output it must say so and check the newest. Once the fixture serves
# missing-1 too, it must pass.
{ self, inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      magnetite = self.nixosConfigurations.magnetite;
      postgresql = magnetite.config.services.postgresql.package;
      probeWith =
        args:
        lib.getExe (
          self.lib.cacheCompleteness.probe (
            {
              inherit pkgs postgresql;
            }
            // args
          )
        );
      probe = probeWith { };
      migrations = "${inputs.nixbot}/nixbot/nixbot/migrations";
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        cache-completeness = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        cache-completeness = pkgs.stdenvNoCC.mkDerivation {
          name = "cache-completeness";
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;
          dontInstall = true;
          doCheck = true;
          nativeCheckInputs = [
            postgresql
            pkgs.postgresqlTestHook
            pkgs.python3
            pkgs.curl
          ];
          meta.description = "behavioural check: the cache completeness probe against nixbot's schema and a fixture cache with a missing narinfo";
          checkPhase = ''
            runHook preCheck
            for m in ${migrations}/*.sql; do
              psql -X -q -1 -v ON_ERROR_STOP=1 -f "$m"
            done
            psql -X -q -v ON_ERROR_STOP=1 -f ${./cache-completeness/fixture.sql}

            mkdir cache
            touch cache/00000000000000000000000000000001.narinfo
            python3 -m http.server --bind 127.0.0.1 --directory cache 8081 2>http.log &
            for _ in $(seq 50); do
              curl -sf -o /dev/null -I http://127.0.0.1:8081/00000000000000000000000000000001.narinfo && break
              sleep 0.2
            done
            url=http://127.0.0.1:8081

            ${probe} since $url > first.txt
            test -s since
            grep -q '^first run' first.txt
            echo "ok: the first run records since and passes"

            date -u -d '10 hours ago' +%Y-%m-%dT%H:%M:%SZ > since
            if ${probe} since $url > got.txt; then
              cat got.txt
              echo "FAIL: the probe passed with missing-1 not served" >&2
              exit 1
            fi
            cat got.txt
            test "$(grep '^missing' got.txt)" = "missing 404 /nix/store/00000000000000000000000000000002-missing-1"
            grep -q '^checked 2 outputs' got.txt
            echo "ok: the probe fails on exactly the missing output"

            # Capped at one output, the newest: build 7's served-1.
            ${probeWith { limit = 1; }} since $url > capped.txt
            cat capped.txt
            grep -q '^the window holds more than 1 outputs' capped.txt
            grep -q '^checked 1 outputs .*, 0 not served' capped.txt
            echo "ok: a capped run says so and checks the newest"

            touch cache/00000000000000000000000000000002.narinfo
            ${probe} since $url > after.txt
            cat after.txt
            grep -q '^checked 2 outputs .*, 0 not served' after.txt
            echo "ok: the probe passes once it is served"

            mkdir -p "$out"
            cp got.txt after.txt "$out/"
            runHook postCheck
          '';
        };
      };
    };
}
