# Bitwarden SSH agent configuration
# Migrated from vanixiets/modules/home/all/core/bitwarden.nix
{ inputs, ... }:
{
  flake.modules.homeManager.core =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      isDarwin = pkgs.stdenv.isDarwin;

      # On Darwin, bitwarden is installed via homebrew MAS and enabled by default
      # On NixOS, it's disabled by default to avoid circular dependencies
      # (checking config.home.packages would create infinite recursion)
      bitwardenEnabled = isDarwin;

      # https://bitwarden.com/help/ssh-agent/#tab-macos-6VN1DmoAVFvm7ZWD95curS
      socketPath = inputs.self.lib.bitwardenSocketPath {
        inherit (config.home) homeDirectory;
        inherit isDarwin;
      };
    in
    {
      # SSH agent provider: Bitwarden on Darwin, systemd ssh-agent on Linux
      # https://bitwarden.com/help/ssh-agent/#configure-bitwarden-ssh-agent
      home.sessionVariables = lib.mkIf bitwardenEnabled {
        SSH_AUTH_SOCK = socketPath;
      };

      # Linux: systemd user ssh-agent for git signing and SSH authentication
      # Add signing key once per session: ssh-add ~/.config/sops-nix/secrets/ssh-signing-key
      services.ssh-agent.enable = !isDarwin;
    };
}
