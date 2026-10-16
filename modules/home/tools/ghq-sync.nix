{ config, ... }:
let
  homeModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.tools.imports = [ homeModules.ghq-sync ];
  flake.modules.homeManager.ghq-sync =
    { config, pkgs, ... }:
    let
      root = config.programs.ghq-shared.root;
    in
    {
      key = "vanixiets/ghq-sync-home-module";
      imports = [ homeModules.ghq-shared-option ];
      home.packages = [
        (
          if root == null then
            pkgs.ghq-sync
          else
            pkgs.ghq-sync.override {
              ghq = pkgs.ghq-shared;
              delegate = "${pkgs.ghq-shared}/libexec/ghq-shared/ghq-writer-client";
            }
        )
      ];
    };
}
