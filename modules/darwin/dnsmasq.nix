# Local dnsmasq configuration for sslip.io wildcard DNS resolution
#
# Enables domain-specific DNS forwarding to bypass router-level DNS rebind
# protection that blocks responses with private IPs (192.168.x.x, 10.x.x.x).
#
# sslip.io is a wildcard DNS service where *.192.168.100.3.sslip.io resolves
# to 192.168.100.3. Many routers block this as a potential DNS rebinding attack.
#
# This module forwards sslip.io queries to Quad9 while keeping all other
# queries on the default resolver.
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
    in
    {
      options.services.localDnsmasq = {
        enable = lib.mkEnableOption "local dnsmasq for sslip.io wildcard resolution";

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
            # Default upstream (if specified)
            ++ lib.optional (cfg.defaultUpstream != "") cfg.defaultUpstream;
        };
      };
    };
}
