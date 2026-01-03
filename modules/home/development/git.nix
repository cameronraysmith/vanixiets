# Git configuration with SSH signing, delta diff, lazygit, allowed_signers
# Note: User-specific values (name, email, ssh key) should be set in user modules
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
        programs.git = {
          package = pkgs.gitFull;
          enable = true;

          # SSH signing configuration using sops-nix
          # sops-nix manages user-level secrets for home-manager
          # Private key stored in encrypted secrets/home-manager/users/{user}/secrets.yaml
          signing = lib.mkDefault {
            key = config.sops.secrets.ssh-signing-key.path;
            format = "ssh";
            signByDefault = true;
          };

          lfs = {
            enable = true;
            skipSmudge = false;
          };

          settings = {
            # git-xet: https://huggingface.co/docs/hub/xet/using-xet-storage
            # The following settings are equivalent to running
            # `git-xet install --concurrency 8`
            lfs.concurrenttransfers = 8;
            "lfs \"customtransfer.xet\"" = {
              path = "git-xet";
              args = "transfer";
              concurrent = true;
            };
            # Submodule optimization: auto-recurse, parallel fetch, shared object store
            submodule = {
              recurse = true; # Auto-update submodules on checkout/pull/switch
              fetchJobs = 8; # Parallel submodule fetching
              alternateLocation = "superproject"; # Share objects with parent repo
              alternateErrorStrategy = "info"; # Warn but continue if alternates fail
            };
            status.submoduleSummary = true; # Show submodule changes in git status
            diff.submodule = "log"; # Show commit log in diffs, not just hashes
            # User modules should override user.name and user.email
            core.editor = "nvim";
            # Clear system helpers, then: sops-managed store first, osxkeychain fallback (Darwin only)
            credential.helper = [
              ""
              "store --file ${config.home.homeDirectory}/.git-credentials"
            ]
            ++ lib.optionals pkgs.stdenv.isDarwin [ "osxkeychain" ];
            github.user = "cameronraysmith";
            color.ui = true;
            diff.colorMoved = "zebra";
            fetch = {
              prune = true;
              recurseSubmodules = "on-demand"; # Fetch submodules when superproject ref changes
            };
            format.signoff = true;
            init = {
              defaultBranch = "main";
              templateDir = ""; # Explicitly disable legacy template directory
            };
            merge.conflictstyle = "diff3";
            push = {
              autoSetupRemote = true;
              useForceIfIncludes = true;
              recurseSubmodules = "check"; # Fail if submodule commits aren't pushed
            };
            rebase = {
              autoStash = true;
              updateRefs = true;
            };
            gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.config/git/allowed_signers";
            log.showSignature = false; # --[no-]show-signature
            alias = {
              a = "add";
              br = "branch";
              bra = "branch -a";
              c = "commit";
              ca = "commit --amend";
              can = "commit --amend --no-edit";
              cavm = "commit -a -v -m";
              cfg = "config --list";
              cl = "clone";
              cm = "commit -m";
              co = "checkout";
              cp = "cherry-pick";
              cpx = "cherry-pick -x";
              d = "diff";
              div = "log --oneline --left-right @{u}...HEAD";
              f = "fetch";
              fo = "fetch origin";
              fu = "fetch upstream";
              lease = "push --force-with-lease";
              ll = "log --pretty=format:\"%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %C(blue)%an%C(reset) %s%C(auto)%d%C(reset)\" --date=format:'%Y-%m-%d %H:%M'";
              lol = "log --graph --decorate --pretty=oneline --abbrev-commit";
              lola = "log --graph --decorate --pretty=oneline --abbrev-commit --all";
              pl = "pull";
              pr = "pull -r";
              ps = "push";
              psf = "push -f";
              rb = "rebase";
              rbi = "rebase -i";
              r = "remote";
              ra = "remote add";
              rr = "remote rm";
              rv = "remote -v";
              rs = "remote show";
              st = "status";
              stn = "status -uno";
            };
          };

          ignores = [
            "*~"
            "*.swp"
          ];
        };

        # Delta diff viewer with side-by-side layout
        programs.delta = {
          enable = true;
          enableGitIntegration = true;
          options = {
            side-by-side = true;
          };
        };

        # Lazygit TUI with delta integration
        programs.lazygit = {
          enable = true;
          settings = {
            git = {
              overrideGpg = true;
              pagers = [
                {
                  colorArg = "always";
                  pager = "delta --color-only --dark --paging=never";
                  useConfig = false;
                }
              ];
              commit = {
                signOff = true;
              };
            };
          };
        };

        # allowed_signers file for SSH signature verification
        # User modules should provide allowed_signers content
        # Example: home.file."${config.xdg.configHome}/git/allowed_signers".text = ''
        #   ${user.email} namespaces="git" ${user.sshKey}
        # '';
      };
  };
}
