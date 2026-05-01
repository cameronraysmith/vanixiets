{
  lib,
  ...
}:
let
  content =
    {
      config,
      pkgs,
      lib,
      flake,
      ...
    }:
    {
      imports = [ flake.modules.homeManager."portable/janettesmith" ];

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

      home.username = lib.mkDefault flake.users.janettesmith.meta.username;
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      programs.git.settings = {
        user.name = flake.users.janettesmith.meta.fullname;
        user.email = flake.users.janettesmith.meta.email;
      };
    };
in
{
  flake.modules.homeManager."users/janettesmith" = content;
  flake.users.janettesmith.contentPrivate = content;
}
