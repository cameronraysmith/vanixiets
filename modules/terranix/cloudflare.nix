{
  flake.modules.terranix.cloudflare =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # Required provider
      terraform.required_providers.cloudflare.source = "cloudflare/cloudflare";

      # Fetch Cloudflare API token from clan secrets
      data.external.cloudflare-api-token = {
        program = [
          (lib.getExe (
            pkgs.writeShellApplication {
              name = "get-cloudflare-secret";
              text = ''
                jq -n --arg secret "$(clan secrets get cloudflare-api-token)" '{"secret":$secret}'
              '';
            }
          ))
        ];
      };

      # Configure provider
      provider.cloudflare.api_token = config.data.external.cloudflare-api-token "result.secret";

      # Zone data source for scientistexperience.net
      data.cloudflare_zone.scientistexperience = {
        filter = {
          name = "scientistexperience.net";
        };
      };

      # R2 bucket for nix binary cache (niks3)
      resource.cloudflare_r2_bucket.sciexp-nix-cache = {
        account_id = config.data.cloudflare_zone.scientistexperience "account.id";
        name = "sciexp-nix-cache";
        location = "enam";
      };

    };
}
