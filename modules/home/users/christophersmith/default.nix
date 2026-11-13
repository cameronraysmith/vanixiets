{
  ...
}:
let
  content =
    {
      pkgs,
      flake,
      ...
    }:
    {
      home.stateVersion = "23.11";

      home.packages = with pkgs; [
        just # Command runner
        ripgrep # Fast grep alternative
        fd # Fast find alternative
        bat # Cat with syntax highlighting
        eza # Modern ls replacement
      ];

      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/christophersmith/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          bitwarden-email = { };
          atuin-key = { };
        };
      };
    };
in
{
  flake.users.christophersmith.contentPrivate = content;
}
