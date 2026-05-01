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
      # Compose portable content via typed slot.
      imports = [ flake.users.christophersmith.contentPortable ];

      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/christophersmith/secrets.yaml";
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
            ${flake.users.christophersmith.meta.email} namespaces="git" ${
              config.sops.placeholder."ssh-public-key"
            }
          '';
        };
      };

      # User-specific git identity from typed meta.
      # Identity setters (home.username/home.homeDirectory) live in
      # users/christophersmith/identity.nix; alias overrides come from aliases-fold.nix.
      programs.git.settings = {
        user.name = flake.users.christophersmith.meta.fullname;
        user.email = flake.users.christophersmith.meta.email;
      };
    };
in
{
  # Typed-slot writer.
  flake.users.christophersmith.contentPrivate = content;
}
