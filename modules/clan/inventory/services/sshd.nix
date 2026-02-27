# Clan SSHD service with CA certificate infrastructure
# Server role: persistent host keys + CA-signed host certificates (NixOS only)
# Client role: CA trust for TOFU-free host verification (NixOS only)
# Darwin CA trust is handled separately in modules/darwin/ssh-ca-trust.nix
{
  clan.inventory.instances = {
    sshd = {
      module = {
        name = "sshd";
        input = "clan-core";
      };

      # Server role generates host keys and CA-signed certificates
      # Restricted to NixOS (clan sshd service has no darwinModule for server)
      roles.server.tags."nixos" = { };

      # Client role installs CA public key in known_hosts
      # Restricted to NixOS (clan sshd service has no darwinModule for client)
      roles.client.tags."nixos" = { };
    };
  };
}
