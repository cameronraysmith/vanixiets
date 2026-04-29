{
  lib,
  ...
}:
{
  flake.modules.homeManager."users/tara" =
    {
      config,
      pkgs,
      lib,
      flake,
      ...
    }:
    {
      imports = [ flake.modules.homeManager."portable/tara" ];

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

      home.username = lib.mkDefault flake.users.tara.meta.username;
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      programs.git.settings = {
        user.name = flake.users.tara.meta.fullname;
        user.email = flake.users.tara.meta.email;
      };
    };
}
