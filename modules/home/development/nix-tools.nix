{ config, ... }:
{
  flake.modules.homeManager.development.imports = [
    config.flake.modules.homeManager.nix-development
  ];
  flake.modules.homeManager.nix-development =
    {
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
    in
    {
      key = "vanixiets/nix-development-home-module";
      home.packages = with pkgs; [
        cachix
        deadnix
        nil
        nixEvalJobs
        nix-info
        nix-output-monitor
        nix-prefetch-scripts
        nix-update
        nixd
        nixfmt
        nixpkgs-reviewFull
        statix
      ];
    };
}
