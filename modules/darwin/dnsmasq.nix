# Local dnsmasq configuration for DNS management
#
# Two modes of operation:
# 1. Default (forceDnsProvider = null): Gateway DNS with sslip.io exception
#    - Forwards sslip.io queries to Quad9 to bypass router DNS rebind protection
#    - All other queries use the network's default resolver
#
# 2. Forced provider (forceDnsProvider = "quad9"|"cloudflare"|"google"):
#    - Routes ALL DNS through local dnsmasq to specified provider
#    - Bypasses gateway/network DNS entirely
#
# sslip.io is a wildcard DNS service where *.192.168.100.3.sslip.io resolves
# to 192.168.100.3. Many routers block this as a potential DNS rebinding attack.
{ ... }:
{
  flake.modules.darwin.dnsmasq =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.localDnsmasq;

      # DNS provider IP mappings (primary + secondary for redundancy)
      dnsProviders = {
        quad9 = [
          "9.9.9.9"
          "149.112.112.112"
        ];
        cloudflare = [
          "1.1.1.1"
          "1.0.0.1"
        ];
        google = [
          "8.8.8.8"
          "8.8.4.4"
        ];
      };
    in
    {
      options.services.localDnsmasq = {
        enable = lib.mkEnableOption "local dnsmasq for DNS management";

        sslipUpstream = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "9.9.9.9"
            "149.112.112.112"
          ];
          description = ''
            Upstream DNS servers for sslip.io queries.
            Defaults to Quad9.
          '';
        };

        defaultUpstream = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "192.168.50.1";
          description = ''
            Default upstream DNS for non-sslip.io queries.
            Empty string uses system default resolver.
          '';
        };

        extraServers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "/internal.example.com/10.0.0.1" ];
          description = ''
            Additional domain-specific DNS server rules.
            Format: /domain/server or server for catch-all.
          '';
        };

        forceDnsProvider = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "quad9"
              "cloudflare"
              "google"
            ]
          );
          default = null;
          example = "quad9";
          description = ''
            Force all DNS queries through specified provider, bypassing gateway DNS.
            When null (default), uses gateway DNS with sslip.io exception only.
            Options: quad9, cloudflare, google.
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
            Network services to configure DNS for when forceDnsProvider is set.
            Use `networksetup -listallnetworkservices` to list available services.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        services.dnsmasq = {
          enable = true;
          bind = "127.0.0.1";
          port = 53;
          servers =
            # sslip.io forwarding to bypass rebind protection
            (map (server: "/sslip.io/${server}") cfg.sslipUpstream)
            # Extra domain-specific servers
            ++ cfg.extraServers
            # Default upstream (if specified via legacy option)
            ++ lib.optional (cfg.defaultUpstream != "") cfg.defaultUpstream
            # Forced provider catch-all (when forceDnsProvider is set)
            ++ lib.optionals (cfg.forceDnsProvider != null) dnsProviders.${cfg.forceDnsProvider};
        };

        # Tell macOS to route sslip.io queries to local dnsmasq
        # nix-darwin's dnsmasq module only creates resolver files for 'addresses',
        # not 'servers', so we create it explicitly here
        environment.etc."resolver/sslip.io" = {
          enable = true;
          text = ''
            nameserver 127.0.0.1
            port 53
          '';
        };

        # Configure system DNS via nix-darwin's networking module
        # Always set knownNetworkServices so activation script runs on revert
        # When forceDnsProvider is null, empty list triggers "empty" sentinel
        # which clears DNS back to DHCP; other modules' values concatenate safely
        networking.knownNetworkServices = cfg.networkServices;
        networking.dns = if cfg.forceDnsProvider != null then [ "127.0.0.1" ] else [ ];

        # Health check: ensure dnsmasq is responding after activation
        # nix-darwin's launchctl unload/load sometimes leaves service unresponsive
        system.activationScripts.postActivation.text = lib.mkAfter ''
          echo "checking dnsmasq health..." >&2
          if ! ${pkgs.dig}/bin/dig @127.0.0.1 +short +time=1 +tries=1 example.com &>/dev/null; then
            echo "dnsmasq not responding, restarting..." >&2
            launchctl bootout system/org.nixos.dnsmasq 2>/dev/null || true
            launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dnsmasq.plist
            sleep 0.5
            if ${pkgs.dig}/bin/dig @127.0.0.1 +short +time=1 +tries=1 example.com &>/dev/null; then
              echo "dnsmasq restart successful" >&2
            else
              echo "warning: dnsmasq still not responding after restart" >&2
            fi
          fi
        '';
      };
    };
}
