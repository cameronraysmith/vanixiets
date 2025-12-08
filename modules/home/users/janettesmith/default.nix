{
  # OUTER: Flake-parts module signature
  lib,
  ...
}:
{
  flake.modules.homeManager."users/janettesmith" =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      lib,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      # Aggregates imported via configurations.nix mkHomeConfig
      # Productivity subset: development + shell (no ai tools)
      # Basic user like raquel - 6 aggregates (core, development, packages, shell, terminal, tools)

      # sops-nix configuration for janettesmith user
      # 5 secrets: development + shell aggregates (NO AI)
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/janettesmith/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # For allowed_signers generation
          bitwarden-email = { };
          atuin-key = { };
        };

        # Generate allowed_signers file using sops.templates
        # Simpler than activation script - uses same pattern as rbw and mcp-servers
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            janettesmith@example.com namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      home.stateVersion = "23.11";
      home.username = "janettesmith";
      home.homeDirectory =
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";

      # Override git module defaults with user-specific values
      programs.git.settings = {
        user.name = "Janette Smith";
        user.email = "janettesmith@example.com";
      };

      home.packages = with pkgs; [
        gh # GitHub CLI (keep from baseline)
        just # Command runner
        ripgrep # Fast grep alternative
        fd # Fast find alternative
        bat # Cat with syntax highlighting
        eza # Modern ls replacement
      ];
    };
}
