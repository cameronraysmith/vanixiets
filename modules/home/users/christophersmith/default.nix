{
  lib,
  ...
}:
{
  flake.modules.homeManager."users/christophersmith" =
    {
      config,
      pkgs,
      lib,
      flake,
      ...
    }:
    {
      imports = [ flake.modules.homeManager."portable/christophersmith" ];

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

      home.username = lib.mkDefault flake.users.christophersmith.meta.username;
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      programs.git.settings = {
        user.name = flake.users.christophersmith.meta.fullname;
        user.email = flake.users.christophersmith.meta.email;
      };
    };
}
