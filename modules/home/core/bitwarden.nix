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
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
      cfg = config.programs.bitwarden-ssh-agent;

      # https://bitwarden.com/help/ssh-agent/#tab-macos-6VN1DmoAVFvm7ZWD95curS
      socketPath = inputs.self.lib.bitwardenSocketPath {
        inherit (config.home) homeDirectory;
        inherit isDarwin;
      };
    in
    {
      options.programs.bitwarden-ssh-agent.enable = lib.mkOption {
        type = lib.types.bool;
        default = isDarwin;
        defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isDarwin";
        description = ''
          Whether the Bitwarden Desktop SSH agent is the session's SSH agent.
          When enabled, SSH_AUTH_SOCK points at its socket and the systemd user
          ssh-agent is not started; when disabled on Linux, the systemd user
          ssh-agent provides SSH_AUTH_SOCK.
          https://bitwarden.com/help/ssh-agent/#configure-bitwarden-ssh-agent
        '';
      };

      config = {
        home.sessionVariables = lib.mkIf cfg.enable {
          SSH_AUTH_SOCK = socketPath;
        };
        systemd.user.sessionVariables = lib.mkIf (cfg.enable && !isDarwin) {
          SSH_AUTH_SOCK = socketPath;
        };

        services.ssh-agent.enable = !isDarwin && !cfg.enable;
      };
    };
}
