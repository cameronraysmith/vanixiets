{ ... }:
{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    {
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
