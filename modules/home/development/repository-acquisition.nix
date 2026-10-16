{ config, ... }:
let
  homeModules = config.flake.modules.homeManager;
in
{
  # A host that shares one ghq tree (modules/system/shared-reference-tree.nix) sets
  # this for each participating account; null keeps ghq's per-account `~/ghq`.
  flake.modules.homeManager.ghq-shared-option =
    { lib, ... }:
    {
      key = "vanixiets/ghq-shared-option";
      options.programs.ghq-shared.root = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host-shared ghq root this account reads but cannot write; null keeps ghq's per-account default.";
      };
    };

  flake.modules.homeManager.ghq =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      root = config.programs.ghq-shared.root;
    in
    {
      key = "vanixiets/ghq-home-module";
      imports = [ homeModules.ghq-shared-option ];
      config = lib.mkMerge [
        { home.packages = [ pkgs.ghq ]; }
        (lib.mkIf (root != null) {
          assertions = [
            {
              assertion = config.programs.git.enable;
              message = "programs.ghq-shared.root is delivered through git configuration and requires programs.git.enable.";
            }
          ];
          programs.git.settings = {
            ghq.root = root;
            safe.directory = [ "${root}/*" ];
          };
          # Activation rather than home.file: Home Manager refuses to replace an
          # existing ~/ghq directory, which stays until ghq-shared-migrate moves it.
          home.activation.ghqSharedLink = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            if [ -L "$HOME/ghq" ] || [ ! -e "$HOME/ghq" ]; then
              run ln -sfn ${lib.escapeShellArg root} "$HOME/ghq"
            else
              warnEcho "$HOME/ghq is a directory; ghq-shared-migrate moves it into ${root}"
            fi
          '';
        })
      ];
    };

  flake.modules.homeManager.repository-acquisition =
    { config, lib, ... }:
    {
      key = "vanixiets/repository-acquisition-home-module";
      imports = [
        homeModules.ghq
        homeModules.ghq-sync
        homeModules.dependency-sources
      ];
      # An enabled zoxide module already installs its selected package and owns shell hooks.
      home.packages = lib.mkIf (!config.programs.zoxide.enable) [ config.programs.zoxide.package ];
    };
}
