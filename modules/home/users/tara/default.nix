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
      # Compose portable content via typed slot (nix-0pd.17 A5).
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

      # User-specific git identity from typed meta.
      # (Identity setters home.username/home.homeDirectory now provided by
      # users/tara/identity.nix via flake.users.tara.identity —
      # nix-0pd.17 A5.)
      programs.git.settings = {
        user.name = flake.users.tara.meta.fullname;
        user.email = flake.users.tara.meta.email;
      };
    };
in
{
  # Typed-slot writer (nix-0pd.17 A5: registry-key dual-write dropped).
  flake.users.tara.contentPrivate = content;
}
