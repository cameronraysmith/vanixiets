{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # sec
        age
        aws-vault
        bitwarden-cli
        # bitwarden-desktop <- via homebrew MAS on Darwin
        # bws # Bitwarden Secrets Manager CLI - disabled: ~1GB Rust build causes CI disk space failures
        gitleaks
        libfido2
        # Note: Nix openssh uses BSD sockets which can't route to zerotier feth
        # interfaces on macOS Tahoe. System SSH uses Network.framework which works.
        # Use `sshm` alias for /usr/bin/ssh when connecting via zerotier IPv6.
        openssh
        sops
        ssh-to-age
        yubikey-manager
      ];
    };
}
