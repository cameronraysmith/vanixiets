{
  # OUTER: Flake-parts module signature
  lib,
  ...
}:
{
  flake.modules.homeManager."users/raquel" =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      lib,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      # Compose portable content via registry reference (dendritic).
      imports = [ flake.modules.homeManager."portable/raquel" ];

      # sops-nix configuration for raquel user
      # 5 secrets: development + shell aggregates (NO AI)
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/raquel/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # NEW: For allowed_signers generation
          bitwarden-email = { };
          atuin-key = { };
        };

        # Generate allowed_signers file using sops.templates
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${flake.users.raquel.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      home.username = lib.mkDefault flake.users.raquel.meta.username;
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      # User-specific git identity from typed meta.
      programs.git.settings = {
        user.name = flake.users.raquel.meta.fullname;
        user.email = flake.users.raquel.meta.email;
      };
    };
}
