{
  # OUTER: Flake-parts module signature
  ...
}:
let
  content =
    {
      # INNER: Home-manager module signature
      pkgs,
      flake, # from extraSpecialArgs
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

      # sops-nix configuration for raquel user
      # 4 secrets: development + shell aggregates (NO AI)
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/raquel/secrets.yaml";
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
  flake.users.raquel.contentPrivate = content;
}
