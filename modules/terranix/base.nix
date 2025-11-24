{
  flake.modules.terranix.base =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # Passphrase variable for OpenTofu state encryption
      variable.passphrase = { };

      # Required providers
      terraform.required_providers.external.source = "hashicorp/external";
      terraform.required_providers.hcloud.source = "hetznercloud/hcloud";

      # Fetch Hetzner API token from clan secrets
      data.external.hetzner-api-token = {
        program = [
          (lib.getExe (
            pkgs.writeShellApplication {
              name = "get-hetzner-secret";
              text = ''
                jq -n --arg secret "$(clan secrets get hetzner-api-token)" '{"secret":$secret}'
              '';
            }
          ))
        ];
      };

      # Configure Hetzner Cloud provider with secret
      provider.hcloud.token = config.data.external.hetzner-api-token "result.secret";
    };
}
