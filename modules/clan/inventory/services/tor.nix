# Clan tor service exposing machines over the Tor network
# Server role: v3 onion service mapping port 22 to sshd; not Tor relaying, which is
# services.tor.relay.enable (default false) and is never set by clan-core's tor role
# despite the onion service nesting under services.tor.relay.onionServices
{
  clan.inventory.instances.tor = {
    module = {
      name = "tor";
      input = "clan-core";
    };
    roles.server.tags."nixos" = { };
  };
}
