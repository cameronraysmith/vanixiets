{ lib, ... }:
let
  # Synthesize a home-manager identity module fragment from a username,
  # parameterized over whether the setters use `lib.mkDefault` (canonical
  # user, may be overridden by per-host configuration) or `lib.mkForce`
  # (alias user, must override the inherited canonical identity).
  mkUserIdentity =
    {
      user,
      force ? false,
    }:
    {
      config,
      pkgs,
      ...
    }:
    let
      setter = if force then lib.mkForce else lib.mkDefault;
    in
    {
      home.username = setter user;
      home.homeDirectory = setter (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );
    };
in
{
  config.flake.lib.mkUserIdentity = mkUserIdentity;

  options.flake.users = lib.mkOption {
    description = ''
      Typed per-user identity and profile data consumed by home-manager
      configurations and capability aggregates.

      Each user provides identity metadata under `meta` and a list of
      capability-aggregate home-manager modules under `aggregates`. The
      `homeConfigurations` flake output is emitted only for users whose
      `aggregates` is non-empty (conservative auto-discovery).
    '';
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          options = {
            meta = {
              username = lib.mkOption {
                type = lib.types.str;
                description = "Login username for this user.";
              };
              fullname = lib.mkOption {
                type = lib.types.str;
                description = "Full personal name (e.g. for git commits).";
              };
              email = lib.mkOption {
                type = lib.types.str;
                description = "Primary email address.";
              };
              githubUser = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "GitHub username, if any.";
              };
              sopsAgeKeyId = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Identifier under `secrets/bridge/<id>-age-key.enc` for the
                  `hm-sops-bridge` NixOS module to deploy this user's age key.
                '';
              };
              sshKeys = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  SSH public keys authorized for this user across machines
                  and clan inventory services. Consumed by per-host
                  `users.users.<u>.openssh.authorizedKeys.keys` setters.
                '';
              };
            };
            aggregates = lib.mkOption {
              type = lib.types.listOf lib.types.deferredModule;
              default = [ ];
              description = ''
                Home-manager aggregate modules to include for this user, given
                as direct references against `config.flake.modules.homeManager.<name>`
                (e.g. `with config.flake.modules.homeManager; [ core development shell ]`).
                An empty list signals that no `homeConfigurations` entry should
                be emitted for this user.
              '';
            };
            contentPrivate = lib.mkOption {
              type = lib.types.deferredModule;
              default = { };
              description = ''
                Identity-bound, secret-bearing home-manager content for this
                user (sops secrets, git/jujutsu user identity, deploy-time
                keys). Composed by `mk-home` alongside the capability
                aggregates. Authored in `modules/home/users/<u>/default.nix`.
              '';
            };
            identity = lib.mkOption {
              type = lib.types.deferredModule;
              default = mkUserIdentity { user = name; };
              description = ''
                Home-manager module fragment that pins this user's
                `home.username` and `home.homeDirectory` for both the
                standalone (`homeConfigurations.<u>@<sys>`) and embedded
                (`<dC|nC>.<host>.config.home-manager.users.<u>`) pathways.

                For canonical users (entries declared directly in
                `flake.users`), this slot defaults to a parametric
                derivation keyed on the attribute name: it sets
                `home.username = lib.mkDefault "<name>"` and a
                self-referential `home.homeDirectory`.

                For alias users (materialized from `flake.userAliases`
                by `aliases-fold.nix`), the alias-fold extension overrides
                the inherited canonical identity using
                `flake.lib.mkUserIdentity { user = alias; force = true; }`,
                pinning the alias name with `lib.mkForce` setters.
              '';
            };
            modules = lib.mkOption {
              type = lib.types.listOf lib.types.deferredModule;
              default = config.aggregates ++ [ config.contentPrivate ] ++ [ config.identity ];
              readOnly = true;
              description = ''
                Materialized home-manager module list for this user:
                `aggregates ++ [ contentPrivate ] ++ [ identity ]` composed
                in standard order. Consumer-side smart constructor — host
                modules import this rather than re-computing the recipe,
                and `mk-home` consumes it for `homeConfigurations.<u>@<sys>`.
                Read-only: derived from the other submodule fields.
              '';
            };
          };
        }
      )
    );
  };
}
