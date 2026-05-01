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
      imports = [ flake.users.janettesmith.contentPortable ];

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

      # User-specific git identity from typed meta.
      # Identity setters (home.username/home.homeDirectory) live in
      # users/janettesmith/identity.nix; alias overrides come from aliases-fold.nix.
      programs.git.settings = {
        user.name = flake.users.janettesmith.meta.fullname;
        user.email = flake.users.janettesmith.meta.email;
      };
    };
in
{
  # Typed-slot writer.
  flake.users.janettesmith.contentPrivate = content;
}
