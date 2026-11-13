# Git configuration with delta diff and lazygit; signing is set by vcs-signing.nix
# Note: User-specific values (name, email) should be set in user modules
{ ... }:
let
  content =
    personal:
    {
      pkgs,
      config,
      lib,
      flake,
      ...
    }:
    {
      home.packages = lib.optional (
        config.programs.git.enable
        && config.programs.git.lfs.enable
        && lib.any (settings: (settings."lfs \"customtransfer.xet\"".path or null) == "git-xet") (
          lib.toList config.programs.git.settings
        )
      ) pkgs.git-xet;

      programs.git = {
        package = pkgs.gitFull;
        enable = true;

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
          credential.helper = lib.mkIf personal (
            [
              ""
              "store --file ${config.home.homeDirectory}/.git-credentials"
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ "osxkeychain" ]
          );
          github = lib.mkIf (personal && flake.users.${config.home.username}.meta.githubUser != null) {
            user = flake.users.${config.home.username}.meta.githubUser;
          };
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
          merge.ff = "only";
          push = {
            autoSetupRemote = true;
            useForceIfIncludes = true;
            recurseSubmodules = "check"; # Fail if submodule commits aren't pushed
          };
          rebase = {
            autoStash = true;
            updateRefs = true;
          };
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
            llt = "!git log --pretty=format:\"%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %C(blue)%an%C(reset) %s%C(auto)%d%C(reset)\" --date=format:'%Y-%m-%d %H:%M' \"$(git describe --tags --abbrev=0)..HEAD\"";
            lt = "log --no-walk --tags --pretty=format:\"%C(yellow)%h%C(reset) %C(green)%ad%C(reset) %C(blue)%an%C(reset) %s%C(auto)%d%C(reset)\" --date=format:'%Y-%m-%d %H:%M' --decorate-refs=refs/tags";
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
            prune-merged = "!git branch --merged main | grep -Ev '^[*]|^  main$' | xargs git branch -d";
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
            # lazygit 0.65 renamed git.pagers to git.diffRenderers and the
            # entry's `pager` key to `command`. Its automatic migration
            # rewrites config.yml, which fails against this store symlink, so
            # the schema is declared post-migration here instead.
            diffRenderers = [
              {
                colorArg = "always";
                command = "delta --color-only --dark --paging=never";
                useConfig = false;
              }
            ];
            commit = {
              signOff = true;
            };
          };
        };
      };
    };
in
{
  flake.modules.homeManager.development = content true;
  flake.modules.homeManager.git = content false;
}
