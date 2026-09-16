{ config, ... }:
{
  flake.modules.homeManager.development.imports = [
    config.flake.modules.homeManager.nix-development
  ];
  flake.modules.homeManager.nix-development =
    { pkgs, ... }:
    {
      key = "vanixiets/nix-development-home-module";
      home.packages = with pkgs; [
        cachix
        deadnix
        nil
        nix-eval-jobs
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
