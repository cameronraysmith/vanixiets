{ config, ... }:
{
  flake.modules.homeManager.development.imports = [
    config.flake.modules.homeManager.nix-development
  ];
  flake.modules.homeManager.nix-development =
    {
      lib,
      pkgs,
      # Supplied by home-manager's NixOS and nix-darwin modules; absent (null,
      # see mk-home.nix) in a standalone home configuration.
      osConfig ? null,
      ...
    }:
    let
      # A user profile precedes the system profile on PATH, so the home
      # installs exactly the host's evaluators: on NixOS the lock-wrapped ones
      # (modules/nixos/nix-eval-lock.nix), on darwin the host's
      # (modules/darwin/nix-eval-jobs.nix), both chosen by the host's memory
      # in flake.lib.hosts. A different nix-eval-jobs here would shadow the
      # host's, and on a locked host `nix-fast-build --remote` over ssh would
      # evaluate outside the lock. A home without a host (standalone, or a
      # NixOS host without the lock) gets stock.
      evalLock = if osConfig == null then null else osConfig.services.nixEvalLock or null;
      hostEvaluators =
        if evalLock != null && evalLock.enable then
          evalLock
        else if osConfig != null && osConfig ? vanixiets.nixEvalJobs then
          osConfig.vanixiets.nixEvalJobs
        else
          {
            package = pkgs.nix-eval-jobs;
            stockPackage = null;
          };
    in
    {
      key = "vanixiets/nix-development-home-module";
      home.packages =
        with pkgs;
        [
          cachix
          deadnix
          nil
          hostEvaluators.package
          nix-output-monitor
          nix-prefetch-scripts
          nix-update
          nixd
          nixfmt
          nixpkgs-reviewFull
          statix
        ]
        ++ lib.optional (hostEvaluators.stockPackage != null) hostEvaluators.stockPackage;
    };
}
