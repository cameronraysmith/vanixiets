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

      security.pam.services.sudo_local.touchIdAuth = lib.mkDefault true;

      # Default of 6 is exhausted by agent forwarding before the right key is
      # offered: the Bitwarden SSH agent commonly holds 10+ keys.
      services.openssh.extraConfig = lib.mkDefault ''
        MaxAuthTries 20
      '';

      # Nix configuration (from test-clan nixos base patterns)
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        trusted-users = [
          "root"
          "@admin" # darwin's wheel equivalent
          # macOS ships group wheel (gid 0) with root as its only member, so
          # this grants nothing beyond "root" above. It is kept fleet-wide so
          # every darwin host states one trust set rather than three hosts
          # carrying it and a fourth silently omitting it.
          "@wheel"
        ];
      };

      # Match GID to a fresh Nix installation; the DeterminateSystems installer
      # has used 350 since Aug 2024 and every darwin host here was installed
      # with it. See
      # https://github.com/DeterminateSystems/nix-installer/pull/1123
      #
      # Plain rather than lib.mkDefault: nix-darwin's modules/misc/ids.nix sets
      # `lib.mkDefault (if stateVersion < 5 then 30000 else 350)`, and every
      # host here forces stateVersion 4, so a second mkDefault ties with it and
      # fails evaluation. A host whose nixbld group really is 30000 must say so
      # with lib.mkForce; a mismatch surfaces as an activation error, not
      # silently.
      ids.gids.nixbld = 350;

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
