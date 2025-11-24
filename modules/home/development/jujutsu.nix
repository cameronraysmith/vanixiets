# Jujutsu (jj) modern VCS with SSH signing and git colocate mode
# Pattern A: flake.modules (plural) with homeManager.development aggregate
# Note: User-specific values (name, email, signing key) should be set in user modules
{ ... }:
{
  flake.modules = {
    homeManager.development =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.jujutsu = {
          enable = true;

          settings = {
            user = {
              # User modules should override user.name and user.email
              name = lib.mkDefault "";
              email = lib.mkDefault "";
            };

            signing = {
              # Sign own commits, drop existing signatures
              behavior = "own";

              # Use SSH backend (migrated from GPG)
              backend = "ssh";

              # Reuse Git's allowedSignersFile for signature verification
              # This enables unified signature verification across Git and Jujutsu
              backends.ssh.allowed-signers = lib.mkDefault "${config.home.homeDirectory}/.config/git/allowed_signers";

              # SSH signing configuration using sops-nix
              # sops-nix manages user-level secrets for home-manager
              # Private key stored in encrypted secrets/home-manager/users/{user}/secrets.yaml
              key = lib.mkDefault config.sops.secrets.ssh-signing-key.path;
            };

            ui = {
              editor = "nvim";
              color = "auto";
              diff-formatter = ":git";
              pager = "delta";

              # Show signature status in log output
              show-cryptographic-signatures = true;
            };

            git = {
              # Enable git colocate mode
              colocate = true;

              # Sign commits before pushing (upstream jujutsu supports revset syntax)
              # Options: true, false, "mine()", "~signed()", "~signed() & mine()", etc.
              # Using true for initial implementation (sign all commits)
              sign-on-push = true;

              # Write Jujutsu change IDs to Git commit headers for Radicle integration
              # Enables Radicle to track change identity across patch revisions
              # See: https://radicle.xyz/2025/08/14/jujutsu-with-radicle.html
              write-change-id-header = true;
            };

            # Snapshot settings control automatic file tracking and size limits
            # auto-track options:
            #   "all()" - automatically track all new files (default, like git without .gitignore)
            #   "none()" - require explicit `jj file track <file>` for each file (like git add)
            #   "glob:pattern" - only track files matching pattern
            snapshot = {
              max-new-file-size = "300KiB"; # Reject new files larger than 300KiB (default: 1MiB)
              auto-track = "all()"; # Explicit default: track all new files automatically
            };
          };
        };

        # Note: Signing key deployed via sops-nix
        # User-specific secrets provide ssh-signing-key for signing
        # Works for all users (crs58, cameron, raquel) via per-user sops modules
      };
  };
}
