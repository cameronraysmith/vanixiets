# Drives Claude Code cloud sessions from the command line (create, send) and
# reads the transcripts the claude-sandbox profile's Stop hook pushes to
# claude/transcripts/<session> (wait, fetch, prune), with its co-located .sh
# sidecar; `nix run .#claude-cloud-session -- --help`.
{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      packages.claude-cloud-session = pkgs.writeShellApplication {
        name = "claude-cloud-session";
        runtimeInputs = [
          config.packages.claude-code
          pkgs.coreutils
          pkgs.gawk
          pkgs.git
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
          pkgs.unixtools.script
        ];
        text = builtins.readFile ./claude-cloud-session.sh;

        # Build locally; no cache holds a wrapper only this repository builds
        # (see apm-context-compile.nix).
        derivationArgs = {
          preferLocalBuild = true;
          allowSubstitutes = false;
        };
      };

      apps.claude-cloud-session = {
        type = "app";
        program = lib.getExe config.packages.claude-cloud-session;
      };
    };
}
