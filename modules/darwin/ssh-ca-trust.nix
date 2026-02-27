# SSH CA trust for Darwin machines
# The clan sshd service only provides nixosModule, not darwinModule.
# This module replicates the sshd client role's CA trust on Darwin
# so that Darwin machines verify NixOS host certificates without TOFU.
# The openssh-ca generator definition enables the .value accessor
# for the shared CA public key (share = true means no regeneration).
# The mkIf guard allows evaluation before clan vars generate has run.
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
      clan.core.vars.generators.openssh-ca = {
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
        lib.mkIf config.clan.core.vars.generators.openssh-ca.files."id_ed25519.pub".exists
          {
            certAuthority = true;
            extraHostNames = [ "*.${config.clan.core.settings.domain}" ];
            publicKey = config.clan.core.vars.generators.openssh-ca.files."id_ed25519.pub".value;
          };
    };
}
