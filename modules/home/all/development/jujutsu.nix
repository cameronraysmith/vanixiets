{
  flake,
  config,
  lib,
  ...
}:
let
in
{
  programs.jujutsu = {
    enable = true;

    settings = {
      user = {
        name = flake.config.me.fullname;
        email = flake.config.me.email;
      };

      signing = {
        # Sign own commits, drop existing signatures
        behavior = "own";

        # Use SSH backend (migrated from GPG)
        backend = "ssh";

        # Reuse Git's allowedSignersFile for signature verification
        # This enables unified signature verification across Git and Jujutsu
        backends.ssh.allowed-signers = config.programs.git.extraConfig.gpg.ssh.allowedSignersFile;

        # Use same SOPS-deployed unified SSH key as Git
        key = config.sops.secrets."radicle/ssh-private-key".path;
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

  # Deploy unified SSH key via SOPS (same key as Git and Radicle)
  # Following defelo-nixos pattern: each module explicitly declares its secret dependencies
  # Using explicit sopsFile pattern (not defaultSopsFile) for future flexibility
  sops.secrets."radicle/ssh-private-key" = {
    sopsFile = flake.inputs.self + "/secrets/radicle.yaml";
    mode = "0400";
  };
}
