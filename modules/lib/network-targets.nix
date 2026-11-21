# The user clan logs in as when it reaches a machine through a network, and
# the per-host judge the machine checks assert (finding F36 of the openspec
# change migrate-mesh-to-tincr).
#
# Without --target-host, `clan machines update` takes inventory
# deploy.targetHost if set; otherwise it tries every network whose export
# lists the machine as a peer, highest priority first, and reaches the
# machine's own clan.core.networking.targetHost only when none answers. A
# network logs in as its peer export's `user`, root when that is null
# (clan-core d718bcf9, pkgs/clan-cli/clan_lib/network/network.py:36-41,
# :183-191, :223-316; network/direct.py:46-55). The login user is
# flake.lib.hosts.<name>.deployUser (root on NixOS, the admin account on
# darwin), so every peer export of a machine must carry it.
{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.flake.lib) hosts;
  inherit (inputs.clan-core.clanLib) parseScope;

  # One message per network that would log in to `name` as someone other
  # than `deployUser`. `peers` maps a network to the machine's peer export.
  problems =
    {
      name,
      deployUser,
      peers,
    }:
    lib.concatLists (
      lib.mapAttrsToList (
        network: peer:
        let
          user = if peer.user == null then "root" else peer.user;
        in
        lib.optional (
          user != deployUser
        ) "${network} would log in to ${name} as ${user}, not its login user ${toString deployUser}"
      ) peers
    );

  # One message per way the machine's deploy address leaves its single
  # source, flake.lib.hosts.<name>.targetHost (F83): clan's targetHost set to
  # anything else, and a darwin machine given an inventory deploy.targetHost,
  # which clan would take before the network peers above.
  targetProblems =
    {
      name,
      class,
      targetHost,
      configTargetHost,
      inventoryTargetHost,
    }:
    lib.optional (configTargetHost != targetHost)
      "${name}'s clan.core.networking.targetHost is ${toString configTargetHost}, not flake.lib.hosts.${name}.targetHost ${toString targetHost}"
    ++
      lib.optional (class == "darwin" && inventoryTargetHost != null)
        "${name} is darwin but sets inventory deploy.targetHost ${inventoryTargetHost}, so clan would skip its network peers";

  # The machine's peer export in every network, keyed by
  # `<service>:<instance>` as clan scopes them.
  peersOf =
    name:
    lib.mapAttrs'
      (
        key: export:
        let
          scope = parseScope key;
        in
        lib.nameValuePair "${scope.serviceName}:${scope.instanceName}" export.peer
      )
      (
        lib.filterAttrs (
          key: export:
          lib.isAttrs export && (export.peer or null) != null && (parseScope key).machineName == name
        ) inputs.self.clan.exports
      );
in
{
  flake.lib.networkTargetObligations = {
    inherit problems targetProblems;
    failures =
      name: machineConfig:
      problems {
        inherit name;
        inherit (hosts.${name}) deployUser;
        peers = peersOf name;
      }
      ++ targetProblems {
        inherit name;
        inherit (hosts.${name}) class targetHost;
        configTargetHost = machineConfig.clan.core.networking.targetHost;
        inventoryTargetHost = inputs.self.clan.inventory.machines.${name}.deploy.targetHost or null;
      };
  };
}
