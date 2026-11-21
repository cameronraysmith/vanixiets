# nginx location restricting a vhost's Prometheus endpoint to loopback and the
# overlay networks, for services whose vhost otherwise proxies `/` publicly.
# The regex covers /metrics, /metrics/ and anything under /metrics/ without
# shadowing sibling paths such as /metricsfoo.
# The ranges are the tincr mesh prefix from flake.lib.mesh and, until ZeroTier
# is retired, the /64 of the members' ZeroTier addresses in flake.lib.hosts.
{ config, lib, ... }:
let
  inherit (config.flake.lib) hosts mesh;
  zerotierNetwork = lib.concatStringsSep ":" (
    lib.take 4 (lib.splitString ":" hosts.cinnabar.zerotier.address)
  );
in
{
  flake.lib.nginxMetricsLocation =
    let
      accessRules = ''
        allow 127.0.0.0/8;
        allow ::1;
        allow ${mesh.prefixOf mesh.instance};
        allow ${zerotierNetwork}::/64;
        deny all;
      '';
    in
    # Proxies exactly as the vhost's `/` location does, plus accessRules.
    vhost: {
      "~ ^/metrics(/|$)" = {
        inherit (vhost.locations."/") proxyPass;
        extraConfig = vhost.locations."/".extraConfig + accessRules;
      };
    };
}
