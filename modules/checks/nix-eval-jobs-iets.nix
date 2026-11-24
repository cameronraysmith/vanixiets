# What nixbot and the evaluation lock need from the iets evaluator package
# (CAM-111 design D3; tasks.md 3.3), checked on flake.lib.mkNixEvalJobsIets
# built from the pinned iets input and nixbot's own stock nix-eval-jobs (the
# derivation magnetite's services.nixbot.packages.nix-eval-jobs.default is),
# so no host configuration is evaluated here:
# - its only executable is bin/nix-eval-jobs, a link to iets' bin/iets;
# - pname is nix-eval-jobs, evaluator is iets, version is iets' version;
# - its nix is the stock evaluator's nix, by derivation;
# - wrapped by the lock (flake.lib.wrapNixEvalJobsWithLock), the wrapper
#   keeps it as `unwrapped`, forwards its version and the same nix (the lock
#   module's isWrapped comparison), and execs its bin/nix-eval-jobs.
# Over the host evaluators (modules/lib/nix-eval-jobs-host.nix):
# - the bound rules give every Linux rule a worker and a per-worker memory
#   bound and every darwin rule a worker bound only, and every member that
#   runs Nix has a memory; mutant `linuxMemoryDropped` (the Linux rules
#   without their memory bound) must be reported;
# - the lock's judgement (flake.lib.nixEvalLockUnwrapped, which the lock
#   module asserts over every profile and service PATH of a locked host)
#   passes the lock-wrapped iets and nix-eval-jobs-stock and reports
#   mutants `ietsUnlocked` (the bounded iets without the lock on nixbot's
#   service PATH) and `stockUnlocked` (nix-eval-jobs-stock over unwrapped
#   stock);
# - the per-host judgement every machine check applies
#   (flake.lib.nixEvalJobsObligations) passes a fixture of magnetite and
#   reports each mutant of it: `boundDropped`, `lockDisabled`,
#   `stockMissing`, `homeShadows`, `nixbotUnwrapped`, `nixbotUnbounded`,
#   and blackphos (memory unknown) carrying iets, `unclassifiedIets`;
# - built over a stub evaluator that prints its arguments, the bounded
#   wrapper at the largest Linux rule supplies the bound when the caller
#   gives none, caps a request above it (and a memory of 0, no limit), keeps
#   one below it and passes every other argument through; mutant
#   `memoryUnbounded` (the same wrapper built without the memory bound) must
#   fail the first case.
# The attribute properties are judged at evaluation and the files at build
# time; `checkFor` takes the package function so a mutant of it can be fed
# through the same judgement. Defined for x86_64-linux only: nixbot runs on
# magnetite, and the rules and the judgement are the same data on every
# system.
{ config, inputs, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.lib.nixEvalJobsIetsCheck =
    {
      lib,
      pkgs,
      system,
      mk ? flakeLib.mkNixEvalJobsIets,
    }:
    let
      iets = inputs.iets.packages.${system}.default;
      stock = inputs.nixbot.packages.${system}.nix-eval-jobs;
      package = mk pkgs iets stock;
      lockFile = "/etc/nix/eval.lock";
      wrapped = flakeLib.wrapNixEvalJobsWithLock pkgs lockFile package;
      failures =
        lib.optional ((package.pname or null) != "nix-eval-jobs")
          "pname is ${toString (package.pname or "unset")}, not nix-eval-jobs"
        ++
          lib.optional ((package.evaluator or null) != "iets")
            "evaluator is ${toString (package.evaluator or "unset")}, not iets"
        ++
          lib.optional ((package.version or null) != iets.version)
            "version is ${toString (package.version or "unset")}, not iets' ${iets.version}"
        ++ lib.optional (
          !(package ? nix) || package.nix.drvPath != stock.nix.drvPath
        ) "nix is not the stock evaluator's nix"
        ++ lib.optional (
          !(wrapped ? unwrapped) || wrapped.unwrapped.drvPath != package.drvPath
        ) "the lock wrapper does not keep the package as unwrapped"
        ++ lib.optional (
          !(wrapped ? nix) || wrapped.nix.drvPath != stock.nix.drvPath
        ) "the lock wrapper does not forward the stock nix"
        ++ lib.optional (
          (wrapped.version or null) != iets.version
        ) "the lock wrapper does not forward iets' version";

      rules = flakeLib.nixEvalJobsBoundRules;
      linuxBound = removeAttrs (builtins.head rules.nixos) [ "minGiB" ];
      linuxMemoryDropped = rules // {
        nixos = map (r: r // { maxMemorySize = null; }) rules.nixos;
      };
      bounded = flakeLib.mkNixEvalJobsIetsBounded pkgs (linuxBound // { inherit package; });
      wrap = flakeLib.wrapNixEvalJobsWithLock pkgs lockFile;
      stockAlias = flakeLib.mkNixEvalJobsStockAlias pkgs;
      judge = flakeLib.nixEvalLockUnwrapped;
      hostFailures =
        map (p: "bound rules: ${p}") (flakeLib.nixEvalJobsBoundProblems rules)
        ++ lib.optional (
          flakeLib.nixEvalJobsBoundProblems linuxMemoryDropped == [ ]
        ) "mutant linuxMemoryDropped is not reported"
        ++ lib.optional (
          judge {
            iets = [ (wrap bounded) ];
            stock = [ (stockAlias (wrap stock)) ];
          } != [ ]
        ) "the lock's judgement rejects the lock-wrapped iets or nix-eval-jobs-stock"
        ++ lib.optional (
          judge { "systemd.services.nixbot.path" = [ bounded ]; } != [ "systemd.services.nixbot.path" ]
        ) "mutant ietsUnlocked is not reported"
        ++ lib.optional (
          judge { stock = [ (stockAlias stock) ]; } != [ "stock" ]
        ) "mutant stockUnlocked is not reported"
        ++ (
          let
            obligations = flakeLib.nixEvalJobsObligations.failures;
            want = flakeLib.nixEvalJobsBound "magnetite";
            fake = drvPath: attrs: { inherit drvPath; } // attrs;
            ietsPkg = fake "/iets" {
              pname = "nix-eval-jobs";
              evaluator = "iets";
              bound = want;
              version = "0";
            };
            locked = fake "/locked-iets" {
              pname = "nix-eval-jobs";
              unwrapped = ietsPkg;
            };
            alias = fake "/stock" { pname = "nix-eval-jobs-stock"; };
            nixbotEvaluator = fake "/nixbot" {
              pname = "nix-eval-jobs";
              unwrapped = ietsPkg;
              version = "0";
            };
            magnetite = {
              services.nixEvalLock = {
                enable = true;
                bound = want;
                package = locked;
                stockPackage = alias;
              };
              environment.systemPackages = [
                locked
                alias
              ];
              home-manager.users.cameron.home.packages = [
                locked
                alias
              ];
              services.nixbot = {
                enable = true;
                evalWorkerCount = want.workers;
                evalMaxMemorySize = want.maxMemorySize;
                packages.nix-eval-jobs = nixbotEvaluator;
              };
              systemd.services.nixbot.environment.NIXBOT_EVALUATOR = "iets 0";
            };
            mutants = {
              boundDropped = lib.recursiveUpdate magnetite {
                services.nixEvalLock.package.unwrapped.bound = null;
              };
              lockDisabled = lib.recursiveUpdate magnetite { services.nixEvalLock.enable = false; };
              stockMissing = magnetite // {
                environment.systemPackages = [ locked ];
              };
              homeShadows = lib.recursiveUpdate magnetite {
                home-manager.users.cameron.home.packages = [ (fake "/other" { pname = "nix-eval-jobs"; }) ];
              };
              nixbotUnwrapped = magnetite // {
                services = magnetite.services // {
                  nixbot = magnetite.services.nixbot // {
                    packages.nix-eval-jobs = ietsPkg;
                  };
                };
              };
              nixbotUnbounded = lib.recursiveUpdate magnetite { services.nixbot.evalWorkerCount = 8; };
            };
            unclassifiedIets = {
              vanixiets.nixEvalJobs = {
                bound = null;
                package = ietsPkg;
                stockPackage = null;
              };
              environment.systemPackages = [ ];
            };
          in
          map (f: "the magnetite fixture fails: ${f}") (obligations "magnetite" magnetite)
          ++ lib.mapAttrsToList (n: _: "mutant ${n} is not reported") (
            lib.filterAttrs (_: c: obligations "magnetite" c == [ ]) mutants
          )
          ++ lib.optional (
            obligations "blackphos" unclassifiedIets == [ ]
          ) "mutant unclassifiedIets is not reported"
        );

      stub = pkgs.writeShellScriptBin "nix-eval-jobs" ''echo "$*"'' // {
        inherit (package) version nix evaluator;
      };
      stubBounded = flakeLib.mkNixEvalJobsIetsBounded pkgs (linuxBound // { package = stub; });
      memoryUnbounded = flakeLib.mkNixEvalJobsIetsBounded pkgs (
        linuxBound
        // {
          package = stub;
          maxMemorySize = null;
        }
      );
      w = toString linuxBound.workers;
      m = toString linuxBound.maxMemorySize;
    in
    pkgs.runCommand "nix-eval-jobs-iets"
      {
        meta.description = "check: the iets evaluator package has what nixbot and the evaluation lock need";
        failures = lib.concatStringsSep "\n" (failures ++ hostFailures);
      }
      ''
        fail() { echo "FAIL: $*" >&2; exit 1; }
        if [ -n "$failures" ]; then
          while IFS= read -r line; do echo "FAIL: $line" >&2; done <<< "$failures"
          exit 1
        fi
        [ "$(ls ${package}/bin)" = nix-eval-jobs ] || fail "bin/ holds $(ls ${package}/bin | tr '\n' ' '), not exactly nix-eval-jobs"
        [ "$(readlink ${package}/bin/nix-eval-jobs)" = ${lib.getExe' iets "iets"} ] \
          || fail "bin/nix-eval-jobs links to $(readlink ${package}/bin/nix-eval-jobs), not ${lib.getExe' iets "iets"}"
        grep -qF ${lib.escapeShellArg "evaluator=${package}/bin/nix-eval-jobs"} ${lib.getExe wrapped} \
          || grep -qF ${lib.escapeShellArg "evaluator='${package}/bin/nix-eval-jobs'"} ${lib.getExe wrapped} \
          || fail "the lock wrapper does not exec ${package}/bin/nix-eval-jobs"
        grep -qF ${lib.escapeShellArg lockFile} ${lib.getExe wrapped} || fail "the lock wrapper does not take ${lockFile}"

        # expect BIN EXPECTED ARGS...: BIN's stub prints EXPECTED for ARGS.
        expect() {
          local bin=$1 want=$2 got
          shift 2
          got=$("$bin" "$@" 2>/dev/null) || return 1
          [ "$got" = "$want" ] || { echo "  $bin $*: got '$got', want '$want'" >&2; return 1; }
        }
        bounded=${lib.getExe stubBounded}
        expect "$bounded" "--workers ${w} --max-memory-size ${m}" \
          || fail "the bounded wrapper does not supply the bound when the caller gives none"
        expect "$bounded" "--workers ${w} --max-memory-size ${m} --flake .#checks --force-recurse" \
          --workers 99 --max-memory-size 99999 --flake .#checks --force-recurse \
          || fail "the bounded wrapper does not cap a request above the bound"
        expect "$bounded" "--workers ${w} --max-memory-size ${m}" --max-memory-size 0 \
          || fail "the bounded wrapper does not cap a memory of 0 (no limit)"
        expect "$bounded" "--workers 1 --max-memory-size 512 --option eval-cache false" \
          --workers=1 --max-memory-size=512 --option eval-cache false \
          || fail "the bounded wrapper does not keep a request below the bound"
        if expect ${lib.getExe memoryUnbounded} "--workers ${w} --max-memory-size ${m}" 2>/dev/null; then
          fail "mutant memoryUnbounded passes the bound case"
        fi
        mkdir -p $out
        echo "ok: ${package} ($(readlink ${package}/bin/nix-eval-jobs)) wrapped by ${wrapped}" > $out/result
      '';

  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        nix-eval-jobs-iets = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        nix-eval-jobs-iets = flakeLib.nixEvalJobsIetsCheck { inherit lib pkgs system; };
      };
    };
}
