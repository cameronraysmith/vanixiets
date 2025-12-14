# Single source of truth for command descriptions organized by category
{
  categories = [
    {
      name = "Git Tools";
      order = 1;
      commands = {
        pmc = "Pre-merge check for git branches";
        gitjson = "Display git log as JSON";
        gitjsonl = "Display git log lines as JSON";
        gfork = "Create a private GitHub fork of current repository";
        stash-staged = "Save staged changes to stash while keeping them staged";
        github-email = "Get GitHub noreply email address for a user";
        check-github-token-scopes = "Check GitHub personal access token scopes";
        rerun-pr-checks = "Re-run GitHub Actions workflow checks for a PR";
        gh-approve-open-prs = "Approve all open PRs with optional exclusions";
      };
    }
    {
      name = "Nix Tools";
      order = 2;
      commands = {
        get-nix-hash = "Compute SHA256 Nix hash of a file from URL";
        ngc = "Nix garbage collection for system and user";
        flakeup = "Update Nix flake and commit lock file";
        dev = "Enter Nix development shell";
      };
    }
    {
      name = "File Tools";
      order = 3;
      commands = {
        n-launcher = "Launch nnn file manager with preset options";
        cleanfn = "Clean up filenames by removing special characters";
        tildepath = "Resolve path to absolute form with tilde expansion for home directory";
      };
    }
    {
      name = "Development Tools";
      order = 4;
      commands = {
        npmccds = "Claude code with dangerous skip permissions";
        ccvers = "List Claude Code npm package versions with tags and release times";
        claude-session-cwd = "Get Claude Code session working directory and metadata";
        kindc = "Create kind Kubernetes cluster with ingress support";
        tre = "Tmux resurrect restore with session selection";
        clean-shell-history-secrets = "Clean secrets from shell history using atuin and gitleaks";
      };
    }
    {
      name = "System Tools";
      order = 5;
      commands = {
        dnsreset = "Flush DNS cache and restart mDNSResponder on macOS";
        rosetta-manage = "Manage nix-rosetta-builder VM (stop/start/restart/gc)";
      };
    }
  ];
}
