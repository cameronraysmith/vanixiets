# Holds the Claude Code cloud setup script template (modules/apps/
# claude-sandbox-setup-script.nix) to the platform's limits and to the closure
# CI builds. Evaluation-time obligations: the asserts fire when this attribute
# is evaluated, and the value is only the template as a file.
#
# - at most 100 lines of at most 200 bytes once the app fills in the longest
#   provenance it can (a dirty revision and an ISO date) (A175);
# - `exit 0` as its last line, since a non-zero setup step stops the session
#   from starting (A170);
# - its `P=` names the same store path as
#   checks.x86_64-linux.home-manager-claude-sandbox, which is what nixbot
#   builds and pushes to cache.scientistexperience.net;
# - no revision in the template itself, which would rebuild the template, the
#   app and this check on every commit.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        claude-sandbox-setup-script =
          let
            inherit (self.lib.claudeSandboxSetupScript) template placeholders;
            filled =
              builtins.replaceStrings
                [
                  placeholders.rev
                  placeholders.date
                ]
                [
                  "${lib.fixedWidthString 40 "f" ""}-dirty"
                  "2000-01-01"
                ]
                template;
            lines = lib.splitString "\n" (lib.removeSuffix "\n" filled);
            long = lib.filter (l: lib.stringLength l > 200) lines;
            built = builtins.unsafeDiscardStringContext self.checks.x86_64-linux.home-manager-claude-sandbox.outPath;
          in
          assert lib.assertMsg (
            lib.length lines <= 100
          ) "claude-sandbox setup script has ${toString (lib.length lines)} lines; the platform allows 100";
          assert lib.assertMsg (
            long == [ ]
          ) "claude-sandbox setup script has lines over 200 bytes: ${lib.concatStringsSep " | " long}";
          assert lib.assertMsg (
            lib.last lines == "exit 0"
          ) "claude-sandbox setup script must end in `exit 0`, not `${lib.last lines}`";
          assert lib.assertMsg (lib.elem "P=${built}" lines)
            "claude-sandbox setup script must set P=${built}, the path home-manager-claude-sandbox builds";
          assert lib.assertMsg (
            builtins.match ".*[0-9a-f]{40}.*" (builtins.replaceStrings [ "\n" ] [ " " ] template) == null
          ) "claude-sandbox setup script template holds a revision; fill it in at run time instead";
          pkgs.writeText "claude-sandbox-setup.sh" template;
      };
    };
}
