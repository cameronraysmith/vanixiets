# Declared facts for the fleet map (flake.lib.fleetTopology): the services a
# host runs outside clan service roles, with the public hostnames and ports a
# person reaches them at. Written by hand and never computed from a host's
# configuration, so each entry is true only as of the edit that last touched
# it. Keys are flake.lib.hosts members; a member's class, public endpoints and
# overlay addresses are read from that registry and are not restated here.
# Mesh-only services carry no hostnames; their mesh names come from the
# registry's `services` labels.
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
        # modules/nixos/buildbot.nix
        (https "buildbot" [ "buildbot.scientistexperience.net" ])
        # modules/nixos/cognee.nix, modules/lib/cognee.nix
        (https "cognee" [ "kb.scientistexperience.net" ])
        # modules/nixos/gitea.nix
        (https "gitea" [ "git.scientistexperience.net" ])
        # modules/nixos/gitea-mq.nix
        (https "gitea-mq" [ "mq.scientistexperience.net" ])
        # modules/nixos/greptimedb.nix
        (meshOnly "greptimedb")
        # modules/nixos/kanidm.nix
        (https "kanidm" [ "accounts.scientistexperience.net" ])
        # modules/nixos/matrix.nix
        (https "matrix" [ "matrix.scientistexperience.net" ])
        # modules/nixos/niks3.nix
        (https "niks3" [
          "cache.scientistexperience.net"
          "niks3.scientistexperience.net"
        ])
        # modules/nixos/nixbot.nix
        (https "nixbot" [ "nixbot.scientistexperience.net" ])
        # modules/nixos/perses.nix
        (https "perses" [ "obs.scientistexperience.net" ])
        # The omnigent server role's domain (modules/clan/inventory/services/omnigent.nix);
        # declared here because role settings are not read for public names.
        (https "omnigent" [ "omni.scientistexperience.net" ])
        # modules/nixos/renovate.nix
        (meshOnly "renovate")
        # modules/nixos/sso-gateway.nix
        (https "sso-gateway" [ "auth.scientistexperience.net" ])
      ];

      # The registry's mesh service labels for cinnabar (modules/lib/hosts.nix).
      cinnabar.services = map meshOnly [
        "hermes"
        "kanban"
        "matrix"
        "ntfy"
        "omnigraph"
        "radicle"
      ];
    };
}
