{ config, ... }:
let
  homeModules = config.flake.modules.homeManager;
  lfsPolicy = config.flake.lib.sharedReferenceTreeLfsPolicy;
  transportPolicy = config.flake.lib.sharedReferenceTreeTransportPolicy;
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
      # git matches gitdir: against the repository's resolved path as well, and
      # on darwin /var resolves to /private/var.
      rootForms = [
        root
      ]
      ++ lib.optional (pkgs.stdenv.hostPlatform.isDarwin && lib.hasPrefix "/var/" root) "/private${root}";
    in
    {
      key = "vanixiets/ghq-home-module";
      imports = [ homeModules.ghq-shared-option ];
      config = lib.mkMerge [
        { home.packages = [ (if root == null then pkgs.ghq else pkgs.ghq-shared) ]; }
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
            # The shared tree may hold bare repositories (upstream fixtures,
            # caches) whose config and hooks no migration sanitises; git then
            # uses a bare repository only when named with --git-dir.
            safe.bareRepository = "explicit";
          };
          # The shared tree holds LFS pointer files as committed, and this account
          # cannot write the LFS cache an LFS filter would use there, so its git runs
          # no LFS filter under the root, as the tree's writer does. Its git also
          # refuses every transport there: a read needing content the copy lacks
          # fails at once rather than starting a fetch into a tree it cannot write.
          programs.git.includes = map (form: {
            condition = "gitdir:${form}/";
            contents = {
              filter.lfs = lfsPolicy;
              protocol = transportPolicy;
            };
          }) rootForms;
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
