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
# The attribute properties are judged at evaluation and the files at build
# time; `checkFor` takes the package function so a mutant of it can be fed
# through the same judgement. Defined for x86_64-linux only: nixbot runs on
# magnetite.
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
    in
    pkgs.runCommand "nix-eval-jobs-iets"
      {
        meta.description = "check: the iets evaluator package has what nixbot and the evaluation lock need";
        failures = lib.concatStringsSep "\n" failures;
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
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        nix-eval-jobs-iets = flakeLib.nixEvalJobsIetsCheck { inherit lib pkgs system; };
      };
    };
}
