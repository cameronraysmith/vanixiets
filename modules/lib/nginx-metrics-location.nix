# nginx location restricting a vhost's Prometheus endpoint to loopback and the
# ZeroTier mesh, for services whose vhost otherwise proxies `/` publicly.
# The regex covers /metrics, /metrics/ and anything under /metrics/ without
# shadowing sibling paths such as /metricsfoo.
# The mesh range is the ZeroTier /64 that cognee's no-public-bind assertion
# already admits (modules/nixos/cognee.nix).
{ ... }:
{
  flake.lib.nginxMetricsLocation =
    let
      accessRules = ''
        allow 127.0.0.0/8;
        allow ::1;
        allow fddb:4344:343b:14b9::/64;
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
