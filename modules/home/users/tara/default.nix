{
  # OUTER: Flake-parts module signature
  lib,
  ...
}:
{
  flake.modules.homeManager."users/tara" =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      lib,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      # Minimal initial secrets: signing key + public key only
      # Additional secrets (github-token, huggingface-token, etc.) added as tara provides them
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/tara/secrets.yaml";
        secrets = {
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { };
        };

        # Generate allowed_signers file for git commit verification
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            17519396+tarachari3@users.noreply.github.com namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      home.stateVersion = "23.11";
      home.username = lib.mkDefault "tara";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      # Git identity for tara
      programs.git.settings = {
        user.name = "Tara Chari";
        user.email = "17519396+tarachari3@users.noreply.github.com";
      };

      home.packages = with pkgs; [
        gh
      ];
    };
}
