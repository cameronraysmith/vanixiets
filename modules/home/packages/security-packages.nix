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
        openssh
        sops
        ssh-to-age
        yubikey-manager
      ];
    };
}
