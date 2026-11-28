# mkNixEvalJobsIets: iets as a `nix-eval-jobs` package nixbot can take in
# services.nixbot.packages.nix-eval-jobs (CAM-111 design D3). Its only
# executable is bin/nix-eval-jobs, a link to iets' own binary, which
# dispatches on its argv[0] (numtide/iets src/cli/classic/mod.rs:45), so
# nixbot's bare `nix-eval-jobs` reaches iets' eval-jobs. Not iets' `classic`
# package, which bundles a second Nix and shims four other command names.
#
# The passthru is what nixbot and the evaluation lock read off the package:
# - pname "nix-eval-jobs": the lock module finds evaluators on a PATH by that
#   name (modules/nixos/nix-eval-lock.nix), so an unwrapped iets is still
#   caught;
# - version: wrapNixEvalJobsWithLock requires it (modules/lib/nix-eval-lock.nix);
# - nix: the stock evaluator's nix, grafted on, because nixbot puts
#   packages.nix-eval-jobs.nix on its unit PATH and links its own package
#   against it; with the stock's derivation the nix CLI and the nixbot
#   package stay as they are, and the lock's isWrapped comparison holds;
# - evaluator "iets": the name nixbot's evaluation records carry
#   (NIXBOT_EVALUATOR, modules/nixos/nixbot.nix).
#
# `stock` is the evaluator nixbot would otherwise use, normally
# options.services.nixbot.packages.nix-eval-jobs.default. Magnetite's
# instance is vanixiets.nixbot.ietsEvaluator, which modules/nixos/nixbot.nix
# selects, lock-wrapped, as nixbot's evaluator (CAM-111 task 5.2);
# checks.x86_64-linux.nix-eval-jobs-iets pins its shape. An iets bump is
# merged only after `just eval-identity` finds it gives the stock
# evaluator's drvPaths.
{ lib, ... }:
{
  flake.lib.mkNixEvalJobsIets =
    pkgs: iets: stock:
    pkgs.runCommand "nix-eval-jobs-iets-${iets.version}"
      {
        passthru = {
          pname = "nix-eval-jobs";
          evaluator = "iets";
          inherit (iets) version;
          inherit (stock) nix;
        };
        meta.mainProgram = "nix-eval-jobs";
      }
      ''
        mkdir -p $out/bin
        ln -s ${lib.getExe' iets "iets"} $out/bin/nix-eval-jobs
      '';
}
