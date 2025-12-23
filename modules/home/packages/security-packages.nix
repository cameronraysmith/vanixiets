{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, lib, ... }:
    {
      home.packages =
        with pkgs;
        [
          # sec
          age
          aws-vault
          bitwarden-cli
          # bitwarden-desktop <- via homebrew MAS on Darwin
          # bws # Bitwarden Secrets Manager CLI - disabled: ~1GB Rust build causes CI disk space failures
          gitleaks
          libfido2
          sops
          ssh-to-age
          yubikey-manager
        ]
        ++ lib.optionals (!stdenv.isDarwin) [
          # Darwin: system SSH uses Network.framework for zerotier feth routing
          # Nix openssh uses BSD sockets which can't route to virtual interfaces
          openssh
        ];
    };
}
