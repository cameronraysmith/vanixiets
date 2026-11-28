{ config, ... }:
{
  flake.users.christophersmith.contentPrivate = config.flake.lib.mkUserContent "christophersmith" (
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        just # Command runner
        ripgrep # Fast grep alternative
        fd # Fast find alternative
        bat # Cat with syntax highlighting
        eza # Modern ls replacement
      ];

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
