# Clan SSHD service with CA certificate infrastructure
# Server role: persistent host keys + CA-signed host certificates (NixOS only)
# Client role: CA trust for TOFU-free host verification (NixOS only)
# Darwin CA trust is handled separately in modules/darwin/ssh-ca-trust.nix
# searchDomains activates CA generators (required on pre-PR#6802 clan-core)
{
  flake.clan.inventory.instances = {
    sshd = {
      module = {
        name = "sshd";
        input = "clan-core";
      };

      # Key and certificate login only: with UsePAM, keyboard-interactive would
      # let PAM accept a password. srvos sets this on hosts that import its
      # server profile; pyrite does not. Checked by
      # checks.x86_64-linux.sshd-no-keyboard-interactive.
      roles.server.extraModules = [
        { services.openssh.settings.KbdInteractiveAuthentication = false; }
      ];

      # Server role generates host keys and CA-signed certificates
      # Restricted to NixOS (clan sshd service has no darwinModule for server)
      roles.server.tags."nixos" = { };
      roles.server.settings.certificate.searchDomains = [ "zt" ];

      # Client role installs CA public key in known_hosts
      # Restricted to NixOS (clan sshd service has no darwinModule for client)
      roles.client.tags."nixos" = { };
      roles.client.settings.certificate.searchDomains = [ "zt" ];
    };
  };
}
