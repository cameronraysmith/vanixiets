{
  flake.modules.darwin.base =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # Passwordless sudo for primary admin user
      security.sudo.extraConfig = ''
        ${config.system.primaryUser} ALL=(ALL) NOPASSWD: ALL
      '';

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

      # Timezone for all darwin machines
      time.timeZone = "America/New_York";

      # Basic packages
      environment.systemPackages = with pkgs; [
        vim
        git
      ];

      # Zsh configuration (system-level)
      programs.zsh.enable = true;

      # Note: zsh completions for nix-installed packages are configured
      # per-user in home-manager
    };
}
