{ config, lib, ... }:
{
  options.flake.users = lib.mkOption {
    description = ''
      Typed per-user identity and profile data consumed by home-manager
      configurations and capability aggregates.

      Each user provides identity metadata under `meta` and a list of
      typed profile records under `profiles`. The `homeConfigurations`
      flake output is emitted only for users whose `profiles` is
      non-empty (conservative auto-discovery).
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
          profiles = lib.mkOption {
            type = lib.types.listOf config.flake.lib.profileType;
            default = [ ];
            description = ''
              Typed profile records this user adopts. Each profile
              contributes its `includes` list of deferred home-manager
              modules to the user's home configuration. Reference profiles
              by attribute access against
              `config.flake.profiles.homeManager`, e.g.
              `with config.flake.profiles.homeManager; [ core shell ]`.
              An empty list signals that no `homeConfigurations` entry
              should be emitted for this user.
            '';
          };
        };
      }
    );
  };
}
