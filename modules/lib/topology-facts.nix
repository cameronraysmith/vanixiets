# Declared facts for the fleet map (flake.lib.fleetTopology): the services a
# host runs outside clan service roles, with the public hostnames and ports a
# person reaches them at. Written by hand and never computed from a host's
# configuration, so each entry is true only as of the edit that last touched
# it. Keys are flake.lib.hosts members; a member's class, public endpoints and
# overlay addresses are read from that registry and are not restated here.
# Mesh-only services carry no hostnames; their mesh names come from the
# registry's `services` labels.
#
# Checked against the hosts on 2026-11-18 (`ss -ltn`/`ss -lun`, the active
# units, magnetite's nginx virtual hosts and cinnabar's Caddyfile, and an
# HTTPS probe of each name). A module that is imported but disabled, such
# as the parked sso-gateway on magnetite, is not declared, and a
# name answered by Cloudflare, such as niks3's cache., is not declared on a
# host.
#
# Editing this file changes packages/docs/diagrams/topology/; run
# `just topology-generate` (checks.x86_64-linux.fleet-topology-fresh fails
# otherwise).
{
  flake.lib.topologyFacts =
    let
      https = name: hostnames: {
        inherit name hostnames;
        ports = [ 443 ];
      };
      meshOnly = name: {
        inherit name;
        hostnames = [ ];
        ports = [ ];
      };
    in
    {
      magnetite.services = [
        # modules/nixos/gitea.nix
        (https "gitea" [ "git.scientistexperience.net" ])
        # modules/nixos/gitea-mq.nix
        (https "gitea-mq" [ "mq.scientistexperience.net" ])
        # modules/nixos/greptimedb.nix
        (meshOnly "greptimedb")
        # modules/nixos/kanidm.nix
        (https "kanidm" [ "accounts.scientistexperience.net" ])
        # modules/nixos/matrix.nix: the homeserver behind nginx, and its
        # TURN relay and LiveKit SFU, which listen on the public address.
        (https "matrix" [ "matrix.scientistexperience.net" ])
        {
          name = "coturn";
          hostnames = [ ];
          ports = [
            3478
            5349
          ];
        }
        {
          name = "livekit";
          hostnames = [ ];
          ports = [
            7880
            7881
          ];
        }
        # modules/nixos/niks3.nix; cache. is served by Cloudflare, not here.
        (https "niks3" [ "niks3.scientistexperience.net" ])
        # modules/nixos/nixbot.nix
        (https "nixbot" [ "nixbot.scientistexperience.net" ])
        # The omnigent server role's domain (modules/clan/inventory/services/omnigent.nix);
        # declared here because role settings are not read for public names.
        (https "omnigent" [ "omni.scientistexperience.net" ])
        # omnigraph-server on :8090, reached over the mesh through cinnabar's
        # omnigraph.vanixiets.internal site.
        (meshOnly "omnigraph")
        # modules/nixos/perses.nix
        (https "perses" [ "obs.scientistexperience.net" ])
        # modules/nixos/renovate.nix, a timer-started job.
        (meshOnly "renovate")
      ];

      # The mesh sites cinnabar's caddy serves for services that run on
      # cinnabar (modules/lib/hosts.nix labels; omnigraph's backend is
      # magnetite's).
      cinnabar.services = map meshOnly [
        "hermes"
        "matrix"
        "ntfy"
        "radicle"
      ];
    };
}
