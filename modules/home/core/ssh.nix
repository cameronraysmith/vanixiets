# SSH client configuration with platform-aware defaults and zerotier network
# Integrates:
# - includes (colima, augment, orbstack, custom_config)
# - zerotier network hosts
# - security key handling (FIDO/U2F)
{ ... }:
{
  flake.modules.homeManager.core =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      programs.ssh = {
        enable = true;

        # explicitly disable home-manager's default config
        enableDefaultConfig = false;

        # include ordered external SSH configurations
        includes = [
          # Custom user config (highest priority for overrides)
          "${config.home.homeDirectory}/.ssh/custom_config"
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          # Darwin-specific includes
          "${config.home.homeDirectory}/.config/colima/ssh_config"
          "${config.home.homeDirectory}/.orbstack/ssh/config"
        ];

        # programs.ssh.settings replaces the deprecated programs.ssh.matchBlocks
        # (home-manager RFC 42 SSH refactor). Each block is keyed by host or match
        # pattern; directive bodies use upstream OpenSSH PascalCase directive names.
        # The "*" block is special-cased by home-manager to always render last, so
        # its values act as the lowest-priority defaults.
        settings = {
          # Security keys (FIDO/U2F) must NOT be auto-added to the agent.
          # Expressed as a Match-exec block via the `header` option, which carries
          # the match expression (including the interpolated home directory).
          # Because "*" always renders last, this AddKeysToAgent override wins over
          # the global default below.
          "sk-keys" = {
            header = ''Match exec "sh -c 'test -e ${config.home.homeDirectory}/.ssh/id_*_sk 2>/dev/null'"'';
            AddKeysToAgent = "no";
          };

          # ====================
          # Zerotier Network Hosts (test-clan)
          # ====================

          "cinnabar.zt" = {
            HostName = "fddb:4344:343b:14b9:399:93db:4344:343b";
            User = "cameron";
            HostKeyAlias = "cinnabar.zt";
          };

          "electrum.zt" = {
            HostName = "fddb:4344:343b:14b9:399:93d1:7e6d:27cc";
            User = "cameron";
            HostKeyAlias = "electrum.zt";
          };

          "blackphos.zt" = {
            HostName = "fddb:4344:343b:14b9:399:930e:e971:d9e0";
            User = "crs58";
            HostKeyAlias = "blackphos.zt";
          };

          "stibnite.zt" = {
            HostName = "fddb:4344:343b:14b9:399:933e:1059:d43a";
            User = "crs58";
            HostKeyAlias = "stibnite.zt";
          };

          "argentum.zt" = {
            HostName = "fddb:4344:343b:14b9:399:93f7:54d5:ad7e";
            User = "cameron";
            HostKeyAlias = "argentum.zt";
          };

          "rosegold.zt" = {
            HostName = "fddb:4344:343b:14b9:399:9315:3431:ee8";
            User = "cameron";
            HostKeyAlias = "rosegold.zt";
          };

          "galena.zt" = {
            HostName = "fddb:4344:343b:14b9:399:9315:c67a:dec9";
            User = "cameron";
            HostKeyAlias = "galena.zt";
          };

          "scheelite.zt" = {
            HostName = "fddb:4344:343b:14b9:399:9380:46d5:3400";
            User = "cameron";
            HostKeyAlias = "scheelite.zt";
          };

          "magnetite.zt" = {
            HostName = "fddb:4344:343b:14b9:399:930f:39db:40d2";
            User = "cameron";
            HostKeyAlias = "magnetite.zt";
          };

          "pixel7.zt" = {
            HostName = "fddb:4344:343b:14b9:399:939f:c45d:577c";
            Port = 8022; # Termux sshd default
            User = "termux"; # Termux accepts any username
          };

          # Wildcard for all zerotier hosts
          "*.zt" = {
            # Enable compression for zerotier (encrypted tunnel over encrypted tunnel)
            Compression = true;
            # Keepalive for NAT traversal
            ServerAliveInterval = 60;
            ServerAliveCountMax = 3;
          };

          # ====================
          # Global Defaults (always rendered last)
          # ====================

          "*" = {
            # platform-specific SSH agent integration
            # note: SSH_AUTH_SOCK is set by modules/home/core/bitwarden.nix
            # - Darwin: uses bitwarden desktop app SSH agent + keychain fallback
            # - Linux: uses bitwarden desktop app SSH agent (if enabled in bitwarden.nix)
            AddKeysToAgent =
              if pkgs.stdenv.isDarwin then
                "yes" # add to both bitwarden agent and macOS keychain
              else
                "confirm"; # prompt before adding to agent on linux

            # Identity files auto-discovered from SSH agent (via SSH_AUTH_SOCK).
            # No explicit IdentityFile needed - prevents "no such identity" errors
            # when the file doesn't exist on headless servers.

            # security defaults
            ForwardAgent = false; # override per-host as needed
            Compression = false; # override for zerotier hosts
            HashKnownHosts = false;
            UserKnownHostsFile = "~/.ssh/known_hosts";

            # connection persistence defaults
            ControlMaster = "no";
            ControlPath = "~/.ssh/master-%r@%n:%p";
            ControlPersist = "no";

            # keepalive (disabled by default, enable per-host)
            ServerAliveInterval = 0;
            ServerAliveCountMax = 3;
          }
          # macOS-specific options.
          # Note: UseKeychain removed - only works with Apple's SSH, not Nix OpenSSH;
          # we use the Bitwarden SSH agent via SSH_AUTH_SOCK instead.
          // lib.optionalAttrs pkgs.stdenv.isDarwin {
            # XAuthLocation for X11 forwarding (XQuartz)
            XAuthLocation = "/opt/X11/bin/xauth";
          };
        };
      };
    };
}
