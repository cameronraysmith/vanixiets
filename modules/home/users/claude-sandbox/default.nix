{ ... }:
let
  content =
    {
      lib,
      pkgs,
      flake,
      ...
    }:
    {
      home.stateVersion = "23.11";

      # The identity default for a linux user is /home/<user>; root's is /root.
      home.username = lib.mkForce "root";
      home.homeDirectory = lib.mkForce "/root";

      vanixiets.sandbox.sopsDir = "/dev/shm/claude-sandbox-sops";

      # The cloud environment's setup script (`nix run .#claude-sandbox-setup-script`)
      # activates as root, and a controller session reads this report back.
      vanixiets.sandbox.bootstrapReport.enable = true;

      # vcs-author's default looks up flake.users.<home.username>, and root is no
      # flake user.
      vcs.author = flake.lib.vcsAuthor flake.users.claude-sandbox.meta;

      # Enabled so the skill corpus links into ~/.claude/skills and the hooks
      # land in ~/.claude/settings.json. The package is null because the cloud
      # harness installs and runs its own claude, and settings are merged into a
      # writable file rather than linked, because the harness and Claude Code
      # both write beside or into it.
      programs.claude-code = {
        enable = true;
        package = null;
        mutableSettings = true;
      };

      programs.openspec.enable = true;
      programs.uv.enable = true;

      # Required tools with no standalone home module; each is installed for
      # other profiles by an aggregate (database, security, development,
      # publishing) that brings much more.
      home.packages = [
        pkgs.age
        pkgs.d2
        pkgs.duckdb
        pkgs.mermaid-cli
        pkgs.sops
      ];
    };
in
{
  flake.users.claude-sandbox.contentPrivate = content;
}
