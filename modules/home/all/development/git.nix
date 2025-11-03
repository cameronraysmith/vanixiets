{
  pkgs,
  flake,
  config,
  lib,
  ...
}:
let
  package = pkgs.gitFull;
  # Look up user config based on home.username (set by each home configuration)
  user = flake.config.${config.home.username};
in
{
  programs.git = {
    inherit package;
    enable = true;
    signing = {
      # Use SOPS-deployed per-user signing key
      key = config.sops.secrets."${user.sopsIdentifier}/signing-key".path;
      format = "ssh";
      signByDefault = true;
    };

    lfs = {
      enable = true;
      skipSmudge = false;
    };

    settings = {
      user.name = user.fullname;
      user.email = user.email;
      core.editor = "nvim";
      credential.helper = "store --file ~/.git-credentials";
      github.user = "cameronraysmith";
      color.ui = true;
      diff.colorMoved = "zebra";
      fetch.prune = true;
      format.signoff = true;
      init = {
        defaultBranch = "main";
        templateDir = ""; # Explicitly disable legacy template directory
      };
      merge.conflictstyle = "diff3";
      push = {
        autoSetupRemote = true;
        useForceIfIncludes = true;
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

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      side-by-side = true;
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      git = {
        overrideGpg = true;
        paging = {
          colorArg = "always";
          pager = "delta --color-only --dark --paging=never";
          useConfig = false;
        };
        commit = {
          signOff = true;
        };
      };
    };
  };

  home.file."${config.xdg.configHome}/git/allowed_signers".text = ''
    ${user.email} namespaces="git" ${user.sshKey}
  '';

  # Deploy per-user signing key via SOPS
  # Path determined by user's sopsIdentifier (admin-user, raquel-user, etc.)
  sops.secrets."${user.sopsIdentifier}/signing-key" = {
    sopsFile = flake.inputs.self + "/secrets/users/${user.sopsIdentifier}/signing-key.yaml";
    mode = "0400";
  };
}
