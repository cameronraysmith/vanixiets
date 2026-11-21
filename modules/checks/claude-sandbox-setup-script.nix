# Holds the generated Claude Code cloud setup script (modules/apps/
# claude-sandbox-setup-script.nix) to the platform's limits and to the closure
# CI builds. Evaluation-time obligations: the asserts fire when this attribute
# is evaluated, and the value is only the script as a file.
#
# - at most 100 lines of at most 200 bytes (A175);
# - `exit 0` as its last line, since a non-zero setup step stops the session
#   from starting (A170);
# - its `P=` names the same store path as
#   checks.x86_64-linux.home-manager-claude-sandbox, which is what nixbot
#   builds and pushes to cache.scientistexperience.net.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        claude-sandbox-setup-script =
          let
            inherit (self.lib.claudeSandboxSetupScript) text;
            lines = lib.splitString "\n" (lib.removeSuffix "\n" text);
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
          pkgs.writeText "claude-sandbox-setup.sh" text;
      };
    };
}
