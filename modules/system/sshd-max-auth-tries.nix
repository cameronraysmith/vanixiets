{
  # Default of 6 is exhausted by agent forwarding before the right key is
  # offered: the Bitwarden SSH agent commonly holds 10+ keys. The darwin half
  # is in modules/darwin/base-essentials.nix, written as sshd_config text.
  flake.modules.nixos.base-sshd-max-auth-tries = {
    services.openssh.settings.MaxAuthTries = 20;
  };
}
