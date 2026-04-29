# Fetch buildbot-nix build logs from magnetite via ssh
# On Darwin, uses /usr/bin/ssh (Apple-signed, Keychain-integrated agent)
# rather than nixpkgs openssh, matching the ntfy-send precedent for
# reaching ZeroTier hosts from macOS.
# Template bifurcation (writeShellApplication): INTERPOLATION FORM.
# Body lives in the sibling ./buildbot-logs.sh (directly executable for
# local debugging). The `text` preamble injects BUILDBOT_SSH_BIN — the
# eval-time-resolved ssh path — so darwin uses /usr/bin/ssh while linux
# uses PATH ssh. Standalone invocation (./buildbot-logs.sh) falls back
# to `ssh` on PATH via the BUILDBOT_SSH_BIN default in the sidecar.
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "buildbot-logs";
          text = ''
            export BUILDBOT_SSH_BIN=${if pkgs.stdenv.isDarwin then "/usr/bin/ssh" else "ssh"}
            ${builtins.readFile ./buildbot-logs.sh}
          '';
          meta.description = "Fetch buildbot-nix build logs from magnetite via ssh";
        })
      ];
    };
}
