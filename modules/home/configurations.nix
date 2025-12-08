{
  inputs,
  config,
  lib,
  ...
}:
let
  users = [
    "crs58"
    "raquel"
  ];

  # Create homeConfiguration for a specific user and system
  mkHomeConfig =
    username: system:
    let
      # Selective aggregate imports per user
      # crs58: all aggregates (development, ai, shell)
      # raquel: development + shell only (no ai tools)
      aggregateImports =
        if username == "crs58" then
          [
            config.flake.modules.homeManager.development
            config.flake.modules.homeManager.ai
            config.flake.modules.homeManager.shell
          ]
        else if username == "raquel" then
          [
            config.flake.modules.homeManager.development
            config.flake.modules.homeManager.shell
          ]
        else
          [ ]; # Default: no aggregates
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      # Create pkgs with all overlays including custom packages
      # Use flake.overlays.default which includes all 5 layers + custom packages
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          config.flake.overlays.default
        ];
      };
      # Pass flake as extraSpecialArgs for module access
      # Include inputs so home-manager modules can access flake.inputs.*
      extraSpecialArgs = {
        flake = config.flake // {
          inherit inputs;
        };
      };
      modules = aggregateImports ++ [
        config.flake.modules.homeManager."users/${username}"
        # Add base sops-nix module for user-level secrets
        # Imports sops-nix.homeManagerModules.sops and sets age.keyFile
        config.flake.modules.homeManager.base-sops
        # Add lazyvim home-manager module for neovim
        inputs.lazyvim-nix.homeManagerModules.default
      ];
    };

  # Generate all user configs for all systems
  # Structure: homeConfigurations.${system}.${username}
  mkAllConfigs = lib.genAttrs config.systems (
    system: lib.genAttrs users (username: mkHomeConfig username system)
  );
in
{
  # Force module loading order - aggregates processed before homeConfigurations
  # This ensures config.flake.modules.homeManager.* are merged before access
  # Multi-aggregate organization (drupol-style):
  #   - core: base config (catppuccin, fonts, bitwarden, xdg, session-variables, ssh)
  #   - development: dev environment (git, jujutsu, neovim, wezterm, zed, starship, zsh)
  #   - ai: AI-assisted tools (claude-code, mcp-servers, glm wrappers, ccstatusline)
  #   - shell: shell/terminal environment (atuin, yazi, zellij, tmux, bash, nushell)
  #   - packages: organized package sets (terminal, development, compute, security, database, publishing)
  #   - terminal: terminal utilities (direnv, fzf, lsd, bat, btop, htop, jq, nix-index, zoxide)
  #   - tools: additional tools (awscli, k9s, pandoc, nix, gpg, macchina, tealdeer, texlive)
  imports = [
    ./core
    ./development
    ./ai
    ./shell
    ./packages
    ./terminal
    ./tools
    ./users
  ];

  # homeConfigurations organized by system, generated for all systems in config.systems
  # Usage: nix build .#homeConfigurations.${system}.${username}
  flake.homeConfigurations = mkAllConfigs;
}
