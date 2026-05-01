{ lib, ... }:
{
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
      lib.types.submodule {
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
              keys). Composed by `mk-home` alongside `contentPortable` and
              the capability aggregates.

              Transitional during nix-0pd.17 dual-write: this slot mirrors
              the content authored at
              `flake.modules.homeManager."users/<u>"`. Consumers should
              prefer this typed slot; the registry key is dropped in a
              later commit.
            '';
          };
          contentPortable = lib.mkOption {
            type = lib.types.deferredModule;
            default = { };
            description = ''
              Secret-free, identity-independent home-manager content for
              this user. Available to `home-trial` alongside the same
              capability aggregate selection.

              Transitional during nix-0pd.17 dual-write: this slot mirrors
              the content authored at
              `flake.modules.homeManager."portable/<u>"`. Consumers should
              prefer this typed slot; the registry key is dropped in a
              later commit.
            '';
          };
        };
      }
    );
  };
}
