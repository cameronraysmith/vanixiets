# niks3 binary cache service for magnetite
#
# Provides clan vars generators for niks3 credentials and will configure
# the niks3 service once the flake input is added.
# Generators define the credential slots; values are populated via:
#   - niks3-s3: manual `clan vars set` (R2 S3 credentials from Cloudflare dashboard)
#   - niks3-api-token: auto-generated
#   - niks3-signing-key: auto-generated
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.niks3 =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # Clan vars for niks3 R2 S3 credentials (populated manually via clan vars set)
      clan.core.vars.generators.niks3-s3 = {
        files."access-key" = {
          owner = "niks3";
        };
        files."secret-key" = {
          owner = "niks3";
        };
        script = ''
          echo "niks3-s3 credentials are populated manually from Cloudflare R2 dashboard" >&2
          exit 1
        '';
      };

      # API authentication token (auto-generated, minimum 36 characters)
      clan.core.vars.generators.niks3-api-token = {
        files."token" = {
          owner = "niks3";
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 24 > $out/token
        '';
      };

      # Ed25519 cache signing key (auto-generated)
      clan.core.vars.generators.niks3-signing-key = {
        files."key" = {
          owner = "niks3";
        };
        files."key.pub".secret = false;
        runtimeInputs = [ pkgs.nix ];
        script = ''
          nix --extra-experimental-features "nix-command flakes" \
            key generate-secret --key-name cache.scientistexperience.net-1 > $out/key
          nix --extra-experimental-features "nix-command flakes" \
            key convert-secret-to-public < $out/key > $out/key.pub
        '';
      };
    };
}
