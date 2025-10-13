{ flake, ... }:
{
  programs.jujutsu = {
    enable = true;

    settings = {
      user = {
        name = flake.config.me.fullname;
        email = flake.config.me.email;
      };

      signing = {
        behavior = "own";
        backend = "gpg";
        key = "FF043B368811DD1C";
      };

      ui = {
        editor = "nvim";
        color = "auto";
        diff-formatter = ":git";
        pager = "delta";
      };

      # Snapshot settings control automatic file tracking and size limits
      # auto-track options:
      #   "all()" - automatically track all new files (default, like git without .gitignore)
      #   "none()" - require explicit `jj file track <file>` for each file (like git add)
      #   "glob:pattern" - only track files matching pattern
      snapshot = {
        max-new-file-size = "500KiB"; # Reject new files larger than 500KiB (default: 1MiB)
        auto-track = "all()"; # Explicit default: track all new files automatically
      };
    };
  };
}
