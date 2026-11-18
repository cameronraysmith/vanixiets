# SSH to pyrite over iroh (dumbpipe), its recovery path independent of the mesh
# pyrite sits behind address-translating routers and runs VM tests and remote builds
# unattended, so it needs a way in when the overlay network is down; iroh brings its
# own QUIC hole punching and relays, a failure domain separate from the mesh.
#
# The service has only a server role (NixOS): a dumbpipe listener forwarding to
# 127.0.0.1:22, with an iroh identity in the vars generator `p2p-ssh-iroh-iroh`
# whose public `ticket` file is the address. The client is the clan CLI on stibnite
# itself: it resolves dumbpipe through nix and reads the ticket from this repository,
# so stibnite needs no inventory role. pyrite keeps its inventory targetHost, which
# clan prefers over every network, so iroh is used only through the explicit
# break-glass invocation in the operations runbook
# (packages/docs/src/content/docs/development/operations/break-glass-recovery.md).
{
  flake.clan.inventory.instances.iroh = {
    module = {
      name = "p2p-ssh-iroh";
      input = "clan-core";
    };
    roles.server.machines.pyrite = { };
  };
}
