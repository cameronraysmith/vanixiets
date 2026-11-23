# Which nix-eval-jobs a host runs, decided by its memory (flake.lib.hosts,
# `memoryGiB`) and nothing else. A host whose memory holds an iets
# evaluation of the check set gets iets as `nix-eval-jobs`, bounded in
# workers and, on Linux, in per-worker memory, with stock beside it as
# `nix-eval-jobs-stock` for what iets refuses (import-from-derivation,
# --override-input, --override-flake, --repair, --help). Any other host,
# and a host whose memory is "unknown", keeps stock as `nix-eval-jobs` and
# gets nothing else. On NixOS both names are lock-wrapped
# (modules/nixos/nix-eval-lock.nix, which every NixOS host imports); on
# darwin they are installed as they are (modules/darwin/nix-eval-jobs.nix).
# Homes on a host install what the host chose (modules/home/development/
# nix-tools.nix); a standalone home gets stock.
#
# The rules, first match by platform, each from a measurement of
# `nix-eval-jobs --force-recurse` over checks at nixbot's arguments, as the
# evaluating cgroup's memory.peak (modules/README.md, Evaluators):
# - nixos, at least 30 GiB: 5 workers x 3072 MiB, nixbot's own bound.
#   magnetite (32 GiB), 2026-11-23: checks.x86_64-linux 41-43 s against
#   stock's 121-131 s, both systems 69 s against 198 s; a user evaluation
#   there is held at user.slice's 10 GiB MemoryHigh, and nixbot's unit,
#   unthrottled, peaks at 68-72 % of its 20 GiB (modules/nixos/nixbot.nix).
# - nixos, at least 15 GiB: 1 worker x 2048 MiB. pyrite (16 GiB, 4 cores,
#   a desktop, QEMU and container tests), 2026-11-23, checks.x86_64-linux:
#   iets 140 s and 3.2 GiB at 1 x 2048, 85-94 s and 5.1-5.5 GiB at 2 x
#   2048; stock at the remote lane's 2 x 2048 took 424-738 s and 4.0-4.6
#   GiB. Both systems: iets 172 s and 2.7 GiB at 1 x 2048, stock 759 s and
#   4.0 GiB. One worker keeps iets below the memory the stock lane already
#   took there, which is all a 16 GiB host is assumed to spare.
# - darwin, at least 48 GiB: 3 workers. iets ignores --max-memory-size on
#   macOS, so memory is bounded by the worker count only: stibnite
#   (64 GiB), 2026-11-23, peak process-tree RSS 19.8-20.2 GiB at 3 workers,
#   13.0 GiB at 1, within 3 % of 5 workers' wall time.
# - darwin, at least 8 GiB: 1 worker. argentum (M1, 8 GiB), 2026-11-23, at
#   nixbot's arguments: checks.aarch64-darwin iets 15.6 s and 4.8 GiB
#   against stock's 68-74 s and 12.6 GiB at 4 workers; both systems (338
#   attributes) iets 62-111 s, 12.8 GiB footprint, +5.3 GiB swap, against
#   stock's 232-354 s and 14.4 GiB. Two iets workers exceeded the swap guard
#   on both systems. The class decides the worker count, not whether iets is
#   installed: every darwin host with a known memory of at least 8 GiB gets
#   it.
{
  config,
  inputs,
  lib,
  ...
}:
let
  flakeLib = config.flake.lib;

  boundRules = {
    nixos = [
      {
        minGiB = 30;
        workers = 5;
        maxMemorySize = 3072;
      }
      {
        minGiB = 15;
        workers = 1;
        maxMemorySize = 2048;
      }
    ];
    darwin = [
      {
        minGiB = 48;
        workers = 3;
        maxMemorySize = null;
      }
      {
        minGiB = 8;
        workers = 1;
        maxMemorySize = null;
      }
    ];
  };

  # The bound for a host's class and memory, or null for stock.
  boundFor =
    {
      class,
      memoryGiB,
      ...
    }:
    let
      rule = lib.findFirst (r: builtins.isInt memoryGiB && memoryGiB >= r.minGiB) null (
        boundRules.${class} or [ ]
      );
    in
    if rule == null then null else removeAttrs rule [ "minGiB" ];

  # A link named nix-eval-jobs-stock to a package's nix-eval-jobs, keeping
  # what the evaluation lock reads off it (unwrapped, nix).
  mkNixEvalJobsStockAlias =
    pkgs: package:
    pkgs.runCommand "nix-eval-jobs-stock-${package.version}"
      {
        passthru = {
          pname = "nix-eval-jobs-stock";
          inherit (package) version;
        }
        // lib.optionalAttrs (package ? unwrapped) { inherit (package) unwrapped; }
        // lib.optionalAttrs (package ? nix) { inherit (package) nix; };
        meta.mainProgram = "nix-eval-jobs-stock";
      }
      ''
        mkdir -p $out/bin
        ln -s ${lib.getExe' package "nix-eval-jobs"} $out/bin/nix-eval-jobs-stock
      '';

  # iets' nix-eval-jobs (flake.lib.mkNixEvalJobsIets) behind
  # nix-eval-jobs-iets-bounded.sh, keeping its passthru so the lock wraps it
  # like any evaluator; `bound` is what the host table gave it.
  mkNixEvalJobsIetsBounded =
    pkgs:
    {
      package,
      workers,
      maxMemorySize,
    }:
    pkgs.writeShellApplication {
      name = "nix-eval-jobs";
      runtimeEnv = {
        NIX_EVAL_JOBS_IETS = lib.getExe package;
        NIX_EVAL_JOBS_IETS_WORKERS = toString workers;
      }
      // lib.optionalAttrs (maxMemorySize != null) {
        NIX_EVAL_JOBS_IETS_MAX_MEMORY_SIZE = toString maxMemorySize;
      };
      text = builtins.readFile ./nix-eval-jobs-iets-bounded.sh;
      passthru = {
        pname = "nix-eval-jobs";
        inherit (package) version nix evaluator;
        unbounded = package;
        bound = { inherit workers maxMemorySize; };
      };
    };
in
{
  flake.lib = {
    nixEvalJobsBoundRules = boundRules;
    inherit mkNixEvalJobsIetsBounded mkNixEvalJobsStockAlias;

    # The bound flake.lib.hosts.<name> gets, or null (stock); null for a name
    # that is not a member (a VM test node).
    nixEvalJobsBound = name: if flakeLib.hosts ? ${name} then boundFor flakeLib.hosts.${name} else null;
    nixEvalJobsBoundFor = boundFor;

    # What is wrong with a set of bound rules: on Linux iets must be bounded
    # in workers and per-worker memory, on darwin in workers only (its memory
    # limit is inert there), and every member that runs Nix must have a
    # memory, so it is classified. Empty when nothing is.
    nixEvalJobsBoundProblems =
      rules:
      let
        positive = v: builtins.isInt v && v > 0;
        ruleProblems =
          class: wantMemory:
          lib.concatMap (
            r:
            lib.optional (
              !positive (r.workers or null)
            ) "${class} rule from ${toString r.minGiB} GiB has no worker bound"
            ++
              lib.optional (wantMemory != positive (r.maxMemorySize or null))
                "${class} rule from ${toString r.minGiB} GiB ${
                  if wantMemory then "has no" else "has a"
                } per-worker memory bound"
          ) (rules.${class} or [ ]);
        unclassified = lib.attrNames (
          lib.filterAttrs (
            _: h: (h.class == "nixos" || h.class == "darwin") && !(builtins.tryEval h.memoryGiB).success
          ) flakeLib.hosts
        );
      in
      ruleProblems "nixos" true
      ++ ruleProblems "darwin" false
      ++ map (n: "host ${n} has no memoryGiB") unclassified;

    # What a host's configuration must hold for its evaluators, judged by
    # its machine check (modules/checks/machines.nix), which evaluates the
    # host anyway: its bound is the one flake.lib.hosts gives it; its system
    # PATH holds its nix-eval-jobs and, where that is iets, nix-eval-jobs-stock;
    # that nix-eval-jobs is iets at the bound exactly where there is one; on
    # NixOS the lock is enabled where iets is; every home that installs an
    # evaluator installs the host's; and where nixbot runs, its evaluator is
    # lock-wrapped iets at the host's bound and is named in its records.
    # `name` is the host and `config` its configuration (or a fixture of one).
    nixEvalJobsObligations.failures =
      name: config:
      let
        want = flakeLib.nixEvalJobsBound name;
        isNixos = (config.services or { }) ? nixEvalLock;
        host = if isNixos then config.services.nixEvalLock else config.vanixiets.nixEvalJobs;
        # Identified by what they wrap, as lib.hiPrio's copy carries it.
        key = p: (p.unwrapped or p).drvPath;
        drvsOf =
          ps: map key (builtins.filter (p: lib.hasPrefix "nix-eval-jobs" (p.pname or p.name or "")) ps);
        system = drvsOf config.environment.systemPackages;
        evaluator = if isNixos then host.package.unwrapped or { } else host.package;
        isIets = (evaluator.evaluator or null) == "iets";
        homes = lib.filterAttrs (_: u: drvsOf u.home.packages != [ ]) (config.home-manager.users or { });
        nixbot = (config.services or { }).nixbot or { enable = false; };
        nixbotEvaluator = nixbot.packages.nix-eval-jobs;
      in
      lib.optional (
        host.bound != want
      ) "its bound is ${builtins.toJSON host.bound}, not flake.lib.hosts' ${builtins.toJSON want}"
      ++ lib.optional (
        want != null && !(isIets && (evaluator.bound or null) == want)
      ) "its nix-eval-jobs is not iets at its bound"
      ++ lib.optional (want == null && isIets) "its nix-eval-jobs is iets without a bound"
      ++ lib.optional (
        isNixos && want != null && !host.enable
      ) "it evaluates with iets without the evaluation lock"
      ++ lib.optional (
        (want != null || isNixos && host.enable) && !(lib.elem (key host.package) system)
      ) "its nix-eval-jobs is not on the system PATH"
      ++ lib.optional (
        want != null && (host.stockPackage == null || !(lib.elem (key host.stockPackage) system))
      ) "nix-eval-jobs-stock is not on the system PATH"
      ++ lib.concatLists (
        lib.mapAttrsToList (
          user: u:
          lib.optional (
            !(lib.all (d: d == key host.package || host.stockPackage != null && d == key host.stockPackage) (
              drvsOf u.home.packages
            ))
          ) "home ${user} installs an evaluator other than the host's"
        ) homes
      )
      ++ lib.optionals nixbot.enable (
        lib.optional (
          !(nixbotEvaluator ? unwrapped && (nixbotEvaluator.unwrapped.evaluator or null) == "iets")
        ) "nixbot's evaluator is not lock-wrapped iets"
        ++
          lib.optional
            (
              want == null
              || nixbot.evalWorkerCount != want.workers
              || nixbot.evalMaxMemorySize != want.maxMemorySize
            )
            "nixbot evaluates at ${toString nixbot.evalWorkerCount} x ${toString nixbot.evalMaxMemorySize}, not at the host's bound"
        ++ lib.optional (
          (config.systemd.services.nixbot.environment.NIXBOT_EVALUATOR or null)
          != "${nixbotEvaluator.unwrapped.evaluator or "nix-eval-jobs"} ${nixbotEvaluator.version}"
        ) "NIXBOT_EVALUATOR does not name nixbot's evaluator"
      );

    # The host's `nix-eval-jobs` (package) and, when that is iets,
    # `nix-eval-jobs-stock` (stockPackage, else null), each through `wrap`
    # (the evaluation lock on NixOS).
    nixEvalJobsPackages =
      pkgs:
      {
        bound,
        wrap ? lib.id,
      }:
      let
        stock = pkgs.nix-eval-jobs;
        iets = mkNixEvalJobsIetsBounded pkgs {
          package =
            flakeLib.mkNixEvalJobsIets pkgs inputs.iets.packages.${pkgs.stdenv.hostPlatform.system}.default
              stock;
          inherit (bound) workers maxMemorySize;
        };
      in
      if bound == null then
        {
          package = wrap stock;
          stockPackage = null;
        }
      else
        {
          package = wrap iets;
          stockPackage = mkNixEvalJobsStockAlias pkgs (wrap stock);
        };

    # The evaluation lock's judgement over a set of package lists: the names
    # of the lists holding an evaluator (a package named nix-eval-jobs or
    # nix-eval-jobs-*) that is not lock-wrapped. A wrapper carries the
    # evaluator it wraps as `unwrapped` and forwards that evaluator's nix CLI
    # passthru (nixbot puts it on its service PATH).
    nixEvalLockUnwrapped =
      lists:
      let
        evaluatorsOf = builtins.filter (
          p: builtins.isAttrs p && lib.hasPrefix "nix-eval-jobs" (p.pname or p.name or "")
        );
        isWrapped =
          p: p ? unwrapped && (!(p.unwrapped ? nix) || (p ? nix && p.nix.drvPath == p.unwrapped.nix.drvPath));
      in
      lib.attrNames (lib.filterAttrs (_: ps: !lib.all isWrapped (evaluatorsOf ps)) lists);
  };
}
