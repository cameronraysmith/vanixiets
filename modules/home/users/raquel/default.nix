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
      # Aggregates imported via configurations.nix mkHomeConfig
      # Productivity subset: development + shell (no ai tools)

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
        # Simpler than activation script - uses same pattern as rbw and mcp-servers
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            raquel@example.com namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };
      };

      home.stateVersion = "23.11";
      home.username = "raquel";
      home.homeDirectory =
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}";

      # Override git module defaults with user-specific values
      programs.git.settings = {
        user.name = "Raquel";
        user.email = "raquel@example.com";
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
