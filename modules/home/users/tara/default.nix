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
      imports = [ flake.users.tara.contentPortable ];

      # Minimal initial secrets: signing key + public key only.
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/tara/secrets.yaml";
        secrets = {
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { };
        };

        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${flake.users.tara.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      programs.git.settings = {
        user.name = flake.users.tara.meta.fullname;
        user.email = flake.users.tara.meta.email;
      };
    };
in
{
  flake.users.tara.contentPrivate = content;
}
