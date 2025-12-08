# Atuin shell history with sync, search, and context
# Encryption key from sops-nix (manually extracted base64 key)
{ ... }:
{
  flake.modules = {
    homeManager.shell =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.atuin = {
          enable = true;
          enableZshIntegration = true;
          # Disable bash integration to avoid nokogiri build failure via bash-preexec → bats → ronn
          # See: https://github.com/NixOS/nixpkgs/issues/XXX (nokogiri 1.16.0 fails on darwin)
          enableBashIntegration = lib.mkDefault false;
          # https://docs.atuin.sh/configuration/config/
          settings = {
            auto_sync = true;
            sync.records = true;
            dotfiles.enabled = true;
            sync_frequency = "15m";
            update_check = false;
            ctrl_n_shortcuts = false;
            enter_accept = true;
            keymap_mode = "vim-insert";
            filter_mode_shell_up_key_binding = "directory";
            search_mode = "skim";
            secrets_filter = true;
            show_help = false;
            show_preview = true;
            # Only necessary on certain file systems e.g. cephfs.
            # daemon = {
            #   enabled = true;
            # };
          };
        };

        # Atuin encryption key deployment
        # Create symlink from sops secret to atuin's expected location at activation time
        # sops secret path: config.sops.secrets.atuin-key.path (available after activation)
        # atuin expects: ~/.local/share/atuin/key
        home.activation.deployAtuinKey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          atuinKeyPath="${config.home.homeDirectory}/.local/share/atuin/key"
          sopsKeyPath="${config.sops.secrets.atuin-key.path}"

          $DRY_RUN_CMD mkdir -p "$(dirname "$atuinKeyPath")"
          if [ -f "$sopsKeyPath" ]; then
            $DRY_RUN_CMD ln -sf "$sopsKeyPath" "$atuinKeyPath"
          fi
        '';
      };
  };
}
