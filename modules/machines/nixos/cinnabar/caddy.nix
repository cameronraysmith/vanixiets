{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { pkgs, ... }:
    let
      meshListenAddrs = [
        "fddb:4344:343b:14b9:399:93db:4344:343b"
        "10.147.17.1"
      ];
    in
    {
      services.caddy = {
        enable = true;
        virtualHosts = {
          "kanban.zt" = {
            listenAddresses = meshListenAddrs;
            extraConfig = ''
              tls internal
              reverse_proxy localhost:3008
            '';
          };
          "matrix.zt" = {
            listenAddresses = meshListenAddrs;
            extraConfig = ''
              tls internal
              reverse_proxy [::1]:8008
            '';
          };
          "ntfy.zt" = {
            listenAddresses = meshListenAddrs;
            extraConfig = ''
              tls internal
              reverse_proxy [::1]:2586
            '';
          };
          "radicle.zt" = {
            listenAddresses = meshListenAddrs;
            extraConfig =
              let
                explorer = pkgs.radicle-explorer.withConfig {
                  preferredSeeds = [
                    {
                      hostname = "radicle.zt";
                      port = 443;
                      scheme = "https";
                    }
                  ];
                };
              in
              ''
                tls internal
                handle /api/* {
                  reverse_proxy [::1]:8080
                }
                handle /raw/* {
                  reverse_proxy [::1]:8080
                }
                handle {
                  root * ${explorer}
                  try_files {path} /index.html
                  file_server
                }
              '';
          };
          "hermes.zt" = {
            listenAddresses = meshListenAddrs;
            # hermes-agent dashboard binds 127.0.0.1 (see clan-service module's
            # hermes-agent-dashboard unit, commit 810777f2); target loopback IPv4
            # to match the bind. Port 18790 mirrors the wrapper's dashboardPort
            # default (loopback-only, reverse-proxied here).
            extraConfig = ''
              tls internal
              reverse_proxy 127.0.0.1:18790 {
                header_up -X-Forwarded-For
                header_up -X-Forwarded-Proto
                header_up -X-Forwarded-Host
                header_up Host 127.0.0.1:18790
                # Dashboard WS guard (web_server.py) checks Origin against the loopback bind; rewrite it so /api/events + /api/pty WS upgrades from hermes.zt aren't refused as origin_mismatch.
                header_up Origin http://127.0.0.1:18790
              }
            '';
          };
        };
      };

      # Caddy binds the ZeroTier-assigned mesh addresses (meshListenAddrs),
      # which zerotierone configures asynchronously and which are briefly
      # tentative during IPv6 Duplicate Address Detection (present in
      # `ip addr show` yet unbindable, so bind() returns EADDRNOTAVAIL).
      # Permit binding addresses that are not yet present/ready rather than
      # racing their lifecycle; the zt+ firewall below remains the access
      # boundary. This is the canonical pattern for binding addresses managed
      # by a separate daemon (cf. keepalived/HAProxy floating IPs).
      boot.kernel.sysctl = {
        "net.ipv6.ip_nonlocal_bind" = 1;
        "net.ipv4.ip_nonlocal_bind" = 1;
      };

      # only allow https on zerotier interfaces
      networking.firewall.interfaces."zt+".allowedTCPPorts = [ 443 ];
    };
}
