{
  flake.modules.darwin.base =
    {
      pkgs,
      lib,
      ...
    }:
    {
      # Nix configuration (from test-clan nixos base patterns)
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@admin"
        ]; # @admin is darwin's wheel equivalent
      };

      # System state version
      system.stateVersion = 5;

      # Basic packages
      environment.systemPackages = with pkgs; [
        vim
        git
      ];

      # Zsh configuration (system-level)
      programs.zsh.enable = true;

      # Note: zsh completions for nix-installed packages are configured
      # per-user in home-manager (nix-darwin doesn't support home-manager.sharedModules)
    };
}
