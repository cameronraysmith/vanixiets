{ config, ... }:
let
  inherit (config.flake.lib) fleet hosts meshInterfaces;
  inherit (hosts) cinnabar magnetite;
in
{
  flake.modules.nixos.caddy =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # cinnabar's ZeroTier IPv4, pinned by zt-dns.nix; the registry carries
      # only IPv6, and this literal goes with ZeroTier's retirement.
      zerotierIPv4 = "10.147.17.1";

      # Each site's caddy configuration, given its own name and the address
      # magnetite is reached on over the same transport.
      sites = {
        matrix = _: ''
          tls internal
          reverse_proxy [::1]:8008
        '';
        ntfy = _: ''
          tls internal
          reverse_proxy [::1]:2586
        '';
        # The 0.14+ CLI refuses a token over plain HTTP to anything but
        # loopback, so magnetite's omnigraph-server is reached through this
        # TLS front. The original Host passes through, which /mcp admits
        # only for the names magnetite lists in --mcp-allowed-host.
        omnigraph =
          { magnetiteAddress, ... }:
          ''
            tls internal
            reverse_proxy [${magnetiteAddress}]:8090
          '';
        radicle =
          { name, ... }:
          let
            explorer = pkgs.radicle-explorer.withConfig {
              preferredSeeds = [
                {
                  hostname = name;
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
        # hermes-agent dashboard binds 127.0.0.1 (see clan-service module's
        # hermes-agent-dashboard unit, commit 810777f2); target loopback IPv4
        # to match the bind. Port 18790 mirrors the wrapper's dashboardPort
        # default (loopback-only, reverse-proxied here).
        hermes = _: ''
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

      # One site per service label the registry places on cinnabar, under
      # the given domain and listening on that transport's addresses.
      sitesUnder =
        {
          domain,
          listenAddresses,
          magnetiteAddress,
        }:
        lib.listToAttrs (
          map (
            label:
            let
              name = "${label}.${domain}";
            in
            lib.nameValuePair name {
              inherit listenAddresses;
              extraConfig = sites.${label} { inherit name magnetiteAddress; };
            }
          ) cinnabar.services
        );
    in
    {
      services.caddy = {
        enable = true;
        virtualHosts =
          sitesUnder {
            domain = "zt";
            listenAddresses = [
              cinnabar.zerotier.address
              zerotierIPv4
            ];
            magnetiteAddress = magnetite.zerotier.address;
          }
          // sitesUnder {
            inherit (fleet) domain;
            listenAddresses = [ cinnabar.address ];
            magnetiteAddress = magnetite.address;
          };
      };

      # Caddy binds the mesh addresses, which zerotierone and tincr configure
      # asynchronously and which are briefly tentative during IPv6 Duplicate
      # Address Detection (present in `ip addr show` yet unbindable, so bind()
      # returns EADDRNOTAVAIL). Permit binding addresses that are not yet
      # present/ready rather than racing their lifecycle; the mesh firewall
      # below remains the access boundary. This is the canonical pattern for
      # binding addresses managed by a separate daemon (cf. keepalived/HAProxy
      # floating IPs).
      boot.kernel.sysctl = {
        "net.ipv6.ip_nonlocal_bind" = 1;
        "net.ipv4.ip_nonlocal_bind" = 1;
      };

      # only allow https on the mesh interfaces
      networking.firewall.interfaces = lib.genAttrs (meshInterfaces config) (_: {
        allowedTCPPorts = [ 443 ];
      });
    };
}
