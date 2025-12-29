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

        matchBlocks = {
          # Security keys (FIDO/U2F) should NOT be auto-added to agent
          # Match block must come before wildcard "*" block
          "*_sk" = {
            match = ''exec "sh -c 'test -e ${config.home.homeDirectory}/.ssh/id_*_sk 2>/dev/null'"'';
            addKeysToAgent = "no";
          };

          # ====================
          # Zerotier Network Hosts (test-clan)
          # ====================

          "cinnabar.zt" = {
            hostname = "fddb:4344:343b:14b9:399:93db:4344:343b";
            user = "cameron";
          };

          "electrum.zt" = {
            hostname = "fddb:4344:343b:14b9:399:93d1:7e6d:27cc";
            user = "cameron";
          };

          "blackphos.zt" = {
            hostname = "fddb:4344:343b:14b9:399:930e:e971:d9e0";
            user = "crs58";
          };

          "stibnite.zt" = {
            hostname = "fddb:4344:343b:14b9:399:933e:1059:d43a";
            user = "crs58";
          };

          "argentum.zt" = {
            hostname = "fddb:4344:343b:14b9:399:93f7:54d5:ad7e";
            user = "cameron";
          };

          "rosegold.zt" = {
            hostname = "fddb:4344:343b:14b9:399:9315:3431:ee8";
            user = "cameron";
          };

          "galena.zt" = {
            hostname = "fddb:4344:343b:14b9:399:9315:c67a:dec9";
            user = "cameron";
          };

          "scheelite.zt" = {
            hostname = "fddb:4344:343b:14b9:399:9380:46d5:3400";
            user = "cameron";
          };

          "pixel7.zt" = {
            hostname = "fddb:4344:343b:14b9:399:939f:c45d:577c";
            port = 8022; # Termux sshd default
            user = "termux"; # Termux accepts any username
          };

          # Wildcard for all zerotier hosts
          "*.zt" = {
            # Enable compression for zerotier (encrypted tunnel over encrypted tunnel)
            compression = true;
            # Keepalive for NAT traversal
            serverAliveInterval = 60;
            serverAliveCountMax = 3;
          };

          # ====================
          # Global Defaults
          # ====================

          "*" = {
            # platform-specific SSH agent integration
            # note: SSH_AUTH_SOCK is set by modules/home/core/bitwarden.nix
            # - Darwin: uses bitwarden desktop app SSH agent + keychain fallback
            # - Linux: uses bitwarden desktop app SSH agent (if enabled in bitwarden.nix)
            addKeysToAgent =
              if pkgs.stdenv.isDarwin then
                "yes" # add to both bitwarden agent and macOS keychain
              else
                "confirm"; # prompt before adding to agent on linux

            # Identity files auto-discovered from SSH agent (via SSH_AUTH_SOCK)
            # No explicit identityFile needed - prevents "no such identity" errors
            # when file doesn't exist on headless servers

            # macOS-specific options
            # Note: UseKeychain removed - only works with Apple's SSH, not Nix OpenSSH
            # We use Bitwarden SSH agent via SSH_AUTH_SOCK instead
            extraOptions = lib.optionalAttrs pkgs.stdenv.isDarwin {
              # XAuthLocation for X11 forwarding (XQuartz)
              XAuthLocation = "/opt/X11/bin/xauth";
            };

            # security defaults
            forwardAgent = false; # override per-host as needed
            compression = false; # override for zerotier hosts
            hashKnownHosts = false;
            userKnownHostsFile = "~/.ssh/known_hosts";

            # connection persistence defaults
            controlMaster = "no";
            controlPath = "~/.ssh/master-%r@%n:%p";
            controlPersist = "no";

            # keepalive (disabled by default, enable per-host)
            serverAliveInterval = 0;
            serverAliveCountMax = 3;
          };
        };
      };
    };
}
