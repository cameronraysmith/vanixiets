# Session environment variables
# Extracted from vanixiets/modules/home/all/terminal/default.nix lines 294-299
{ ... }:
{
  flake.modules.homeManager.core =
    { ... }:
    {
      home.sessionVariables = {
        EDITOR = "nvim";
        # Colorize man pages via bat (applies across zsh, fish, and bash).
        MANPAGER = "sh -c 'col -bx | bat -l man -p'";
        MANROFFOPT = "-c";
        # Suppress the optional .git/index stat-cache writeback that git status-class
        # pollers (ccstatusline, Zed, shell prompts) perform and that can race jj's
        # colocated index export. Performance-only (git recomputes when stat info is
        # stale); complementary to the gitmux GIT_INDEX_FILE wrapper (git diff ignores
        # this flag) and inert for jj's own git2/gitoxide index handling. There is no
        # core.optionalLocks git-config key, so this must be delivered as an env var.
        GIT_OPTIONAL_LOCKS = "0";
        LANG = "en_US.UTF-8";
        LC_ALL = "en_US.UTF-8";
        LC_CTYPE = "en_US.UTF-8";
      };
    };
}
