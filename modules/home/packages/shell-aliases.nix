{ ... }:
{
  flake.modules.homeManager.packages =
    { ... }:
    {
      home.shellAliases = {
        agc = "bunx -p @augmentcode/auggie auggie";
        b = "but";
        bt = "btop";
        bm = "btm";
        bazel = "bazelisk";
        npmbw = "bunx -p @bitwarden/cli bw";
        ccd = "bunx -p @anthropic-ai/claude-code claude --dangerously-skip-permissions";
        e = "nvim";
        dl = "aria2c -x 16 -s 16 -k 1M";
        dr = "docker container run --interactive --rm --tty";
        g = "git";
        gemi = "bunx -p @google/gemini-cli gemini";
        ghe = "github_email";
        gbc = "git branch --sort=-committerdate | grep -v '^\*\|main' | fzf --multi | xargs git branch -d";
        gls = "PAGER=cat git log --oneline --name-status --pretty=format:'%C(auto)%h %s'";
        gmach = "git machete";
        gu = "git machete traverse --fetch --start-from=first-root";
        gts = "check_github_token_scopes";
        i = "macchina";
        j = "just";
        jg = "jj git";
        k = "kubectl";
        kns = "kubectl config unset contexts.$(kubectl config current-context).namespace";
        ks = "kubens";
        kx = "kubectx";
        l = "ll";
        ld = "lazydocker";
        lg = "lazygit";
        lsdir = "ls -d1 */";
        nr = "nix run";
        npmoc = "bunx -p opencode-ai@latest opencode";
        oc = "opencode";
        p = "procs --tree";
        py = "poetry run python";
        rn = "fd -d 1 -t f '.*' | renamer";
        t = "tree";
        tls = "tmux ls";
        tns = "tmux new -s";
        tat = "tmux attach -t";
        tks = "tmux kill-session -t";
        tmh = "tmux list-keys | less";
        mm = "micromamba";
        nb = "nix build --json --no-link --print-build-logs";
        nix-hash = "get_nix_hash";
        s = "sesh connect \"$(sesh list -i | gum filter --limit 1 --placeholder 'Pick a sesh' --prompt='⚡')\"";
        s5b2 = "s5cmd --profile b2 --endpoint-url https://s3.us-east-005.backblazeb2.com";
        y = "yazi";
        cfn = "cleanfn";
      };
    };
}
