# DNS-over-HTTPS via dnscrypt-proxy for encrypted DNS resolution
#
# Routes ALL DNS queries through encrypted DoH (DNS-over-HTTPS) to the selected
# provider, completely bypassing any network-level DNS interception (including
# Cisco Secure Client DNS Proxy and similar enterprise tools).
#
# How it works:
# - DNS stamps with embedded IP addresses eliminate bootstrap DNS lookups
# - DoH uses HTTPS (port 443), indistinguishable from normal web traffic
# - Enterprise DNS proxies typically only intercept port 53, not HTTPS
#
# Rollback instructions (no internet required):
#   sudo /nix/var/nix/profiles/system-N-link/activate  # where N is previous gen
#   OR: sudo darwin-rebuild --rollback
#
# Cannot be enabled simultaneously with localDnsmasq (both bind to port 53).
{ ... }:
{
  flake.modules.darwin.dnscrypt-proxy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.localDnscryptProxy;

      # DoH stamps with embedded IP addresses (no DNS lookup required)
      # Format: sdns://... with IP address encoded in the stamp
      # This completely bypasses any DNS interception for bootstrap
      providerConfig = {
        quad9 = {
          # Quad9 secured (malware blocking enabled)
          stamps = {
            "quad9-doh-ip4-primary" = {
              stamp = "sdns://AgMAAAAAAAAABzkuOS45LjkgsBkgdEu7dsmrBT4B4Ht-BQ5HPSD3n3vqQ1-v5DydJC8SZG5zOS5xdWFkOS5uZXQ6NDQzCi9kbnMtcXVlcnk";
            };
            "quad9-doh-ip4-secondary" = {
              stamp = "sdns://AgMAAAAAAAAADzE0OS4xMTIuMTEyLjExMiCwGSB0S7t2yasFPgHge34FDkc9IPefe-pDX6_kPJ0kLxFkbnMucXVhZDkubmV0OjQ0MwovZG5zLXF1ZXJ5";
            };
          };
          server_names = [
            "quad9-doh-ip4-primary"
            "quad9-doh-ip4-secondary"
          ];
        };
        cloudflare = {
          # Cloudflare 1.1.1.1 (no filtering)
          stamps = {
            "cloudflare-doh-primary" = {
              stamp = "sdns://AgcAAAAAAAAABzEuMS4xLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
            };
            "cloudflare-doh-secondary" = {
              stamp = "sdns://AgcAAAAAAAAABzEuMC4wLjEAEmRucy5jbG91ZGZsYXJlLmNvbQovZG5zLXF1ZXJ5";
            };
          };
          server_names = [
            "cloudflare-doh-primary"
            "cloudflare-doh-secondary"
          ];
        };
        google = {
          # Google Public DNS
          stamps = {
            "google-doh-primary" = {
              stamp = "sdns://AgUAAAAAAAAABzguOC44LjgAC2Rucy5nb29nbGUKL2Rucy1xdWVyeQ";
            };
            "google-doh-secondary" = {
              stamp = "sdns://AgUAAAAAAAAABzguOC40LjQAC2Rucy5nb29nbGUKL2Rucy1xdWVyeQ";
            };
          };
          server_names = [
            "google-doh-primary"
            "google-doh-secondary"
          ];
        };
      };

      selectedProvider = providerConfig.${cfg.provider};
    in
    {
      options.services.localDnscryptProxy = {
        enable = lib.mkEnableOption "local dnscrypt-proxy for encrypted DNS-over-HTTPS";

        provider = lib.mkOption {
          type = lib.types.enum [
            "quad9"
            "cloudflare"
            "google"
          ];
          default = "quad9";
          example = "cloudflare";
          description = ''
            DNS-over-HTTPS provider to use.
            - quad9: Privacy-focused, malware blocking (9.9.9.9)
            - cloudflare: Fast, privacy-focused (1.1.1.1)
            - google: Fast, extensive logging (8.8.8.8)
          '';
        };

        networkServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "Wi-Fi" ];
          example = [
            "Wi-Fi"
            "Ethernet"
          ];
          description = ''
            Network services to configure DNS for.
            Use `networksetup -listallnetworkservices` to list available services.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Ensure dnsmasq and dnscrypt-proxy are not both enabled
        assertions = [
          {
            assertion = !(config.services.localDnsmasq.enable or false);
            message = "Cannot enable both localDnsmasq and localDnscryptProxy - they both bind to port 53";
          }
        ];

        # Configure dnscrypt-proxy via nix-darwin's module
        services.dnscrypt-proxy = {
          enable = true;
          settings = {
            # Listen on localhost port 53 for system DNS
            listen_addresses = [ "127.0.0.1:53" ];

            # Server selection
            server_names = selectedProvider.server_names;

            # Protocol settings - DoH only, no DNSCrypt
            ipv4_servers = true;
            ipv6_servers = false;
            dnscrypt_servers = false;
            doh_servers = true;

            # Security settings
            require_dnssec = false; # Let upstream handle DNSSEC
            require_nolog = true; # Prefer no-logging servers
            require_nofilter = false; # Allow filtering (Quad9 blocks malware)

            # Performance settings
            force_tcp = false;
            cache = true;
            cache_size = 4096;
            cache_min_ttl = 2400;
            cache_max_ttl = 86400;
            cache_neg_min_ttl = 60;
            cache_neg_max_ttl = 600;

            # Connection settings
            timeout = 5000;
            keepalive = 30;
            max_clients = 250;

            # Disable bootstrap resolvers - stamps have embedded IPs
            # Setting to invalid address ensures no plaintext DNS leaks
            bootstrap_resolvers = [ "127.0.0.1:5399" ];
            ignore_system_dns = true;

            # Static server definitions with embedded-IP stamps
            static = selectedProvider.stamps;
          };
        };

        # Override launchd config to run as root (required for port 53 binding)
        # The default _dnscrypt-proxy user cannot bind to privileged ports
        launchd.daemons.dnscrypt-proxy.serviceConfig = {
          UserName = lib.mkForce "root";
          GroupName = lib.mkForce "wheel";
        };

        # Configure system DNS to use local dnscrypt-proxy
        networking.knownNetworkServices = cfg.networkServices;
        networking.dns = [ "127.0.0.1" ];

        # Health check: ensure dnscrypt-proxy is responding after activation
        system.activationScripts.postActivation.text = lib.mkAfter ''
          echo "checking dnscrypt-proxy health..." >&2
          sleep 1  # Give dnscrypt-proxy time to start
          if ! ${pkgs.dig}/bin/dig @127.0.0.1 +short +time=2 +tries=1 example.com &>/dev/null; then
            echo "dnscrypt-proxy not responding, restarting..." >&2
            launchctl bootout system/org.nixos.dnscrypt-proxy 2>/dev/null || true
            launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dnscrypt-proxy.plist
            sleep 2
            if ${pkgs.dig}/bin/dig @127.0.0.1 +short +time=2 +tries=1 example.com &>/dev/null; then
              echo "dnscrypt-proxy restart successful" >&2
            else
              echo "warning: dnscrypt-proxy still not responding after restart" >&2
              echo "  Rollback: sudo darwin-rebuild --rollback" >&2
            fi
          fi
        '';
      };
    };
}
