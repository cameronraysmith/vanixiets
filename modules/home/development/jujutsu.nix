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

          # User-specific values (name, email, signing key) should be set in user modules
          settings = {
            user = {
              name = lib.mkDefault "";
              email = lib.mkDefault "";
            };

            signing = {
              # Sign own commits, drop existing signatures
              behavior = "own";

              # Use ssh backend as opposed to GPG
              backend = "ssh";

              # Reuse git's allowedSignersFile for signature verification
              # to enable unified signature verification across git and jujutsu
              backends.ssh.allowed-signers = lib.mkDefault "${config.home.homeDirectory}/.config/git/allowed_signers";

              # sops-nix manages user-level secrets for home-manager
              # private key stored in encrypted secrets/home-manager/users/{user}/secrets.yaml
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
              sign-on-push = true;

              # Write Jujutsu change IDs to git commit headers for radicle integration
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
              auto-track = "all()";
            };
          };
        };
      };
  };
}
