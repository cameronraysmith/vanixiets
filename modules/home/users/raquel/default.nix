{
  # OUTER: Flake-parts module signature
  ...
}:
let
  content =
    {
      # INNER: Home-manager module signature
      config,
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
      # 5 secrets: development + shell aggregates (NO AI)
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/raquel/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # NEW: For allowed_signers generation
          bitwarden-email = { };
          atuin-key = { };
        };

        # Generate allowed_signers file using sops.templates
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${config.vcs.author.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };
    };
in
{
  flake.users.raquel.contentPrivate = content;
}
