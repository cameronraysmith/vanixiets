{ config, ... }:
{
  flake.users.raquel.contentPrivate = config.flake.lib.mkUserContent "raquel" (
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        just # Command runner
        ripgrep # Fast grep alternative
        fd # Fast find alternative
        bat # Cat with syntax highlighting
        eza # Modern ls replacement
      ];

      # The development and shell aggregates' secrets; raquel takes no AI tools.
      sops.secrets = {
        github-token = { };
        ssh-signing-key = {
          mode = "0400";
        };
        bitwarden-email = { };
        atuin-key = { };
      };
    }
  );
}
