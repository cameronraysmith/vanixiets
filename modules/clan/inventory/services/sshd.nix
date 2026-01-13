# Clan SSHD service configuration
# Manages persistent SSH host keys via clan vars
# Basic configuration without CA certificates (sufficient for zerotier private network)
{
  clan.inventory.instances = {
    sshd-basic = {
      module = {
        name = "sshd";
        input = "clan-core";
      };

      # Enable server role for all NixOS machines
      # Note: clan-core sshd service only supports NixOS, not nix-darwin
      # nix-darwin machines (blackphos) use SSH client only
      roles.server.tags."all" = { };
    };
  };
}
