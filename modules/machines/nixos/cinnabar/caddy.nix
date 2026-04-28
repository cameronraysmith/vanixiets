{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { pkgs, lib, ... }:
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
          "beads.zt" = {
            listenAddresses = meshListenAddrs;
            extraConfig = ''
              tls internal
              reverse_proxy localhost:3009
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
          "openclaw.zt" = {
            listenAddresses = meshListenAddrs;
            extraConfig = ''
              tls internal
              reverse_proxy [::1]:18789 {
                header_up -X-Forwarded-For
                header_up -X-Forwarded-Proto
                header_up -X-Forwarded-Host
              }
            '';
          };
        };
      };

      # Caddy binds ZeroTier-assigned addresses (meshListenAddrs above). zerotierone.service
      # becomes "active" before its daemon finishes assigning addresses to zt+ interfaces, so
      # caddy can lose the bind race at boot and exit with status 1 (which the upstream module's
      # RestartPreventExitStatus=1 deliberately excludes from auto-restart). Wait until every
      # configured address is present locally before letting caddy start.
      systemd.services.caddy = {
        after = [ "zerotierone.service" ];
        wants = [ "zerotierone.service" ];
        serviceConfig.ExecStartPre = pkgs.writeShellScript "wait-for-mesh-addrs" ''
          set -eu
          addrs="${lib.concatStringsSep " " meshListenAddrs}"
          for _ in $(seq 1 60); do
            missing=0
            for addr in $addrs; do
              ${pkgs.iproute2}/bin/ip addr show | ${pkgs.gnugrep}/bin/grep -qF "$addr" || missing=1
            done
            [ "$missing" = "0" ] && exit 0
            sleep 0.5
          done
          echo "Mesh addresses never appeared: $addrs" >&2
          exit 1
        '';
      };

      # only allow https on zerotier interfaces
      networking.firewall.interfaces."zt+".allowedTCPPorts = [ 443 ];
    };
}
