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
# Captive portals (public WiFi login pages):
#   Portal auth requires DNS before external traffic works. Temporarily disable:
#     sudo launchctl bootout system/org.nixos.dnscrypt-proxy
#   Complete portal login, then re-enable:
#     sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dnscrypt-proxy.plist
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

      # DoH stamps with embedded IP addresses (no DNS lookup required).
      # Stamps encode: protocol, IP, hostname, path, flags in base64 sdns:// URI.
      # This bypasses DNS interception for bootstrap - no plaintext DNS needed.
      #
      # Stamp sources and verification:
      #   Spec: https://dnscrypt.info/stamps-specifications/
      #   Public list: https://dnscrypt.info/public-servers (filter: DoH, embedded IP)
      #   Generator: https://dnscrypt.info/stamps/ (create/decode stamps)
      #   CLI decode: uvx --from dnsstamps dnsstamp.py parse "sdns://..."
      #   Verify Hashes: [] (pin-free) and correct IP/hostname/path
      #
      # Provider docs (verify IPs match current infrastructure):
      #   Quad9: https://quad9.net/news/blog/doh-with-quad9-dns-servers/
      #   Cloudflare: https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/
      #   Google: https://developers.google.com/speed/public-dns/docs/doh
      # Pin-free stamps: omit SPKI hashes to avoid breakage on provider key rotation.
      # TLS still validated via system CA chain. Trade-off: lose protection against
      # CA compromise + MITM (extremely unlikely for personal infrastructure).
      providerConfig = {
        quad9 = {
          # Quad9 secured (malware blocking enabled)
          stamps = {
            "quad9-doh-ip4-primary" = {
              stamp = "sdns://AgMAAAAAAAAABzkuOS45LjkADWRucy5xdWFkOS5uZXQKL2Rucy1xdWVyeQ";
            };
            "quad9-doh-ip4-secondary" = {
              stamp = "sdns://AgMAAAAAAAAADzE0OS4xMTIuMTEyLjExMgANZG5zLnF1YWQ5Lm5ldAovZG5zLXF1ZXJ5";
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

      # Merge stamps and server_names from all selected providers
      mergedConfig =
        lib.foldl'
          (acc: name: {
            stamps = acc.stamps // providerConfig.${name}.stamps;
            server_names = acc.server_names ++ providerConfig.${name}.server_names;
          })
          {
            stamps = { };
            server_names = [ ];
          }
          cfg.providers;

      # First provider's first IP for netprobe (any will do - just needs reachability check)
      firstProviderFirstIp =
        {
          quad9 = "9.9.9.9";
          cloudflare = "1.1.1.1";
          google = "8.8.8.8";
        }
        .${builtins.head cfg.providers};
    in
    {
      options.services.localDnscryptProxy = {
        enable = lib.mkEnableOption "local dnscrypt-proxy for encrypted DNS-over-HTTPS";

        providers = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "quad9"
              "cloudflare"
              "google"
            ]
          );
          default = [
            "quad9"
            "cloudflare"
          ];
          example = [ "quad9" ];
          description = ''
            DNS-over-HTTPS providers to use. Multiple providers increases robustness
            (load balancer picks fastest available). Default uses both no-logging providers.
            - quad9: Privacy-focused, malware blocking, DNSSEC (9.9.9.9, 149.112.112.112)
            - cloudflare: Fast, privacy-focused, DNSSEC (1.1.1.1, 1.0.0.1)
            - google: Fast, logs queries, DNSSEC (8.8.8.8, 8.8.4.4)
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
            # Listen on localhost port 53 for system DNS (IPv4 and IPv6)
            listen_addresses = [
              "127.0.0.1:53"
              "[::1]:53"
            ];

            # Server selection (merged from all configured providers)
            server_names = mergedConfig.server_names;

            # Protocol settings - DoH only, no DNSCrypt
            ipv4_servers = true;
            ipv6_servers = false;
            dnscrypt_servers = false;
            doh_servers = true;

            # Security settings
            # DNSSEC validation delegated to upstream (Quad9/Cloudflare/Google all
            # perform DNSSEC validation and return SERVFAIL for invalid signatures)
            require_dnssec = false;
            require_nolog = true; # Prefer no-logging servers
            require_nofilter = false; # Allow filtering (Quad9 blocks malware)

            # Prevent internal name leakage to upstream resolvers
            block_unqualified = true; # Block A/AAAA for single-label hostnames
            block_undelegated = true; # Block queries for undelegated TLDs

            # Performance settings
            force_tcp = false;
            cache = true;
            cache_size = 4096;
            cache_min_ttl = 600; # 10 minutes - balanced freshness vs performance
            cache_max_ttl = 86400; # 24 hours - reasonable upper bound for stable records
            cache_neg_min_ttl = 60;
            cache_neg_max_ttl = 600;

            # Connection settings
            timeout = 5000;
            keepalive = 30;
            max_clients = 250;

            # Bootstrap resolvers disabled - DoH stamps embed IP addresses directly,
            # eliminating the need for plaintext DNS bootstrap lookups
            bootstrap_resolvers = [ ];
            ignore_system_dns = true;

            # Network probe - verify connectivity before accepting queries
            netprobe_timeout = 60;
            netprobe_address = "${firstProviderFirstIp}:443"; # HTTPS port for DoH

            # Load balancing - probabilistic selection weighted by RTT
            lb_strategy = "p2";
            lb_estimator = true;

            # Static server definitions with embedded-IP stamps
            static = mergedConfig.stamps;
          };
        };

        # Declare existing system user's home directory to satisfy nix-darwin
        # activation check (nix-darwin refuses to change existing users' homes)
        users.users._dnscrypt-proxy.home = "/private/var/lib/dnscrypt-proxy";

        # Override launchd config to run as root (required for port 53 binding)
        # The default _dnscrypt-proxy user cannot bind to privileged ports
        launchd.daemons.dnscrypt-proxy.serviceConfig = {
          UserName = lib.mkForce "root";
          GroupName = lib.mkForce "wheel";
        };

        # Configure system DNS to use local dnscrypt-proxy (IPv4 and IPv6)
        networking.knownNetworkServices = cfg.networkServices;
        networking.dns = [
          "127.0.0.1"
          "::1"
        ];

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
