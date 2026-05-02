{
  ...
}:
let
  content =
    {
      config,
      pkgs,
      flake,
      ...
    }:
    {
      home.stateVersion = "23.11";

      home.packages = with pkgs; [
        gh # GitHub CLI (keep from baseline)
        just # Command runner
        ripgrep # Fast grep alternative
        fd # Fast find alternative
        bat # Cat with syntax highlighting
        eza # Modern ls replacement
      ];

      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/janettesmith/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { };
          bitwarden-email = { };
          atuin-key = { };
        };

        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${flake.users.janettesmith.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      programs.git.settings = {
        user.name = flake.users.janettesmith.meta.fullname;
        user.email = flake.users.janettesmith.meta.email;
      };
    };
in
{
  flake.users.janettesmith.contentPrivate = content;
}
