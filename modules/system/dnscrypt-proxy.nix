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
# The provider stamps, the dnscrypt-proxy settings, and the `enable` and
# `providers` options are platform-independent and shared below; each platform
# module adds only how the operating system is pointed at the local listener.
#
# Rollback instructions (no internet required):
#   darwin: sudo /nix/var/nix/profiles/system-N-link/activate  # where N is previous gen
#           OR: sudo darwin-rebuild --rollback
#   NixOS:  boot the previous generation, or sudo nixos-rebuild switch --rollback
#
# macOS pins every hardware network service to the local listener, including
# services created later by newly attached adapters (see dnscrypt-pin-dns.sh),
# so switching between Wi-Fi and wired adapters keeps DNS encrypted.
#
# NixOS sends every name to the local listener through systemd-resolved's
# global server (Domains=~.) and stops both NetworkManager and
# systemd-networkd handing resolved the DNS servers and search domains that
# each network's DHCP or router advertisements offer, so no interface,
# whenever attached, has a DNS server of its own to leak to. Plaintext
# fallback servers are removed.
#
# Captive portals (public WiFi login pages):
#   Portal auth needs the network's own DNS.
#   darwin: stop the pinning daemon so it does not re-pin, then hand the
#   portal's service back to DHCP-supplied DNS:
#     sudo launchctl bootout system/org.nixos.dnscrypt-pin-dns
#     sudo networksetup -setdnsservers Wi-Fi empty
#   Complete portal login, then restart the daemon, which re-pins every service:
#     sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dnscrypt-pin-dns.plist
#   NixOS: give the portal's link the DNS server its DHCP lease offered, make
#   it a default route, and route every name to it alongside the global ~.
#   (a link DNS server alone is never consulted):
#     sudo resolvectl dns wlp2s0 "$(nmcli -g IP4.DNS device show wlp2s0 | cut -d'|' -f1)"
#     sudo resolvectl default-route wlp2s0 true
#     sudo resolvectl domain wlp2s0 '~.'
#   Complete portal login, then drop all three again:
#     sudo resolvectl revert wlp2s0
{ lib, ... }:
let
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

  # First IP of each provider, used for the netprobe (any will do - just needs
  # a reachability check)
  providerProbeIp = {
    quad9 = "9.9.9.9";
    cloudflare = "1.1.1.1";
    google = "8.8.8.8";
  };

  # Options common to every platform
  sharedOptions = {
    enable = lib.mkEnableOption "local dnscrypt-proxy for encrypted DNS-over-HTTPS";

    providers = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (builtins.attrNames providerConfig));
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
  };

  # dnscrypt-proxy settings for the selected providers, common to every platform
  mkSettings =
    providers:
    let
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
          providers;
    in
    {
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
      netprobe_address = "${providerProbeIp.${builtins.head providers}}:443"; # HTTPS port for DoH

      # Load balancing - probabilistic selection weighted by RTT
      lb_strategy = "p2";
      lb_estimator = true;

      # Static server definitions with embedded-IP stamps
      static = mergedConfig.stamps;
    };
in
{
  flake.modules.darwin.dnscrypt-proxy =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.localDnscryptProxy;

      pinDns = pkgs.writeShellApplication {
        name = "dnscrypt-pin-dns";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnugrep
        ];
        runtimeEnv.EXCLUDED_SERVICES = lib.concatStringsSep "\n" cfg.excludeNetworkServices;
        text = builtins.readFile ./dnscrypt-pin-dns.sh;
      };
    in
    {
      options.services.localDnscryptProxy = sharedOptions // {
        excludeNetworkServices = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "Thunderbolt Bridge" ];
          description = ''
            Hardware network services whose DNS servers are left alone.
            Every other service with a hardware device (Wi-Fi, Ethernet, and
            adapters attached later) is pointed at the local listener; software
            services such as VPNs are never touched.
            Use `networksetup -listnetworkserviceorder` to list services.
          '';
        };

        userHome = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/dnscrypt-proxy";
          example = "/private/var/lib/dnscrypt-proxy";
          description = ''
            Home directory for the _dnscrypt-proxy system user.
            Must match the existing user's NFSHomeDirectory on this machine.
            Check with: dscl . -read /Users/_dnscrypt-proxy NFSHomeDirectory
            macOS symlinks /var to /private/var, but nix-darwin does string
            comparison, so the path must match exactly.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        # Configure dnscrypt-proxy via nix-darwin's module
        services.dnscrypt-proxy = {
          enable = true;
          settings = mkSettings cfg.providers;
        };

        # Declare existing system user's home directory to satisfy nix-darwin
        # activation check (nix-darwin refuses to change existing users' homes)
        users.users._dnscrypt-proxy.home = lib.mkForce cfg.userHome;

        # Override launchd config to run as root (required for port 53 binding)
        # The default _dnscrypt-proxy user cannot bind to privileged ports
        launchd.daemons.dnscrypt-proxy.serviceConfig = {
          UserName = lib.mkForce "root";
          GroupName = lib.mkForce "wheel";
        };

        # Point every hardware network service at the local listener, now and
        # whenever the network configuration changes: attaching an adapter for
        # the first time creates its service in the SystemConfiguration
        # preferences, which this watch picks up within seconds.
        launchd.daemons.dnscrypt-pin-dns = {
          command = lib.getExe pinDns;
          serviceConfig = {
            RunAtLoad = true;
            WatchPaths = [ "/Library/Preferences/SystemConfiguration/preferences.plist" ];
            StandardOutPath = "/var/log/dnscrypt-pin-dns.log";
            StandardErrorPath = "/var/log/dnscrypt-pin-dns.log";
          };
        };

        # `dnscrypt-pin-dns --check` lists any service not pinned
        environment.systemPackages = [ pinDns ];

        # Health check: ensure dnscrypt-proxy is responding after activation
        system.activationScripts.postActivation.text = lib.mkAfter ''
          ${lib.getExe pinDns}
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
          # The listener answering is not enough: the resolver macOS actually
          # uses must be it, or queries leave in plaintext via the active service.
          active="$(/usr/sbin/scutil --dns | ${pkgs.gawk}/bin/awk '/^resolver #1/ { r = 1 } r && !found && /nameserver\[0\]/ { print $3; found = 1 }')"
          if [ -n "$active" ] && [ "$active" != 127.0.0.1 ] && [ "$active" != ::1 ]; then
            echo "warning: active resolver is $active, not the local dnscrypt-proxy" >&2
            ${lib.getExe pinDns} --check || true
          fi
        '';
      };
    };

  flake.modules.nixos.dnscrypt-proxy =
    { config, ... }:
    let
      cfg = config.services.localDnscryptProxy;
    in
    {
      options.services.localDnscryptProxy = sharedOptions;

      # Every systemd-networkd network, including the catch-all DHCP networks
      # that match adapters attached later, stops taking DNS servers and
      # search domains from DHCP and router advertisements. A network that
      # sets them explicitly (a static DNS= or Domains=, such as the
      # ZeroTier split DNS) is unaffected, and a network can still opt back
      # in by setting these at normal priority.
      options.systemd.network.networks = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            config = lib.mkIf cfg.enable {
              dhcpV4Config = {
                UseDNS = lib.mkDefault false;
                UseDomains = lib.mkDefault false;
              };
              dhcpV6Config = {
                UseDNS = lib.mkDefault false;
                UseDomains = lib.mkDefault false;
              };
              ipv6AcceptRAConfig = {
                UseDNS = lib.mkDefault false;
                UseDomains = lib.mkDefault false;
              };
            };
          }
        );
      };

      config = lib.mkIf cfg.enable {
        services.dnscrypt-proxy = {
          enable = true;
          # The upstream example config adds [sources] that download resolver
          # lists by hostname. With bootstrap_resolvers and the system resolver
          # disabled, and this listener being the system resolver, those names
          # cannot resolve and dnscrypt-proxy exits before serving; the
          # embedded-IP static stamps are the only servers wanted.
          upstreamDefaults = false;
          settings = mkSettings cfg.providers;
        };

        # The listener is resolved's only upstream (DNS= comes from
        # networking.nameservers). resolved's own stub stays on 127.0.0.53, so
        # the two do not contend for port 53.
        networking.nameservers = [
          "127.0.0.1"
          "::1"
        ];
        services.resolved.settings.Resolve = {
          # Route every name to the global server rather than to whichever
          # link resolved considers the default route
          Domains = [ "~." ];
          # An empty list renders FallbackDNS= and disables the plaintext
          # 1.1.1.1 / 8.8.8.8 fallback
          FallbackDNS = [ ];
          # The listener already encrypts, and the providers validate DNSSEC
          DNSOverTLS = false;
          DNSSEC = false;
        };

        # Without this NetworkManager gives resolved each connection's DHCP
        # DNS server and search domain as link settings, and names under that
        # search domain would still be sent to the link server in plaintext.
        # Forced because nixpkgs' resolved module sets "systemd-resolved" at
        # normal priority.
        networking.networkmanager.dns = lib.mkIf config.networking.networkmanager.enable (
          lib.mkForce "none"
        );
      };
    };
}
