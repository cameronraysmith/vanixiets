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
            ${flake.users.janettesmith.meta.gitEmail} namespaces="git" ${
              config.sops.placeholder."ssh-public-key"
            }
          '';
        };
      };

      programs.git.settings = {
        user.name = flake.users.janettesmith.meta.fullname;
        user.email = flake.users.janettesmith.meta.gitEmail;
      };
      programs.jujutsu.settings.user.email = flake.users.janettesmith.meta.gitEmail;
    };
in
{
  flake.users.janettesmith.contentPrivate = content;
}
