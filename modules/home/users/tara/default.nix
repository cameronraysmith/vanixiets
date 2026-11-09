{
  ...
}:
let
  content =
    {
      config,
      flake,
      ...
    }:
    {
      home.stateVersion = "23.11";

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
            ${config.vcs.author.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };
    };
in
{
  flake.users.tara.contentPrivate = content;
}
