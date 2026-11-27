# SSH CA trust for Darwin machines
# The clan sshd service only provides nixosModule, not darwinModule.
# This module replicates the sshd client role's CA trust on Darwin
# so that Darwin machines verify NixOS host certificates without TOFU.
# The openssh-ca entry of vanixiets.secrets is this module's own copy of
# the sshd service's shared CA generator, declared so that the CA public
# key's .value can be read (share = true means no regeneration).
# The mkIf guard allows evaluation before the CA key has been generated.
{ lib, ... }:
{
  flake.modules.darwin.ssh-ca-trust =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      vanixiets.secrets.openssh-ca = {
        share = true;
        runtimeInputs = [ pkgs.openssh ];
        files.id_ed25519.deploy = false;
        files."id_ed25519.pub" = {
          deploy = false;
          secret = false;
        };
        script = ''
          ssh-keygen -t ed25519 -N "" -C "" -f "$out"/id_ed25519
        '';
      };

      programs.ssh.knownHosts.ssh-ca =
        lib.mkIf config.vanixiets.secrets.openssh-ca.files."id_ed25519.pub".exists
          {
            certAuthority = true;
            extraHostNames = [ "*.${config.clan.core.settings.domain}" ];
            publicKey = config.vanixiets.secrets.openssh-ca.files."id_ed25519.pub".value;
          };
    };
}
