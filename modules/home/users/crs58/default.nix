{
  # OUTER: Flake-parts module signature
  lib,
  ...
}:
{
  flake.modules.homeManager."users/crs58" =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      lib,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      # Pattern A: All aggregates imported via configurations.nix mkHomeConfig
      # No local imports needed - all 17 modules available via aggregate merging

      # sops-nix configuration for crs58/cameron user
      # 8 secrets: development + ai + shell aggregates
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # NEW: For allowed_signers generation
          glm-api-key = { };
          firecrawl-api-key = { };
          huggingface-token = { };
          bitwarden-email = { };
          atuin-key = { };
        };

        # Generate allowed_signers file using sops.templates
        # Simpler than activation script - uses same pattern as rbw and mcp-servers
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            cameron.ray.smith@gmail.com namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      home.stateVersion = "23.11";
      # Username defaults to crs58 but can be overridden (e.g., for cameron alias)
      home.username = lib.mkDefault "crs58";
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      # Override git module defaults with user-specific values
      programs.git.settings = {
        user.name = "Cameron Smith";
        user.email = "cameron.ray.smith@gmail.com";
      };

      # Override jujutsu module defaults with user-specific values
      programs.jujutsu.settings.user = {
        name = "Cameron Smith";
        email = "cameron.ray.smith@gmail.com";
      };

      home.packages = with pkgs; [
        gh # GitHub CLI (keep from baseline)
      ];
    };
}
