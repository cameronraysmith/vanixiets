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
      let
        trunk =
          lib.pipe
            {
              bookmark = [
                "main"
                "master"
                "develop"
              ];
              remote = [
                "rad"
                "origin"
                "upstream"
              ];
            }
            [
              lib.cartesianProduct
              (lib.concatMapStrings (
                { bookmark, remote }:
                "remote_bookmarks(exact:${builtins.toJSON bookmark}, exact:${builtins.toJSON remote}) | "
              ))
              (x: "latest(${x}root())")
            ];
      in
      {
        programs.jujutsu = {
          enable = true;

          # User-specific values (name, email, signing key) should be set in user modules
          settings = {
            aliases = {
              # Diagnostic: show divergent, orphaned, and dangling changes
              orphans = [
                "log"
                "-r"
                "divergent() | (heads(all()) ~ visible_heads() ~ bookmarks())"
              ];
              # Cleanup: abandon all mutable changes not in main's ancestry or current @
              tidy = [
                "abandon"
                "mutable() ~ @ ~ ::main"
              ];
              # Convenience: run git garbage collection to reclaim disk space
              gc = [
                "util"
                "gc"
              ];
              # Advance bookmarks behind @ to latest meaningful commit in @'s ancestry
              tug = [
                "bookmark"
                "move"
                "--from=heads(::@ & bookmarks())"
                "--to=heads(::@ ~ description(exact:\"\") ~ (empty() ~ merges()))"
              ];
              # Cherry-pick with provenance trailer, inserting before working copy
              cherry-pick = [
                "duplicate"
                "--config=templates.duplicate_description=cherry_pick_description"
                "--insert-before=@"
              ];
              # Batch-sign all unsigned mutable ancestors of working copy
              fsign = [
                "sign"
                "--revisions=mutable()::@ ~ @::"
              ];
              # Park current changes by creating new empty commit at parent
              stash = [
                "new"
                "@-"
              ];
              # Force rewrite commit metadata to trigger descendant rebases
              touch = [
                "metaedit"
                "--ignore-immutable"
                "--force-rewrite"
                "-r"
              ];
            };

            revset-aliases = {
              "trunk()" = trunk;
              "private()" = ''subject(regex:"^(private|wip)(:|$)") | conflicts()'';
              "merged(x)" = "first_parent(x)..x-";
              "sign(x)" = "(mutable() ~ signed())::x ~ @::";
            };

            revsets = {
              sign = "sign(@)";
            };

            templates = {
              log = "builtin_log_comfortable";
              op_log = "builtin_op_log_comfortable";
              evolog = "builtin_evolog_compact ++ \"\n\"";
              draft_commit_description = ''
                concat(
                  coalesce(description, default_commit_description, "\n"),
                  "\n",
                  "JJ: Change ID: " ++ format_short_change_id(change_id),
                  "\n",
                  surround(
                    "JJ: This commit contains the following changes:\n", "",
                    indent("JJ:     ", diff.summary()),
                  ),
                  "\nJJ: ignore-rest\n" ++ diff.git(),
                )
              '';
            };

            template-aliases = {
              cherry_pick_description = "description.trim_end() ++ \"\n\n(cherry picked from commit \" ++ commit_id ++ \")\n\"";
              "format_short_cryptographic_signature(signature)" = ''
                if(signature,
                  label("signature status", concat(
                    "[",
                    label(signature.status(), concat(
                      coalesce(
                        if(signature.status() == "good", "✓︎"),
                        if(signature.status() == "unknown", "?"),
                        "x",
                      ),
                      if(signature.display(),
                        " " ++ stringify(signature.display()).replace(regex:" <(.+)>$", "")),
                    )),
                    "]",
                  ))
                )
              '';
            };

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
