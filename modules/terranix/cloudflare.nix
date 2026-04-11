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

      # DNS CNAME record for niks3 cache endpoint (resolves to magnetite)
      resource.cloudflare_dns_record.niks3 = {
        zone_id = config.data.cloudflare_zone.scientistexperience "id";
        name = "niks3";
        type = "CNAME";
        content = "magnetite.scientistexperience.net";
        ttl = 1; # automatic
        proxied = false;
      };

      # DNS CNAME record for buildbot CI endpoint (resolves to magnetite)
      resource.cloudflare_dns_record.buildbot = {
        zone_id = config.data.cloudflare_zone.scientistexperience "id";
        name = "buildbot";
        type = "CNAME";
        content = "magnetite.scientistexperience.net";
        ttl = 1; # automatic
        proxied = false;
      };

      # DNS CNAME record for Gitea forge endpoint (resolves to magnetite)
      resource.cloudflare_dns_record.git = {
        zone_id = config.data.cloudflare_zone.scientistexperience "id";
        name = "git";
        type = "CNAME";
        content = "magnetite.scientistexperience.net";
        ttl = 1; # automatic
        proxied = false;
      };

      # R2 custom domain for public cache access (Cloudflare auto-manages DNS CNAME)
      resource.cloudflare_r2_custom_domain.nix-cache = {
        account_id = config.data.cloudflare_zone.scientistexperience "account.id";
        bucket_name = "sciexp-nix-cache";
        domain = "cache.scientistexperience.net";
        zone_id = config.data.cloudflare_zone.scientistexperience "id";
        enabled = true;
        min_tls = "1.2";
      };

      # Cache rule: cache all nix binary cache objects at the CDN edge
      # .narinfo and nix-cache-info are not in Cloudflare's default cached extensions,
      # so without this rule every narinfo lookup hits R2 directly with no edge caching.
      resource.cloudflare_ruleset.nix-cache-settings = {
        zone_id = config.data.cloudflare_zone.scientistexperience "id";
        name = "Nix binary cache settings";
        description = "Cache all nix binary cache objects on cache.scientistexperience.net";
        kind = "zone";
        phase = "http_request_cache_settings";
        rules = [
          {
            description = "Cache everything for nix binary cache";
            expression = ''(http.host eq "cache.scientistexperience.net")'';
            action = "set_cache_settings";
            action_parameters = {
              edge_ttl = {
                mode = "override_origin";
                default = 86400;
                status_code_ttl = [
                  {
                    status_code_range = {
                      from = 400;
                      to = 499;
                    };
                    value = 60;
                  }
                ];
              };
              cache = true;
            };
          }
        ];
      };

    };
}
