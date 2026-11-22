# Holds the Claude Code cloud setup script templates (modules/apps/
# claude-sandbox-setup-script.nix) to the platform's limits, the pinned one to
# the closure CI builds and the track-mode one to its fixed text. Evaluation-time
# obligations: the asserts fire when this attribute is evaluated. Its build runs
# shellcheck over both and holds them as files.
#
# Both templates:
# - at most 100 lines of at most 200 bytes, the pinned one once the app fills
#   in the longest provenance it can (a dirty revision and an ISO date) (A175);
# - `exit 0` as their last line, since a non-zero setup step stops the session
#   from starting (A170);
# - no revision in the template itself, which would rebuild the template, the
#   app and this check on every commit.
#
# The pinned template's `P=` names the same store path as
# checks.x86_64-linux.home-manager-claude-sandbox, which is what nixbot builds
# and pushes to cache.scientistexperience.net.
#
# The track-mode template's text is the cloud environment's setup step, so a
# commit-dependent value in it would cost an approval card per commit: it holds
# no store path and no date either. It realises with `--max-jobs 0 --option
# builders ''`, so nothing is built, and it passes the substituters and keys as
# bash arrays, expanded only quoted, since the Q97 probe saw an unquoted string
# split into arguments.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        claude-sandbox-setup-script =
          let
            inherit (self.lib.claudeSandboxSetupScript) template trackTemplate placeholders;
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
            linesOf = text: lib.splitString "\n" (lib.removeSuffix "\n" text);
            limits =
              name: text:
              let
                lines = linesOf text;
                long = lib.filter (l: lib.stringLength l > 200) lines;
              in
              lib.assertMsg (lib.length lines <= 100)
                "claude-sandbox ${name} setup script has ${toString (lib.length lines)} lines; the platform allows 100"
              && lib.assertMsg (
                long == [ ]
              ) "claude-sandbox ${name} setup script has lines over 200 bytes: ${lib.concatStringsSep " | " long}"
              && lib.assertMsg (
                lib.last lines == "exit 0"
              ) "claude-sandbox ${name} setup script must end in `exit 0`, not `${lib.last lines}`";
            oneLine = builtins.replaceStrings [ "\n" ] [ " " ];
            revision = text: builtins.match ".*[0-9a-f]{40}.*" (oneLine text) != null;

            track = oneLine trackTemplate;
            trackLines = linesOf trackTemplate;
            quoted = [
              "\"\${S[*]}\""
              "\"\${K[*]}\""
              "\"\${O[@]}\""
            ];
            unquoted = builtins.replaceStrings quoted (map (_: "") quoted) track;

            lines = linesOf filled;
            built = builtins.unsafeDiscardStringContext self.checks.x86_64-linux.home-manager-claude-sandbox.outPath;
          in
          assert limits "track-mode" trackTemplate;
          assert lib.assertMsg (
            !revision trackTemplate
          ) "claude-sandbox track-mode setup script holds a revision; its text must not change per commit";
          assert lib.assertMsg (
            !lib.hasInfix "${builtins.storeDir}/" track
          ) "claude-sandbox track-mode setup script holds a store path; its text must not change per commit";
          assert lib.assertMsg (
            builtins.match ".*[0-9]{4}-[0-9]{2}-[0-9]{2}.*" track == null
          ) "claude-sandbox track-mode setup script holds a date; its text must not change per commit";
          assert lib.assertMsg (lib.hasInfix "--max-jobs 0 --option builders ''" track)
            "claude-sandbox track-mode setup script must realise with `--max-jobs 0 --option builders ''`, never building";
          assert lib.assertMsg
            (
              lib.all (v: lib.any (lib.hasPrefix "${v}=(") trackLines) [
                "S"
                "K"
                "O"
              ]
              && lib.all (q: lib.hasInfix q track) quoted
            )
            "claude-sandbox track-mode setup script must set S, K and O as bash arrays and expand them as ${lib.concatStringsSep ", " quoted}";
          assert lib.assertMsg (builtins.match ".*\\$\\{?[SKO]([^A-Za-z0-9_].*)?" unquoted == null)
            "claude-sandbox track-mode setup script expands S, K or O other than as ${lib.concatStringsSep ", " quoted}";
          assert limits "pinned" filled;
          assert lib.assertMsg (lib.elem "P=${built}" lines)
            "claude-sandbox setup script must set P=${built}, the path home-manager-claude-sandbox builds";
          assert lib.assertMsg (
            !revision template
          ) "claude-sandbox setup script template holds a revision; fill it in at run time instead";
          pkgs.runCommand "claude-sandbox-setup-scripts"
            {
              nativeBuildInputs = [ pkgs.shellcheck ];
              pinned = pkgs.writeText "claude-sandbox-setup.sh" template;
              track = pkgs.writeText "claude-sandbox-setup-track.sh" trackTemplate;
            }
            ''
              shellcheck --shell=bash "$pinned" "$track"
              mkdir "$out"
              cp "$pinned" "$out/pinned.sh"
              cp "$track" "$out/track.sh"
            '';
      };
    };
}
