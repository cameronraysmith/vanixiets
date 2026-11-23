{ config, inputs, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.modules.homeManager.development.imports = [
    config.flake.modules.homeManager.nix-development
  ];
  flake.modules.homeManager.nix-development =
    {
      config,
      lib,
      pkgs,
      # Supplied by home-manager's NixOS and nix-darwin modules; absent (null,
      # see mk-home.nix) in a standalone home configuration.
      osConfig ? null,
      ...
    }:
    let
      # A user profile precedes the system profile on PATH, so on a host with
      # the evaluation lock (modules/nixos/nix-eval-lock.nix) a plain
      # nix-eval-jobs here would shadow the wrapper, and `nix-fast-build
      # --remote` over ssh would evaluate outside the lock.
      evalLock = if osConfig == null then null else osConfig.services.nixEvalLock or null;
      nixEvalJobs = if evalLock != null && evalLock.enable then evalLock.package else pkgs.nix-eval-jobs;

      cfg = config.nixEvalJobsIets;
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      # Its own name beside stock nix-eval-jobs, so a tool expecting stock
      # behaviour (import-from-derivation, --override-input, --override-flake,
      # --repair, --help, all refused by iets) still finds stock.
      nixEvalJobsIets = pkgs.writeShellApplication {
        name = "nix-eval-jobs-iets";
        runtimeEnv = {
          NIX_EVAL_JOBS_IETS = lib.getExe (
            flakeLib.mkNixEvalJobsIets pkgs inputs.iets.packages.${pkgs.stdenv.hostPlatform.system}.default
              pkgs.nix-eval-jobs
          );
          NIX_EVAL_JOBS_IETS_WORKERS = toString cfg.workers;
        };
        text = builtins.readFile ./nix-eval-jobs-iets.sh;
      };
    in
    {
      key = "vanixiets/nix-development-home-module";

      # iets keeps everything a worker evaluated (no garbage collector), and on
      # macOS ignores --max-memory-size (it reads the worker's peak from /proc),
      # so a worker's memory grows with the work it is given and the worker
      # count is the only, weak, bound. Peak process-tree RSS of `iets
      # eval-jobs --force-recurse` over checks of both nixbot systems (335
      # attributes), stibnite, 2026-11-23, trunk 72213c3b: 1 worker 13.0 GiB,
      # 2 workers 13.7-18.0 GiB, 3 workers 19.8-20.2 GiB, 5 workers 20.4-21.8
      # GiB (13.3-29 s); checks.aarch64-darwin alone (111 attributes): 1
      # worker 4.6 GiB, 2 workers 6.0 GiB. No worker count fits the default
      # two-system run in an 8 GiB Mac (rosegold and argentum, by sysctl;
      # blackphos unrecorded), so those keep stock nix-eval-jobs only, whose
      # --max-memory-size does recycle workers on macOS. A darwin-only run
      # would fit one at 1 worker, so opting such a host in is a deliberate
      # choice, not a default.
      options.nixEvalJobsIets.workers = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 3;
        description = ''
          Installs nix-eval-jobs-iets (iets' nix-eval-jobs, flake.lib.mkNixEvalJobsIets)
          beside stock nix-eval-jobs on a darwin host, using this many workers
          when the caller gives no --workers and at most this many when it asks
          for more. null installs nothing: the host's memory cannot hold an
          iets evaluation of the check set at any worker count. darwin only:
          a Linux host's evaluators belong behind its evaluation lock
          (services.nixEvalLock), which this wrapper would bypass.
        '';
      };

      config = {
        assertions = [
          {
            assertion = cfg.workers == null || isDarwin;
            message = "nixEvalJobsIets.workers is darwin only: on Linux nix-eval-jobs-iets would evaluate outside the host evaluation lock (services.nixEvalLock)";
          }
        ];

        home.packages =
          with pkgs;
          [
            cachix
            deadnix
            nil
            nixEvalJobs
            nix-output-monitor
            nix-prefetch-scripts
            nix-update
            nixd
            nixfmt
            nixpkgs-reviewFull
            statix
          ]
          ++ lib.optional (cfg.workers != null && isDarwin) nixEvalJobsIets;
      };
    };
}
