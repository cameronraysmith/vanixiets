{
  # OUTER: Flake-parts module signature
  lib,
  ...
}:
let
  content =
    {
      # INNER: Home-manager module signature
      config,
      pkgs,
      lib,
      flake, # from extraSpecialArgs
      ...
    }:
    {
      # Compose portable content via registry reference (dendritic).
      imports = [ flake.modules.homeManager."portable/crs58" ];

      # sops-nix configuration for crs58/cameron user
      # 15 secrets: development + ai + shell aggregates
      sops = {
        defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/crs58/secrets.yaml";
        secrets = {
          github-token = { };
          ssh-signing-key = {
            mode = "0400";
          };
          ssh-public-key = { }; # For allowed_signers generation
          glm-api-key = { };
          firecrawl-api-key = { };
          huggingface-token = { };
          cerebras-api-key = { };
          context7-api-key = { };
          bitwarden-email = { };
          atuin-key = { };
          mcp-agent-mail-bearer-token = { };
          honcho-api-key = { };
          git-credentials = {
            mode = "0400"; # Read-only: prevent git credential-store from modifying
            path = "${config.home.homeDirectory}/.git-credentials";
          };
          aws-credentials = {
            mode = "0600"; # AWS SDK requires 600 for credentials file
            path = "${config.home.homeDirectory}/.aws/credentials";
          };
          niks3-auth-token = {
            path = "${config.xdg.configHome}/niks3/auth-token";
          };
        };

        # Generate allowed_signers file using sops.templates
        # Simpler than activation script - uses same pattern as rbw and mcp-servers
        templates."allowed_signers" = {
          mode = "0400";
          path = "${config.xdg.configHome}/git/allowed_signers";
          content = ''
            ${flake.users.crs58.meta.email} namespaces="git" ${config.sops.placeholder."ssh-public-key"}
          '';
        };

        # Note: Radicle keys deployed via home.file below (not sops.templates due to pure eval path issues)
      };

      # Deploy radicle public key (not secret - can be plaintext, but identity-bound)
      # This is the SSH public key used for Radicle node identity
      home.file.".radicle/keys/radicle.pub".text = ''
        ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+ ${flake.users.crs58.meta.email}
      '';

      # Note: Radicle signing key linked via activation script in radicle.nix
      # Cannot use home.file.source with sops.secrets.path due to pure eval mode restrictions
      # TODO: Investigate sops-nix symlink option or activation script approach

      # Username defaults to meta.username but can be overridden (e.g., for cameron alias).
      home.username = lib.mkDefault flake.users.crs58.meta.username;
      home.homeDirectory = lib.mkDefault (
        if pkgs.stdenv.isDarwin then "/Users/${config.home.username}" else "/home/${config.home.username}"
      );

      # User-specific git/jujutsu identity from typed meta.
      # (Capability aggregates may consume meta directly in a later refactor.)
      programs.git.settings = {
        user.name = flake.users.crs58.meta.fullname;
        user.email = flake.users.crs58.meta.email;
      };

      programs.jujutsu.settings.user = {
        name = flake.users.crs58.meta.fullname;
        email = flake.users.crs58.meta.email;
      };
    };
in
{
  # Transitional dual-write (nix-0pd.17 A1): typed slot + registry key
  # share the same module body via `content`. The registry key is dropped
  # in a later commit once all consumers are migrated.
  flake.modules.homeManager."users/crs58" = content;
  flake.users.crs58.contentPrivate = content;
}
