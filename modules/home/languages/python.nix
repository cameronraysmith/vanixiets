{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    let
      python = pkgs.python3.withPackages (
        ps: with ps; [
          duckdb
          huggingface-hub
          pip
          trafilatura
        ]
      );
    in
    {
      home.packages = with pkgs; [
        # Disabled: dotnet-sdk requires Swift which has not been cached on
        # Hydra for aarch64-darwin since Dec 30, 2025. Monitor build status:
        #   https://hydra.nixos.org/job/nixpkgs/trunk/swiftPackages.swift.aarch64-darwin
        #   https://hydra.nixos.org/job/nixpkgs/trunk/dotnet-sdk.aarch64-darwin
        # dotnet-sdk_8 # for fable transpiler
        pixi
        poethepoet
        pydeps
        pylint
        pyright
        python
        ruff
        uv
      ];
    };
}
